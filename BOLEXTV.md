# BolexTV

An Android TV client for the Nostalgex web tuner, rebuilt for Alex Benthem's own use: Plex only,
no telemetry, no links to the upstream creator, and a navigation model that works with a remote
that has nothing but four arrows, OK and Back.

This file is the front door. The detail lives in `docs/`.

## What runs where

BolexTV is **two artifacts with two independent version schemes**. Neither one is the "app
version" on its own — the tuner carries almost every feature, and the shell carries navigation.

| Artifact | What it is | Version scheme | Where it runs |
|---|---|---|---|
| **Tuner image** | The web tuner (guide, player, subtitles, settings) built as a container | `bolextv-tuner:<YYYYMMDD><a-z>` | LXC 228 on the Proxmox host `bolex`, served on `:8080` |
| **APK** | The Android TV shell: WebView, remote handling, lifecycle | Semver `versionName` + `versionCode` | The Mi Box (`MiTV-AFMU0`) |

The page inside the WebView is the product. The APK is a window onto it.

## Start here

| Document | Read it for |
|---|---|
| [`docs/BOLEXTV-20261030-v1.md`](docs/BOLEXTV-20261030-v1.md) | The overview: what it is, the rename, the architecture, the features and their measured evidence, known limits, deploy and rollback. |
| [`docs/VERSIONS-20261030-v1.md`](docs/VERSIONS-20261030-v1.md) | Every tuner image and every APK, with image IDs and the commit that produced them. |
| [`androidtv/README.md`](androidtv/README.md) | Building and installing the APK. |
| [`docs/NAVIGATION-20261030-v1.md`](docs/NAVIGATION-20261030-v1.md) | The six-button navigation model, layer by layer. |
| [`docs/SUBTITLES-20261030-v1.md`](docs/SUBTITLES-20261030-v1.md) | Plex subtitles: how tracks are chosen and why the label never lies. |
| [`docs/BRAND-20261029-v1.md`](docs/BRAND-20261029-v1.md) | The identity: Guide Play mark, palette, sizes. |
| [`docs/FIELD-RESULTS-20261029-v1.md`](docs/FIELD-RESULTS-20261029-v1.md) | The measured codec matrix on the real box: what plays, what is silent, what does not play. |
| [`CHANGELOG.md`](CHANGELOG.md) | Dated history of every change. |

## The short version

- **Plex only.** Jellyfin and Emby code paths exist upstream and are out of scope here.
- **Page-first.** Every feature the user can see lives in `plex-tuner.html` or `web-tuner.html`,
  so the browser and the television behave identically. The shell only moves focus and keys.
- **Six buttons, no dead ends.** Every screen is reachable with arrows, OK and Back, and Back
  never traps the user or leaves the app without asking.
- **Sideload only.** No store, no accounts, no telemetry.

## Repo conventions

- Project work lives in `androidtv/`, `docs/`, `tuner/`, `brand/`.
- `plex-tuner.html` and `web-tuner.html` are **fork-patched** by explicit instruction; the rest
  of the upstream tree is left alone so upstream merges stay possible.
- Dated documents and versioned files carry `-YYYYMMDD-vN` before the extension.
