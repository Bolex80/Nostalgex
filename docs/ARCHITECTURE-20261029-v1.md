# BolexTV Architecture — WebView tuner + native Media3 player

BolexTV, Android TV. Plex only. Derived from the Nostalgex web tuner
(`plex-tuner.html`) and its shared engine (`scripts/*.js`) in this repository.
Jellyfin and Emby paths exist in the code but are out of scope; where they
diverge from Plex it is noted, not specified.

The plan: the web tuner runs inside an Android WebView and keeps ownership of
sign-in, server discovery, channel definitions, the schedule engine, and the
guide UI. A native Media3/ExoPlayer surface takes over playback of the resolved
stream URL. This document states what the tuner actually does today, with
citations, and defines the JS↔native bridge the Android build must add, because
today it does not exist (see section 3).

## 1. Plex API contract

Base assumptions. Two base URLs are in play: `https://plex.tv` (account, PIN,
discovery) and the selected server base URL (`plexServerUrl`), which is chosen at
runtime from the server's connection list and can change if a connection fails —
a connection that responds to a library fetch replaces the stored one
(`plex-tuner.html:9067-9076`). The tuner therefore never assumes one canonical
server URL; the native side must treat the server URL as data handed over per
tune, not as config.

### 1.1 Sign-in / token acquisition (Plex PIN flow)

Implemented in `startPlexAuth` (`plex-tuner.html:7658-7726`):

1. `POST https://plex.tv/api/v2/pins` with `plexHeaders()` as headers. The code
   and PIN id come back in JSON (`plex-tuner.html:7664-7671`).
2. The 4-character code is shown with a QR pointing at `https://www.plex.tv/link/`
   (`plex-tuner.html:7678-7687`). The user authorises out of band.
3. Poll `GET https://plex.tv/api/v2/pins/{pin.id}` every 2 s, up to 150 attempts
   (5 min), until `authToken` appears in the response (`plex-tuner.html:7693-7714`).
4. The token is stored in `sessionStorage['plex90_token']` and a saved-auth blob
   in `localStorage['plex90_saved_auth']` (`plex-tuner.html:7708-7710`, and the
   persist block at `plex-tuner.html:7647-7652`).

Common Plex headers are built by `plexHeaders()` / `PLEX_HEADERS`
(`plex-tuner.html:7581-7621`): `X-Plex-Product: Nostalgex`,
`X-Plex-Version: 1.0.0`, `X-Plex-Platform: Web`, and
`X-Plex-Client-Identifier` from `getClientId()` (a per-device id,
`plex-tuner.html:7609`). A token, when present, goes in the `X-Plex-Token`
header (`plex-tuner.html:7620`).

On reload the token is re-validated against `GET https://plex.tv/api/v2/user`;
a 401 means revoked, a network error falls back to trying the server directly
(`plex-tuner.html:8029-8069`).

### 1.2 Server discovery

`GET https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1` with the
token header (`plex-tuner.html:7769`). Each candidate connection URI is probed
with `GET {uri}/identity`, 5 s timeout (`plex-tuner.html:7730-7742`). Multiple
servers and per-server fallback connection URIs are supported; every library
fetch walks `server.url + server.connections[].uri` until one answers
(`plex-tuner.html:9045-9114`).

### 1.3 Library sections and item listing

- Sections: `GET {server}/library/sections` with `Accept: application/json` and
  `X-Plex-Token` (`plex-tuner.html:9098-9100`, per-server variant at 9169).
- Items: paged, never unpaginated.
  `GET {server}/library/sections/{section.key}/all?includeGuids=1&X-Plex-Container-Start={start}&X-Plex-Container-Size=300`
  (`plex-tuner.html:9137-9152`, `PLEX_PAGE_SIZE = 300` at :9137). Paging stops
  on an empty page or when the accumulated count reaches
  `MediaContainer.totalSize` (`plex-tuner.html:9157-9160`). `includeGuids=1` is
  required so items carry `Guid: [{id: 'tmdb://…'}]`; without it, membership
  matching and enrichment have no TMDB id (:9143-9146).

### 1.4 Stream resolution for a tuned programme

Decision point is the `else` (Plex) branch of the play routine
(`plex-tuner.html:5565-5595`).

Direct play (`plex-tuner.html:5566-5575`): allowed only when
`!item._forceTranscode && item.partKey && container ∈ {mp4, webm, mov}` and
`NostalgexStreamQuality.directPlayAllowed(currentLevel, item.bitrate)`
(`scripts/nostalgex-stream-quality.js:110`). The URL is the raw part:

```
{item.serverUrl || plexServerUrl}{item.partKey}?X-Plex-Token={item.serverToken || plexToken}
```

The join offset is applied client-side by seeking the element
(`video.currentTime = item.offsetSeconds`, `plex-tuner.html:5687` and
`:5697`). Note there is no container sniffing beyond the container field; the
comment at :8854 admits "container alone lies" and an `onerror` handler retries
once via transcode (`plex-tuner.html:5750-5753`). For Media3 this browser
codec check is meaningless — the Android build must redo the direct-play
decision against ExoPlayer capabilities.

Transcode (`plex-tuner.html:5577-5594`):

```
{item.serverUrl}/video/:/transcode/universal/start.m3u8
  ?path={encodeURIComponent('/library/metadata/' + item.ratingKey)}
  &mediaIndex=0&partIndex=0&protocol=hls
  &offset={floor(item.offsetSeconds || 0)}
  &copyts=1&X-Plex-Token={token}
  &session={uuid}&X-Plex-Session-Identifier={uuid}
  &X-Plex-Client-Identifier={getClientId()}
  &X-Plex-Product=Plex%2090
  &X-Plex-Platform=Web&X-Plex-Platform-Version=1.0
  &X-Plex-Device=Browser&X-Plex-Device-Name=Plex90
  + NostalgexStreamQuality.plexTranscodeQuery(currentLevel)   // :87-108
```

Here the join offset is server-side via the `offset` query parameter (seconds).
The session id is generated client-side because otherwise "Plex keys the
transcode off the client id alone" (`plex-tuner.html:4166-4168`), and is used
to stop the transcode on exit:
`GET {server}/video/:/transcode/universal/stop?session={id}&X-Plex-Token={token}`
(`plex-tuner.html:4266-4267`).

Watch-state reporting (Now Playing / scrobble) runs through
`NostalgexWatchState.plexGuard`, which PUTs `/:/timeline` updates carrying
position and session (`plex-tuner.html:5241-5341`; `timelineUrl` at :5328).
The Jellyfin/Emby divergence (`/Sessions/Playing*`, :5334-5341) is out of scope.

Credentials are per-item: `item.serverUrl || plexServerUrl`,
`item.serverToken || plexToken` (`plex-tuner.html:5571-5572`) for
multi-server pools. The bridge payload must therefore carry the full
credentialled URL, never a URL the native side reassembles.

## 2. The schedule algorithm

Entirely client-side. There is no server-side schedule component; Plex is only
a source of items and durations. The engine is
`scripts/nostalgex-daily-manifest.js` (UMD, mirrors the tvOS
DailyManifestStore — the parity harness is
`scripts/nostalgex-schedule-parity-smoke.mjs`).

Pool and memberships. Channel definitions come from `channels.json`
(`plex-tuner.html:3955-3970`) and per-channel programme membership rules from
`channels-memberships.json` (`plex-tuner.html:4069-4072`), shared with
`scripts/nostalgex-channel-filter.cjs`. An item's duration in minutes comes
from its Plex metadata (`minutesFromPlexMs`, `nostalgex-daily-manifest.js:505`).

Determinism. `packDay` (`nostalgex-daily-manifest.js:360-465`) builds one local
day of blocks: interleave by show with a seeded shuffle
(`interleaveByShow`, :100; `splitmix64`/`makeSeededRNG` seeded from
`channelId` and the day number, :43-98), prime-time promotion of recently
added items on premiere channels only (:177-211), sequel grouping (:213),
then blocks laid contiguously from local midnight using item durations. A
cross-day seam guard rotates the first item if it equals yesterday's last
(:381-388). Any unfilled remainder is a filler cycle offset by
`dayNumber * floor(totalPoolSec * 0.6180339887) mod totalPoolSec` — a golden-ratio
shift so consecutive days differ deterministically (:405-415).

Storage. Manifests are cached client-side keyed by
`(serverKey, channelId, localDayKey)` (`storageKey`, :313; `loadManifest` /
`saveManifest`, :317-337) with a `poolFingerprint` (:304) so a library change
invalidates the day. `airedRatingKeys`/:338 tracks what aired yesterday to feed
the seam guard. On Android this persists in the WebView's localStorage;
nothing needs porting.

Join offset. `tuneIn(channel, pool, precomputed, nowSec, serverKey)`
(:607-614): use the guide's precomputed schedule if it is still current, else
build one; the seek target is `liveElapsedSeconds(schedule, nowSec)` = the
wall-clock seconds elapsed since `nowPlaying.startSec` (:592-598;
identical math inline in `buildSchedule`, :572-579). The caller then puts that
on the item: `item.offsetSeconds = NostalgexDailyManifest.liveElapsedSeconds(...)`
(`plex-tuner.html:4692`) or on advance `{...pick.item, offsetSeconds: pick.seekSeconds}`
(`plex-tuner.html:4736`, `advancePick` :670-686). Channel-down conflicts
(`resolveConflicts` :621, `findConflict` :654) keep a channel playing the title
it yielded with, mirroring tvOS.

DST. Handled explicitly. Days are local, not fixed-length: `startOfLocalDayMs`,
`startOfNextLocalDayMs` (midnight +36 h then floor — "36 hours after a day's
start is always inside the next day", :272-285), `previousLocalDayKey`
(midnight −12 h, :290-293), and `localDayLengthSec` returning 23/24/25 h
(:295-298). `packDay` fills to `dayStartSec + localDayLengthSec(dayStartSec)`
so a 25-hour day has no empty last hour (:361-363). There is a dedicated smoke
test, `scripts/nostalgex-schedule-dst-smoke.mjs`, with golden
`scripts/schedule-dst-golden.json`.

## 3. The JS↔native boundary (bridge contract)

Current state: the web tuner exposes nothing usable to a native host. The only
deliberate window assignment is `window.__openPromoModal` (`plex-tuner.html:9928`),
a marketing hook. All engine pieces (`NostalgexDailyManifest`,
`NostalgexWatchState`, `NostalgexStreamQuality`, `NostalgexPlaybackInfo`) are
plain browser globals written for in-page use, and playback drives a `<video>`
element directly (`plex-tuner.html:5608-5697`). There is no postMessage layer,
no event bus, no `prompt()`/`console` bridge convention. **The bridge below
must be added.** Recommended implementation: an injected
`@JavascriptInterface` object named `BolexTV` for JS→native, and
`webView.evaluateJavascript(...)` calling a small dispatcher
(`window.BolexTVNative`) for native→JS. All payloads JSON.

### 3.1 `BolexTV.tune(payload)` — JS → native

Payload:
`{ url, headers: {…}, seekSeconds, isHls, item: { ratingKey, title, show?, durationSec, serverUrl, serverToken?, clientId }, transcodeSessionId?, generation }`.

- `url` must be the fully resolved, credentialled stream URL exactly as section
  1.4 builds it (either `...partKey?X-Plex-Token=...` or the
  `transcode/universal/start.m3u8` URL with all query params).
- `seekSeconds` = `item.offsetSeconds` (join offset). For HLS it is already in
  the URL's `offset` param; native must still `seekTo` for direct play, matching
  `video.currentTime` at `plex-tuner.html:5687`.
- Fires from inside the play routine after `ownsPlaybackRequest(request)`
  (`plex-tuner.html:5598`), replacing the `video.src =` assignment.
- If native fails to open the stream it must call back
  `BolexTVNative.onTuneFailed({ generation, reason })`; the JS side already has
  a direct-play→transcode retry path keyed on decode failure
  (`plex-tuner.html:5750-5753`) which should be driven by this callback instead
  of `video.onerror`.
- Late callbacks must be dropped by `generation`, the same rule
  `NostalgexPlaybackInfo` uses (`scripts/nostalgex-playback-info.js:14-18`).

### 3.2 `BolexTV.stop(payload)` — JS → native

Payload: `{ generation, reason: 'tune-away'|'user-stop'|'page-hide' }`.
Fires where the tuner today pauses/clears the video element and stops
`playbackTracker` (`plex-tuner.html:5494`, :5807, `pagehide` at :6451). On
receipt native stops and releases the player. If a transcode session was
handed over, JS keeps ownership of the `/transcode/universal/stop` call
(`plex-tuner.html:4266`) — do not duplicate it natively.

### 3.3 `BolexTVNative.onPlaybackState({ generation, state, positionMs })` — native → JS

States: `loading | playing | paused | stalled | ended | error`. Drives the
Playback Information panel (`beginPlaybackInfo` / `watchPlaybackInfoReady`,
`plex-tuner.html:4188-4208`) and `playbackTracker.onReady/onPause/onResume`
(:5737-5743). The web `NostalgexWatchState` `/:/timeline` reporting stays in JS
(timeline positions are computed from wall-clock watch time, not from element
time, :5294-5296) so native position reports are for the OSD only, 1 Hz while
playing. If native reports `ended`, JS must run its programme-advance path
(`advancePick` equivalent, `plex-tuner.html:4736`) rather than native looping.

### 3.4 `BolexTV.getNowNext(payload)` / `BolexTVNative.onNowNext(...)` — request + push

JS already computes now/next per channel via `tuneIn`'s schedule
(`{ nowPlaying, upNext, progress, elapsedSeconds }`,
`nostalgex-daily-manifest.js:572-579`). Expose a function the native OSD calls
with `{ channelId }` and a push when the underlying schedule rolls over (the
`tuneIn`/`buildSchedule.nowPlaying` boundary). Native uses it to draw the
channel-change OSD; it must never block waiting — if JS is mid-refresh, show
stale metadata and wait for the push.

### 3.5 Failure contract summary

- Native tune failure → `onTuneFailed` → JS one-shot transcode retry, then give
  up and tell the guide (existing UX copy paths).
- JS sends `tune` for a new generation while native is playing → native hard
  stops the old session first; `stop` for the old generation is not guaranteed.
- WebView crash/reload → native must release the player on
  `WebView.destroy()`/render-process-gone; the transcode-stop on `pagehide`
  (`plex-tuner.html:6451-6452` + :4266) will not fire on a hard kill, so the
  transcode session may linger server-side until Plex's own idle timeout.

## 4. Risks and unknowns

- Whether Plex honours an HLS `offset` > 0 universally, or only for certain
  containers/agents: not determined from the repository. Needs a real Plex
  server against channels with mkv/hevc content.
- Whether ExoPlayer can direct-play the same MP4/MOV part URLs without extra
  headers beyond the query token: not determined from the repository; Plex may
  also scope the token by client identifier. Needs a device test.
- The exact `plexTranscodeQuery` param set per quality level
  (`scripts/nostalgex-stream-quality.js:87-108`) was not enumerated line by
  line; treat lines 87-108 as the source of truth before freezing the native
  transcode contract.
- The audio-stream picker (`pickAudioStream`, `plex-tuner.html:5545`) is only
  applied to the Jellyfin/Emby static-stream branch in the code read; whether
  the Plex branch ever picks a non-default audio track: not determined from the
  repository.
- Multi-server item credentials (`item.serverToken`, `plex-tuner.html:5571-5572`):
  whether every pool item actually carries per-server tokens populated, or just
  `serverUrl`: not determined from the repository. The bridge carries both and
  JS must always send the token to use.
- `crypto.randomUUID` availability inside the Android WebView on the oldest
  target WebView: the code already falls back (`web-${Date.now()}-...`,
  `plex-tuner.html:5579-5580`), so this is low risk but worth a smoke test on a
  Mi Box.
- WebView localStorage quota for daily manifests + `plex90_saved_auth` on
  Android TV: not determined from the repository. WebView storage is normally
  adequate, but clearing app data currently means full re-auth; decide whether
  that is acceptable.
- Playback decision parity: the web branch decides direct play by container
  whitelist and browser codecs (`plex-tuner.html:5566`, :8854). ExoPlayer's
  supported-format matrix differs; until measured on a Mi Box, transcode may be
  chosen more (or less) often than the web tuner would, changing server load.
