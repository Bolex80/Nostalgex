# Changelog

All notable changes to this project are documented here.
Format follows the household convention: dated entries, `-YYYYMMDD-vN` suffixes on versioned files.

## 30/10/2026 — BolexTV running on the television

### Added
- **Plex subtitles**, cycled `OFF → EN → ES` from the rail and the `S` key. Plex serves SRT from
  `/library/streams/<id>?download=1`; the page converts it to WEBVTT and attaches it as a
  `<track>`. Language comes from Plex metadata when tagged, otherwise from reading the cues,
  because Plex leaves external SRTs untagged. The label and `srclang` always report the language
  **actually playing** — asking for English on a Spanish-only channel yields Spanish and the
  toast `NO EN — SHOWING SPA`. Text tracks only; image subtitles (PGS/DVD) are skipped.
  See `docs/SUBTITLES-20261030-v1.md`.
- **Real full screen.** OK on the playing channel expands the video to the whole screen
  (measured 960×540 at 0,0, previously a 484×270 corner box), hiding the guide, rail and info
  panel. OK or Back opens the in-player menu over the picture.
- **In-player menu** with progress (`1:08:00 / 1:36:00`), the channel, sound and
  **EXIT FULL SCREEN** — previously unreachable from the remote.
- **Guide time travel** in 30-minute steps, so the guide is not frozen on a two-hour window.
- **One navigation engine** for six buttons (`androidtv/app/src/main/assets/tvnav.js`): geometric
  focus over visible controls, zones for guide/rail/overlays/player, and a focus ring that
  survives the page's re-renders.
- **Visible exit** — a rail control and a leave prompt that defaults to **Stay**; Leave
  backgrounds the app instead of killing it.
- `docs/BOLEXTV-20261030-v1.md`, `docs/VERSIONS-20261030-v1.md`, `androidtv/README.md` and
  `BOLEXTV.md` — the project, its two version schemes and the shell's build instructions.

### Fixed
- **Full screen only hid the guide.** The video kept its preview box because `#video-area` is a
  flex row occupying the top half; the layout now pins both boxes to the screen and drops the
  flex basis that was overriding `width`.
- **Left looked dead in the guide.** It was stepping the time window back half an hour per press,
  so it silently rewound a dozen times before reaching the rail. One press now returns to live.
- **Keys were swallowed during playback** and on a WebView that had lost focus; `requestFocus()`
  before dispatching.
- **CH+/CH− browsed but never tuned**: a `div` receives neither keydown nor click from
  `DPAD_CENTER`, so tuning clicks the focused guide row instead.
- **Settings CLOSE was unreachable** (tabs sat at y = −77) and long lists would not scroll, because
  below-fold nodes were filtered out of the focus list.
- **Title overlapped the channel tag** by 2 px; `.info-title` 42 → 26 px with correct margins.
- Guide rows raised 44 → 50 px; channel column 160 → 205 px so names fit.
- **Plex login was lost on every restart** — `sessionStorage` → `localStorage` (51 `plex90_*` keys).
  The start-over smoke test was rewritten to assert against `localStorage`.
- **Branding never reached the landing page**: `tv.bolex.es` serves `web-tuner.html`, not
  `index.html`.

### Deployed
- Tuner image `bolextv-tuner:20261030k` (`de4492913990`) on LXC 228, `healthy`, serving
  `http://192.168.2.93:8080` with enrichment on. Full version history in
  `docs/VERSIONS-20261030-v1.md`.
- APK `0.1.0` (code 1) installed on `MiTV-AFMU0`.

### Known
- AC3 direct-play files render picture with no audio (16 items, 2.1 % of the direct-play set).
  A tuner-side force-transcode predicate is the fix and is **not yet implemented**.
- Element fullscreen is rejected inside Android WebView; `body.tv-full` is a layout, not the API.

## [Unreleased] — planning

### Added
- `docs/PLAN-20261029-v1.md` — foundation plan for an Android TV client: architecture options,
  phase gates, agent/model routing, repo conventions, definition of done, risks, open decisions.
- `docs/CONTINUATION-20261029-v1.md` — the authoritative resume point: verified project state,
  the nine decisions ratified by Alex on 29/10/2026 (name `BolexTV`, Mi Box only, sideload only,
  subtitles nice-to-have, enrichment on, dedicated LXC on bolex `.5`, no telemetry, Plex only,
  own logo), the deltas those decisions make to the plan, and the Phase 0 dispatch order.

- `docs/DISPATCH-CONTROL-20261029-v1.md` — pause/resume operating procedure: the exact chat commands
  (`/pause BolexTV`, `/pause off`), what the emergency stop covers and what it does not, the
  `/stop` kill path for in-flight work, batch discipline, and the measured budget baseline.
- `docs/BRAND-20261029-v1.md` — the identity decision: concept table, the three mark candidates,
  the three-colour palette, delivered sizes, and the size compromises stated openly.
- `brand/build-brand-assets.py` — single source of truth for the mark geometry; emits the SVG
  masters, the 1024 previews, the 512 icon, the 320×180 `LEANBACK_LAUNCHER` banner and the
  real-size contact sheets.
- `brand/assets/` — the generated assets, including `bolextv-banner-320x180-20261029-v1.png`.
- `docs/ARCHITECTURE-20261029-v1.md` — Phase 0 role 1 (Cartographer, `kimi-k3`). The Plex-only
  API contract, the client-side schedule algorithm, and the JS↔native bridge contract. Headline
  finding: the tuner exposes **nothing** native-usable today (only `window.__openPromoModal`; zero
  `postMessage`/`addJavascriptInterface` in `plex-tuner.html`), so Phase 2 must add the bridge to
  upstream code. Citations were spot-checked against the source by the orchestrator.
- `docs/FIELD-HARNESS-20261029-v1.md` — Phase 0 role 2 (Field Tester, `glm-5.3-flash`). The 16-item
  codec matrix to run on the Mi Box in TV Bro, with a results table, verdict definitions, an optional
  adb path and a decision rule. Its key structural finding — verified by the orchestrator — is that
  the tuner **direct-plays only mp4/webm/mov and sends every MKV through Plex's server-side HLS
  transcode** (`plex-tuner.html:5566-5593`), so the tuner UI can never answer the surround-audio
  question: a raw-part probe is required.

### Deployed
- LXC **228 `bolextv-tuner`** on Bolex `.5`, **`192.168.2.93:8080`** — the Nostalgex web tuner,
  image pinned by digest (`sha256:0c4d619b…`, tag `1.0.9`), enrichment on, container `healthy`,
  Plex `.30:32400` reachable from inside the container. Verified 29/10/2026.

### Notes
- Fork of `chadMueller/Nostalgex` (MIT). Upstream name, icon and site are outside the licence grant;
  this project will ship under its own name once chosen.
- `main` is intended to track upstream. All project work lives in `androidtv/` and `docs/`.
