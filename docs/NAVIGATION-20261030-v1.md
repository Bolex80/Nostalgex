# Remote navigation model

Six buttons only: up, down, left, right, OK, back. Every rule below exists because a
measured failure made the old behaviour ambiguous.

## The rules

| Button | In the guide | On the side rail | In a full overlay (settings, server picker) |
|---|---|---|---|
| Up / Down | browse the guide (the page's own cursor) | walk the rail | move the focus ring geometrically |
| Left | enter the rail | nothing | move left |
| Right | nothing | return to the guide | move right |
| OK | tune the highlighted channel | activate the control | activate the control |
| Back | leave prompt | return to the guide | close the overlay |

Back never leaves the app from inside something. It closes the topmost layer first, then
offers to leave on the top screen, which is Plex's behaviour and what Alex asked for. The
leave prompt focuses **Stay**, so a stray second press cannot quit.

## Why the focus ring is drawn by the shell

The page keeps its own guide cursor and highlights it itself, so in the guide the page is
the single source of truth and the shell leaves the arrows alone. In an overlay the page
draws no focus state at all: its settings tabs render at negative y (measured: `y = -77`
while the panel is scrolled), so the D-pad walked into elements scrolled out of view, the
ring vanished, and CLOSE could never be reached. The shell therefore walks the overlay
geometrically and paints `.tv-focus` itself.

Geometric, not list order: on one measured screen the nearest control to the left of CLOSE
was the last tab, not the first, and only geometry gets that right. It also means any
overlay the page adds later works without new code.

## Focus is read from the title

Back needs to know which layer is open *synchronously*. `evaluateJavascript` callbacks go
silent while a video plays - exactly when Back is pressed - so the engine mirrors its layer
into `document.title` (`BolexTV:ov` / `:guide` / `:player`) and the shell reads
`webView.title` before acting. A Back that sometimes does nothing is worse than no Back.

## Submenus are left to the page

The quality and sleep submenus navigate natively. An earlier build treated them as "guide"
and the next OK tuned a channel while the user thought he was picking a stream quality.
Anything focusable that is not the rail and not inside the guide is now passed straight
through, untouched.

## Sizing, measured at 960x540 CSS with a 2x device pixel ratio

| Element | Was | Now | Reason |
|---|---|---|---|
| `.info-title` | 42px, up to 4 lines | 26px, clamped to 2 | four lines of film title ate a third of the screen |
| `.info-channel-tag` | ended at y 68, title began at y 66 | 6px gap | the 2px overlap was the "text on top of text" in the photo |
| `.grid-row` | 38px tall | 44px minimum | unreadable from a sofa |
| `.grid-row-channel` | 160px, "FAMILY H…" | 230px at 16px | channel names now fit whole |
| focus ring | none | 3px amber `#E9A13B` | the page draws no focus state in overlays |

## Second pass, after Alex tested it on the box

Four things he could not reach, all measured on the device afterwards.

**The announcement banner was unreachable.** Its three buttons sit directly above channel 1
and are real `<button>`s, but the page's guide cursor only visits channels. Up from the
first channel now lands on the banner, and the three buttons walk sideways. Measured:
Up -> "PRESS TO ADD THE SCREAM PACKAGE", Right -> "NOT THIS YEAR", Right -> "DON'T ASK
AGAIN", Down -> back to channel 1.

**Leaving the rail was impossible.** Back on the rail opened the leave prompt, because the
shell only knew about overlays. It now reports `BolexTV:rail` and Back on the rail returns
to the channel list. Measured: Left -> rail (`:rail`), Back -> guide (`:guide`).

**Long lists would not scroll.** The overlay focus list was filtered to elements already on
screen, so every card below the fold was dropped and focus could never travel down to drag
the panel. Overlays now list anything laid out, and scrolling is what makes it visible.
Two separate bugs were behind this: the filter, and a selector that matched `.bundle-card`
and `.config-row` when the rows are actually `.bundle-row`. Measured: Down from CLOSE walks
the tabs and then eight bundle rows while the panel scroll moves 0 -> 266 px on a list
7,892 px long.

**Exit is now visible, and leaving is instant.** The rail ends with an EXIT button, added by
the shell to the page's own rail so it looks and moves like the rest. It navigates to
`bolextv://exit`, a scheme only this client answers, because there is no JS bridge and the
page does not need one. "Leave" backgrounds the task instead of finishing it: the WebView
keeps its library, session and playback position, and the process survived the exit
(pid unchanged). Reopening measured `TotalTime: 0`, against a full reload of roughly 20
seconds before.

## Third pass: time travel in the guide, and a ring that survives a tune

**Arrow-right did nothing because there was nothing to move along.** The guide renders a fixed
two-hour window anchored on "now" (`windowStartMs`, rounded down to 30 minutes), so the time
axis was never navigable - on the web either. The window is now offset by a half-hour step:

- Right walks forward: measured 14:30 -> 15:00 -> 15:30 on the header, with the programmes
  re-rendered for the new window.
- Left rewinds, and at the live edge it still opens the rail, which is the route Alex uses
  for the buttons.
- The page's own keyboard handler does the same, so the browser and the box behave alike.

**The highlight jumped back to the first channel after every selection.** Two causes, both real:

1. The page's guide cursor (`guideFocusIndex`) was never updated by `switchChannel`, so it
   stayed wherever the guide opened and the page's own highlight sat on row 1. It now follows
   the channel that starts playing.
2. The shell's amber ring lives on a DOM node that the page destroys whenever it re-renders
   the guide - which happens on a timer and after every tune. A one-shot restore was wiped by
   the next render. The ring is now restored whenever it goes missing while the guide is on
   screen, and Down with no ring starts from the channel that is playing instead of row 1.

Measured after the fix: ring on channel 1 at launch; walk to channel 6, OK -> playing
CH 06, ring stays 6, page cursor 6, still 6 three seconds later, and the next Down moves to 7.

## Fourth pass: full screen, and a way back out of it

Two requests: a second OK should fill the screen, and Back while watching must not offer to leave
the app.

**Element fullscreen does not work in an Android WebView.** `requestFullscreen()` rejects and the
page's `toggleFullscreen()` does nothing there, so the FULL SCREEN button and the overlay's exit
control were both inert on the box (they still work in a browser). On a television the guide *is*
the windowed view, so "full screen" means hiding it: the shell calls the page's own `hideGuide()`,
and "exit full screen" calls `showGuide()`.

**OK on a guide row delivered neither a keydown nor a click.** A guide row is a `div`; a WebView
turns DPAD_CENTER on a focused div into nothing at all, which is why pressing OK on the programme
already playing did nothing. OK is now decided in the page (`__tvOkPress`): tune a different row,
fill the screen on the one already playing, or press an announcement button — and the shell calls
it only while the guide is up, leaving every other screen's OK untouched.

**The in-player menu already existed** — channel, title, progress bar, time, CH-/CH+, SOUND and
EXIT FULL SCREEN — but nothing could reach it from a D-pad. Back (or OK) while watching now opens
it and puts the ring on CH-; Back or OK again closes it and keeps watching.

Measured on the box: guide -> OK -> `:player` with the guide hidden; OK -> `:fsmenu` showing
`1:11:05 / 1:36:00` and a 74% bar; OK -> menu closed, still full screen; Back -> menu; Back ->
closed. Right x3 lands on EXIT FULL SCREEN, and OK there restores the guide.
