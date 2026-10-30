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
