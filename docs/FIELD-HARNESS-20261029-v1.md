# BolexTV Phase 0 — Field codec matrix on the Mi Box (TV Bro)

**Date:** 29/10/2026 · **Version:** v1 · **Executor:** one person with the TV remote plus a laptop on the same LAN; no coding, no adb.
**Under test:** Xiaomi Google TV box (HA `media_player.xiaomi_tv_box`, model `MiTV-AFKR0`), TV Bro browser; tuner `http://192.168.2.93:8080` (nginx static HTTP, `docker/nginx.conf:11-16`); Plex `http://192.168.2.30:32400` (v1.43.5). Front door `web-tuner.html` as `index.html` (`scripts/selfhost-build.mjs:244-249`), tuner 1.0.9 = deployed tag (`package.json:4`).
**Credentials:** repo is public (`CLAUDE.md:4-5`). `<PLEX_TOKEN>` is a placeholder; the real token is typed at runtime only, never committed.

## 1. What must be proven

Phase 0's exit criterion, operationally: per codec combination, record what **plays**, what **downmixes** (audible, flattened to stereo), what is **silent** — measured, not inferred (`docs/PLAN-20261029-v1.md:107-110`; target matrix h264+aac, h264+ac3, hevc+eac3, hevc+dts, `docs/PLAN-20261029-v1.md:236`). Stakes: 1,237 movie-section items — video h264 909 / hevc 316 / mpeg4 10 / av1 1; audio aac 921 / ac3 185 / dca 67 / eac3 37 / dca-ma 12 / truehd 10; 6ch 692, 2ch 525, 8ch 17 — so 311 items (25 %) have non-AAC audio. The census is API-derived (§7); this harness measures it.

Only the probe route can answer the surround question. The tuner UI direct-plays mp4/webm/mov only (`plex-tuner.html:5566-5567`, gated by `scripts/nostalgex-stream-quality.js:110-115`) and sends all MKV to server HLS transcode (`plex-tuner.html:5577-5593`) played via hls.js/MSE (`plex-tuner.html:5609-5617`) — it can never reveal whether the browser decodes AC3/DTS/EAC3/TrueHD inside MKV. The probe (§2) plays the raw part file, the tuner's own direct-play URL shape (`plex-tuner.html:5570-5575`), isolating the browser's demuxer + decoders — what a Phase 1 WebView inherits.

## 2. Forcing a specific item to play

The tuner airs a fixed daily schedule. Verified play entry points: tune-to-channel (`tuneFromGuide` → `switchChannel`, `plex-tuner.html:6829-6831`), playback on tune (`plex-tuner.html:5100-5101`), auto-advance (`plex-tuner.html:5794-5795`). No preview, browse-and-play or "play this item now" path exists (searched preview / play-now / start-over / force-transcode hooks; the only START OVER control, `plex-tuner.html:3343`, signs out to the connect page, `plex-tuner.html:8137-8139`).

**P1 — direct-play probe (deterministic):** (1) laptop: open `http://192.168.2.30:32400/library/metadata/{ratingKey}?X-Plex-Token=<PLEX_TOKEN>` (ratingKey = row's rk); (2) find `Part key="/library/parts/…"` — the exact string the tuner stores per item (`plex-tuner.html:9228-9229`); (3) compose `http://192.168.2.30:32400/library/parts/<part-key-path>?X-Plex-Token=<PLEX_TOKEN>` — the tuner's own direct-play URL shape (`plex-tuner.html:5574-5575`); (4) open it in TV Bro (address bar; a phone with the Android TV remote app types faster).

**P1 bypasses the tuner UI**: it tests the browser's decoder on the file as stored — not the tuner's direct-play-vs-transcode decision (per-row Route in §4 is code-derived), not the server's transcoder. Never probe with the transcode URL; that measures Plex, not TV Bro. **P2 — in-schedule:** when a listed item airs on a tuned channel, add `tuner:` facts to its Notes.

## 3. Procedure on the TV (TV remote)

1. Box home → TV Bro → address bar → `http://192.168.2.93:8080/`.
2. Sign in: start the Plex connect flow; a 4-character code and QR to `https://www.plex.tv/link/` appear (`web-tuner.html:501-526`). On phone/laptop open plex.tv/link, sign into Plex, enter the code; the tuner polls ≤ 5 min (`web-tuner.html:528-543`), stores auth locally, opens the tuner page (`web-tuner.html:585,604-614`). Later opens skip sign-in (`web-tuner.html:140-147`).
3. First run: wait out the library scan (minutes; `plex-tuner.html:3323-3327`), pick a channel from the guide (D-pad + OK); video starts mid-programme via the join-offset seek (`plex-tuner.html:5693-5697`).
4. Sanity gate: run P1 on row 1 (h264+aac stereo, mp4) — sound must be audible. If not: TV/AVR volume + mute, box audio output setting, retry. Rows 1-2 are the setup control; record codec verdicts only after row 1 sounds.
5. Per row: run P1, watch ~30 s, fill the table. Where possible, leave a channel running and note `tuner:` behaviour when listed items air.

**Columns.** *Video OK?* — picture renders, keeps advancing; `stutter` if in bursts. *Audio heard?* — yes/no at any volume after step-4 checks. *Verdict* — `plays`: multichannel confirmed (box passthrough/auto into an AVR/ARC path); `downmix`: audible but flattened through TV speakers; `silent`: video advancing, no audio at any volume; `stutter`; `error`: fails or the browser downloads instead of playing. *Silent vs quiet:* video advances, volume up, row 1 still sounds; same settings + row 1 audible + row N silent = codec, not setup. *Track shown:* whatever TV Bro's player menu lists, else empty — no Plex audio-track picker in the tuner (`docs/ARCHITECTURE-20261029-v1.md:266-269`). Header of the report records once: box firmware/Android version, TV Bro version, box audio output setting, TV-speaker vs AVR.

## 4. Results table

Verdict values: `plays · downmix · silent · stutter · error`. Result columns empty. Route pre-filled from code (§1): **D** = in-tuner direct play expected (mp4; AUTO/MAXIMUM always allow direct play, `scripts/nostalgex-stream-quality.js:111`, and every D row is ≤ 2,524 kbps, under even the High ceiling); **T** = in-tuner HLS transcode expected (MKV). Codec columns are the probe's input; P1 doubles as the browser's MKV-container test (rows 5, 7-16) — an MKV row failing on video means audio unconcluded, not `silent`.

| # | Item (year) | rk | Cont | Vid | Aud | Ch | kbps | Sec | Route | Video OK? | Audio heard? | Verdict | Track shown | Notes |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2 Fast 2 Furious (2003) | 5 | mp4 | h264 | aac | 2 | 1861 | 1 | D | | | | | |
| 2 | 8MM (1999) | 56 | mp4 | h264 | aac | 2 | 2316 | 1 | D | | | | | |
| 3 | 28 Days Later (2002) | 33008 | mp4 | hevc | aac | 6 | 2231 | 1 | D | | | | | |
| 4 | 28 Years Later (2025) | 86420 | mp4 | hevc | aac | 6 | 2384 | 1 | D | | | | | |
| 5 | The 51st State (2001) | 3067 | mkv | h264 | ac3 | 6 | 3010 | 1 | T | | | | | |
| 6 | 1492: Christophe Colomb (1992) | 3 | mp4 | h264 | ac3 | 2 | 2524 | 1 | D | | | | | |
| 7 | Alpha Dog (2006) | 146 | mkv | hevc | ac3 | 6 | 8114 | 1 | T | | | | | |
| 8 | Green Book (2018) | 73531 | mkv | hevc | ac3 | 6 | 5596 | 1 | T | | | | | |
| 9 | Arrival (2016) | 286 | mkv | h264 | dca (DTS) | 6 | 3607 | 1 | T | | | | | |
| 10 | Austin Powers: Int. Man of Mystery (1997) | 10782 | mkv | h264 | dca (DTS) | 6 | 8266 | 1 | T | | | | | |
| 11 | Avatar Aang: The Last Airbender (2026) | 90550 | mkv | hevc | eac3 | 6 | 7173 | 1 | T | | | | | |
| 12 | Casino (1995) | 817 | mkv | hevc | eac3 | 6 | 5163 | 1 | T | | | | | |
| 13 | Disclosure Day (2026) | 90424 | mkv | hevc | truehd | 8 | 5725 | 1 | T | | | | | |
| 14 | The Hobbit: An Unexpected Journey (2012) | 21999 | mkv | hevc | truehd | 8 | 9425 | 10 | T | | | | | |
| 15 | 300 (2007) | 21613 | mkv | hevc | dca-ma | 6 | 8382 | 10 | T | | | | | |
| 16 | A Clockwork Orange (1971) | 21614 | mkv | hevc | dca-ma | 6 | 14483 | 10 | T | | | | | |

## 5. Optional adb path (advanced; the matrix stands without it)

Enable (menu names vary by firmware; inferred): Settings → Device Preferences → About → tap "Android TV OS build"/"Build" 7× with OK → Developer options → **Network debugging**. From any platform-tools machine (not this build host): `adb connect <BOX_IP>:5555`.

- `adb logcat -c && adb logcat -v time | grep -iE 'ACodec|CCodec|MediaCodec|AudioTrack|audio_flinger|ac3|eac3|dts|truehd|omx.*error|codec.*fail'` during a probe — names the failing decoder/format; scope with `pidof com.phlox.tvwebbrowser` (TV Bro package name inferred; verify via `adb shell pm list packages | grep -i bro`).
- `adb shell dumpsys media.audio_flinger` while playing — active track's format/channels: decoded PCM mix vs no track.
- Leak groundwork for the Phase 1 gate (50 channel changes, no memory climb; `docs/PLAN-20261029-v1.md:119-120,238`): `adb shell dumpsys meminfo com.phlox.tvwebbrowser` before/after 50 guide → channel switches in TV Bro.

## 6. Decision rule

Read the **probe** verdicts for decoder facts:

- **Rows 1-2 silent after setup verification** → browser playback chain broken on this box; a Phase 1 WebView inherits it — browser path is a dead end. Stop, re-scope.
- **AC3 audible (rows 5,6,8-10)** → browser clears the largest non-AAC tier (185 items) plus the tuner's in-schedule mp4+AC3 case (row 6): Phase 1 justified, Phase 2 buys no audio. AC3 silent while video plays → Phase 2 (native Media3 passthrough) has a concrete named win.
- **EAC3 (11-12) / DTS family (9-10,15-16) silent, video OK** → 37 + 79 items ride the server transcode in the tuner UI or need native passthrough. The Phase 2 exit bar is defined against this table — browser-playing rows must stay playing natively, plus the failed AC3/EAC3 rows (`docs/PLAN-20261029-v1.md:130-132`) — it doubles as Phase 2's acceptance set.
- **TrueHD (13-14)**: expect no browser decode; ~10 items; fixable only by an FFmpeg-extended native player — record, don't build.
- **HEVC mp4 (3-4) video-fails in probing** but the tuner recovers via its one-shot transcode retry (`plex-tuner.html:5750-5755`) → note `tuner: recovered`; tuner-viable, probe-marginal. MKV HEVC rows are pre-transcoded by the tuner regardless.

## 7. What stays inferred

Measured only: browser decode of raw part files (P1); incidentally, tuner behaviour when listed items air (P2). Unresolved:

- The transcode audio format Plex emits on this server (out of repo; inferred AAC-over-HLS) — why tuner-UI "plays" on MKV rows proves nothing about browser DTS/AC3 decode.
- The §1 census is API-derived, not played; it sizes the stakes only.
- Device-side unknowns, first seen when the table fills: TV Bro auto-play vs download of direct media URLs; MSE/hls.js stability in TV Bro; box audio menu names; network-debug enabling; TV Bro's adb package name.
- Whether the tuner's Plex branch ever picks a non-default audio stream: undetermined in the repo (`docs/ARCHITECTURE-20261029-v1.md:266-269`).
- Phase 1-only gates (50-change memory, cold-start < 5 s) stay out of this harness (`docs/PLAN-20261029-v1.md:119-120,234`).