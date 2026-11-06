# BolexTV Phase 0 — Measured Codec Matrix Results

**Date:** 29/10/2026 · **Version:** v1 · **Method:** `adb`-driven playback in TV Bro 2.1.6
(system Android WebView) on the Mi Box, 16 library items, raw part URLs.

This is the measurement `docs/FIELD-HARNESS-20261029-v1.md` was written to produce. It replaces
inference with observation for the codec question.

---

## 1. How a verdict was decided

Not by ear and not by screenshot. Per item, after a 14 s playback window with TV Bro forced to the
foreground, two independent signals were read from the device:

- `dumpsys audio` → an `AudioPlaybackConfiguration … state:started` entry (a media player ran);
- `dumpsys media.audio_flinger` → the count of output threads **not** in standby.

Both were confirmed to discriminate on item 1 before the run proceeded. Screenshots are supporting
evidence only — a hardware video overlay can return a stale frame to `screencap`, so pixel-diffing
two captures is **not** a valid motion test on this device (this was tried and abandoned).

## 2. Results

| # | Item | Cont | Video | Audio | Ch | Measured verdict | Evidence |
|---|---|---|---|---|---|---|---|
| 1 | 2 Fast 2 Furious | mp4 | h264 | aac | 2 | **plays** | 1 started player, 1 active thread |
| 2 | 8MM | mp4 | h264 | aac | 2 | **plays** | 1 started player, 1 active thread |
| 3 | 28 Days Later | mp4 | hevc | aac | 6 | **plays** | 1 started player, 1 active thread |
| 4 | 28 Years Later | mp4 | hevc | aac | 6 | **plays** | 1 started player, 1 active thread |
| 5 | The 51st State | mkv | h264 | ac3 | 6 | no playback | 0 players, 0 active threads |
| 6 | **1492: Christophe Colomb** | **mp4** | h264 | **ac3** | 2 | **picture, no audio** | 0 players, 0 active threads; frame rendered |
| 7 | Alpha Dog | mkv | hevc | ac3 | 6 | no playback | 0 / 0 |
| 8 | Green Book | mkv | hevc | ac3 | 6 | no playback | 0 / 0 |
| 9 | Arrival | mkv | h264 | dts | 6 | no playback | 0 / 0 |
| 10 | Austin Powers | mkv | h264 | dts | 6 | no playback | 0 / 0 |
| 11 | Avatar Aang | mkv | hevc | eac3 | 6 | no playback | 0 / 0 |
| 12 | Casino | mkv | hevc | eac3 | 6 | no playback | 0 / 0 |
| 13 | Disclosure Day | mkv | hevc | truehd | 8 | no playback | 0 / 0 |
| 14 | The Hobbit | mkv | hevc | truehd | 8 | no playback | 0 / 0 |
| 15 | 300 | mkv | hevc | dts-hd ma | 6 | no playback | 0 / 0 |
| 16 | A Clockwork Orange | mkv | hevc | dts-hd ma | 6 | no playback | 0 / 0 |

Foreground was `com.phlox.tvwebbrowser` for all 16 — so no row failed because of an app chooser.

## 3. What it means

**MKV does not play in the WebView at all (rows 5, 7–16).** Expected and not a defect: the browser
cannot demux Matroska, which is precisely why the tuner routes every MKV to Plex's transcoder
(`plex-tuner.html:5577-5593`). **In the product these items are unaffected** — the probe deliberately
bypasses that transcoder, and the browser never sees MKV in normal use.

**MP4 + AAC plays, with audio (rows 1–4).** The WebView path is sound for the majority of the library:
748 of the 764 direct-play items are AAC.

**MP4 + AC3 renders picture but produces no audio (row 6).** This is the plan's silent-surround
failure, now measured — and it is real. It contradicts the static-capability reading in
`docs/FIELD-DEVICE-20261029-v1.md` §2, which noted the platform declares
`c2.amlogic.audio.decoder.ac3`: **declared ≠ used**. A declared Amlogic decoder did not save this
file, and `mali_gralloc: Unsupported dataspace standard (589824)` repeated during the attempt.
That correction matters more than the original claim.

**Scope: 16 items, not the whole library.** 16 of 764 direct-play items (2.1 %) are `mp4 + h264 + AC3`.
Everything else in the risk column is inside MKV, where Plex transcodes it away.

## 4. Consequence for the build

The silent-audio bug is real but small, and there are three ways to answer it — in cost order:

1. **Tuner-side predicate (cheapest).** The tuner already supports `item._forceTranscode`
   (`plex-tuner.html:5566`). Force a transcode when the container is direct-play-eligible **and** the
   audio codec is AC3/EAC3/DTS/TrueHD. That converts the 16 failures into 16 transcodes — a bounded,
   already-paid-for cost — and needs no new player at all.
2. **Rely on the existing retry.** The tuner retries once via transcode on a decode failure
   (`plex-tuner.html:5750-5753`). Whether that handler actually catches "video renders, audio silent"
   is **not established** — a silent track may not raise `onerror` at all. Do not assume it.
3. **Native Media3 player (Phase 2).** Justified less by these 16 files and more by the fact that
   **ExoPlayer can direct-play MKV**, which would remove ~476 server transcodes. That is the honest
   Phase 2 business case — cost and server load, not silence.

**Recommendation:** take (1) now, and re-scope Phase 2 around transcode cost. It is a far cheaper
answer than a native player, and (1) is testable in one afternoon.

## 5. Threats to validity

- **One sample per codec class.** One MP4+AC3 file is a thin basis for a class-level claim; a second
  AC3 MP4 (the other 15 are `h264+ac3` too) would strengthen it.
- **My error detector was too loose.** `has_codec_error` fired on item 4, which demonstrably played —
  the regex matched `CCodecConfig` because it contains "codec". The verdicts above therefore rest on
  the player/thread signals, **not** on that flag, and the flag should not be quoted as an error count.
- **Picture-motion is not proven.** Audio was measured; whether the video advances (rather than
  showing a held frame) was not established, because `screencap` cannot be trusted against a hardware
  video layer on this box.
- MKV "no playback" is a statement about *this app on this device*, not about ExoPlayer.

---

*Raw evidence: `run-matrix.py` output and per-item screenshots under `/home/alex/hermes_data/cache/bolextv/results/`.
Verdicts derive from `dumpsys audio` and `dumpsys media.audio_flinger`, both read from the device.*
