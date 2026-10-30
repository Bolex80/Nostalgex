# Subtitles (Plex)

The page could only do Jellyfin/Emby captions: it asked their API for a ready-made VTT. Plex
serves SRT from `/library/streams/<id>?download=1`, so the same blob-plus-`<track>` technique
works after converting the format.

## Control

One rail button, `SUBTITLES [S]`, cycling **OFF → EN → ES**, and the `S` key in the browser.
A remote has six buttons; a language menu is one too many.

## Choosing a track

Plex metadata is asked for `Stream[streamType="3"]` and text codecs only (srt/subrip/vtt/webvtt).
Image subtitles (PGS/DVD) cannot be rendered as a `<track>` and are skipped rather than shown as
garbage.

Plex often leaves external SRTs untagged — measured on one film, two of three had no language —
so after trying a tagged match the page reads a sample of each track and detects English or
Spanish from the cue text.

The button and the track's `srclang` always show the language **actually playing**, not the one
requested. Asking for EN on a channel that only has Spanish gives the Spanish track and a toast
reading `SUBTITLES: NO EN — SHOWING SPA`.

## Measured on the box

| Case | Result |
|---|---|
| Spanish-only channel (5, Step by Step) | `shown:453946:spa`, label SPA, cue "porque hace meses, tú, Linda," |
| English channel (7, When Harry Met Sally) | `shown:438069:eng`, label ENG, cue "Than live with the man you've had" |
| Request EN where only Spanish exists | toast `NO EN — SHOWING SPA`, label SPA |
| Film with English + Hindi only (ch 1) | labels honestly, no false claim of Spanish |

Library sample, 75 recently added films: **67 have text subtitles, 61 English, 57 Spanish**, 8
none — so a Spanish miss is the exception, not the rule.

## Notes

- Cues follow channel changes: the page re-applies the chosen language when the programme changes.
- The existing Jellyfin/Emby subtitle path is untouched; this is an additive Plex path.
- The preference is stored in `localStorage['plex90_plex_sub_mode']` and survives restarts.
