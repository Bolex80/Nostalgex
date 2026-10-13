# Plex Session Reporting & Scrobbling

**Status:** Shipped in 1.0.9 (June 2026). Off by default since 1.0.11. Jellyfin and Emby use the same switch and the same 75% watch rule.  
**Why:** Keep watch history accurate while Nostalgex is in use. Rewatchables filters on real play counts from whichever server is connected.

Timeline reporting and scrobbling ship in the tvOS app, implemented in `Services/PlaybackTracker.swift`. Plex uses its timeline and scrobble endpoints. Jellyfin and Emby use their session reports, and the app reads `PlayCount` back when it loads the library. Rewatchables filters on `viewCount >= 3` for all three.

**Activity sync defaults to OFF.** The user turns it on in Settings under CONNECTION (REPORT PLAYBACK). Nothing is reported until they do. Plays they already made in Plex, Jellyfin, or Emby still count toward Rewatchables, because those counts live on the server.

**Reporting never fills Continue Watching (2026-10-11).** Turning it on means "my server sees what's playing and a real watch counts", not "every channel I surf past lands in Continue Watching". Settings copy, both surfaces: *"Off by default. When on, your server sees what's playing and a film you watch most of counts as watched. Channel surfing never fills your Continue Watching."*

---

## Continue Watching guard

Code: `Services/WatchStateGuard.swift` + `Services/PlaybackTracker.swift` (tvOS), `scripts/nostalgex-watch-state.js` + the tracker in `plex-tuner.html` (web). The decision table is shared through `scripts/watch-cleanup-golden.json`; `WatchStateGuardTests` and `npm run test:watch-state` both read it.

1. **Before the first report** the tracker reads what the server holds for the item (Plex `GET /library/metadata/{rk}`, plus `GET /hubs/continueWatching/items` for an episode to learn whether its show already had an entry; Jellyfin/Emby `GET /Users/{uid}/Items/{id}` UserData).
2. **Reports go out as before** (timeline / `Sessions/Playing`), so Now Playing and Tautulli still see the session. Every report and cleanup call runs through one serial queue: Plex writes a resume point on *every* timeline report, so a cleanup that lands before the last report is undone by it.
3. **When the session ends** (channel change, advance, disconnect, app backgrounded, reporting turned off) the tracker puts the item back:

| Server | Before | Session | Cleanup |
|---|---|---|---|
| Plex | unwatched, no resume point | surfed | `GET /:/unscrobble?key={rk}&identifier=com.plexapp.plugins.library` |
| Plex | resume point R | surfed | `PUT /:/progress?key={rk}&identifier=...&time=R&state=stopped` |
| Plex | watched, no resume point | surfed | `PUT /actions/removeFromContinueWatching?ratingKey={rk}` |
| Plex | unreadable | surfed | `removeFromContinueWatching` only, never unscrobble |
| Plex | episode, show not in CW | counted | `removeFromContinueWatching` on the next-up entry the scrobble created |
| Jellyfin/Emby | never played | surfed | `DELETE /Users/{uid}/PlayedItems/{id}` |
| Jellyfin/Emby | anything else | surfed | `POST /Users/{uid}/Items/{id}/UserData` with the prior position, PlayCount, Played, LastPlayedDate |
| Jellyfin/Emby | known | counted | `UserData` position 0, Played, PlayCount = prior + 1 |
| Jellyfin/Emby | unreadable | either | `UserData` position 0 only |

4. **After a Plex scrobble** the tracker keeps reporting with `time=0`. Any nonzero position re-creates a resume point on the item Plex just marked watched, which puts it straight back in Continue Watching.

All cleanup calls are best effort: one attempt each, off the main actor, one log line each (`[Tracker] cleanup ...`). They never block playback.

### Measured 2026-10-11

A real Plex Media Server, Emby 4.10.1.0, Jellyfin 12.2.0 (local, test library):

- Plex: `playing` timeline reports write `viewOffset` immediately (the item is in `/hubs/continueWatching/items` after the first one). `stopped` with `time=0` and `/:/progress` with `time=0`, `1` or `-1` change nothing. `/:/progress` with a real time sets that exact offset. `removeFromContinueWatching` hides the entry and keeps the offset. `/:/unscrobble` clears offset, `viewCount` and `lastViewedAt`. A scrobble clears the offset, but the next nonzero report writes a new one on the now-watched item; reports at `time=0` do not. An episode scrobble adds the show's next episode to Continue Watching within a second.
- **Plex `/:/scrobble` with `key=/library/metadata/{rk}` returns 404.** Only the bare rating key works. Both surfaces had sent the path form since 1.0.9, so no Nostalgex watch had ever been counted on Plex. Fixed.
- Emby and Jellyfin both increment `PlayCount` on the `/Sessions/Playing` start report (a 30 second surf counted as a play) and store the stop position as a resume point. `POST .../UserData` restores position, PlayCount, Played and a non-null LastPlayedDate exactly; it cannot null LastPlayedDate, which is why a never-played item is reset with `DELETE .../PlayedItems/{id}` instead. Both servers answer the `/Users/{uid}/...` routes (Jellyfin keeps them beside `/UserItems`). The transcode cleanup's `Sessions/Playing/Stopped` with only a `PlaySessionId` does not touch user data.
- Jellyfin 12.2 rejects `api_key` in the query string (401); the `Authorization: MediaBrowser ... Token=` header works on both.
- End to end, through the real tvOS tracker on a fake clock (`LiveContinueWatchingTests`, skipped unless `TEST_RUNNER_NOSTALGEX_LIVE_*` is set): a two minute surf on an unwatched Plex film (in Continue Watching mid-surf) and a counted Plex episode leave the Continue Watching row identical and the items' metadata back to their original state; the same surf plus a counted watch on Emby and Jellyfin leave Resume unchanged and UserData exact.

Not verified: Jellyfin/Emby **Next Up** after a counted episode (the Emby server measured has no TV library and the local Jellyfin test library has no shows). Next Up is a separate row from Resume on both, and a counted episode is a real watch, so it is left alone.

---

The rest of this document is the original design, kept because the gates, endpoints, and edge cases below are what actually shipped.

---

## Problem

Nostalgex is a read-only Plex client. Content plays continuously but Plex has no idea anything is being watched. Watch counts, On Deck, and Continue Watching all go stale. A future Rewatchables channel needs reliable watch data to mean anything.

## Goals

1. Report playback status to Plex server in real time (Now Playing)
2. Scrobble (mark watched) items the user actually watched
3. Keep Plex library stats accurate without inflating them from idle playback or late tune-ins

---

## What counts as "watched"? (hybrid rule)

**Both gates must pass:**

1. **Entry gate** — tune in during the **first 15%** of the simulated program  
   `entryFraction = seekOffset / (item.duration × 60) ≤ 0.15`

2. **Active time gate** — accumulate **≥ 75%** of the item’s total duration as **active watch time** from tune-in forward (only while playing on this channel, same session, not backgrounded)

Scrobble does **not** require reaching EOF — crossing 75% active while entry-eligible is enough.

**Examples:**

| Scenario | Scrobble? |
|----------|-----------|
| Join at 5%, watch 80% of runtime | Yes |
| Join at 5%, watch 50%, flip channel | No (below 75%) |
| Join at 90%, watch the last 10% | No (failed entry gate) |
| Join at 10%, watch to natural end | Yes |

The cable TV model still risks inflation if the app auto-advances while nobody is watching. Optional future: “Still watching?” after N auto-advances with no input.

---

## API endpoints

**1. Timeline update** — `PUT /:/timeline` (~every 10s while playing)

- `ratingKey`, `key`, `state` (`playing` / `paused` / `stopped`)
- `time`, `duration` (milliseconds)
- `X-Plex-Session-Identifier` — UUID per tune-in

**2. Scrobble** — `GET /:/scrobble`

- `key` = `{ratingKey}` (the bare key; `/library/metadata/{ratingKey}` is answered with 404, measured 2026-10-11)
- `identifier` = `com.plexapp.plugins.library`

---

## Implementation plan

**PlexAPIService:**

- `reportTimeline(...)` — PUT `/:/timeline`
- `scrobble(ratingKey:)` — GET `/:/scrobble`

**PlaybackTracker** (new service or AppState extension):

- Session UUID per tune-in
- Track `activeWatchTimeMs` per item / `loadGeneration`
- Set `eligibleEntry` from entry gate at `loadCurrentItem`
- Timeline timer ~10s while playing
- Evaluate hybrid rule on threshold, channel change, advance, disconnect

**AppState hooks:**

- `loadCurrentItem()` — start tracking
- `advanceToNextItem()` — evaluate outgoing item before advance
- Channel change / `disconnect()` — evaluate + invalidate
- Background — pause active clock, send `stopped`

---

## Edge cases

| Scenario | Behavior |
|----------|----------|
| Join at 80%, watch remaining 20% | No scrobble (entry gate) |
| Join at 10%, watch 80%, change channel | Scrobble on leave |
| Leave room, episodes auto-advance | May inflate — monitor; optional still-watching prompt |
| App backgrounded mid-item | `stopped` timeline; no scrobble unless 75% already hit |
| Network drop on timeline | Fail silently; retry scrobble if important |

---

## Opt-in default

Reporting is **off unless the user turns it on** (Settings → CONNECTION → REPORT PLAYBACK; web tuner: Settings → PLAYBACK). Channel surfing tunes past far more programs than a user deliberately starts. Since 2026-10-11 the Continue Watching guard above means turning it on no longer buries the household's real Continue Watching row either. Consequence for the Rewatchables channel: `viewCount` stays as reliable as it ever was, but Nostalgex only adds to it for users who opted in.

---

## Future: Rewatchables channel

Once scrobble data flows, Plex `viewCount` becomes reliable. Rewatchables filters on **rewatch count** (`viewCount >= N`) — **not year range**. Channel rules already support `rewatched` / `watchedOnly`; they need accurate Plex stats first.

---

## Related

- Daily manifest scheduling (Nostalgex-internal freshness) is separate — does not use Plex `viewCount`
