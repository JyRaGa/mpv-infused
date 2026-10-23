-- Fetches subtitles from OpenSubtitles (REST API) when a local file has none in the preferred language.
-- Settings live in ~~/script-opts/opensubtitles.conf (api_key is required; username/password raise the daily limit).
-- Alt+o searches again on demand. Downloads are saved next to the video as "<name>.<lang>.srt".

local mp = require "mp"
local utils = require "mp.utils"
local msg = require "mp.msg"
local options = require "mp.options"
local ffi = require "ffi"

local o = {
    api_key = "",
    username = "",
    password = "",
    languages = "en",           -- OpenSubtitles language codes, comma separated, in order of preference
    match_langs = "en,eng,english", -- existing tracks with these language tags count as "already have subs"
    auto = true,                -- search automatically when no matching subtitle track exists
    proxy = "",                 -- optional HTTP proxy for all OpenSubtitles traffic, e.g. http://user:pass@host:port/
    proxy_page = "",            -- optional page to open when the proxy stops working (e.g. your proxy provider's list)
}
options.read_options(o, "opensubtitles")

local API = "https://api.opensubtitles.com/api/v1"
local USER_AGENT = "mpv-opensubtitles v1.0"
local CONF = "~/.config/mpv/script-opts/opensubtitles.conf"
local token
local proxy_page_opened = false

local function osd(text, secs)
    msg.info(text)
    mp.osd_message("OpenSubtitles: " .. text, secs or 4)
end

local function with_proxy(cmd)
    if o.proxy ~= "" then
        table.insert(cmd, 2, "--proxy")
        table.insert(cmd, 3, o.proxy)
    end
    return cmd
end

-- A dead or expired proxy shows up as a curl error naming the proxy, its CONNECT reply (e.g. 404/407), or its host.
local function proxy_failed(stderr)
    if o.proxy == "" or not stderr then return false end
    local host = o.proxy:match("@([^:/]+)") or o.proxy:match("//([^:/]+)") or "\0"
    if not (stderr:find("[Pp]roxy") or stderr:find("CONNECT") or stderr:find(host, 1, true)) then return false end
    osd("proxy isn't working - put a new one in " .. CONF .. " (proxy=http://user:pass@host:port/)", 10)
    if not proxy_page_opened and o.proxy_page ~= "" then
        proxy_page_opened = true
        mp.command_native_async({name = "subprocess", args = {"open", o.proxy_page}, playback_only = false}, function() end)
    end
    return true
end

-- OpenSubtitles hash: file size plus the 64-bit little-endian word sums of the first and last 64 KiB.
local function movie_hash(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end")
    local chunk = 65536
    if size < chunk * 2 then f:close() return nil end
    local sum = ffi.new("uint64_t", size)
    for _, offset in ipairs({0, size - chunk}) do
        f:seek("set", offset)
        local data = f:read(chunk)
        local words = ffi.cast("const uint64_t *", data)
        for i = 0, chunk / 8 - 1 do sum = sum + words[i] end
    end
    f:close()
    return bit.tohex(tonumber(sum / 0x100000000ULL), 8) .. bit.tohex(tonumber(sum % 0x100000000ULL), 8)
end

local function urlencode(s)
    return (s:gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end))
end

local function curl(args, cb)
    -- Retries cover the connection resets seen on the first request after an idle period.
    local cmd = {"curl", "-sS", "-L", "--max-time", "30", "--retry", "3", "--retry-all-errors", "--retry-delay", "1",
                 "-H", "Api-Key: " .. o.api_key,
                 "-H", "User-Agent: " .. USER_AGENT, "-H", "Accept: application/json"}
    if token then table.insert(cmd, "-H") table.insert(cmd, "Authorization: Bearer " .. token) end
    for _, a in ipairs(args) do table.insert(cmd, a) end
    mp.command_native_async({name = "subprocess", args = with_proxy(cmd), capture_stdout = true,
                             capture_stderr = true, playback_only = false}, function(_, r)
        if not r or r.status ~= 0 then
            if proxy_failed(r and r.stderr) then return end
            cb(nil, (r and r.stderr ~= "" and r.stderr) or "network error")
            return
        end
        local json = utils.parse_json(r.stdout)
        if not json then cb(nil, "unexpected reply: " .. r.stdout:sub(1, 120)) return end
        if json.message and not json.data and not json.link and not json.token then
            cb(nil, json.message) return
        end
        cb(json)
    end)
end

local function post(path, body, cb)
    curl({"-X", "POST", "-H", "Content-Type: application/json", "-d", utils.format_json(body), API .. path}, cb)
end

local function login(cb)
    if token or o.username == "" or o.password == "" then cb() return end
    post("/login", {username = o.username, password = o.password}, function(res, err)
        if res and res.token then token = res.token else msg.warn("login failed: " .. tostring(err)) end
        cb()
    end)
end

-- Guess a search title and season/episode from the file name, e.g. "Show S01E04 1080p..." -> "Show", 1, 4.
local function parse_name(path)
    local _, name = utils.split_path(path)
    name = name:gsub("%.[^.]+$", ""):gsub("[%._]", " ")
    local title, s, e = name:match("^(.-)%s*[Ss](%d+)%s*[Ee](%d+)")
    if title then return title, tonumber(s), tonumber(e) end
    title = name:match("^(.-)%s*[%(%[]?%d%d%d%d[%)%]]?%s") or name
    return title
end

local function pick(results)
    table.sort(results, function(a, b)
        local x, y = a.attributes, b.attributes
        if (x.moviehash_match or false) ~= (y.moviehash_match or false) then return x.moviehash_match == true end
        if (x.hearing_impaired or false) ~= (y.hearing_impaired or false) then return not x.hearing_impaired end
        return (x.download_count or 0) > (y.download_count or 0)
    end)
    for _, r in ipairs(results) do
        local files = r.attributes.files
        if files and files[1] then return r, files[1].file_id end
    end
end

local function save_path(video, lang)
    local dir, name = utils.split_path(video)
    local base = name:gsub("%.[^.]+$", "")
    return utils.join_path(dir, base .. "." .. lang .. ".srt")
end

local function fetch(manual)
    local path = mp.get_property("path")
    if not path or path:match("^%a[%w+.-]*://") then
        if manual then osd("only works for local files") end
        return
    end
    if o.api_key == "" then
        osd("add your api_key to ~/.config/mpv/script-opts/opensubtitles.conf", 6)
        return
    end
    path = mp.command_native({"normalize-path", path})
    local hash = movie_hash(path)
    local title, season, episode = parse_name(path)
    local q = {"languages=" .. urlencode(o.languages), "order_by=download_count"}
    if hash then table.insert(q, "moviehash=" .. hash) end
    table.insert(q, "query=" .. urlencode(title:lower()))
    if season then
        table.insert(q, "season_number=" .. season)
        table.insert(q, "episode_number=" .. episode)
    end
    table.sort(q) -- the API redirects unless parameters are alphabetical
    osd("searching...", 30)
    login(function()
        curl({API .. "/subtitles?" .. table.concat(q, "&")}, function(res, err)
            if not res then osd("search failed: " .. err) return end
            if not res.data or #res.data == 0 then osd("no subtitles found") return end
            local best, file_id = pick(res.data)
            if not file_id then osd("no downloadable subtitles found") return end
            post("/download", {file_id = file_id, sub_format = "srt"}, function(dl, derr)
                if not dl or not dl.link then osd("download failed: " .. tostring(derr)) return end
                local lang = best.attributes.language or "en"
                local out = save_path(path, lang)
                mp.command_native_async({name = "subprocess", playback_only = false, capture_stderr = true,
                                         args = with_proxy({"curl", "-sS", "-L", "--max-time", "60", "--retry", "3",
                                                 "--retry-all-errors", "--retry-delay", "1", "-o", out, dl.link})},
                    function(_, r)
                        if not r or r.status ~= 0 then
                            if not proxy_failed(r and r.stderr) then osd("could not save subtitle") end
                            return
                        end
                        -- Reject anything that isn't an SRT (e.g. an ISP block page served in its place).
                        local f = io.open(out, "rb")
                        local head = f and f:read(4096) or ""
                        if f then f:close() end
                        if not head:find("%d%d:%d%d:%d%d[,.]%d+%s*%-%->") then
                            os.remove(out)
                            osd("download was not a subtitle file (blocked by your network?)", 6)
                            return
                        end
                        mp.commandv("sub-add", out, "select", best.attributes.release or "OpenSubtitles", lang)
                        local note = best.attributes.moviehash_match and "exact match" or "best guess"
                        osd(("loaded (%s), %s downloads left today"):format(note, tostring(dl.remaining)))
                    end)
            end)
        end)
    end)
end

local function has_wanted_sub()
    local wanted = {}
    for l in o.match_langs:gmatch("[^,%s]+") do wanted[l:lower()] = true end
    for _, t in ipairs(mp.get_property_native("track-list", {})) do
        if t.type == "sub" and ((t.lang and wanted[t.lang:lower()])
                or (t.title and t.title:lower():find("english", 1, true))) then
            return true
        end
    end
    return false
end

mp.register_event("file-loaded", function()
    if o.auto and not has_wanted_sub() then fetch(false) end
end)

mp.add_key_binding("Alt+o", "download", function() fetch(true) end)
