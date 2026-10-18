# Jellyfin and Emby: the plan

Discussion #8, item 4. The Roku app reads only Plex today. Upstream's Apple TV
app (1.0.26) and web tuner (tuner-v1.0.1) also read Jellyfin and Emby. This is
how the port fits in, in what order, and how each step is tested.

## What upstream does

Read from upstream `origin/main` at 8a55386:

- `Nostalgex/Services/JellyfinAPIService.swift`, `EmbyAPIService.swift` and
  `JellyfinPlaybackResolver.swift`.
- Their tests.
- `scripts/nostalgex-jellyfin-urls.js` and `plex-tuner.html`.

Jellyfin is a fork of Emby, and upstream drives both through one MediaBrowser
code path.

**Sign-in**

- Header on every request:
  `Authorization: MediaBrowser Client=…, Device=…, DeviceId=…, Version=…, Token=…`.
- Password: `POST /Users/AuthenticateByName` with `{Username, Pw}`. The answer
  carries `AccessToken` and `User.Id`.
- Jellyfin also has Quick Connect: the TV shows a code, and you approve it in
  Jellyfin's web or phone app. The calls are `GET /QuickConnect/Initiate`, then
  poll `GET /QuickConnect/Connect?Secret=` every 2 s, then
  `POST /Users/AuthenticateWithQuickConnect`. A 401 on Initiate means the server
  has Quick Connect switched off.
- Servers answer a UDP broadcast on port 7359 (`who is JellyfinServer?` or
  `who is EmbyServer?`), so the TV can find them without anyone typing an
  address.

**Library**

- The libraries come from `/UserViews?userId=` on Jellyfin and
  `/Users/{id}/Views` on Emby. Emby answers 404 to the first.
- Items: `GET /Items?userId=&ParentId=&Recursive=true&IncludeItemTypes=` with
  the `Fields` list (`ProviderIds,Genres,Studios,MediaSources,ProductionYear,PremiereDate,DateCreated,UserData`),
  in pages of 200.
- TV shows: list the series, then each series' episodes, several series at a
  time. Each episode takes its show's genres, TMDB id, year, studio and
  ratings, because the channel rules match on the show.
- Runtime is `RunTimeTicks` (10,000,000 per second). Items with none are
  dropped.
- Collections are `BoxSet` items. Jellyfin lists a collection's series; Emby
  lists their episodes instead.
- There is no library-changed signature. Upstream rescans Jellyfin and Emby in
  full every time.

**Playback**

- Direct play: `/Videos/{id}/stream.mp4?Static=true&MediaSourceId=`.
- Otherwise: `POST /Items/{id}/PlaybackInfo` with a device profile, and the
  server's `TranscodingUrl` (HLS).
- If neither works, a hand-built `/Videos/{id}/master.m3u8`. Emby needs a
  `PlaySessionId` on it or every segment fails with 400.
- **Never put `StartTimeTicks` on an HLS address**: Jellyfin then rejects every
  segment with 400. Joining a channel part-way through a programme means
  starting the stream at 0 and seeking on the client.
- To stop a stream: `DELETE /Videos/ActiveEncodings?deviceId=&playSessionId=`.
- Reporting what was watched back to the server is off by default upstream.

**Emby differs from Jellyfin** in these places:

1. the libraries call;
2. no Quick Connect;
3. `PlaySessionId` on the hand-built HLS address;
4. the retry after a failed direct play has to turn off both direct play and
   direct stream;
5. collection members (episodes rather than series);
6. how the server name is found.

## What we checked on test servers

Jellyfin 12.2 and Emby 4.10.1 in containers, each reading a test library
read-only.

- **The token can stay in a header for streams.** On both servers a static
  stream answered 206 with the token only in the `Authorization` header. The
  Roku player sends a content node's `HttpHeaders` with every request, as the
  Plex path already does. So the token never goes in an address, and the maintainer's new
  Roku privacy text ("your token travels in a request header, not in the
  address") stays true. Upstream puts `api_key` in addresses because AVPlayer
  can't add headers. We don't need to.
  - HLS segments haven't been checked this way yet: a transcode first needs a
    PlaybackInfo session. That is phase 2's first test.
- **Jellyfin serves a static stream to anyone who knows the item id**: it
  answered 206 with no token at all. Emby answered 401. That is the server's
  business, not ours, but it is worth knowing when reading logs.
- Jellyfin's `/System/Info/Public` answered in camelCase before its first-start
  setup and in PascalCase after. BrightScript's associative arrays ignore case,
  so the app is safe either way.

## How it fits the app

Most of the app needs no change. Channels, filtering, enrichment, the guide,
saved libraries and the package switches all work on the scanned items, and a
Jellyfin item can be made into the same shape as a Plex one.

The Plex-only places, and what each one becomes:

| Today (Plex only) | Becomes |
|---|---|
| `PlexSignInTask` (plex.tv/link code) | A first screen that picks Plex, Jellyfin or Emby. Plex goes as now. Jellyfin and Emby: find the server on the LAN (or type its address), then sign in with Quick Connect (Jellyfin) or a username and password. |
| Registry `plex` section: token, `servers` | Each saved server gains `kind`: `plex`, `jellyfin` or `emby`. A Jellyfin or Emby server keeps `uri`, `userId` and `accessToken`, and its key is the server's `Id`. |
| `NxPlexScanServer` | Picks by `kind`. A new `source/mediabrowser/` holds the Jellyfin/Emby scan and the item mapping. |
| `NxPlexServerSignature` | Returns invalid for Jellyfin and Emby, as upstream does, so they are scanned each launch. Phase 4 can try something better. |
| `NxPlexCollectionsFetcher` | A BoxSet fetcher beside it, which takes both series ids and episode ids. |
| `NxPlexStreamContent` / `NxPlexApplyAuth` | Pick by `kind`: direct play, else PlaybackInfo's `TranscodingUrl`, else a hand-built HLS address. The token is always a header. |
| `PlexStopTask` | Also sends `DELETE /Videos/ActiveEncodings` for Jellyfin and Emby. |
| Settings: account, sign-out | Shows which kind the TV is signed in to. Sign-out clears the same things for every kind. |

**One kind at a time, as upstream does.** The Apple TV app holds one
`backend_kind`, and so would we: a TV is signed in to Plex, or to one Jellyfin
server, or to one Emby server. Mixing them would mean a server picker and
channels that cross backends. Upstream doesn't do that, and nobody has asked
for it.

**No reporting to the server.** The Roku app sends Plex nothing about what you
watch, and the privacy policy says so. We'd keep it that way for Jellyfin and
Emby, which also spares us upstream's watch-state restore machinery. Upstream
has it off by default anyway.

## Phases

Each phase ends with something working on a TV, and nothing in a
phase breaks Plex.

1. **Playback spike, first.** This is the riskiest part, so it goes first and
   is thrown away afterwards. A test-only screen plays one Jellyfin movie, then
   one Emby movie, joining 20 minutes in.
   - Questions it answers:
     - Does direct play of an MP4 seek to the offset?
     - Does a PlaybackInfo HLS stream start, seek, and keep the token in a
       header for every segment?
     - What happens with an MKV? On Plex, joining an MKV part-way crawled on
       a Roku, which is why Plex remuxes it for us. Jellyfin can't start the
       remux at the offset, so the client seek has to be fast enough.
   - If the HLS seek is unusable, we know before building the rest.
2. **Jellyfin, read and play.**
   - Sign-in by address with password and Quick Connect.
   - The library scan and item mapping.
   - The guide builds, and channels play, including mid-programme joins.
   - Stop on channel change.
   - Then sign-out and switching back to Plex.
3. **Emby.**
   - Its libraries call.
   - Password-only sign-in.
   - `PlaySessionId` on the hand-built HLS address.
   - Its direct-play retry flags.
   - Its episode-id collection members.
4. **Collections, LAN discovery, polish.**
   - BoxSet channels.
   - Finding the server without typing.
   - Error messages for a wrong address, a wrong password, and Quick Connect
     switched off.
   - Possibly a cheap library-changed check, so a relaunch doesn't always
     rescan.

## Tests

- **Item mapping** (the part the channel rules depend on).
  - Off-device tests read real `/Items` answers saved from our two servers,
    trimmed to a few movies, a show with episodes, a disc-stacked film and a
    collection.
  - The cases:
    - each field of the common item shape;
    - show fields copied onto episodes;
    - ticks to minutes, with zero-length items dropped;
    - TMDB ids found whatever the key's case;
    - both shapes of collection members.
- **Same channels as upstream.** The same library read through Plex and
  through Jellyfin should fill about the same channels. It won't be identical,
  since the two servers match titles to TMDB differently. A per-channel count
  side by side shows mapping mistakes quickly.
- **On the TV:** `deploy.sh --test` runs the mapping tests on the TV. The rest
  is checked by driving a TV over ECP:
  - sign-in each way;
  - a guide build;
  - joining part-way;
  - a channel change stopping the stream;
  - sign-out.
- **The maintainer** runs Emby and could try a build against a second, real
  Emby server once phase 3 works.

## For upstream

- **Privacy policy.** The maintainer's Roku privacy section says "The Nostalgex app for
  Roku works with Plex only". It would need an edit once this ships. The rest
  of it (the token in a header, no reporting) can stay true by design.
- **Starting offset.** It's worth asking whether upstream found a better answer for
  mid-programme joins on Jellyfin than seeking on the client. Roku's player
  may behave differently from AVPlayer.
