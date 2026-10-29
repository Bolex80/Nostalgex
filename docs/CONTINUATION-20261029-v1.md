# BolexTV (Nostalgex for Android TV) — Continuation Brief

**Status:** authoritative resume point · **Version:** v1 · **Date:** 29/10/2026
**Supersedes nothing.** Complements [`PLAN-20261029-v1.md`](PLAN-20261029-v1.md) — that file is the
design; this file is *where we are, what Alex decided, and what happens next*.
**Repo:** `Bolex80/Nostalgex` (public fork of `chadMueller/Nostalgex`, MIT).

---

## 1. What this file is for

The project began in a Telegram conversation with Hermes. Telegram conversations are read-only in the
Nesquena WebUI (the gateway refuses cross-surface writes with `permission_denied`), so the work moved
here: **the repo is the conversation's memory.** Everything needed to continue from a fresh chat is in
this file plus `PLAN-20261029-v1.md`.

To resume, open a new chat and paste the prompt in section 7. Nothing else is required.

---

## 2. Where the project stands (verified, not asserted)

| Item | State |
|---|---|
| Fork | `github.com/Bolex80/Nostalgex` — public, `fork: true` of `chadMueller/Nostalgex`, `upstream` remote configured |
| PR #1 | **open** → https://github.com/Bolex80/Nostalgex/pull/1 |
| PR #1 contents | `docs/PLAN-20261029-v1.md` (284 lines), this brief, `CHANGELOG.md` — **documentation only, no product code** |
| Branch | `plan/20261029-foundation` (local clone clean, tracks `origin`; tip is this brief's commit) |
| Local clone | `/home/alex/projects/nostalgex-android` (on the build host `ai-agents`, VM105 on Bolex) |
| Model routing | Verified live on the build host: `glm-5.3:cloud`, `glm-5.3-flash:cloud`, `kimi-k3:cloud`, `deepseek-v4-pro:cloud` each returned a real completion via `hermes -z -m <model>` |
| Target device | Xiaomi Google TV box, HA model `MiTV-AFKR0` (`media_player.xiaomi_tv_box`) |
| Plex | `http://192.168.2.30:32400`, v1.43.5, reachable |
| Phase 0 | **not started** — blocked only on approval of PR #1 (see §3) |

Nothing has been installed on any host. No containers, no Android toolchain, no code beyond `docs/`.

---

## 3. Decisions ratified by Alex — 29/10/2026

These answer §9 of the plan in full. They are **decided; do not re-open them.**

1. **Project name: `BolexTV`.** Satisfies upstream's request that forks not ship under the Nostalgex
   name. Repo stays a linked fork. Working titles (CableVision/RetroTV/VHSTV/ChannelSurf) are dropped.
2. **Scope: the Mi Box only, initially.** Explicitly *not* the six Philips `TPM191E` sets and not the
   bedroom Chromecast. Scaling out is a later decision, gated on the Mi Box working end to end.
3. **Distribution: sideload only, for now.** No Play Store TV listing in v1. $25 developer account and
   TV review stay deferred.
4. **Subtitles: nice-to-have**, not a must-have. Consequence: the native Plex subtitle path does **not**
   gate Phase 2; it may slip to Phase 3 without blocking release.
5. **Enrichment: ON** (`NOSTALGEX_ENRICHMENT` left enabled — TMDB/IMDb ids and the shared Supabase cache
   leave the LAN).
6. **Container: a dedicated LXC on Proxmox `bolex` (`.5`)**, not the arr-suite LXC and not
   `bolex-cloud`. IP chosen by Hermes at provisioning time and recorded in the wiki.
   *Known-claimed addresses, do not reuse:* `.81` timeline, `.82` convertx, `.83` bolex.es,
   `.84` gluetun, `.85` arr-suite, `.86` gods-eye-view, `.88` flaresolverr, `.89` taberna-alameda.
7. **Telemetry: none.**
8. **Backends: Plex only.** Alex does not use Emby. Jellyfin/Emby support is out of scope unless it is
   genuinely cheap — treat any Jellyfin/Emby work as a follow-up, never as a v1 dependency.
9. **Branding: a purpose-made `BolexTV` logo**, Plex-inspired in *feel* (guide/TV motif), not a copy of
   Plex's mark or palette-locked assets — Plex's logo is a trademark and this repo is public.

---

## 4. What those decisions change in the plan

- **Phase 0 narrows to Plex.** The Cartographer's API-contract work covers the Plex path only. The
  multi-backend matrix in `PLAN` §2/§4 is documentation, not v1 scope.
- **Phase 0 gains an LXC provisioning step** on `bolex` (`.5`) — new container, Docker inside it, tuner
  pinned to an upstream tag, plain HTTP on a LAN port only. Alex wires any public route himself.
- **Phase 2 loses its subtitle exit criterion.** Replaced by: "external SRT renders where the backend
  offers it; PGS documented as unsupported." Subtitles become a Phase 3 deliverable.
- **Phase 4 loses the Play Store decision point.** Release = signed sideload APK + GitHub release.
- **New Phase 1 prerequisite:** the `BolexTV` logo and launcher banner (Android TV banner is 320×180,
  `LEANBACK_LAUNCHER`), because the app cannot be installed with the upstream identity.
- **`delegation.model` pinning per phase is unchanged** (plan §5): change it at each gate together with
  the config guard's expectation table.

---

## 5. Next actions once PR #1 is approved

1. **Provision** the tuner LXC on `bolex` (`.5`): Docker, `plex-tuner` pinned to a tag, document the IP.
2. **Phase 0 dispatch, two roles in parallel** (the plan's original intent):
   - **Role 1 — Cartographer** (`kimi-k3:cloud`): Plex-only API contract, schedule algorithm, the
     JS↔UI boundary. Output → `docs/ARCHITECTURE-20261030-v1.md`.
   - **Role 2 — Field Tester** (`glm-5.3-flash:cloud`): deploy the container, open it in **TV Bro** on
     the Mi Box, run the audio/codec matrix over real library items. Output →
     `docs/FIELD-REPORT-20261030-v1.md`.
3. **Logo** for `BolexTV` + launcher banner, derived from the guide/TV motif.
4. Publish the field report — the project's first public artefact.

**Gate after Phase 0:** Alex decides on the audio evidence whether the WebView shell (Phase 1) and the
native Media3 bridge (Phase 2) are worth the spend.

---

## 6. Open, but not blocking

- **LXC IP** — allocated at provisioning; must be checked against the wiki IP map first.
- **`androidtv/` skeleton** — deliberately not created yet; nothing is installed until Alex says go.
- **Second test device** — verification throughput is the schedule bottleneck (plan §8). A second
  Android TV target would roughly halve Phase 2–3 calendar time.
- **Weekly upstream merge** — should become a scheduled job, not a good intention (plan §8).

---

## 7. Resume prompt (paste into a new chat)

> Continue the **BolexTV** project (Android TV client for the Nostalgex schedule engine).
> Read `docs/CONTINUATION-20261029-v1.md` and `docs/PLAN-20261029-v1.md` in
> `/home/alex/projects/nostalgex-android` first — they contain the ratified decisions and the current
> state. PR #1 is open on `Bolex80/Nostalgex` (`plan/20261029-foundation`). Decisions are settled:
> name BolexTV, Mi Box only, sideload only, subtitles nice-to-have, enrichment on, dedicated LXC on
> bolex `.5`, no telemetry, Plex only. Start Phase 0 with roles 1 and 2 in parallel, as described in
> §5 of the continuation brief. Nothing gets installed on the box until I say go.

---

## 8. Provenance

- Every upstream claim in `PLAN-20261029-v1.md` was read from the repository at commit `52e83c2`.
- Every host claim was verified live on the build host on 29/10/2026.
- The decisions in §3 were given by Alex in the originating Telegram conversation on 29/10/2026 and are
  recorded here because that conversation is not writable from the WebUI.
- The PR state, branch head and repo metadata in §2 were re-verified on 29/10/2026 immediately before
  this file was written.
