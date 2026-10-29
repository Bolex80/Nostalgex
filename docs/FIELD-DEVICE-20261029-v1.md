# BolexTV Phase 0 — Device Reality and Codec Findings

**Date:** 29/10/2026 · **Version:** v1 · **Method:** live `adb` over the LAN, read from the device itself.
**Corrects:** `docs/PLAN-20261029-v1.md` and `docs/CONTINUATION-20261029-v1.md`, which both name the
target as `MiTV-AFKR0` and assume TV Bro is available. Neither is true of the actual box.

---

## 1. The device, as measured

| Property | Value |
|---|---|
| Model | **`MiTV-AFMU0`** (not `AFKR0`) |
| Manufacturer / product | Xiaomi / `twilight` |
| Android | **14** (`ro.build.version.release`), SDK **34** |
| ABI | **`armeabi-v7a, armeabi` — 32-bit only** |
| Network | **`192.168.5.86`** — a different subnet from the servers; routed via `192.168.2.1` |
| adb | reachable on **`5555`** ("MiTV Adb debugging"), RSA-authorised 29/10/2026 |
| Installed browser | **none** |

Two of those are architectural, not trivia: the box runs **32-bit only**, and it is on `192.168.5.0/24`
while Plex and the tuner are on `192.168.2.0/24`. Both matter for the client build.

## 2. The audio-decode risk does not apply to this hardware

The plan's headline risk was that a TV browser cannot decode AC3/DTS and plays **silently**. The
device declares licensed Amlogic decoders for exactly that family:

```
c2.amlogic.audio.decoder.aac     audio/mp4a-latm
c2.amlogic.audio.decoder.ac3     audio/ac3
c2.amlogic.audio.decoder.ac4     audio/ac4
c2.amlogic.audio.decoder.eac3    audio/eac3
c2.amlogic.audio.decoder.dts     audio/vnd.dts
c2.amlogic.audio.decoder.dtse    audio/vnd.dts.hd;profile=lbr
c2.amlogic.audio.decoder.dtshd   audio/vnd.dts.hd
c2.amlogic.audio.decoder.dtsuhd  audio/vnd.dts.uhd;profile=p2
c2.amlogic.audio.decoder.mp1/mp2 audio/mpeg-L1, -L2
```

**TrueHD is not declared anywhere** in `/vendor/etc/media_codecs*.xml`.

## 3. Why that is enough — the risk population is 2.1 %, not 25 %

Measured over 1,253 media items (Plex sections 1, 10, 4, 5):

| Container | Items | Route in the tuner |
|---|---|---|
| `mp4` | **764** | direct play (the only direct-play-eligible container in the library) |
| `mkv` | **476** | always server-side HLS transcode |
| `avi` / `mpeg` | 13 | server-side transcode |
| **total** | **1,253** | |

Of the **764 direct-play items, only 16 (2.1 %) carry non-AAC audio — all of them `mp4 + h264 + AC3`**,
and AC3 has a declared platform decoder.

Put together with `plex-tuner.html:5566-5593` (direct play only for `mp4/webm/mov`; every MKV goes to
Plex's transcoder):

- **476 MKV + 13 other = 489 items are re-encoded by Plex before the browser sees them.** Whatever
  audio the browser receives, it is not DTS/TrueHD — so the browser's decoder is irrelevant for them.
  This is why every `mkv` row in `FIELD-HARNESS` is marked route T.
- **748 of 764 direct-play items are AAC** — no risk at all.
- **16 items are MP4 + AC3**, and the platform has an AC3 decoder.
- **TrueHD exists only in MKV** in this library, so its absence from the platform list costs nothing
  on the browser path.

**Conclusion: on this box there is no meaningful population of silently-playing media in the tuner
path.** The earlier "≈311 items (25 %) at risk" figure counted the whole library's non-AAC audio; it
was never a playback-failure estimate, and against this hardware it is not one at all.

## 4. What this changes

1. **Phase 2's audio justification mostly evaporates.** A native Media3 player no longer earns its
   place by fixing silent surround. What remains is real but different: **ergonomics** (a real
   launcher tile, D-pad focus, native OSD) and **server cost** — 489 transcodes instead of direct
   play, on a GPU-VM that also runs Plex, Immich and Ollama.
2. **The cost question becomes the Phase 2 gate** — not "will it be silent". Worth measuring: CPU/GPU
   load and startup latency of transcoding the MKV half of the library versus direct-playing it.
3. **A live matrix is currently impossible.** The box has **no browser installed** and no activity
   handler for `http`/`video/*` VIEW intents — `cmd package query-activities` returns nothing. The
   tuner cannot be opened on this device at all until one is installed.
4. **The harness needs a browser before it can run.** Its P1 probe assumed TV Bro.

## 5. Still unmeasured

Everything in §3 is static capability data (declared decoders + container census). It is strong, but
it is not a playback measurement. Not yet established, and requiring a browser on the box:

- whether a WebView actually instantiates the AC3 decoder for an MP4 part URL (declared ≠ used);
- whether the 16 AC3 MP4s play with sound rather than downmixing or failing;
- cold-start and channel-change behaviour (Phase 1 gates).

---

*Measured with `adb` on 29/10/2026 from device properties, `/vendor/etc/media_codecs*.xml`, and the
Plex API. No claim here is inferred from documentation; the tuner's routing behaviour is cited to
`plex-tuner.html` in `docs/ARCHITECTURE-20261029-v1.md`.*
