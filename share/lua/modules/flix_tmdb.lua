--[[
 flix_tmdb.lua: movie / series information from TMDB for the Flix interface.

 Fills a cache folder (<userdata>/flix-meta) that the interface reads:
   movie/<key>.json   overview, genres, runtime, rating, IMDb id, poster and backdrop paths
   posters/, backdrops/   the images
   top10.json         the movies that are trending this week
 The interface asks for titles through the libvlc variable "flix-meta-request" and is told
 about new data through "flix-meta-update" (see flixsubs.lua, which drives this module).

 This product uses the TMDB API but is not endorsed or certified by TMDB.

 GPL-2.0-or-later.
]]

local M = {}
local Service = {}
Service.__index = Service

local API = "https://api.themoviedb.org/3"
local IMAGES = "https://image.tmdb.org/t/p"
local TOP10_AGE = 12 * 3600
local MAX_QUEUE = 400

local json = require("dkjson")
local os_api = require("flix_opensubtitles")

local function now()
    return os.time()
end

local function normalize(s)
    s = tostring(s or ""):lower():gsub("&", " and "):gsub("[^%w]+", " ")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end
M.normalize = normalize

-- directory: where the cache lives. The service creates the sub folders.
function M.new(token, language, base, image_base, directory)
    local self = setmetatable({
        token = token or "",
        language = (language and language ~= "") and language or "en-US",
        base = (base and base ~= "") and base or API,
        images = (image_base and image_base ~= "") and image_base or IMAGES,
        dir = directory:gsub("[\\/]+$", ""),
        queue = {},
        queued = {},
        top10_at = 0,
    }, Service)
    return self
end

function Service:path(...)
    return self.dir .. "/" .. table.concat({ ... }, "/")
end

function Service:prepare()
    for _, sub in ipairs({ "", "movie", "posters", "backdrops" }) do
        pcall(vlc.io.mkdir, sub == "" and self.dir or self:path(sub), "0700")
    end
end

local function read_file(path)
    local f = vlc.io.open(path, "rb")
    if not f then return nil end
    local data = f:read(8 * 1024 * 1024)
    f:close()
    return data
end

local function write_file(path, data)
    local f = vlc.io.open(path, "wb")
    if not f then return false end
    local ok = f:write(data)
    f:close()
    return ok and true or false
end

function Service:read_json(path)
    local data = read_file(path)
    if not data then return nil end
    return json.decode(data)
end

------------------------------------------------------------------------------
-- http
------------------------------------------------------------------------------

-- decoded JSON, or nil + reason
function Service:get(path, params)
    if self.token == "" then return nil, "missing_token" end
    params = params or {}
    local headers = { Accept = "application/json" }
    if self.token:match("^%x+$") and #self.token == 32 then
        params.api_key = self.token                     -- v3 API key
    else
        headers.Authorization = "Bearer " .. self.token -- v4 read access token
    end
    local url = self.base .. path .. "?" .. os_api.query(params)
    local status, body = vlc.http.get(url, headers)
    if not status then return nil, "network" end
    if status == 401 then return nil, "unauthorized" end
    if status == 429 then return nil, "rate_limit" end
    if status < 200 or status >= 300 then return nil, "http_error" end
    local decoded = type(body) == "string" and json.decode(body) or nil
    if type(decoded) ~= "table" then return nil, "invalid_response" end
    return decoded
end

-- saves https://image.tmdb.org/t/p/<size><file> as <folder>/<id>.jpg; returns the relative path
function Service:image(folder, size, file, id)
    if type(file) ~= "string" or not file:match("^/[%w%._%-]+$") then return nil end
    local relative = folder .. "/" .. tostring(id) .. ".jpg"
    local path = self:path(folder, tostring(id) .. ".jpg")
    local existing = vlc.io.open(path, "rb")
    if existing then
        existing:close()
        return relative
    end
    local status, body = vlc.http.get(self.images .. "/" .. size .. file)
    if status ~= 200 or type(body) ~= "string" or #body < 200 or #body > 8 * 1024 * 1024 then
        return nil
    end
    if not write_file(path, body) then return nil end
    return relative
end

------------------------------------------------------------------------------
-- lookup
------------------------------------------------------------------------------

local function pick(results, title)
    local wanted = normalize(title)
    local first
    for _, row in ipairs(results or {}) do
        first = first or row
        if normalize(row.title or row.name) == wanted
            or normalize(row.original_title or row.original_name) == wanted then
            return row
        end
    end
    return first
end

local function genre_names(list)
    local names = {}
    for _, g in ipairs(list or {}) do
        if type(g.name) == "string" then names[#names + 1] = g.name end
    end
    return names
end

-- turns a /movie/{id} or /tv/{id} answer into the cache record
function Service:record(kind, d)
    local runtime = tonumber(d.runtime)
    if not runtime and type(d.episode_run_time) == "table" then
        runtime = tonumber(d.episode_run_time[1])
    end
    local date = d.release_date or d.first_air_date or ""
    local ids = d.external_ids or {}
    local id = tostring(d.id)
    return {
        found = true,
        tmdb_id = d.id,
        media_type = kind,
        title = d.title or d.name,
        year = tonumber(date:match("^(%d%d%d%d)")) or 0,
        overview = d.overview or "",
        tagline = d.tagline or "",
        genres = genre_names(d.genres),
        runtime = runtime or 0,
        rating = tonumber(d.vote_average) or 0,
        imdb_id = d.imdb_id or ids.imdb_id or "",
        poster = self:image("posters", "w342", d.poster_path, kind .. id),
        backdrop = self:image("backdrops", "w780", d.backdrop_path, kind .. id),
        language = self.language,
        fetched = now(),
    }
end

-- one request {key, title, year, season, episode}: writes movie/<key>.json
function Service:lookup(req)
    local tv = (tonumber(req.season) or 0) > 0 and (tonumber(req.episode) or 0) > 0
    local kind = tv and "tv" or "movie"
    local year = tonumber(req.year) or 0
    local base = { query = req.title, language = self.language, include_adult = "false" }

    local result, err = nil, nil
    local function search(with_year)
        local params = {}
        for k, v in pairs(base) do params[k] = v end
        if with_year and year > 0 then
            params[tv and "first_air_date_year" or "year"] = year
        end
        local found, e = self:get("/search/" .. kind, params)
        if not found then return nil, e end
        return found.results or {}
    end

    local rows
    rows, err = search(true)
    if err then return nil, err end
    result = pick(rows, req.title)
    if not result and year > 0 then
        -- the year in a file name is not always right: accept an exact title only
        rows, err = search(false)
        if err then return nil, err end
        local wanted = normalize(req.title)
        for _, row in ipairs(rows) do
            if normalize(row.title or row.name) == wanted then result = row break end
        end
    end

    local record
    if result then
        local d, e = self:get("/" .. kind .. "/" .. tostring(result.id),
            { language = self.language, append_to_response = "external_ids" })
        if not d then return nil, e end
        if (d.overview or "") == "" and self.language:sub(1, 2) ~= "en" then
            local en = self:get("/" .. kind .. "/" .. tostring(result.id), { language = "en-US" })
            if en then d.overview = en.overview or ""; d.tagline = d.tagline or en.tagline end
        end
        record = self:record(kind, d)
    else
        record = { found = false, fetched = now(), language = self.language }
    end
    record.key = req.key
    if not write_file(self:path("movie", req.key .. ".json"), json.encode(record)) then
        return nil, "save_failed"
    end
    return true
end

-- the movies that are trending this week, with IMDb ids, into top10.json
function Service:top10()
    local trending, err = self:get("/trending/movie/week", { language = self.language })
    if not trending then return nil, err end
    local items = {}
    for _, row in ipairs(trending.results or {}) do
        if #items >= 10 then break end
        local d = self:get("/movie/" .. tostring(row.id),
            { language = self.language, append_to_response = "external_ids" })
        if d then
            local r = self:record("movie", d)
            items[#items + 1] = {
                rank = #items + 1, tmdb_id = d.id, title = r.title, year = r.year,
                overview = r.overview, genres = r.genres, runtime = r.runtime,
                rating = r.rating, imdb_id = r.imdb_id, poster = r.poster, backdrop = r.backdrop,
            }
        end
    end
    if #items == 0 then return nil, "invalid_response" end
    local doc = { fetched = now(), language = self.language, items = items }
    if not write_file(self:path("top10.json"), json.encode(doc)) then return nil, "save_failed" end
    self.top10_at = now()
    return true
end

------------------------------------------------------------------------------
-- queue
------------------------------------------------------------------------------

-- adds the requests the interface made (a JSON list) to the queue
function Service:enqueue(text)
    local list = json.decode(text)
    if type(list) ~= "table" then return end
    for _, req in ipairs(list) do
        if type(req) == "table" and type(req.key) == "string"
            and req.key:match("^[%w%-_]+$") and type(req.title) == "string"
            and req.title ~= "" and not self.queued[req.key] and #self.queue < MAX_QUEUE then
            self.queued[req.key] = true
            self.queue[#self.queue + 1] = req
        end
    end
end

-- Does at most one piece of work (a lookup or the Top 10 refresh) per call.
-- Returns the key that changed ("top10" or a lookup key), or nil.
function Service:step()
    if self.token == "" then return nil end
    local req = table.remove(self.queue, 1)
    if req then
        self.queued[req.key] = nil
        local ok, err = self:lookup(req)
        if ok then return req.key end
        if err == "rate_limit" then
            self.queue[#self.queue + 1] = req           -- try again later
            self.queued[req.key] = true
        end
        return nil, err
    end
    if now() - self.top10_at > TOP10_AGE then
        self.top10_at = now() - TOP10_AGE + 600         -- failed: retry in 10 minutes
        local ok, err = self:top10()
        if ok then return "top10" end
        return nil, err
    end
end

return M
