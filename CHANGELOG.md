# Changelog

All notable changes to this project are documented here.
Format follows the household convention: dated entries, `-YYYYMMDD-vN` suffixes on versioned files.

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

### Notes
- Fork of `chadMueller/Nostalgex` (MIT). Upstream name, icon and site are outside the licence grant;
  this project will ship under its own name once chosen.
- `main` is intended to track upstream. All project work lives in `androidtv/` and `docs/`.
