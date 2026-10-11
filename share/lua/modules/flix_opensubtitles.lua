--[[
 OpenSubtitles.com REST client for the Flix subtitle service.

 Derived from PowerVLC's pvlc_opensubtitles.lua (https://github.com/Olsro/powervlc,
 GPL-2.0-or-later): REST v1 login / search / download, the 64 KiB file hash and the
 result ranking come from there. Differences: no bundled application key (the user
 provides their own), searches by title + year parsed with vlc.strings.release_info
 instead of the raw file name, a test hook for the server address, and file saving
 that works without vlc.io.open_exclusive.

 GPL-2.0-or-later.
]]

local M = {}
local Client = {}
Client.__index = Client

local API = "https://api.opensubtitles.com/api/v1"

------------------------------------------------------------------------------
-- small helpers
------------------------------------------------------------------------------

function M.trim(s)
    return (tostring(s or ""):gsub("^%s*(.-)%s*$", "%1"))
end

function M.display_text(value)
    return (M.trim(value):gsub("[%c<>]", " "):gsub("%s+", " "))
end

-- "en,id" -> { "en", "id" }; nil when malformed or more than three
function M.languages(s)
    local list, seen = {}, {}
    for code in tostring(s or ""):lower():gmatch("[^,%s;]+") do
        if not code:match("^%a%a$") and not code:match("^%a%a%-%a%a$") then
            return nil
        end
        if not seen[code] then
            list[#list + 1] = code
            seen[code] = true
        end
    end
    if #list == 0 or #list > 3 then return nil end
    return list
end

local function encode(s)
    return (tostring(s):gsub("([^%w%-._~ ])", function(c)
        return string.format("%%%02X", c:byte())
    end):gsub(" ", "+"))
end

-- sorted, URL-encoded query string
function M.query(params)
    local keys, out = {}, {}
    for key, value in pairs(params) do
        if value ~= nil and value ~= "" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        out[#out + 1] = key .. "=" .. encode(params[key])
    end
    return table.concat(out, "&")
end

-- title / year / season / episode / resolution of a release or torrent file name
function M.release_info(name)
    if vlc and vlc.strings and vlc.strings.release_info then
        return vlc.strings.release_info(name)
    end
    -- only reached outside VLC (offline tests)
    local title = tostring(name or ""):gsub("%.%w+$", ""):gsub("[._]", " ")
    local year = tonumber(title:match("%f[%d]([12]%d%d%d)%f[%D]"))
    return { title = M.trim(title:gsub("%s*[12]%d%d%d.*$", "")), year = year or 0,
             season = 0, episode = 0, resolution = "", recognized = year ~= nil }
end

------------------------------------------------------------------------------
-- OpenSubtitles file hash: size + 64-bit sum of the first and last 64 KiB
-- (two 32-bit halves: Lua 5.1 numbers are doubles)
------------------------------------------------------------------------------

function M.hash_blocks(size, first, last)
    if type(size) ~= "number" or size < 65536 or size > 9007199254740991
        or type(first) ~= "string" or #first ~= 65536
        or type(last) ~= "string" or #last ~= 65536 then
        return nil
    end
    local base = 4294967296
    local lo, hi = size % base, math.floor(size / base) % base
    for _, block in ipairs({ first, last }) do
        for i = 1, #block, 8 do
            local a, b, c, d, e, f, g, h = block:byte(i, i + 7)
            lo = lo + a + b * 256 + c * 65536 + d * 16777216
            hi = (hi + e + f * 256 + g * 65536 + h * 16777216 + math.floor(lo / base)) % base
            lo = lo % base
        end
    end
    -- format in 16-bit pieces: %x takes a signed long on some targets
    return string.format("%04x%04x%04x%04x", math.floor(hi / 65536), hi % 65536,
                         math.floor(lo / 65536), lo % 65536)
end

-- hash of a local file (file:// uri), nil for anything else
function M.hash(uri)
    if not tostring(uri):match("^file://") then return nil end
    local stream
    local ok, hash = pcall(function()
        stream = vlc.stream(uri)
        if not stream then return nil end
        local size = stream:getsize()
        if size < 65536 or size > 9007199254740991 then return nil end
        local first = stream:read(65536)
        if not stream:seek(size - 65536) then return nil end
        return M.hash_blocks(size, first, stream:read(65536))
    end)
    stream = nil
    collectgarbage("collect") -- release the file handle
    return ok and hash or nil
end

------------------------------------------------------------------------------
-- client
------------------------------------------------------------------------------

-- key: the user's own API consumer key; base: optional server address (tests)
function M.new(key, version, base)
    local self = setmetatable({
        key = key,
        json = require("dkjson"),
        base = (base and base ~= "") and base or API,
        agent = "VLC-Flix v" .. tostring(version or "1"),
        token = nil,
    }, Client)
    self.test_origin = (self.base ~= API) and self.base:match("^https?://[^/]+") or nil
    return self
end

-- Only follow / fetch from OpenSubtitles over HTTPS, never from an arbitrary host:
-- the key and token must not leak. A custom base (tests) is trusted for itself.
function Client:trusted(url)
    if type(url) ~= "string" then return false end
    if self.test_origin and url:sub(1, #self.test_origin) == self.test_origin then
        return true
    end
    local host = url:match("^https://([^/]+)")
    return host ~= nil and (host == "opensubtitles.com"
                            or host:match("^[%w%-%.]+%.opensubtitles%.com$") ~= nil)
end

function Client:request(method, path, params)
    if not self.key or self.key == "" then return nil, "missing_key" end
    local headers = { ["Api-Key"] = self.key, ["User-Agent"] = self.agent,
                      Accept = "application/json" }
    if self.token and method == "GET" then
        headers.Authorization = "Bearer " .. self.token
    end

    local status, body, raw
    if method == "GET" then
        local url = self.base .. path .. "?" .. M.query(params or {})
        for _ = 1, 5 do
            status, body, raw = vlc.http.get(url, headers, true)
            if status ~= 301 and status ~= 302 and status ~= 307 and status ~= 308 then
                break
            end
            local next_url = (raw or ""):match("[\r\n][Ll][Oo][Cc][Aa][Tt][Ii][Oo][Nn]:%s*([^\r\n]+)")
            if next_url and next_url:sub(1, 1) == "/" and next_url:sub(1, 2) ~= "//" then
                next_url = url:match("^https?://[^/]+") .. next_url
            end
            if not self:trusted(next_url) then return nil, "invalid_response" end
            url = next_url
        end
    else
        status, body = vlc.http.post(self.base .. path,
            self.json.encode(params or {}), "application/json",
            self.token and ("Bearer " .. self.token) or nil, headers)
    end

    if not status then return nil, "network" end
    local decoded = type(body) == "string" and self.json.decode(body) or nil
    if status < 200 or status >= 300 then
        if status == 401 then return nil, "unauthorized", decoded end
        if status == 403 then return nil, "forbidden", decoded end
        if status == 406 then return nil, "quota", decoded end
        if status == 429 then return nil, "rate_limit", decoded end
        return nil, "http_error", { status = status }
    end
    if type(decoded) ~= "table" then return nil, "invalid_response" end
    return decoded
end

function Client:login(user, password)
    self.token = nil
    self.base = (self.test_origin and self.base) or API
    local result, err = self:request("POST", "/login", { username = user, password = password })
    if not result then return nil, err end
    if type(result.token) ~= "string" or result.token == "" or result.token:find("[%c]") then
        return nil, "invalid_response"
    end
    -- the account may live on another cluster: stay on opensubtitles.com
    if result.base_url and not self.test_origin then
        local base = result.base_url
        if type(base) ~= "string" then return nil, "invalid_response" end
        if not base:match("^https://") then base = "https://" .. base end
        base = base:gsub("/+$", "")
        if not self:trusted(base) or not base:match("^https://[^/]+$") then
            return nil, "invalid_response"
        end
        self.base = base .. "/api/v1"
    end
    self.token = result.token
    -- account details, for "logged in as ..." messages
    self.account = type(result.user) == "table" and result.user or nil
    return true
end

-- rows of results, best first once passed through M.sort
function Client:search(params)
    local result, err, detail = self:request("GET", "/subtitles", params)
    if not result then return nil, err, detail end
    if type(result.data) ~= "table" then return nil, "invalid_response" end
    local rows = {}
    for _, item in ipairs(result.data) do
        local a = item.attributes
        if type(a) == "table" and type(a.files) == "table" then
            for _, file in ipairs(a.files) do
                local id = tonumber(file.file_id)
                if id and id > 0 then
                    local language = tostring(a.language or "?"):lower()
                    if not language:match("^%a%a[%a%-]*$") then language = "?" end
                    local feature = type(a.feature_details) == "table" and a.feature_details or {}
                    rows[#rows + 1] = {
                        id = id, language = language,
                        release = M.display_text(file.file_name or a.release),
                        feature = feature.feature_id, title = feature.title,
                        hash_match = a.moviehash_match == true,
                        trusted = a.from_trusted == true,
                        hearing_impaired = a.hearing_impaired == true,
                        foreign_only = a.foreign_parts_only == true,
                        ai_translated = a.ai_translated == true,
                        machine_translated = a.machine_translated == true,
                        downloads = tonumber(a.download_count) or 0,
                        rating = tonumber(a.ratings) or 0,
                    }
                end
            end
        end
    end
    return rows
end

-- best first: exact hash match, then the film the service ranked first, then the
-- user's language order, trusted uploaders, popularity
function M.sort(rows, languages)
    local priority, features, count = {}, {}, 0
    for i, code in ipairs(languages) do priority[code] = i end
    for _, row in ipairs(rows) do
        local feature = row.feature or "unknown"
        if not features[feature] then
            count = count + 1
            features[feature] = count
        end
    end
    table.sort(rows, function(a, b)
        if a.hash_match ~= b.hash_match then return a.hash_match end
        local fa, fb = features[a.feature or "unknown"], features[b.feature or "unknown"]
        if fa ~= fb then return fa < fb end
        local pa, pb = priority[a.language] or 99, priority[b.language] or 99
        if pa ~= pb then return pa < pb end
        if a.hearing_impaired ~= b.hearing_impaired then return not a.hearing_impaired end
        if a.foreign_only ~= b.foreign_only then return not a.foreign_only end
        if a.trusted ~= b.trusted then return a.trusted end
        if a.downloads ~= b.downloads then return a.downloads > b.downloads end
        return a.id < b.id
    end)
end

-- the .srt text, or nil + reason ("quota", "unauthorized", "network", ...)
function Client:download(id, user, password)
    if not self.token and user ~= "" and password ~= "" then
        local ok, err = self:login(user, password)
        if not ok then return nil, err end
    end
    local result, err, detail = self:request("POST", "/download", { file_id = id, sub_format = "srt" })
    -- tokens expire: log in again once, but never retry quota errors
    if not result and err == "unauthorized" and self.token and user ~= "" and password ~= "" then
        local ok, login_err = self:login(user, password)
        if not ok then return nil, login_err end
        result, err, detail = self:request("POST", "/download", { file_id = id, sub_format = "srt" })
    end
    if not result then return nil, err, detail end
    if not self:trusted(result.link) then return nil, "invalid_response" end

    -- signed link: send neither the token nor the key
    local status, body = vlc.http.get(result.link)
    if status ~= 200 then return nil, "network" end
    if type(body) ~= "string" or #body > 8 * 1024 * 1024
        or not body:find("%d%d:%d%d:%d%d[,.]%d+%s*%-%->%s*%d%d:%d%d:%d%d") then
        return nil, "invalid_subtitle"
    end
    return body, nil, result
end

------------------------------------------------------------------------------
-- saving
------------------------------------------------------------------------------

function M.safe_name(s)
    local name = M.trim(s):gsub("[\\/:*?\"<>|%c]", "_"):gsub("[%. ]+$", "")
    if name == "" then name = "subtitle" end
    if #name > 160 then
        name = name:sub(1, 160):gsub("[\194-\244][\128-\191]*$", "")
    end
    return name
end

-- Writes `<directory>/<stem>.<language>.srt`; never overwrites an existing file.
-- directories: tried in order. Returns the path, or nil + "save_failed".
function M.save(body, directories, stem, language, id)
    local name = M.safe_name(stem) .. "." .. M.safe_name(language)
    for _, directory in ipairs(directories) do
        if directory and directory ~= "" then
            for index = 1, 100 do
                local suffix = index == 1 and "" or ("." .. tostring(id) .. "." .. index)
                local path = directory:gsub("[\\/]+$", "") .. "/" .. name .. suffix .. ".srt"
                local probe = vlc.io.open(path, "rb")
                if probe then
                    probe:close()           -- exists: try the next name
                else
                    local file = vlc.io.open(path, "wb")
                    if not file then break end  -- directory not writable: next directory
                    local written = file:write(body)
                    file:close()            -- vlc.io's close() returns nothing
                    if written then return path end
                    vlc.io.unlink(path)
                    break
                end
            end
        end
    end
    return nil, "save_failed"
end

return M
