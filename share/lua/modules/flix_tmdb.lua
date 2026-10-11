--[[
 flix_tmdb.lua: movie / series information from TMDB for the Flix interface.

 Fills a cache folder (<userdata>/flix-meta) that the interface reads:
   movie/<key>.json   overview, genres, runtime, rating, IMDb id, poster and backdrop paths
   posters/, backdrops/   the images
   top10.json         the movies that are trending this week
   discover/<key>.json   search / discover results (sorted, filtered) with posters
   genres.json        TMDB genre names in the chosen language
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
        dir = (directory:gsub("[\\/]+$", ""):gsub("\\", "/")),
        queue = {},
        queued = {},
        top10_at = 0,
    }, Service)
    return self
end

function Service:path(...)
    return self.dir .. "/" .. table.concat({ ... }, "/")
end

-- vlc.io.mkdir is a plain mkdir(2): given a path whose parent is not there yet it stops with
-- ENOENT and creates nothing at all. The cache root sits two levels down, and Settings >
-- Storage > Clear deletes the whole tree, so every level is made here in order. EEXIST (17)
-- means the directory is already there, which is the usual answer and not a failure.
local function mkdirs(path)
    path = path:gsub("\\", "/")
    local prefix = path:match("^%a:") or ""            -- "D:" on Windows
    if prefix == "" and path:sub(1, 1) == "/" then
        prefix = "/"                                    -- absolute on posix
    end
    local acc = prefix
    for part in (prefix ~= "" and path:sub(#prefix + 1) or path):gmatch("[^/]+") do
        local tail = acc:sub(-1)
        if acc == "" or tail == "/" then
            acc = acc .. part
        elseif tail == ":" then
            acc = acc .. "/" .. part
        else
            acc = acc .. "/" .. part
        end
        local i_res, i_err = vlc.io.mkdir(acc, "0700")
        if i_res ~= 0 and i_err ~= 17 then
            return false, acc, i_err
        end
    end
    return true
end

-- makes the cache tree. Returns false when a directory cannot be made at all: the answers
-- can then be fetched but never saved, and that has to be told apart from a dead network.
function Service:prepare()
    self.cache_ok = true
    for _, sub in ipairs({ "", "movie", "posters", "backdrops", "discover", "detail" }) do
        local ok, path, i_err = mkdirs(sub == "" and self.dir or self:path(sub))
        if not ok then
            self.cache_ok = false
            self.cache_error = string.format("%s (error %d)", path, i_err or 0)
        end
    end
    -- the Top 10 on disk is still good after a restart: do not fetch it again at every start
    local top = self:read_json(self:path("top10.json"))
    if type(top) == "table" and tonumber(top.fetched) and top.language == self.language then
        self.top10_at = tonumber(top.fetched)
    end
    return self.cache_ok
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
    if self.blocked_until and now() < self.blocked_until then return nil, "rate_limit" end
    local status, body = vlc.http.get(url, headers)
    if not status then
        self.blocked_until = now() + 5                  -- offline: do not hammer, try again shortly
        return nil, "network"
    end
    if status == 401 then return nil, "unauthorized" end
    if status == 429 then
        self.blocked_until = now() + 10                 -- TMDB asked us to slow down
        return nil, "rate_limit"
    end
    if status >= 500 then
        self.blocked_until = now() + 5
        return nil, "http_error"
    end
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

-- details of a title (with external ids) from detail/<kind><id>.json when it is younger than 14 days,
-- else from TMDB (and saved)
function Service:cached_detail(kind, id)
    local path = self:path("detail", kind .. tostring(id) .. ".json")
    local saved = self:read_json(path)
    if type(saved) == "table" and saved.language == self.language
        and now() - (tonumber(saved.fetched) or 0) < 14 * 86400 and type(saved.data) == "table" then
        return saved.data
    end
    local d = self:get("/" .. kind .. "/" .. tostring(id),
        { language = self.language, append_to_response = "external_ids" })
    if d then
        write_file(path, json.encode({ language = self.language, fetched = now(), data = d }))
        return d
    end
    return type(saved) == "table" and saved.data or nil   -- offline: an old copy is better than none
end

-- the movies that are trending this week, with IMDb ids, into top10.json
function Service:top10()
    local trending, err = self:get("/trending/movie/week", { language = self.language })
    if not trending then return nil, err end
    local items = {}
    for _, row in ipairs(trending.results or {}) do
        if #items >= 10 then break end
        local d = self:cached_detail("movie", row.id)
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
-- discover / search / details of online titles
------------------------------------------------------------------------------

local MOVIE_SORTS = {
    ["popularity.desc"] = "popularity.desc",
    ["popularity.asc"] = "popularity.asc",
    ["date.desc"] = "primary_release_date.desc",
    ["date.asc"] = "primary_release_date.asc",
    ["rating.desc"] = "vote_average.desc",
    ["rating.asc"] = "vote_average.asc",
    ["title.asc"] = "original_title.asc",
    ["revenue.desc"] = "revenue.desc",
}
local TV_SORTS = {
    ["popularity.desc"] = "popularity.desc",
    ["popularity.asc"] = "popularity.asc",
    ["date.desc"] = "first_air_date.desc",
    ["date.asc"] = "first_air_date.asc",
    ["rating.desc"] = "vote_average.desc",
    ["rating.asc"] = "vote_average.asc",
    ["title.asc"] = "name.asc",
    ["revenue.desc"] = "popularity.desc",
}

-- sorts the items of a search page (the search endpoint cannot sort)
local function sort_items(items, sort)
    local field, direction = tostring(sort or ""):match("^(%a+)%.(%a+)$")
    field = ({ popularity = "popularity", rating = "rating", date = "year", title = "title" })[field]
    if not field then return end
    local ascending = direction == "asc"
    table.sort(items, function(a, b)
        local x, y = a[field], b[field]
        if field == "title" then x, y = tostring(x):lower(), tostring(y):lower() end
        if x == y then return (a.popularity or 0) > (b.popularity or 0) end
        if ascending then return x < y end
        return x > y
    end)
end

-- req.params: {type, query, sort, genres="28,12", year_from, year_to, min_rating, page}
-- writes discover/<key>.json {items = {...}, page, total_pages}
function Service:discover(req)
    local p = type(req.params) == "table" and req.params or {}
    local tv = p.type == "tv"
    local kind = tv and "tv" or "movie"
    local sorts = tv and TV_SORTS or MOVIE_SORTS
    local sort = sorts[p.sort] or sorts["popularity.desc"]
    local page = math.max(1, math.min(20, math.floor(tonumber(p.page) or 1)))
    local year_from, year_to = tonumber(p.year_from) or 0, tonumber(p.year_to) or 0
    local min_rating = tonumber(p.min_rating) or 0
    local genres = tostring(p.genres or ""):match("^[%d,|]+$") or ""
    local query = type(p.query) == "string" and p.query or ""

    local answer, err
    if query ~= "" then
        answer, err = self:get("/search/" .. kind, {
            query = query, language = self.language, include_adult = "false", page = page })
    else
        local date = tv and "first_air_date" or "primary_release_date"
        local params = {
            language = self.language, include_adult = "false", page = page, sort_by = sort,
            ["vote_count.gte"] = sort:match("^vote_average") and 300 or 30,
        }
        if genres ~= "" then params.with_genres = genres end
        if year_from > 0 then params[date .. ".gte"] = string.format("%04d-01-01", year_from) end
        if year_to > 0 then params[date .. ".lte"] = string.format("%04d-12-31", year_to) end
        if min_rating > 0 then params["vote_average.gte"] = min_rating end
        answer, err = self:get("/discover/" .. kind, params)
    end
    if not answer then return nil, err end

    local wanted = {}
    for id in genres:gmatch("%d+") do wanted[tonumber(id)] = true end
    local has_wanted = next(wanted) ~= nil

    local items = {}
    for _, row in ipairs(answer.results or {}) do
        local date = row.release_date or row.first_air_date or ""
        local year = tonumber(date:match("^(%d%d%d%d)")) or 0
        local keep = true
        if query ~= "" then                     -- a search cannot be filtered on the server
            if year_from > 0 and year < year_from then keep = false end
            if year_to > 0 and year > year_to then keep = false end
            if min_rating > 0 and (tonumber(row.vote_average) or 0) < min_rating then keep = false end
            if has_wanted then
                keep = false
                for _, g in ipairs(row.genre_ids or {}) do
                    if wanted[g] then keep = true break end
                end
            end
        end
        if keep then
            items[#items + 1] = {
                tmdb_id = row.id, media_type = kind,
                title = row.title or row.name, year = year,
                overview = row.overview or "", genre_ids = row.genre_ids or {},
                rating = tonumber(row.vote_average) or 0,
                popularity = tonumber(row.popularity) or 0,
                poster = self:image("posters", "w342", row.poster_path, kind .. tostring(row.id)),
            }
        end
    end
    if query ~= "" then sort_items(items, p.sort) end

    local doc = { key = req.key, fetched = now(), language = self.language, page = page,
                  total_pages = tonumber(answer.total_pages) or 1, items = items }
    if not write_file(self:path("discover", req.key .. ".json"), json.encode(doc)) then
        return nil, "save_failed"
    end
    return true
end

-- full details (IMDb id, backdrop, tagline...) of one online title into movie/<key>.json
function Service:detail(req)
    local kind = req.type == "tv" and "tv" or "movie"
    local id = tonumber(req.tmdb_id)
    if not id then return nil, "bad_request" end
    local d, e = self:get("/" .. kind .. "/" .. tostring(math.floor(id)),
        { language = self.language, append_to_response = "external_ids" })
    if not d then return nil, e end
    local record = self:record(kind, d)
    record.key = req.key
    if not write_file(self:path("movie", req.key .. ".json"), json.encode(record)) then
        return nil, "save_failed"
    end
    return true
end

-- genre names (movie + tv) in the chosen language into genres.json
function Service:genres()
    local doc = { language = self.language, fetched = now() }
    for _, kind in ipairs({ "movie", "tv" }) do
        local d, e = self:get("/genre/" .. kind .. "/list", { language = self.language })
        if not d then return nil, e end
        doc[kind] = d.genres or {}
    end
    if not write_file(self:path("genres.json"), json.encode(doc)) then return nil, "save_failed" end
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
            and req.key:match("^[%w%-_]+$") and not self.queued[req.key] and #self.queue < MAX_QUEUE then
            if req.kind == "discover" or req.kind == "detail" then
                -- the user is waiting for these: before the background lookups
                self.queued[req.key] = true
                table.insert(self.queue, 1, req)
            elseif type(req.title) == "string" and req.title ~= "" then
                self.queued[req.key] = true
                self.queue[#self.queue + 1] = req
            end
        end
    end
end

-- Does at most one piece of work (a lookup or the Top 10 refresh) per call.
-- Returns the key that changed ("top10" or a lookup key), or nil.
function Service:step()
    if self.token == "" then return nil end
    -- nothing could be saved even if the answer came: say that, instead of paying for a
    -- request whose result is thrown away and letting it look like a network failure
    if self.cache_ok == false then return nil, "cache_unavailable" end
    if self.blocked_until and now() < self.blocked_until and #self.queue > 0 then return nil end
    local req = table.remove(self.queue, 1)
    if req then
        self.queued[req.key] = nil
        local run = req.kind == "discover" and self.discover
                    or req.kind == "detail" and self.detail or self.lookup
        local ok, err = run(self, req)
        if ok then return req.key end
        if err == "rate_limit" then
            self.queue[#self.queue + 1] = req           -- try again later
            self.queued[req.key] = true
        end
        return nil, err
    end
    if not self.genres_done then
        self.genres_done = true                         -- once per session, a failure is not retried
        local ok, err = self:genres()
        if ok then return "genres" end
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
