--[[
 flixsubs.lua: online subtitles for local videos (OpenSubtitles.com).

 A Lua interface started together with VLC (extraintf=luaintf, lua-intf=flixsubs).
 When a local video starts with no subtitle track it looks for subtitles:
   1. by the OpenSubtitles file hash (an exact match for the file),
   2. otherwise by title and year parsed from the file name
      ("Donnie.Darko.2001.REMASTERED.DC.1080p.BluRay" -> "Donnie Darko", 2001).
 Then, depending on the settings, it asks the interface (variable "flix-sub-offer",
 answered in "flix-sub-reply") or just downloads the best match, saves it next to
 the video and turns it on.

 Settings (Preferences > Interface > Main interfaces > Lua): flixsubs-api-key,
 flixsubs-user, flixsubs-password, flixsubs-languages, flixsubs-auto, flixsubs-ask.

 GPL-2.0-or-later.
]]

local api = require("flix_opensubtitles")
local json = require("dkjson")
local tmdb = require("flix_tmdb")

local VERSION = "1.0"
local libvlc = vlc.object.libvlc()

-- Effective value of a setting: command line, then saved preferences, then the default.
-- (vlc.config.get only sees the saved item, not command-line overrides, and maps an empty
-- string setting to nil.)
local function str(name)
    local value = vlc.var.inherit(nil, name)
    return value or ""
end

local function flag(name, default)
    local value = vlc.var.inherit(nil, name)
    if value == nil then return default end
    return value
end

local function log(msg)
    vlc.msg.dbg("[flixsubs] " .. msg)
end

-- on-screen message; there is no video output yet when the script starts, so no channel
-- is registered and a failure here must never stop the service
local function notify(text)
    vlc.msg.info("[flixsubs] " .. text)
    pcall(vlc.osd.message, text, nil, "bottom-left", 5000000)
end

-- user's languages in order, e.g. {"en", "id"}
local function languages()
    local list = api.languages(str("flixsubs-languages"))
    if list then return list end
    local env = (os.getenv("LANG") or ""):match("^(%a%a)")
    return { env and env:lower() or "en" }
end

local function basename(path)
    return path:match("([^/\\]+)$") or path
end

local function dirname(path)
    return path:match("^(.*)[/\\][^/\\]*$")
end

local function copy(t)
    local c = {}
    for k, v in pairs(t) do c[k] = v end
    return c
end

-- "Title (Year)", "Show - S01E02", or the title alone
local function display_name(info)
    if info.season and info.season > 0 and info.episode and info.episode > 0 then
        return string.format("%s - S%02dE%02d", info.title, info.season, info.episode)
    elseif info.year and info.year > 0 then
        return string.format("%s (%d)", info.title, info.year)
    end
    return info.title
end

local ERRORS = {
    missing_key  = "Set your OpenSubtitles API key in Preferences to get subtitles.",
    unauthorized = "OpenSubtitles refused the username or password.",
    forbidden    = "OpenSubtitles refused the request. Check the API key.",
    quota        = "OpenSubtitles download limit reached for today.",
    rate_limit   = "OpenSubtitles is busy, try again in a moment.",
    network      = "Could not reach OpenSubtitles.",
    invalid_subtitle = "OpenSubtitles returned something that is not a subtitle.",
    save_failed  = "Could not save the subtitle file.",
}

local function explain(err)
    return ERRORS[err] or ("OpenSubtitles error: " .. tostring(err))
end

------------------------------------------------------------------------------
-- search
------------------------------------------------------------------------------

-- best subtitle for the media, or nil + reason
local function find_best(client, uri, info, langs)
    local base = {
        languages = table.concat(langs, ","),
        ai_translated = "exclude",
        machine_translated = "exclude",
    }

    local rows
    -- a torrent stream (local http address): no file to hash, the IMDb id is the best key
    if info.imdb and info.imdb:match("^tt%d+$") then
        local params = copy(base)
        local digits = info.imdb:match("%d+")
        if info.season and info.season > 0 and info.episode and info.episode > 0 then
            params.parent_imdb_id = digits
            params.season_number = info.season
            params.episode_number = info.episode
        else
            params.imdb_id = digits
        end
        local found, err = client:search(params)
        if not found and err ~= "invalid_response" and err ~= "http_error" then
            return nil, err
        end
        rows = found
    end

    local hash = (not rows or #rows == 0) and not uri:match("^http://127%.0%.0%.1:") and api.hash(uri) or nil
    if hash then
        local params = copy(base)
        params.moviehash = hash
        params.moviehash_match = "only"
        local found, err = client:search(params)
        if not found and err ~= "invalid_response" and err ~= "http_error" then
            return nil, err                      -- quota / network / key problems
        end
        rows = found
    end

    if not rows or #rows == 0 then
        local params = copy(base)
        params.query = info.title:lower()
        if info.year and info.year > 0 then params.year = info.year end
        if info.season and info.season > 0 and info.episode and info.episode > 0 then
            params.season_number = info.season
            params.episode_number = info.episode
        end
        local found, err = client:search(params)
        if not found then return nil, err end
        rows = found
    end

    if #rows == 0 then return nil, "none" end
    api.sort(rows, langs)
    return rows[1]
end

------------------------------------------------------------------------------
-- download + enable
------------------------------------------------------------------------------

local function download_and_enable(client, offer)
    local user, password = str("flixsubs-user"), str("flixsubs-password")
    if user == "" or password == "" then
        notify("Set your OpenSubtitles username and password in Preferences to download subtitles.")
        return
    end

    local body, err = client:download(offer.row.id, user, password)
    if not body then
        notify(explain(err))
        return
    end

    pcall(vlc.io.mkdir, vlc.config.userdatadir() .. "/subtitles", "0700")
    local stem = basename(offer.path):gsub("%.%w+$", "")
    local dirs = { vlc.config.userdatadir() .. "/subtitles" }
    if not offer.stream then table.insert(dirs, 1, dirname(offer.path)) end
    local saved, save_err = api.save(body, dirs, stem, offer.row.language, offer.row.id)
    if not saved then
        notify(explain(save_err))
        return
    end

    vlc.player.add_subtitle(saved, true)
    notify(string.format("Subtitles added (%s): %s", offer.row.language, offer.display))
end

------------------------------------------------------------------------------
-- main loop
------------------------------------------------------------------------------

local handled = {}       -- uri -> true: searched already (or declined) in this session
local pending = nil      -- offer waiting for the interface's answer
local current, since, checked = nil, 0, true

local function new_client()
    return api.new(str("flixsubs-api-key"), VERSION, str("flixsubs-base-url"))
end

local function consider(uri)
    if handled[uri] then return end
    handled[uri] = true

    if str("flixsubs-api-key") == "" then
        log("no API key set, not looking for subtitles")
        return
    end
    local stream = uri:match("^http://127%.0%.0%.1:%d+/") ~= nil
    if not stream and not uri:match("^file://") then return end

    -- only videos that have no subtitles at all (embedded or next to the file)
    if #(vlc.player.get_video_tracks() or {}) == 0 then return end
    if #(vlc.player.get_spu_tracks() or {}) > 0 then
        log("subtitles already present")
        return
    end

    local path, info
    if stream then
        -- the interface publishes what it is streaming; without it we cannot name the movie
        local text = vlc.var.get(libvlc, "flix-stream-info")
        local data = text and text ~= "" and json.decode(text) or nil
        if type(data) ~= "table" or (data.title or "") == "" then return end
        info = { title = data.title, year = tonumber(data.year) or 0,
                 season = tonumber(data.season) or 0, episode = tonumber(data.episode) or 0,
                 imdb = data.imdb }
        local safe = (data.title:gsub("[^%w%-_ ]", ""):gsub("%s+", "."))
        if info.year > 0 then safe = safe .. "." .. info.year end
        path = vlc.config.userdatadir() .. "/subtitles/" .. safe .. ".mkv"
    else
        path = vlc.strings.make_path(uri)
        if not path then return end
        info = api.release_info(basename(path))
    end
    local client = new_client()
    local row, err = find_best(client, uri, info, languages())

    if not row then
        if err ~= "none" then notify(explain(err)) else log("no subtitles found") end
        return
    end

    local offer = { row = row, uri = uri, path = path, info = info, stream = stream,
                    display = display_name(info), expires = vlc.misc.mdate() + 90 * 1000000 }

    if flag("flixsubs-ask", true) then
        pending = offer
        vlc.var.set(libvlc, "flix-sub-offer", json.encode({
            id = row.id, uri = uri, title = offer.display, language = row.language,
            release = row.release, hash_match = row.hash_match }))
    else
        download_and_enable(client, offer)
    end
end

local function answer(reply)
    local verdict, id = tostring(reply):match("^(%a+):(%d+)$")
    if not pending or not verdict or tostring(pending.row.id) ~= id then return end
    local offer = pending
    pending = nil
    if verdict == "yes" then
        download_and_enable(new_client(), offer)
    end
end

-- TMDB artwork / synopsis service: the interface queues titles in "flix-meta-request"
local meta = nil
local meta_busy = false
local function meta_step()
    local token = str("flix-tmdb-token")
    if token == "" then return end
    local language = str("flix-meta-language")
    if not meta or meta.token ~= token or meta.language ~= (language ~= "" and language or "en-US") then
        meta = tmdb.new(token, language, str("flix-tmdb-base-url"), str("flix-tmdb-image-url"),
                        vlc.config.userdatadir() .. "/flix-meta/" .. (str("flix-tmdb-base-url") ~= "" and "test" or "tmdb"))
        meta:prepare()
    end
    local request = vlc.var.get(libvlc, "flix-meta-request")
    if request and request ~= "" then
        vlc.var.set(libvlc, "flix-meta-request", "")
        meta:enqueue(request)
    end
    -- several jobs per tick (the queue used to move one title every half second)
    local started = vlc.misc.mdate()
    local busy = false
    repeat
        local key, err = meta:step()
        if key then
            vlc.var.set(libvlc, "flix-meta-update", key)
            busy = true
        elseif err then
            log("metadata: " .. tostring(err))
            break
        else
            break
        end
    until vlc.misc.mdate() - started > 400000
    meta_busy = busy
end

local function step()
    pcall(meta_step)
    -- the interface answered a subtitle offer
    local reply = vlc.var.get(libvlc, "flix-sub-reply")
    if reply and reply ~= "" then
        vlc.var.set(libvlc, "flix-sub-reply", "")
        answer(reply)
    end
    if pending and vlc.misc.mdate() > pending.expires then pending = nil end

    if not flag("flixsubs-auto", true) then return end

    local item = vlc.player.item()
    if not item then
        current, checked = nil, true
        return
    end

    local uri = item:uri()
    if uri ~= current then
        current, since, checked = uri, vlc.misc.mdate(), false
        pending = nil
    end

    -- give the input a few seconds to create its tracks (and pick up a subtitle file)
    if not checked and vlc.misc.mdate() - since > 4000000 then
        checked = true
        consider(uri)
    end
end

log("started")
-- VLC stops a Lua interface by cancelling its thread; mwait() is a cancellation point and is
-- deliberately outside the pcall
while true do
    local ok, err = pcall(step)
    if not ok then
        vlc.msg.warn("[flixsubs] " .. tostring(err))
    end
    -- poll fast while the metadata queue is being worked through, slowly otherwise
    vlc.misc.mwait(vlc.misc.mdate() + (meta_busy and 50000 or 500000))
end
