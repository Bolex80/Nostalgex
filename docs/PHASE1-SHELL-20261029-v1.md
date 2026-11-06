# BolexTV Phase 1 — WebView Kiosk Shell

**Date:** 29/10/2026 · **Version:** v1 · **Module:** `androidtv/` · **Package:** `es.benthem.bolextv`

Phase 1 per `docs/PLAN-20261029-v1.md` §4: launcher tile, TV banner, `LEANBACK_LAUNCHER`, kiosk
WebView pinned to the self-hosted tuner, remote key handling, back returns to the guide and never
exits, and a debug APK that installs with `adb install`.

---

## 1. What exists

```
androidtv/
├── settings.gradle.kts           plugin + dependency repos, rootProject "BolexTV"
├── build.gradle.kts              AGP 8.5.2, Kotlin 1.9.24
├── gradle.properties             no AndroidX, 2 GB heap
├── local.properties              sdk.dir — machine-local, gitignored
└── app/
    ├── build.gradle.kts          minSdk 23 / target 34, TUNER_URL build constant
    └── src/main/
        ├── AndroidManifest.xml    LEANBACK_LAUNCHER + LAUNCHER, banner, cleartext config
        ├── java/es/benthem/bolextv/MainActivity.kt
        └── res/
            ├── drawable/bolextv_banner.png   (320×180 — the size Android TV requires)
            ├── drawable/bolextv_icon.png     (512×512, Guide Play mark)
            ├── values/strings.xml, values/themes.xml
            └── xml/network_security_config.xml
```

**Deliberately zero external dependencies.** A framework `Activity` and a `WebView` need nothing
else. No AndroidX, no Compose, no Media3 yet. This keeps the first build fast and immune to
dependency-resolution failure — the most common reason a fresh Android project will not build.

## 2. Decisions and why

**Autoplay is enabled outright** (`mediaPlaybackRequiresUserGesture = false`). This is not a
convenience setting — it is a direct consequence of the Phase 0 measurement
(`docs/FIELD-RESULTS-20261029-v1.md`): a raw media URL in the WebView rendered one frame and started
no audio until a gesture was supplied. The tuner's own channel tap happens to satisfy Chrome's rule,
but a kiosk shell should not depend on that for every entry point.

**CH+ / CH- are intercepted, D-pad is not — a deliberate deviation from PLAN §4.** The plan says
"D-pad mapped to channel up/down". That mapping would break the guide: up/down is how you move
*within* a grid, and the tuner's grid is exactly that. Meanwhile a WebView ignores
`KEYCODE_CHANNEL_UP`/`CHANNEL_DOWN` entirely, so those keys otherwise do nothing at all. So the shell
intercepts the keys that are demonstrably free and leaves the ones the WebView already uses for focus.

Making D-pad mean "channel" *while watching* is genuinely mode-dependent, and deciding it in the
shell would mean guessing at page state. It belongs to the Phase 2 bridge contract, which is the
next ADR.

**Back never exits.** `KEYCODE_BACK` always returns `true` and asks the page for the guide; no branch
calls `finish()`. A kiosk that can be accidentally exited from a remote is a support call.

**Cleartext is allow-listed, not blanket-permitted.** `network_security_config.xml` permits plain
HTTP only for `192.168.2.93` (tuner) and `192.168.2.30` (Plex). `base-config` stays
`cleartextTrafficPermitted="false"`, so the exception is narrow and visible rather than a global
"turn off TLS" switch.

**Navigation is trapped in-app.** `shouldOverrideUrlLoading` returns `false` — every URL loads in the
kiosk WebView. There is no address bar and no way to navigate elsewhere.

**No JavaScript bridge.** Verified in Phase 0: `plex-tuner.html` contains zero occurrences of
`postMessage`, `addJavascriptInterface` or `window.BolexTV`. The shell therefore talks to the page
only by dispatching DOM events, which cannot silently corrupt page state. Adding a real bridge is
the Phase 2 ADR.

**A failed load explains itself.** `onReceivedError` on the main frame renders a dark page naming the
tuner URL and the error — never a silent black screen.

## 3. Building

Toolchain installed 29/10/2026 on `ai-agents` (none of it existed before):

| Component | Version | Location |
|---|---|---|
| JDK | OpenJDK 17.0.20.1 | `/usr/bin/java` |
| Android SDK platform | `android-34` | `/home/alex/Android/Sdk` |
| Build tools | `34.0.0` | `/home/alex/Android/Sdk/build-tools` |
| Gradle | 8.7 | `/home/alex/opt/gradle-8.7` |

```bash
cd androidtv
ANDROID_HOME=/home/alex/Android/Sdk /home/alex/opt/gradle-8.7/bin/gradle --no-daemon assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk
```

No Gradle wrapper is committed yet; the distribution is pinned by version in this document. Adding
`gradlew` belongs with the Phase 4 CI work so the wrapper and the CI image agree.

## 4. Installing

```bash
adb connect 192.168.5.86:5555          # Mi Box, authorised 29/10/2026
adb install -r androidtv/app/build/outputs/apk/debug/app-debug.apk
adb shell monkey -p es.benthem.bolextv -c android.intent.category.LEANBACK_LAUNCHER 1
```

## 5. Exit criteria — status

| Criterion | Status |
|---|---|
| Installs on the Mi Box | pending — APK not yet built at time of writing |
| Cold-starts to the guide | pending |
| Channel up/down from the remote | pending — needs a page-side listener for `bolextv:channel` |
| 50 channel changes without a memory climb | pending — `adb shell dumpsys meminfo es.benthem.bolextv` |

These are **not** claimed as met. This document records the code and the reasoning; the on-device
verification is a separate, cited measurement.

## 6. Known gaps

- **`bolextv:channel` has no consumer yet.** The shell dispatches the event; the tuner does not
  listen for it. Until the bridge exists, CH+ / CH- are delivered but end up as an unhandled
  `ChannelUp` keydown. Closing this needs either a small upstream patch or the Phase 2 bridge.
- No OSD, no subtitles, no sleep timer, no settings screen — all later phases.
- Release build is unsigned; sideloading uses the debug APK.
- `docs/PLAN-20261029-v1.md` still says the tuner runs on `.85`; it was provisioned as LXC 228 at
  `192.168.2.93`. The plan predates provisioning and should be corrected at the next revision.

---

*Code is cited by path; behaviour claims about the device come from `docs/FIELD-RESULTS-20261029-v1.md`
and `docs/FIELD-DEVICE-20261029-v1.md`, not from assumption.*
