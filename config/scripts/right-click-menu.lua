-- Right-click menu for the video window (mpv's built-in context_menu script draws it).
-- The macOS menu bar can't be extended by scripts, so extra actions like the subtitle search live here.

local mp = require "mp"

local function sub_tracks()
    local items = {}
    for _, t in ipairs(mp.get_property_native("track-list", {})) do
        if t.type == "sub" then
            local name = t.title or t.lang or ("Track " .. t.id)
            if t.title and t.lang then name = t.title .. " (" .. t.lang .. ")" end
            items[#items + 1] = {title = name, cmd = "set sid " .. t.id, state = t.selected and {"checked"} or {}}
        end
    end
    return items
end

local function build()
    local tracks = sub_tracks()
    local subs = {
        {title = "Search Subtitles Online", cmd = "script-binding opensubtitles/download", shortcut = "Alt+O"},
        {type = "separator"},
        {title = "Off", cmd = "set sid no", state = mp.get_property("sid") == "no" and {"checked"} or {}},
    }
    for _, t in ipairs(tracks) do subs[#subs + 1] = t end
    local paused = mp.get_property_bool("pause")
    mp.set_property_native("menu-data", {
        {title = paused and "Play" or "Pause", cmd = "cycle pause", shortcut = "Space"},
        {title = "Fullscreen", cmd = "cycle fullscreen", shortcut = "F"},
        {type = "separator"},
        {title = "Subtitles", type = "submenu", submenu = subs},
        {title = "Search Subtitles Online", cmd = "script-binding opensubtitles/download", shortcut = "Alt+O"},
        {title = "Next Audio Track", cmd = "cycle audio"},
        {type = "separator"},
        {title = "Skip to Next Chapter", cmd = "add chapter 1"},
        {title = "Float on Top", cmd = "cycle ontop",
         state = mp.get_property_bool("ontop") and {"checked"} or {}},
    })
end

mp.observe_property("track-list", "native", build)
mp.observe_property("sid", "native", build)
mp.observe_property("pause", "bool", build)
mp.observe_property("ontop", "bool", build)

-- macOS has no native context menu, so ask the built-in context_menu script to draw it.
mp.add_key_binding("MBTN_RIGHT", "open-menu", function() mp.commandv("script-message-to", "context_menu", "open") end)
