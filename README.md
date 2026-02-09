# mpv A/B Toggle Scripts (Instant + Sync)

Two tiny mpv Lua scripts for A/B testing two encodes of the *same* video with quick switching.

* **`ab_toggle_fast.lua`**: *instant* switching (both encodes decoded at once) using `--external-file` as an alternate video track.
* **`ab_toggle_sync.lua`**: *sync-aware* switching (reloads files on toggle) that lets you align slightly different encodes via marked sync points.

---

## Requirements

* mpv with Lua scripting enabled (standard mpv builds support this)
* Two video files of the same content (ideally same cut / same episode)

Put the `.lua` files in the repo root (or wherever you like) and pass them to mpv with `--script=...`.

---

## 1) Instant A/B (fast, locked playback): `ab_toggle_fast.lua`

### What it’s for

Use this when both encodes are **frame-aligned** and you want **zero-flicker** switching.

Because mpv treats the `--external-file` video as an alternate track:

* playback position stays **perfectly locked**
* pausing/playing/seeking stays **perfectly locked**
* switching is **instant**

### Run

```bash
mpv "Encode1.mkv" --external-file="Encode2.mkv" --script=ab_toggle_fast.lua
```

### Controls

* `TAB` = toggle between encodes
* `1` = force first (main file)
* `2` = force second (external file)
* `Q` = hold to preview the other encode, release to go back

### Limitations (important)

* You **cannot** introduce an offset between them in this mode.
* If the encodes aren’t frame-perfectly aligned (different intros, trims, ads, etc.), use the **sync** script instead.

---

## 2) Sync A/B (works even if not perfectly aligned): `ab_toggle_sync.lua`

### What it’s for

Use this when the two files are *almost* the same, but:

* one has a slightly different cut
* one starts a bit earlier/later
* there’s a timing drift or offset you want to correct

This mode **reloads** the video on each switch (so you’ll see a tiny flicker), but it can keep them aligned using **your sync marks**.

### Run

```bash
mpv "Encode1.mkv" "Encode2.mkv" --script=ab_toggle_sync.lua
```

### Controls

* `TAB` = toggle between encodes (keeps sync using your marks)
* `1` = force-load file #1
* `2` = force-load file #2
* `s` = mark sync point for **current** file at the current frame/time
* `i` = show sync status (what’s marked, what’s active)
* `q` = hold to temporarily preview the other encode, release to snap back

### How to use the sync marking (practical workflow)

1. Start with file 1:

   * Find a distinctive frame (hard cut, flash frame, logo pop, etc.)
   * Press `s` exactly on that frame.

2. Switch to file 2 (`TAB`), find *the same moment*, press `s`.

3. Now toggling (`TAB`) should keep the two files aligned relative to those marks.

If you haven’t set marks yet, it falls back to “switch to same timestamp”.

### Notes / Caveats

* Switching reloads the file, so it’s **not instant**.
* **Audio switches with the video** in this mode (because you’re changing files, not just video tracks).
* Works best if both files are in the playlist as the first two entries (i.e. exactly how the run command above launches them).

---

## Tips for better A/B comparisons

* Disable extra processing if you want a “pure” view:

  * consider turning off interpolation / frame smoothing on your display/TV
  * avoid post-processing shaders unless you’re intentionally testing them

* Use mpv’s frame stepping if you want to land on an exact moment:

  * `.` = frame step forward
  * `,` = frame step backward
    (mpv defaults; your config may vary)

* For very fair comparisons, keep everything else identical (scaling settings, dithering, HDR mapping, etc.) across both.

---

## Troubleshooting

### `ab_toggle_fast.lua` says it expected 2 video tracks

You probably didn’t provide the second file as an external file. Make sure you used:

```bash
mpv "Encode1.mkv" --external-file="Encode2.mkv" --script=ab_toggle_fast.lua
```

### The labels look wrong / show “external”

mpv exposes metadata for external tracks slightly differently depending on version/build. The script tries:

* `external-filename` → `title` → `"external"` as fallback

So if you see generic labels, it’s just mpv not exposing the external path in your build.

### Sync script only finds one file

The sync script reads the first two playlist items. Launch it with both files on the command line:

```bash
mpv "Encode1.mkv" "Encode2.mkv" --script=ab_toggle_sync.lua
```

---

## Which script should you use?

* **Encodes are perfectly aligned and you want instant switching** → `ab_toggle_fast.lua`
* **Encodes differ slightly and you need manual alignment** → `ab_toggle_sync.lua`

---

## Licence

Do whatever you want with it. If you need an explicit licence file later, MIT is usually the easiest default for little mpv scripts.
