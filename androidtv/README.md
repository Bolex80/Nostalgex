# BolexTV — Android TV shell

The APK that puts the tuner on the television. It is deliberately thin: a WebView plus the
navigation, key dispatch and lifecycle that a six-button remote needs. Everything the user can
*see* lives in the page (`plex-tuner.html`), so the browser and the TV stay identical.

- **Application ID:** `es.benthem.bolextv`
- **Device:** Xiaomi Mi Box `MiTV-AFMU0`, Android 14 / SDK 34, **`armeabi-v7a` — 32-bit only**
- **Sideload only.** No store listing, no telemetry, no accounts.

## Layout

| Path | Role |
|---|---|
| `app/src/main/java/es/benthem/bolextv/MainActivity.kt` | WebView host, `dispatchKeyEvent`, channel keys, Back hierarchy, exit prompt, injected CSS/JS |
| `app/src/main/assets/tvnav.js` | **The only copy** of the navigation engine: geometric focus, zones, ring persistence |
| `app/src/main/res/` | Launcher icon and banner (generated from `brand/`) |
| `app/src/main/res/xml/network_security_config.xml` | Cleartext allow-list for the LAN tuner and Plex |

There used to be two copies of the navigation engine (a Kotlin string and a JS file); they drifted
twice, so the engine now lives only in `assets/tvnav.js` and is loaded with `asset("tvnav.js")`.

## Build

Requirements, all present on the build host:

- JDK 17 (`openjdk-17-jdk-headless`)
- Android SDK at `/home/alex/Android/Sdk` with `platforms;android-34`, `build-tools;34.0.0`, `platform-tools`
- Gradle 8.7 at `/home/alex/opt/gradle-8.7`
- `android-tools-adb`

```sh
cd androidtv
ANDROID_HOME=/home/alex/Android/Sdk /home/alex/opt/gradle-8.7/bin/gradle \
  --no-daemon --console=plain assembleDebug
```

Output: `app/build/outputs/apk/debug/app-debug.apk` (~820–840 KB, builds in 7–15 s).

`local.properties` pins the SDK path locally and is not committed.

## Install

```sh
adb connect 192.168.5.86:5555          # wireless debugging must be enabled on the box
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n es.benthem.bolextv/.MainActivity
```

The first `adb connect` shows an authorisation prompt on the television; accept it once.

## Point it at a tuner

The URL is baked in at build time as `BuildConfig.TUNER_URL`:

```kotlin
buildConfigField("String", "TUNER_URL", "\"http://192.168.2.93:8080/plex-tuner.html\"")
```

Any new host must also be added to `network_security_config.xml`, or the WebView refuses the
cleartext connection.

## What the shell handles

Only the things a page cannot do for itself:

1. **Keys** — `dispatchKeyEvent` forwards arrows, OK and media keys to the WebView, which must be
   focused first (`requestFocus()`); an unfocused WebView silently drops dispatched keys.
2. **Channel keys** — CH+/CH− move the guide cursor and then click the row, because a `div`
   receives neither a keydown nor a click from `DPAD_CENTER`.
3. **Back hierarchy** — in-player menu → close; full screen → open the menu; settings/picker →
   close; rail → guide; guide → leave prompt (defaulting to **Stay**).
4. **Leaving** — Leave backgrounds the app rather than killing it, so returning is instant and the
   channel keeps playing.

## Verifying on the device

```sh
PID=$(adb shell pidof es.benthem.bolextv)
adb forward tcp:9222 localabstract:webview_devtools_remote_$PID
curl -s http://127.0.0.1:9222/json
```

The WebView **must be foregrounded**: backgrounded, it lays out at 0×0 and every measurement
comes back wrong. `evaluateJavascript` callbacks also stop during playback, so the DevTools socket
is the reliable oracle.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Keys do nothing, Back still works | The WebView lost focus; the Activity handles Back itself. Call `requestFocus()` after dialogs. |
| adb `unauthorized` | Accept the prompt on the television, then `adb connect` again. |
| adb drops every few minutes | Power-saving WiFi on the box; ping 105–1120 ms is normal. |
| Blank page, no error | Tuner unreachable, or its host missing from the cleartext allow-list. |
| Video plays, no sound | Known AC3 direct-play defect — see `docs/FIELD-RESULTS-20261029-v1.md`. |

## Versioning

`versionName` / `versionCode` live in `app/build.gradle.kts`. The shell and the tuner version
independently; see [`docs/VERSIONS-20261030-v1.md`](../docs/VERSIONS-20261030-v1.md) for the
current pair and every image ID.
