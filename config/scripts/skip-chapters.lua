-- Offers to skip intro/recap/credits chapters, like Infuse's "Skip Recap" button.
-- When a chapter whose title matches one of the patterns starts, a prompt appears for a few seconds;
-- Enter jumps to the next chapter (or the end of the file, for trailing credits).

local mp = require "mp"
local options = require "mp.options"

local o = {
    patterns = "recap|previously|intro|opening|^op$|credits|ending|^ed$|outro",
    prompt_seconds = 10,
    key = "ENTER",
}
options.read_options(o, "skip-chapters")

local overlay = mp.create_osd_overlay("ass-events")
local hide_timer

local function matches(title)
    title = (title or ""):lower()
    for p in o.patterns:gmatch("[^|]+") do
        if title:find(p) then return true end
    end
    return false
end

local function hide()
    overlay:remove()
    mp.remove_key_binding("skip-chapter")
    if hide_timer then hide_timer:kill() hide_timer = nil end
end

local function skip()
    hide()
    local index = mp.get_property_number("chapter", -1)
    local next_ch = mp.get_property_native("chapter-list", {})[index + 2]
    if next_ch then
        mp.commandv("seek", tostring(next_ch.time), "absolute+exact")
    else
        mp.commandv("add", "chapter", "1") -- trailing credits: go to the end / next file
    end
end

local function show(title)
    local w, h = mp.get_osd_size()
    if not w or w == 0 then w, h = 1280, 720 end
    overlay.res_x, overlay.res_y = w, h
    local label = "Skip " .. title:gsub("^%l", string.upper)
    overlay.data = ("{\\an3\\pos(%d,%d)\\bord0\\shad0\\1c&HFFFFFF&\\fs%d\\b1}%s  ⏎")
        :format(w - h * 0.05, h * 0.86, math.floor(h * 0.035), label)
    overlay:update()
    mp.add_forced_key_binding(o.key, "skip-chapter", skip)
    if hide_timer then hide_timer:kill() end
    hide_timer = mp.add_timeout(o.prompt_seconds, hide)
end

mp.observe_property("chapter", "number", function(_, index)
    hide()
    if not index or index < 0 then return end
    local chapters = mp.get_property_native("chapter-list", {})
    local ch = chapters[index + 1]
    if ch and matches(ch.title) then show(ch.title) end
end)

mp.register_event("end-file", hide)
