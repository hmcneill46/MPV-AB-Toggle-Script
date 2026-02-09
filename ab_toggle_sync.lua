-- ab_toggle_sync.lua
-- Run like:
--   mpv "Encode1.mkv" "Encode2.mkv" --script=ab_toggle_sync.lua
--
-- Controls:
--   TAB  = toggle between encodes (keeps sync using your marks)
--   1    = force-load file #1
--   2    = force-load file #2
--   s    = mark sync point for CURRENT file at current frame/time
--   i    = show sync status (what's marked, etc.)
--   q    = hold to temporarily preview the other encode, release to snap back
--
-- Notes:
--   - This mode *reloads* the file on each toggle. So you will see a tiny flicker.
--   - BUT you can line up two not-quite-identical encodes and keep them matched.
--   - Audio will switch with the video in this mode.
--
-- How sync math works:
--   Suppose file1 mark = T1, file2 mark = T2, and you're at P now in file1.
--   We treat (P - T1) as "global time". When going to file2 we jump to (global + T2).
--   That keeps the marked frame aligned across toggles.

local state = {
    files = {},            -- { "Encode1.mkv", "Encode2.mkv" }
    current_idx = 1,       -- which file is currently loaded (1 or 2)
    ref_time = { [1]=nil, [2]=nil },  -- sync marks per file
    hold_prev_idx = nil,
    pending_switch = nil,  -- data we apply right after file loads
    initialised = false,
}

local function basename(path)
    if not path or path == "" then return "?" end
    local clean = path:gsub("\\","/")
    local name = clean:match("([^/]+)$")
    return name or clean
end

-- Figure out which two files we're comparing.
-- We do this once, at first file load, by reading the playlist.
local function init_state_from_playlist()
    if state.initialised then return end

    local pl = mp.get_property_native("playlist")
    for _, item in ipairs(pl) do
        if #state.files < 2 then
            table.insert(state.files, item.filename)
        end
    end

    if #state.files < 2 then
        mp.osd_message("WARNING: I expected 2 files on the mpv command line.", 4)
    end

    -- Set current_idx based on which file is *actually playing right now*
    local cur_path = mp.get_property("path")
    state.current_idx = 1
    for i, f in ipairs(state.files) do
        if f == cur_path then
            state.current_idx = i
        end
    end

    state.initialised = true

    mp.osd_message("Loaded " .. basename(cur_path), 1.2)
end

-- Given we're currently on cur_idx at cur_pos,
-- and we want to switch to new_idx,
-- return what time-pos we *should* jump to in new_idx
-- using the sync marks if both sides are marked.
local function compute_target_pos(cur_idx, new_idx, cur_pos)
    local cur_mark = state.ref_time[cur_idx]
    local new_mark = state.ref_time[new_idx]

    if cur_mark and new_mark then
        -- global_t is "time since the sync frame"
        local global_t = cur_pos - cur_mark
        local desired = new_mark + global_t
        if desired < 0 then desired = 0 end
        return desired
    else
        -- No sync info yet. Just go to same timestamp.
        return cur_pos
    end
end

-- Actually perform the file switch.
local function perform_switch(new_idx, target_pos, paused, msg)
    state.pending_switch = {
        idx = new_idx,
        tpos = target_pos,
        paused = paused,
        msg = msg,
    }
    state.current_idx = new_idx
    mp.commandv("loadfile", state.files[new_idx], "replace")
end

-- After *any* file load (initial load or after we call loadfile),
-- we may need to:
--   - finalise init
--   - if this was a pending switch, jump to target_pos and restore pause state
local function on_file_loaded()
    if not state.initialised then
        init_state_from_playlist()
    end

    if state.pending_switch then
        local sw = state.pending_switch
        state.pending_switch = nil

        -- Seek to desired timestamp in the newly loaded file
        if sw.tpos then
            mp.set_property_number("time-pos", sw.tpos)
        end

        -- Restore pause/play
        if sw.paused ~= nil then
            mp.set_property_bool("pause", sw.paused)
        end

        -- On-screen message
        if sw.msg then
            mp.osd_message(sw.msg, 1.2)
        end
    else
        -- Just loaded the first file at start
        local cur_name = basename(mp.get_property("path"))
        mp.osd_message("Loaded " .. cur_name, 1.2)
    end
end

mp.register_event("file-loaded", on_file_loaded)

-- Core helper to switch to a particular file index.
-- is_peek just changes the wording in the OSD.
local function switch_to(new_idx, is_peek)
    if not state.files[new_idx] then return end
    if new_idx == state.current_idx then return end

    local cur_idx = state.current_idx
    local cur_pos = mp.get_property_number("time-pos", 0)
    local paused = mp.get_property_bool("pause")

    local target_pos = compute_target_pos(cur_idx, new_idx, cur_pos)

    local prefix = is_peek and "Preview: " or "Switched to: "
    local msg = prefix .. basename(state.files[new_idx])

    perform_switch(new_idx, target_pos, paused, msg)
end

-- Toggle between file #1 and file #2.
local function toggle_track()
    if #state.files < 2 then return end
    local other = (state.current_idx == 1) and 2 or 1
    switch_to(other, false)
end

-- Force jump to file #1 or file #2 directly.
local function force_first()
    if state.current_idx ~= 1 then
        switch_to(1, false)
    end
end

local function force_second()
    if state.current_idx ~= 2 then
        switch_to(2, false)
    end
end

-- Mark sync point for whatever file is currently loaded.
-- This stores the current timestamp as "this is the reference frame".
local function mark_sync()
    local pos = mp.get_property_number("time-pos", 0)
    state.ref_time[state.current_idx] = pos

    local fname = basename(state.files[state.current_idx] or ("#" .. state.current_idx))
    mp.osd_message(
        "Marked sync for " .. fname .. " @ " .. string.format("%.3fs", pos),
        1.5
    )
end

-- Show current status: which file is active, and both sync marks.
local function show_status()
    local msg = "A/B status:\n"
    for i, f in ipairs(state.files) do
        local rt = state.ref_time[i]
        msg = msg
            .. i .. ": " .. basename(f)
            .. "  sync=" .. (rt and string.format("%.3fs", rt) or "—")
            .. (i == state.current_idx and "  [ACTIVE]\n" or "\n")
    end
    mp.osd_message(msg, 3)
end

-- Hold-to-peek (press and hold q).
-- On key down: jump to the other file (preview).
-- On key up: jump back.
local function hold_compare(ev)
    if #state.files < 2 then return end

    if ev.event == "down" then
        state.hold_prev_idx = state.current_idx
        local other = (state.current_idx == 1) and 2 or 1
        switch_to(other, true)

    elseif ev.event == "up" then
        if state.hold_prev_idx ~= nil then
            switch_to(state.hold_prev_idx, true)
            state.hold_prev_idx = nil
        end
    end
end

-- Key bindings
mp.add_key_binding("TAB", "ab_toggle_sync", toggle_track)
mp.add_key_binding("1",   "ab_force_first",  force_first)
mp.add_key_binding("2",   "ab_force_second", force_second)
mp.add_key_binding("s",   "ab_mark_sync",    mark_sync)
mp.add_key_binding("i",   "ab_show_status",  show_status)
mp.add_key_binding("q",   "ab_hold_sync",    hold_compare, {complex = true})
