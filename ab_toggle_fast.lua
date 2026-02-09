-- ab_toggle_fast.lua
-- Run like:
--   mpv "Encode1.mkv" --external-file="Encode2.mkv" --script=ab_toggle_fast.lua
--
-- Controls:
--   TAB  = toggle between encodes
--   1    = force first (main file)
--   2    = force second (external file)
--   Q    = hold to preview the other encode, release to go back
--
-- Notes:
--   - This method is instant because both encodes are decoded at once.
--   - Because mpv is treating the second file as an "alternate video track",
--     playback position, pause state, and seeking are always 100% locked.
--   - You CANNOT introduce an offset between them in this mode.
--     If the encodes aren't frame-aligned, use the sync script instead.

local state = {
    vid_tracks = {},
    current_idx = 1,
    hold_prev_idx = nil,
    label_for_id = {},  -- track.id -> nice label (basename of file)
}

local function basename(path)
    if not path or path == "" then return "?" end
    local clean = path:gsub("\\","/")
    local name = clean:match("([^/]+)$")
    return name or clean
end

-- We want main file first, external second.
local function sort_tracks(a, b)
    local a_ext = a["external"] and true or false
    local b_ext = b["external"] and true or false
    if a_ext == b_ext then
        return a.id < b.id
    else
        return (not a_ext) and b_ext
    end
end

local function init_tracks()
    local tracks = mp.get_property_native("track-list")
    state.vid_tracks = {}
    state.label_for_id = {}

    for _, tr in ipairs(tracks) do
        if tr.type == "video" then
            table.insert(state.vid_tracks, tr)
        end
    end

    if #state.vid_tracks < 2 then
        mp.osd_message("ERROR: expected 2 video tracks (main + --external-file).", 4)
        return
    end

    table.sort(state.vid_tracks, sort_tracks)

    -- Give each track a human label using its filename.
    for _, tr in ipairs(state.vid_tracks) do
        local nm
        if tr["external"] then
            -- mpv exposes the external file's path on external tracks.
            -- In mpv's Lua API this is usually "external-filename".
            -- I'm ~70% sure about that field name. If it's nil,
            -- we fall back to the track title or just "external".
            nm = tr["external-filename"] or tr["title"] or "external"
        else
            nm = mp.get_property("path")
        end
        state.label_for_id[tr.id] = basename(nm)
    end

    -- Start on the first (which should be the "main file")
    state.current_idx = 1
    mp.set_property_number("vid", state.vid_tracks[1].id)
    local disp = state.label_for_id[state.vid_tracks[1].id] or "Track1"
    mp.osd_message("Video " .. disp .. " active", 1.5)
end

mp.register_event("file-loaded", init_tracks)

local function set_track(idx, prefix)
    if idx < 1 or idx > #state.vid_tracks then return end
    state.current_idx = idx
    local tr = state.vid_tracks[idx]
    mp.set_property_number("vid", tr.id)

    local disp = state.label_for_id[tr.id] or ("#" .. idx)
    mp.osd_message((prefix or "") .. disp, 1.0)
end

local function toggle_track()
    if #state.vid_tracks < 2 then return end
    local new_idx = (state.current_idx == 1) and 2 or 1
    set_track(new_idx, "Switched to: ")
end

local function force_first()
    set_track(1, "Switched to: ")
end

local function force_second()
    set_track(2, "Switched to: ")
end

local function hold_compare(ev)
    if #state.vid_tracks < 2 then return end

    if ev.event == "down" then
        state.hold_prev_idx = state.current_idx
        local temp_idx = (state.current_idx == 1) and 2 or 1
        set_track(temp_idx, "Preview: ")

    elseif ev.event == "up" then
        if state.hold_prev_idx ~= nil then
            set_track(state.hold_prev_idx, "Back: ")
            state.hold_prev_idx = nil
        end
    end
end

mp.add_key_binding("TAB", "ab_toggle_fast", toggle_track)
mp.add_key_binding("1",   "ab_force_first",  force_first)
mp.add_key_binding("2",   "ab_force_second", force_second)
mp.add_key_binding("q",   "ab_hold_fast",    hold_compare, {complex = true})
