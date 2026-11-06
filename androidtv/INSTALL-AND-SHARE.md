# BolexTV — install and share for Android TV

What is in this folder:

| File | Purpose |
|---|---|
| `BolexTV-v1.0.0.apk` | The app, release-signed, ready to install on any Android TV you give it |
| `INSTALL-AND-SHARE.md` | This guide |

SHA-256 of the APK starts with `bc419a8ef59dc452` (check it matches on the copy you send).

## What BolexTV is

A WebView TV guide shell that loads the BolexTV tuner page and plays its channels full screen
with a Plex account the viewer signs in with on the box. Six-button remote only
(directional keys, OK, Back). No phone UI, no browser needed.

## Install on an Android TV

1. Copy `BolexTV-v1.0.0.apk` onto the TV's network storage (Drive, USB stick, or
   `adb install` from a computer).
2. On the TV: Settings → Apps → Security & Restrictions → allow installs from the app
   you opened the APK with (File Manager / any TV file app).
3. Open the APK, confirm the install.
4. Press CONNECT WITH PLEX and sign in — the app remembers the login across restarts
   even while it clears its web cache on cold start.

### About Plex accounts

- No Plex account of any kind is embedded in the APK. The shell contains exactly one address
  (`http://192.168.2.93:8080/plex-tuner.html`) and nothing else network-related — verified by
  extracting the release APK and scanning every file: zero occurrences of any Plex token, of the
  maintainer's emails, or of any plex.tv endpoint.
- Signing-in happens per device: CONNECT WITH PLEX shows a four-character code to enter at
  **plex.tv/link**, and the token it issues is stored only in that TV's local storage.
- Each install also generates its own device identity, so Plex sees each box (and each browser)
  as its own client.
- Whoever signs in controls what plays: the guide's channel line-up comes from the tuner service;
  programmes resolve and play through the account and servers that account can reach.

To switch a box from the older development build to this one, uninstall the old one first
(its Plex login is erased by uninstalling) and install this APK.

## What it needs from the network

The tuner address is baked into this APK at build time: `http://192.168.2.93:8080`.
So the box must be able to reach that address:

- **Inside the home network or over the household VPN:** works as delivered.
- **Outside, without any tunnel:** the guide will not load, because the address is private.
  Someone self-hosting can build their own APK with their own tuner in one line: the
  address is a build-time constant (`TUNER_URL`) in `androidtv/app/build.gradle.kts` of the
  public repository `github.com/Bolex80/Nostalgex`, and the server itself is a Docker image
  from the same repository — no code changes anywhere else.

## Updates

Install a new version with the same key directly over an installed one — the Plex login and
all settings survive. Different versioning only matters after a change of signing key,
which does not exist yet.

## Compatibility notes for other boxes

- Needs Android 6 (API 23) or newer; the package is 32-bit ARM and installs on
  both ARM32 and ARM64 boxes.
- Verified on Android 14 (Mi Box). Older boxes ship older system WebView versions; a
  several-year-old box should have its system WebView updated from the Store before
  first use, otherwise the guide page may render partially or refuse to run.
- The full-screen player transcodes what the tuner decides; boxes without AC3-capable
  hardware playback will still get audio because the tuner transcodes those files.
- Layout targets a 960×540 guide viewport, which is the standard Android TV scale; some
  exotic boxes report a larger one, where the guide simply shows a bit smaller.
