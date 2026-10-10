--[[
 FlixSubs.lua: "Find Subtitles Online..." (OpenSubtitles.com), the manual search window.

 Searches by the file hash first and then by the title and year parsed from the file
 name (you can edit both), lists the results, and downloads the chosen one next to the video.
 The account is set in Preferences > Interface > Main interfaces > Lua (flixsubs-*).

 The search and download code is shared with the automatic service (flix_opensubtitles).
 The window layout follows the idea of VLSub and PowerVLSub (GPL).

 GPL-2.0-or-later.
]]

local api = require("flix_opensubtitles")

local VERSION = "1.0"

function descriptor()
    return {
        title = "Find Subtitles Online...",
        shortdesc = "FlixSubs",          -- the interface finds the extension by this name
        version = VERSION,
        author = "Flix",
        capabilities = {},
    }
end

local LANGUAGES = {
    { "en", "English" }, { "id", "Indonesian" }, { "es", "Spanish" }, { "fr", "French" },
    { "de", "German" }, { "it", "Italian" }, { "pt-br", "Portuguese (Brazil)" },
    { "pt-pt", "Portuguese" }, { "nl", "Dutch" }, { "ru", "Russian" }, { "ja", "Japanese" },
    { "ko", "Korean" }, { "zh-cn", "Chinese" }, { "ar", "Arabic" }, { "tr", "Turkish" },
    { "pl", "Polish" }, { "sv", "Swedish" }, { "th", "Thai" }, { "vi", "Vietnamese" },
}

local dlg = nil
local widgets = {}
local results = {}          -- list index -> row
local order = {}            -- languages as listed in the dropdown
local last_path = nil

local function setting(name)
    return vlc.var.inherit(nil, name) or ""
end

local function say(text)
    if widgets.status then widgets.status:set_text(text) end
    if dlg then dlg:update() end
end

local function current_media()
    local item
    if vlc.player and vlc.player.item then
        local ok, value = pcall(vlc.player.item)
        if ok then item = value end
    end
    if not item and vlc.input and vlc.input.item then
        local ok, value = pcall(vlc.input.item)
        if ok then item = value end
    end
    if not item then return nil end
    local uri = item:uri()
    if not uri then return nil end
    return uri, uri:match("^file://") and vlc.strings.make_path(uri) or nil
end

local function basename(path)
    return (path or ""):match("([^/\\]+)$") or ""
end

local function dirname(path)
    return (path or ""):match("^(.*)[/\\][^/\\]*$")
end

local function user_languages()
    local list = api.languages(setting("flixsubs-languages"))
    if list then return list end
    local env = (os.getenv("LANG") or ""):match("^(%a%a)")
    return { env and env:lower() or "en" }
end

local function new_client()
    return api.new(setting("flixsubs-api-key"), VERSION, setting("flixsubs-base-url"))
end

local ERRORS = {
    missing_key = "Set your OpenSubtitles API key in Preferences first.",
    unauthorized = "OpenSubtitles refused the username or password.",
    forbidden = "OpenSubtitles refused the request. Check the API key.",
    quota = "OpenSubtitles download limit reached for today.",
    rate_limit = "OpenSubtitles is busy, try again in a moment.",
    network = "Could not reach OpenSubtitles.",
    invalid_subtitle = "OpenSubtitles returned something that is not a subtitle.",
    save_failed = "Could not save the subtitle file.",
}

local function explain(err)
    return ERRORS[err] or ("OpenSubtitles error: " .. tostring(err))
end

------------------------------------------------------------------------------
-- actions
------------------------------------------------------------------------------

local function language_code()
    local entry = order[tonumber((widgets.language:get_value()))]
    return entry and entry[1] or "en"
end

local function show_results(rows)
    results = rows
    widgets.list:clear()
    for index, row in ipairs(rows) do
        local flags = {}
        if row.hash_match then flags[#flags + 1] = "exact match" end
        if row.hearing_impaired then flags[#flags + 1] = "HI" end
        if row.trusted then flags[#flags + 1] = "trusted" end
        local text = string.format("[%s] %s  (%d downloads%s)", row.language, row.release,
            row.downloads, #flags > 0 and (", " .. table.concat(flags, ", ")) or "")
        widgets.list:add_value(text, index)
    end
    dlg:update()
end

local function search()
    local uri = current_media()
    local client = new_client()
    local language = language_code()
    local base = { languages = language, ai_translated = "exclude", machine_translated = "exclude" }
    local rows

    say("Searching...")

    local title = api.trim(widgets.title:get_text())
    local year = tonumber(widgets.year:get_text())

    if uri and uri:match("^file://") and widgets.by_file_hash then
        local hash = api.hash(uri)
        if hash then
            local params = {}
            for k, v in pairs(base) do params[k] = v end
            params.moviehash, params.moviehash_match = hash, "only"
            local found = client:search(params)
            if found and #found > 0 then rows = found end
        end
    end

    if not rows then
        if title == "" then
            say("Type a title to search for.")
            return
        end
        local params = {}
        for k, v in pairs(base) do params[k] = v end
        params.query = title:lower()
        if year and year > 0 then params.year = year end
        local season, episode = tonumber(widgets.season:get_text()), tonumber(widgets.episode:get_text())
        if season and season > 0 and episode and episode > 0 then
            params.season_number, params.episode_number = season, episode
        end
        local found, err = client:search(params)
        if not found then
            say(explain(err))
            return
        end
        rows = found
    end

    if #rows == 0 then
        show_results({})
        say("No subtitles found. Try another title or language.")
        return
    end
    api.sort(rows, { language })
    show_results(rows)
    say(string.format("%d subtitles found. Select one and press Download.", #rows))
end

local function download()
    local selection = widgets.list:get_selection()
    local index = nil
    for key in pairs(selection or {}) do index = key end
    local row = index and results[tonumber(index)]
    if not row then
        say("Select a subtitle first.")
        return
    end

    local user, password = setting("flixsubs-user"), setting("flixsubs-password")
    if user == "" or password == "" then
        say("Set your OpenSubtitles username and password in Preferences first.")
        return
    end

    say("Downloading...")
    local body, err = new_client():download(row.id, user, password)
    if not body then
        say(explain(err))
        return
    end

    local uri, path = current_media()
    local stem = path and basename(path):gsub("%.%w+$", "") or api.trim(widgets.title:get_text())
    local dirs = {}
    if path then dirs[#dirs + 1] = dirname(path) end
    dirs[#dirs + 1] = vlc.config.userdatadir() .. "/subtitles"
    local saved, save_err = api.save(body, dirs, stem, row.language, row.id)
    if not saved then
        say(explain(save_err))
        return
    end
    last_path = saved

    local added = false
    if vlc.player and vlc.player.add_subtitle then
        added = pcall(vlc.player.add_subtitle, saved, true)
    end
    if not added and vlc.input and vlc.input.add_subtitle then
        added = pcall(vlc.input.add_subtitle, saved)
    end
    say(added and ("Subtitles added: " .. basename(saved)) or ("Saved to " .. saved))
end

-- an error in a button handler must show up in the window, not vanish
local function guarded(fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then
            vlc.msg.warn("[FlixSubs] " .. tostring(err))
            say("Error: " .. tostring(err))
        end
    end
end

------------------------------------------------------------------------------
-- window
------------------------------------------------------------------------------

local function build()
    dlg = vlc.dialog("Find Subtitles Online")

    local uri, path = current_media()
    local info = api.release_info(path and basename(path):gsub("%.%w+$", "") or "")

    dlg:add_label("<b>Title</b>", 1, 1, 1, 1)
    widgets.title = dlg:add_text_input(info.title or "", 2, 1, 3, 1)
    dlg:add_label("<b>Year</b>", 1, 2, 1, 1)
    widgets.year = dlg:add_text_input((info.year and info.year > 0) and tostring(info.year) or "", 2, 2, 1, 1)
    dlg:add_label("<b>Season / Episode</b>", 3, 2, 1, 1)
    widgets.season = dlg:add_text_input((info.season and info.season > 0) and tostring(info.season) or "", 4, 2, 1, 1)
    widgets.episode = dlg:add_text_input((info.episode and info.episode > 0) and tostring(info.episode) or "", 5, 2, 1, 1)

    dlg:add_label("<b>Language</b>", 1, 3, 1, 1)
    widgets.language = dlg:add_dropdown(2, 3, 2, 1)
    -- the user's own languages first, so the dropdown opens on the right one
    order = {}
    for _, code in ipairs(user_languages()) do
        for _, entry in ipairs(LANGUAGES) do
            if entry[1] == code then order[#order + 1] = entry end
        end
    end
    for _, entry in ipairs(LANGUAGES) do
        local listed = false
        for _, other in ipairs(order) do if other == entry then listed = true end end
        if not listed then order[#order + 1] = entry end
    end
    for index, entry in ipairs(order) do
        widgets.language:add_value(entry[2] .. " (" .. entry[1] .. ")", index)
    end
    dlg:add_button("Search", guarded(search), 4, 3, 2, 1)
    widgets.by_file_hash = uri and uri:match("^file://") and true or false

    widgets.list = dlg:add_list(1, 4, 5, 6)
    dlg:add_button("Download", guarded(download), 1, 10, 2, 1)
    widgets.status = dlg:add_label("", 3, 10, 3, 1)

    if not setting("flixsubs-api-key") or setting("flixsubs-api-key") == "" then
        widgets.status:set_text("Set your OpenSubtitles API key, username and password in Preferences first.")
    end
    dlg:show()
end

function activate()
    build()
end

function deactivate()
    if dlg then dlg:hide() end
    dlg, widgets, results = nil, {}, {}
end

function close()
    vlc.deactivate()
end

function input_changed() end
function meta_changed() end
