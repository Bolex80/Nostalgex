# Phase 1 measurements — 29/10/2026

Device: `MiTV-AFMU0`, Android 14 / SDK 34, 32-bit, `192.168.5.86:5555`.
Build under test: `es.benthem.bolextv` debug APK on branch `plan/20261029-foundation`.
Tuner: LXC 228 `.93:8080`, image `20261029c`, `enrichment: true`.

The gate is **not passed**. Two of the three measurements are done, one fails, and
one could not be completed because the TV was taken over by someone else.

## A. Cold start to guide — PASS

| Run | Activity first frame | Guide painted |
|---|---|---|
| 1 | 1,239 ms | 5,814 ms |
| 2 | 1,176 ms | 5,676 ms |
| 3 | 1,257 ms | 5,857 ms |

`TotalTime` from `am start -W` is the activity's first frame; "guide painted" is the
first moment the guide's own text appeared, measured by polling. The poll costs
~0.35 s per sample, so treat 5.7-5.9 s as an **upper bound**, not a precise figure.

Also observed in all three runs: the app opened **already signed in**. That is the
session-persistence fix proven across a real `force-stop`, which is the thing it was
written for. No PIN, no connect screen.

## B. CH+ / CH- through real channels — FAIL

Measured with `adb shell input keyevent 166` (CHANNEL_UP) while a channel was playing:

- Programme title on screen: unchanged after the press.
- Pixel diff of the title region: **0 of 122,400 px changed (0.00%)**.
- Pixel diff of the video region: **18.36% changed** — the sanity check that the
  screenshot was of a live screen and not a stale frame.

So the screen was moving and the channel was not. CH+ does nothing.

Root cause: the previous implementation changed channel by running JavaScript in the
page. That stops working during playback — the app's debug page dump also goes
completely silent in the player, which is the same symptom. Anything routed through
`evaluateJavascript` is unreliable exactly when a channel change matters.

Fix implemented, **not yet validated**: `changeChannel()` now delivers the key to the
WebView as a real input event (`webView.dispatchKeyEvent`, DPAD_DOWN for CH+, DPAD_UP
for CH-), which needs no JS and therefore keeps working during playback. The page
already binds ArrowUp/ArrowDown to prevChannel/nextChannel, so no page change is
needed.

## C. 50 channel changes + memory — INCONCLUSIVE

50 presses of CH+ took 20.2 s (404 ms per press), process alive, **0 FATAL EXCEPTION**,
PSS 172.1 MB -> 195.8 MB (**+23.7 MB**).

But because B fails, those 50 presses did not change channels. This run therefore
measures key-handling stability under repeated input, not what the criterion asks
for. It must be re-run after B is fixed. Previous runs measured +6.5 MB and +33.1 MB;
the spread is measurement noise from `dumpsys meminfo` sampling, not a trend.

## Why the TV could not be used further

The last attempt returned 0% change in both the title and the video regions — a static
screen. `dumpsys` showed `com.disney.disneyplus/.MainActivity` in the foreground and
the app not running at all. Someone is using the box, so the measurement stopped
there rather than pressing keys on an occupied TV.

## Harness notes (for the next run)

Take 1 was invalid twice over: it pressed F1 to force a page dump when the debug build
already dumps on every key press, and it re-read the whole logcat buffer each time,
which the large PAGE lines overflowed. Take 2 filtered `BolexTV:I`, which excludes the
app's **Debug** lines, and tested liveness with `PKG in pidof(PKG)` — `pidof` returns a
bare PID, so that could never match. Both are fixed in `phase1-measure3.py`.

The `||CH:` field was added to the debug dump (`#np-channel-tag`, plex-tuner.html:5062)
because the guide prints "CHANNEL n OF m" but the player does not, so the channel
number vanished exactly when a channel change was being measured. It is empty during
fullscreen playback, which is what exposed the blocked-JS problem in the first place.

## Take 3 — after the focus fix, read with vision

`webView.dispatchKeyEvent` alone did nothing because an unfocused View drops dispatched
keys. Adding `webView.requestFocus()` made the keys reach the page: the app now logs
`dispatch dpad key=... focus=true`.

What the keys then actually do was read off the screen rather than inferred from a pixel
diff, because the diff was unstable (0.76% in one run, 13.41% in another) as the overlay
fades in and out:

- Before CH+: playing programme **"Gigi & Nate"**, guide highlight on **row 20**.
- After CH+: playing programme **"Gigi & Nate"** (unchanged), guide highlight moved to
  **row 21 DIZ FLICKS**.

So CH+/CH- move the guide cursor one channel. They do **not** change the playing channel.
That matches the page's own on-screen hint, `[ENTER] TUNE IN [UP/DOWN] BROWSE`: with the
guide open, ArrowDown is browse, not tune.

Measurement B is therefore still **FAIL**, but for a different reason than before, and the
remaining work is small and well defined: tuning must be a two-step action when the guide
is open (move the cursor, then ENTER to tune in), and a one-step action when it is not.
The page's state has to be known to pick between them, and `evaluateJavascript` is
unreliable during playback - so this wants a native signal rather than a JS query.

Measurement C, re-run with the keys now reaching the page:

| | |
|---|---|
| 50 CH+ presses | 60.0 s (1.2 s each) |
| PSS | 185.9 MB -> 188.6 MB (**+2.7 MB**) |
| Crashes | **0 FATAL EXCEPTION** |
| After | process alive, app still rendering |

That is a markedly better memory figure than the earlier runs (+23.7 MB, +33.1 MB), which
were taken while the channel was not changing at all - so the earlier numbers were not
measuring channel churn.

## Take 4 — gate PASSED

The channel-change route that works is the page's own guide row click, and nothing else.

Diagnosis, using the WebView's DevTools socket (Chrome 155 over `adb forward`) rather than
pixels or `evaluateJavascript` callbacks:

- The DOM carries `.grid-row[data-channel-id]` for 25 channels, with `active` on the one
  playing and `focused` on the guide cursor. After a key-only CH+ the state read
  `active=20, focused=21` — the cursor had moved and the programme had not.
- Clicking `.grid-row.focused` changed playback from "CH 20 FAMILY HOUR" to
  "CH 21 DIZ FLICKS". That is the tune path: the row's own click handler.
- Key-based routes all failed: lone arrow, arrow+DPAD_CENTER, arrow+KEYCODE_ENTER, and
  arrow-then-click (which worked exactly once — after the click the DOM focus moves to the
  row, so later arrows stop driving the guide and the cursor freezes).

So `changeChannel()` now does the whole step in JS: read the playing row, step ±1 through
the rendered guide rows, click the target. No keys, no dependence on focus.

Final measurements:

| Criterion | Result |
|---|---|
| Cold start | activity first frame **1,118 ms**; guide-ready ~5.7 s in earlier runs (the poll in this run only read logcat, and the page only logs on a key press) |
| CH+ / CH- | sequence **20 -> 21 -> 25 -> 21**; direction correct, repeatable |
| 50 changes | 67.1 s (1,342 ms each), channels reached **21, 31, 44, 52, 86** |
| Memory | PSS 211.8 -> 195.2 MB (**-16.6 MB**), process alive, still responding |
| Crashes | **0 FATAL EXCEPTION** |

Earlier pixel-diff numbers are superseded: the diff was unstable because the overlay
fades, and it was measuring the cursor moving, not the channel changing.
