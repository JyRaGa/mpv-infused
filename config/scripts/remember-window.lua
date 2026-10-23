-- Remembers the window's size and position between sessions.
-- mpv can't report its own window position on macOS, so ~~/bin/mpv-winbounds reads it from the window server.
-- The saved value is written to ~~/window-geometry.conf, which mpv.conf includes at startup.

local utils = require "mp.utils"

local helper = mp.command_native({"expand-path", "~~/bin/mpv-winbounds"})
local out_file = mp.command_native({"expand-path", "~~/window-geometry.conf"})
local pid = tostring(utils.getpid())
local last

-- Saved whenever the window changes, so it survives however mpv exits.
local function sample()
    if mp.get_property_bool("fullscreen") or mp.get_property_bool("window-minimized") then return end
    local r = mp.command_native({name = "subprocess", args = {helper, pid},
                                 capture_stdout = true, playback_only = false})
    local g = r.status == 0 and r.stdout:match("^(%d+x%d+%+%d+%+%d+)")
    if not g or g == last then return end
    last = g
    local f = io.open(out_file, "w")
    if f then
        f:write("# Written by scripts/remember-window.lua\ngeometry=" .. g .. "\n")
        f:close()
    end
end

-- The first sample is the restored window itself, so record it without rewriting the file.
mp.add_timeout(1, function()
    local r = mp.command_native({name = "subprocess", args = {helper, pid},
                                 capture_stdout = true, playback_only = false})
    last = r.status == 0 and r.stdout:match("^(%d+x%d+%+%d+%+%d+)") or nil
    mp.add_periodic_timer(2, sample)
end)
