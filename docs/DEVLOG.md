# Dev log

Why things changed, and what state they were left in. Newest first.
Commits carry the detail of *what*; this carries the *why*.

## 2026-10-11 (franchise numbers, Marvel TV, default-on franchises, branch only)

**Shipped.** Nothing. Branch `franchise-polish`, cut from `stock-fold` at
`be67d61`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** Three changes on `franchise-polish`:

- Runtime channel numbers collided. Found franchises numbered from 220 and
  OTHER COLLECTIONS from 260, so a library with 86 three-film franchises under
  ADD ALL ran franchise numbers to 305 and two rows shared a number,
  interleaved in the guide (it sorts by number). Ids were never the problem
  (they live at 1,000,000+). Franchises now take CH 300-499 and collections
  CH 500-699, each a hard cap of 200: enabled items past the end are not built,
  the log says how many, and Settings shows one quiet line under FOUND IN YOUR
  LIBRARY only when the franchise range is full. Saved choices are ids, never
  numbers, so nothing a viewer switched on is lost; a stale row from an old
  snapshot is rebuilt on the new number. channels.json is untouched (1-140,
  music videos 200-213). The web tuner builds no collection or franchise
  channels at all, so it needed nothing.
- MARVEL (CH101) now carries TV. Its films stay with the `studios` rule; shows
  join by exact title only (case and punctuation ignored, so "What If...?",
  "What If…?" and "S.H.I.E.L.D" without the last dot all match, and "Echo"
  cannot take "Echo Park"). The list covers the Disney+ MCU shows, the Netflix
  era and the ABC era, plus the "Marvel's ..." spellings older agents use. It
  is editorial and can be trimmed in `FranchiseDictionary.swift`.
- STAR TREK and FAST & FURIOUS start switched on (`defaultOn`). An explicit
  off is kept in `nostalgex_disabled_franchises`, which iCloud sync carries
  next to the enabled list, so a viewer who removed one does not get it back
  on the next rescan, relaunch or other Apple TV. No films, no channel, same
  three-film gate as before.

16 new tests; full `NostalgexTests` 591 passed, 0 failed, 2 skipped (the two
live harnesses). Not run on a device or against a real library.

## 2026-10-11 (stock franchise channels mix movies and shows, branch only)

**Shipped.** Nothing. Branch `stock-fold`, cut from `enrichment-proxy` at
`3c1a2ed`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** CH100-106 built their pools from the channels.json rule alone,
and six of the seven rules say `type: movie`. The franchise builder already
placed The Mandalorian and Andor under STAR WARS and Rings of Power under LORD
OF THE RINGS, but Settings only showed that as a greyed "ON CH 100" label; the
episodes never aired. On `stock-fold` a stock channel's pool is its rule's pool
plus the covered franchise's movies and shows, deduped by item id, while the
FRANCHISES package is on. Manifest locks and exclusive rules still win, so an
item another channel owns is not taken. The covered row now reads "3 movies,
2 shows on CH 100". Swift only: the web tuner has no franchise dictionary and
keeps the rule-only pool. 4 new tests, full `NostalgexTests` 575 passed,
0 failed. Not run on a device or against a real library.

Known limit: a classic whose rule matches fewer than `minItems` (3) films is
never built, so two Star Wars films plus The Mandalorian still give no CH100.

## 2026-10-11 (TMDB proxy and Supabase key plumbing, branch only)

**Shipped.** Nothing. Branch `enrichment-proxy`, cut from `icloud-opt-in` at
`42320a5`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** No build has ever carried the TMDB, Supabase or OMDb values, so
every install logs `[Enrichment] Skipping: API keys not configured` and the
channels that lean on enrichment stay empty. `enrichment-proxy` turns the layer
on without shipping the TMDB key:

- `api/tmdb.js`, a Vercel function next to `subscribe.js`. GET with `?path=`
  restricted to `movie/{id}`, `tv/{id}`, `collection/{id}` and
  `search/collection` (numeric ids only, anything else is a 400). It adds the
  key from the `TMDB_API_KEY` env var, adds `append_to_response=keywords` for
  movie and tv, and returns TMDB's JSON and status. A 200 carries
  `Cache-Control: public, s-maxage=86400, stale-while-revalidate=604800` so
  Vercel's edge cache absorbs repeats; anything else is `no-store`. It requires
  `X-Nostalgex-Client: tvos` (403 without it), a cheap filter, not security, and
  logs nothing. `npm run test:tmdb` covers the allowlist and the handler with a
  stubbed fetch (48 checks) and is part of `npm test`.
- `TMDBService` gains a proxy mode. With an empty key it calls
  `https://www.nostalgex.app/api/tmdb?path=movie/{id}` with the client header
  and no key in the URL; with a key it keeps calling TMDB directly, for dev
  builds. `TMDBConfig.tmdbProxyURL` holds the base. The document is the same
  either way, so `parseResponse`, franchise fields included, is untouched.
- `EnrichmentService` proceeds when a key or the proxy is available but still
  requires the Supabase URL and anon key, since the shared cache is the point.
  The skip log names what is missing:
  `[Enrichment] Skipping: missing supabase url, anon key`.
- Supabase values arrive through an xcconfig. `Nostalgex/Config.xcconfig`
  (committed) is the app target's base configuration for Debug and Release; it
  defaults both values to empty and does `#include? "Secrets.xcconfig"`.
  `Nostalgex/Secrets.example.xcconfig` is the template, `Secrets.xcconfig` is
  gitignored, and `Info.plist` maps `SUPABASE_URL` and `SUPABASE_ANON_KEY` to
  `SupabaseURL` and `SupabaseAnonKey`. A missing base configuration file is a
  hard xcodebuild error (measured: exit 65, "Unable to open base configuration
  reference file"), which is why the committed file sits in between.

Verified: `NostalgexTests` passes with no `Secrets.xcconfig` on disk (573 tests,
571 passed, 2 skipped live harnesses, 13 new in `TMDBProxyTests`) and the built
Info.plist carries empty Supabase strings. With a dummy `Secrets.xcconfig` using
`https:/$()/host`, the built plist reads `https://host` with both slashes. The
function called locally against real TMDB returns `movie/603` with
`belongs_to_collection` and 18 keywords, `tv/1399` with keywords and networks,
and rejects `person/1` with 400 and a missing header with 403. `npm run build`
passes. Not run on a device or simulator against the live function: nothing is
deployed yet.

**Next.** Set `TMDB_API_KEY` on the Vercel project and deploy so `/api/tmdb`
exists. Put the real Supabase URL and anon key in a local `Secrets.xcconfig`
before the next archive. Then rescan on a device and watch for
`[Enrichment] TMDB via site proxy` followed by the cache and save counts. The
README's "What leaves your network" now names the proxy hop; the privacy page
covers TMDB lookups in general terms but does not name nostalgex.app as a hop,
worth a line before that build ships.

## 2026-10-10 (iCloud sync, now opt-in, branch only)

**Shipped.** Nothing. Branch `icloud-opt-in`, stacked on `franchise-ui`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** `icloud-sync` mirrored lineup and display preferences through
iCloud key-value storage from the first launch, and whichever Apple TV launched
first seeded the household. That is the wrong default for a household where one
TV has a curated lineup and another is a fresh install, so `icloud-opt-in`
carries the same two commits on top of the franchise work and adds a switch:

- SYNC WITH MY OTHER APPLE TVS, under DISPLAY in Settings. Off by default. The
  flag (`nostalgex_icloud_sync_enabled`) is per TV and is never itself synced.
- While off, nothing reads or writes the ubiquitous store: launch neither pulls
  nor seeds, Settings changes stay local, and incoming change notifications are
  ignored. A fake store in the tests counts reads, writes and synchronize calls
  and asserts all three stay at zero.
- Turning it on pushes this TV's current preferences first (this TV wins),
  adopts cloud values only for keys this TV has never set, then starts
  listening. Turning it off stops listening and leaves iCloud and the local
  values as they are. A TV that turns it on later follows the same rule.
- The found-franchise switches (`nostalgex_enabled_franchises`) join the synced
  set. The never-sync list in the tests now also names the switch itself, the
  rating nudge counters and the tip ledger, next to credentials, server
  address, stream quality and playback reporting.

Cherry-picking onto `franchise-ui` conflicted only in `AppState+Channels.swift`
(the franchise branch had renamed `materializeCollectionChannels` to
`materializeDynamicChannels`); the sync code now calls the new name.

Verified: the full `NostalgexTests` run passes (557 tests, 37 of them for the
sync service and its merge rules). A Release archive signed through the App
Store Connect key carries `com.apple.developer.ubiquity-kvstore-identifier`,
and a local App Store export with automatic signing produces an IPA whose
distribution profile includes it; nothing was uploaded. Not yet tried on
hardware: two real Apple TVs on one Apple ID flipping the switch.

**Next.** Hardware round trip with two TVs: switch on with different lineups,
confirm the first TV to switch on wins, then flip one off and confirm nothing
moves. Then merge order: `franchise-data`, `franchise-channels`, `franchise-ui`,
`icloud-opt-in`.

## 2026-10-10 (franchise bundle, branch only)

**Shipped.** Nothing. Everything below is on branches off `main`, not merged.

**Changed.** Nothing on `main`.

**Half-done.** The FRANCHISES package is being rebuilt in three phases, each on
its own branch stacked on the last:

- `franchise-data` (Phase 0): enrichment rows gain `franchise_id` and
  `franchise_name`, parsed from TMDB `belongs_to_collection` with no extra
  request. The two columns are added by `Nostalgex/docs/franchise-migration.sql`,
  which has NOT been applied to the shared table yet, so live enrichment still
  carries no franchise fields. Rows without the columns decode fine.
- `franchise-channels` (Phase 1): `FranchiseChannelBuilder` turns a library plus
  its enrichment into a franchise list. Three or more owned films sharing a
  TMDB collection make a channel; `FranchiseDictionary` merges split
  collections (Star Trek is three on TMDB), folds known franchises into the
  stock classics CH100-106, and adds TV by title (The Mandalorian under STAR
  WARS). Films TMDB leaves outside any collection (Rogue One, Solo, Bumblebee,
  Rise of the Beasts, all checked against the live API) join dictionary
  franchises by title. Marvel stays studio-ruled, never grouped by collection.
  Every dictionary id was verified live on 2026-10-10.
- `franchise-ui` (Phase 2, this entry): the Settings half. Under the FRANCHISES
  package row, when it is on, FOUND IN YOUR LIBRARY lists each found franchise
  with a switch, ADD ALL and REMOVE ALL, and the ones a classic already covers
  greyed as "ON CH 100". Found franchises default off so a big library does not
  flood the guide. Switches persist as a plain string array under
  `nostalgex_enabled_franchises`, keyed by dictionary name or TMDB collection
  id, so a later iCloud sync can carry it unchanged. A switched-on franchise is
  a dynamic channel (`rules == nil`) in the collection range (numbers from
  220), shown while the package is on; the schedule engine and playback are
  untouched. A server collection that is really one of these franchises is
  folded: credited under the franchise, hidden from MY COLLECTIONS, never
  materialised twice (`FranchiseCollectionFold`, reusing the scan's name and
  manifest signals plus a 60% item overlap). NOTABLE STARS is gone; actor and
  director sets classify as OTHER COLLECTIONS, a persisted `collections-actors`
  id migrates, and older snapshot rows resolve. Full `NostalgexTests`: 521
  passed, 2 skipped (pre-existing), 0 failed.

  Verified on the tvOS 26.1 simulator through a test-only launch argument,
  `-uiTestFranchiseFixture`, which layers an enriched sample library over demo
  mode (six franchises, two sample collections) because the shared table has
  no franchise columns yet. Not verified: the real enrichment path end to end,
  which needs the migration applied; a relaunch from a snapshot that carries
  found franchises; the fold against a real server's collections.

**Next.** Apply the migration, then load a real library and compare the found
list against what the library actually holds before merging. Decide whether
STAR TREK and FAST & FURIOUS become stock classics or stay found-only. Merge
order: `franchise-data`, `franchise-channels`, `franchise-ui`.

## 2026-10-09 (app)

**Shipped.** Nothing to Apple. 1.0.24 (45) is still in TestFlight beta review.
`main` now carries 1.0.25 (46), not archived or uploaded.

**Changed.**

- Jellyfin and Emby connect forms have a FIND SERVERS ON MY NETWORK button
  (`LANServerDiscovery.swift`). UDP 7359, `who is JellyfinServer?` and
  `who is EmbyServer?`, three second listen, deduped by server id, kind taken
  from which probe the server answered. Measured before writing it: the Emby
  under test answered the subnet directed broadcast and ignored
  255.255.255.255, so the app sends to both, computing the directed broadcast
  from every live IPv4 interface. Network.framework could not receive the reply
  (a connected UDP socket drops datagrams from the server's unicast address),
  so it is a BSD socket with SO_BROADCAST. No system prompt seen in the tvOS 26
  simulator; `NSLocalNetworkUsageDescription` now names all three servers in
  case hardware asks. Jellyfin side verified only as far as the parser, no
  Jellyfin server was on the test network. Plex skipped on purpose: that form
  has no address field.
- The Plex to Emby switch bug from the 2026-10-08 entry is fixed, and the cause
  was not either suspect named there. It was a race: a stale snapshot starts a
  background Plex refresh at launch, which on a large library runs for minutes;
  the user disconnects and signs into Emby meanwhile; Emby's scan finishes
  first; then the Plex scan returns and, with nothing checking that its sign-in
  still exists, rebuilt every pool from Plex items and saved the snapshot under
  the Emby identity. That poisoned snapshot is why it survived relaunch. The
  harness (`BackendSwitchScheduleTests.swift`) showed the clean switch passing
  on the old code and the race failing with "CH 7 VHS VAULT schedule would send
  18 Plex key(s) to Emby". Fix: a session generation bumped on Disconnect or a
  server change, checked before every commit in `loadLibrary` and used to abort
  the remaining requests; items from servers not signed in are dropped at load;
  a snapshot holding such items is refused on launch and rescanned; playback
  skips a foreign item with the failure card instead of sending the server a
  request it will answer 500. Disconnect now also clears today's manifests and
  the collection scan. Behaviour change: disconnect and re-sign-in to the same
  server reshuffles today's guide.
- Settings: Connection moved above Display and took in the report-playback
  switch (it had its own section). The two subtitle switches became one
  SUBTITLES row cycling Off, Foreign audio, Always: the fullscreen switch only
  ever overrode the foreign-audio one, so they were one three-way setting.
  Subtitle language only shows when subtitles are not Off. The Buy Me a Coffee
  and update-email QR codes are gone from Settings, with their analytics event.
  The in-player panel still has separate CC and auto buttons.
- `NostalgexTests`: 436 passed, 0 failed, 2 skipped on the merged tree
  (417 before, 9 discovery, 9 backend switch, 1 moved).

**Verified on hardware** (Apple TV 4K, first generation): RESCAN LIBRARY on a
Plex library of about 11,600 items, Disconnect mid scan, then Emby found via FIND
SERVERS. The log read "sign-in changed while the scan was running, discarding its
results", the Emby library loaded, and five programmes played with no HTTP 500s.
The automatic background refresh that started the original report was not
reproduced (the snapshot was only hours old) but runs through the same check. No
local network prompt appeared; a clean install is still the true first press.
A 4K HEVC title with EAC3 audio that stalled in the simulator played cleanly.

**Next.** 46 to TestFlight. App Store
listing for the next submission: "131 themed channels across 14 bundles" and
new screenshots. Discussion #2 (Fire TV fork): ordering and DayPacker ports match
the JS reference byte for byte; the channel filter does not (22 channels
diverge), asked the contributor for filter golden vectors in `scripts/` before
deciding where it lives. Discussions #8 (Roku) and #14 (languages) are
unanswered.

## 2026-10-09

**Shipped.** nostalgex.app: the four SEO blog drafts and table styling (#15),
then site wide SEO and speed work (#16). The buddy cop post went live a day
early; the other drafts each moved up a day (Oct 12, 14, 16, 19, 21) and still
need their `draft: true` removed on the day. No app change.

**Changed.**

- Hero text no longer waits for JavaScript. `.hero-copy` (and `.hero-shot`) on
  `/`, `/plex`, `/jellyfin` and `/emby` lost the `reveal` class, which kept them
  at opacity 0 until `app.js` ran. That was most of the mobile LCP.
- Hero media is lighter and off the critical path. New poster
  `guide-hero-1280.webp` (54 KB, was 511 KB) is preloaded; the video is
  `preload="none"` and `app.js` starts it after `load`, never under reduced
  motion or Save Data. New encodes: 480p mp4 412 KB (phones), 1600 webm 1.46 MB
  and 1280 mp4 1.37 MB (desktop). Old files stay for one release so cached
  pages don't 404. Screenshots below the hero get 1280 and 1920 `srcset` sizes.
- Lighthouse mobile, local static build, same machine before and after: `/`
  went 71 to 96 (LCP 6.3 s to 2.4 s, 1,068 to 745 KiB), `/jellyfin` 74 to 94
  (LCP 8.1 s to 2.3 s). Not yet measured on the Vercel preview.
- `/plex`, `/jellyfin` and `/emby` were near copies, and two of them sat outside
  Google's index. Each now has its own H1, direct answer, setup steps, tips and
  gotchas, and six server specific FAQs.
- Every page has new titles and descriptions, a 1200x630 card image
  (`og-image-1200.png`, letterboxed because a center crop clipped the logo), a
  48px favicon, an apple-touch-icon, and one JSON-LD `@graph` linking the app,
  Chad and Muell Haus by `@id`. Visible FAQs and FAQPage text are generated from
  the same strings.
- Blog: titles end in " | Nostalgex", Article author is the Person `#chad`,
  posts get a BreadcrumbList, and new optional front matter `cover_alt`. FAQPage
  and table wrapping from #15 are kept, folded into the single graph.
- Sitemap entries carry `lastmod` only (Google ignores changefreq and priority).
  Added `public/llms.txt`.
- Support page CORS configs said `https://nostalgex.app`, but the tuner runs on
  `https://www.nostalgex.app`, so the documented config could not work. Fixed.
- Removed the Data Haus analytics script from every page, the blog template and
  the CSP. statsngraphs stays. The privacy page, README and the support FAQ
  now describe one analytics script; the support FAQ no longer says there are
  no analytics on the tuner pages, because the connect page loads one.
- "Over a hundred" is now 131 everywhere it appeared.
- `Nostalgex/PRIVACY_POLICY.md` matches the privacy page: statsngraphs only,
  effective October 9. `docs/FAQ.md` named 1.0.22 for the Tailscale/VPN http fix,
  which shipped in 1.0.23 (support page was already right).

**Half-done.** Rich Results Test and a Lighthouse run against production still
need doing.

**Next.** Merge #15 first, then this. After deploy, resubmit the sitemap and
request indexing for /plex, /jellyfin, /support and the blog post.

## 2026-10-08

**Shipped.** 1.0.23 reached the App Store (build 44). It carries the Jellyfin
channel-change fix, the Plex playback fixes, the SCREAM and TIS THE SEASON
packages, eleven new channels and the Y2K renames. The web tuner on
nostalgex.app shipped separately the same day.

**Changed.**

- Merged #5 and #7 from @Gorbataras, who found the tune-in bug independently and
  traced it further than we had, through Jellyfin's `DynamicHlsController` across
  10.10.7, 10.11.0, 10.11.11 and 12.1. #5 routes **Emby** through the same
  client-side seek Jellyfin already used, and deletes `addingStartTime`, which no
  longer had a caller. #7 stops Jellyfin and Emby direct-playing the two things
  AVPlayer will not render: HEVC in MP4 tagged `hev1` (it renders only
  `hvc1`/`dvh1`) and 10-bit H.264. Both guards already existed on the Plex path
  and had never been ported.
- Closed #3. The symptom was the tune-in bug, fixed in 1.0.23 and verified by
  @Gorbataras on an Apple TV 4K against Jellyfin 12.1.
- **Plex adaptive mode is no longer requested.** With `autoAdjustQuality=1`, any
  film where the server re-encodes both video and audio came back as 3-second
  segments: the first eight arrived at full speed, then one every 6.1 seconds for
  the rest of the film. tvOS 26 abandons a segment that slow (CoreMedia -15628)
  and the picture died at 24 seconds, at 4K and at the 1080p retry alike. With it
  off, the same request returns 1-second segments and keeps pace. Audio-copied
  streams were never affected, which is why some channels played and others did
  not.
- **Dolby Vision profile 5 plays on Plex.** Plex refuses to re-encode DV5
  (decision 2003), but it will remux it for a client it resolves as Generic,
  which is what Plex's own Apple TV app gets: `container=mp4, video=copy hevc
  DOVI 5`. On a DoVi refusal the app now re-asks once that way. Measured on
  device: picture in 1.8s, 61.6s of playhead across a 60s hold, zero stalls, zero
  dropped frames.
- **A starving stream steps down instead of freezing.** When a server cannot keep
  up, the same film is re-requested from the current position capped at 1080p,
  and only a starving capped stream advances. Previously it froze or jumped to
  the next programme.
- **An offset HLS transcode reports the remainder as its duration**, not the full
  runtime. The end-of-item fallback was adding the offset back, so `remaining`
  went negative on every tuned-in transcode and the first rate-0 moment skipped
  to the next film.
- **Web tuner: a failed stream retried forever.** The hls.js error handler
  guarded its one recovery with a flag written onto the error payload, and hls.js
  builds a fresh payload per event, so the guard never held. Measured against a
  playlist of 404s: **14,612 requests in 8 seconds**, roughly 1,800/s aimed at
  the user's own server; the same handler with the flag held outside the event
  made 14. A real session was caught making 2,239 requests for one dead segment
  while an unrelated channel played normally.
- **Web tuner: each playback now mints its own Plex transcode session** and
  releases it on the way out. Without one, Plex keyed the transcode off the
  client id alone, so every channel change quietly repurposed the previous
  session, which is what left the old loader requesting segments that 404.
- **Web tuner: a manifest that will not load now skips.** `start.m3u8` answering
  400 produces exactly one fatal `manifestLoadError` and nothing after it, so
  `startLoad()` had nothing to retry and the channel sat on black indefinitely.
  It now says so and moves to the next programme, stopping after three failures
  in a row because that points at the server rather than the file.
- **Music video genres come from Deezer** when the server reports none. On a test
  library of 1,131 music videos only 148 carried a genre, and MusicBrainz tags
  filled almost none of the rest, which is why CALIENTE and HEADBANGERS sat
  empty. Deezer resolved 47 of a random 60, and a filename cleaner (underscores,
  scene tags, `ft.`/`feat.`) recovered 10 of the 13 misses.
- **Music video years** are read from the filename first, then MusicBrainz, then
  the server only when plausible. Servers commonly report 1970 or the date the
  file was added, and Deezer's year is the album's, wrong on 15 of 15 sampled, so
  the decade channels were sorting by the wrong year.

**Changed, evening session (real hardware).** Build 1.0.24 (45) ran on an Apple TV HD
(tvOS 26.6) and an Apple TV 4K simulator against an Emby 4.10.1.0 server. Everything below
was measured there, not inferred.

- **Issue #6 confirmed fixed on hardware, with a controlled before/after.** The shipped
  1.0.23 (44) from TestFlight on the same device: `HTTP 404. The file '/UserViews' could
  not be found.` Build 45 ten minutes later: `[Emby] LIBRARY: 1541 items`, 69 channels,
  playback at a 57-minute mid-schedule join. Gorbataras's #5 Emby seek is confirmed by the
  same run.
- **The guide wrap works on tvOS 26.6**, the reporter's exact version, which the 26.1
  simulator could never reproduce. Down wraps, Up reaches SETTINGS.
- **The failure card now says why, accurately.** Three classifier corrections from
  watching it misfire: the probe walks master to variant to first segment, because the
  master answers 200 while every segment beneath it is refused; CoreMedia -12889 (no
  response in 3s) and -15628 (segment abandoned) classify as the server being too slow,
  not the device failing to decode; and a decoded frame vetoes "Apple TV couldn't play
  this file" outright. Verified verdicts on hardware: `Emby HTTP 500, refused before
  video` and `Emby below real time on the capped stream`.
- **Audio track selection.** Jellyfin and Emby hand back the file's default track, and
  Joe Dirt's default is Spanish 2ch with English 5.1 unflagged, so it played in Spanish
  on a channel with no picker. The resolver now reads MediaStreams from PlaybackInfo,
  prefers a track in the viewer's language with the most channels, then the default,
  then the first, and pins `AudioStreamIndex` on the transcode URL. Verified against the
  server: Emby's own URL pinned index 1 (spa); ours pins 2 (eng); Emby accepts it. 7 tests.
- **The starvation ladder's Emby rung fired for real** (The Wedding Singer, 13 Going on
  30): starve, cap to 1080p, `TRANSCODE READY`. It recovers what it can.

**Found, not fixed.**

- **Switching backend keeps the old day schedule.** A device signed into Plex, then
  Disconnected and connected to Emby for the first time, kept playing the Plex running
  order: Plex rating keys sent to Emby resolve to Person records and 500, every channel,
  looping between two titles indefinitely. A fresh install is flawless, so it is the
  transition that leaks. `DailyManifestStore.clearAll` on Disconnect uses the fingerprint
  current at that moment, and `apiForServer` never checks an item's `serverID` belongs to
  the connected backend. Workaround: delete and reinstall. Worth fixing before a wide push.
- **Two test rigs invent failures.** The tvOS simulator has no EAC3/AC3 decoder, so ~25%
  of a typical library stalls 3s in and looks like starvation; the Apple TV HD has no HEVC
  decoder, so every HEVC title forces a server re-encode that held 1.07x here against
  CoreMedia's 3s first-segment patience. The same file for an HEVC-capable client is a
  17.3x remux. Playback claims need the 4K unit.
- **On this Emby, 10-bit sources cannot transcode at all.** `VideoFilters.format..ctor()`
  throws "An item with the same key has already been added. Key: threads" before ffmpeg
  starts; 190 of 1541 movies affected. Ruled out by measurement with the server restored
  afterwards: codec, resolution, bitrate, subtitles, audio stream, thread count, hardware
  acceleration. A server bug, reported by the card as a refusal, nothing for the app to do.

**Half-done.**

- `fix/emby-userviews-404` — **Emby library scans fail immediately.**
  `loadSections` asked for `/UserViews?userId=`, which is Jellyfin's spelling.
  Measured against Emby Server 4.10.1.0: `/UserViews` answers 404,
  `/Users/{id}/Views` answers 200. It is the first request after sign-in, so it
  fails whatever the libraries are named and however large they are. Fixed with
  three tests on the branch, not yet merged. This is issue #6, and it is present
  in the released 1.0.23. **Now verified end to end against an Emby server**
  (see below).
- `feat/playback-failure-card` — **a programme that will not play now says why,
  instead of being swapped for the next one in silence.** Only three of about eight
  failure paths showed any UI at all; the startup watchdog, the starvation verdict and an
  AVPlayer item reaching `.failed` all advanced with nothing on screen, which reads as a
  broken app and hides whether the person should look at their server or at the file.
  `PlaybackState.error` now carries a `PlaybackFailure` rather than a sentence, and every
  failure path funnels through one place that records the verdict, emits the matching
  analytics code and shows a card for five seconds before advancing. Amber when the server
  is the thing to go and look at, red when the file or the device is.
  Getting the reason right needed a new source of truth: tvOS has no `httpStatusCode` on
  `AVPlayerItemErrorLogEvent`, so the status of a refused segment cannot be read out of the
  player, and that status is the difference between "your server refused this" and "this
  file will not decode". `StreamFailureProbe` asks the server instead, with one ranged GET
  on the URL that just failed. 14 tests, classification being a pure function over what was
  observed. Not merged.
- The startup watchdog's capped retry had the same missing client-side seek the starvation
  ladder got, so a watchdog retry on Jellyfin or Emby would have restarted the film from
  frame one. Fixed on the same branch as the ladder.
- `fix/starvation-ladder-all-backends` — **the starvation ladder had no rung on
  Jellyfin or Emby, so one stall skipped the programme.** `handleStarvation` steps
  a starving stream down to 1080p and only advances once there is nothing smaller
  to ask for, but `cappedTranscodeURL` was implemented on Plex alone and the
  `MediaBackend` default returns nil. Measured on Emby Server 4.10.1.0: each
  6-second segment took 3.4s to produce before its first byte, at 128 Mbps once
  flowing, so the server and not the network was the limit; a film jumped out
  mid-scene to the next scheduled title at its first frame. Both backends now
  build the rung at 1920 wide and 8 Mbps under their own `PlaySessionId`, with no
  start time on the URL, because the segment handler refuses one. A new
  `cappedStreamStartsAtOffset` says which backends seek client-side. 4 tests.
  Not merged.
- `fix/backend-error-copy` — error messages name the server the user actually
  connected to. `PlexAPIService.APIError` is the shared error type for all three
  backends, but every message hung off it was written for Plex, so an Emby user
  whose scan 404s was told "Plex (or your network path) returned HTTP 404" and
  sent to check Plex's Remote Access setting. Plex keeps its own copy, including
  the `/library` and `/identity` paths only Plex serves. One test asserts no
  Jellyfin or Emby message contains the word "Plex", across every error case.
  Not merged.
- `fix/guide-wrap-scrolling` — the guide's vertical wrap now runs off a focusable
  sentinel row just outside the last channel rather than a 150ms staleness timer,
  so "ran off the end" is proven by the focus engine instead of inferred from a
  clock. Up out of channel one deliberately still leaves for SETTINGS and does
  not wrap. 9 UI tests. Not merged. The report that prompted it came from tvOS
  26.6 and never reproduced on the 26.1 simulator at any list length or cadence,
  so treat this as hardening fragile timing rather than a confirmed fix.
- The web tuner still appends `StartTimeTicks` to its Jellyfin fallback URL in
  `getJellyfinTranscodeUrl` (`plex-tuner.html`). Same defect #5 fixed on tvOS.
  hls.js already seeks via `startPosition`, so the parameter only breaks segment
  requests. Spotted by @Gorbataras. In progress.
- **Emby, measured.** The Emby halves of #5 and #7 were reasoned from Jellyfin's
  HLS controller being forked from Emby's, and from Emby's own web client seeking
  client-side. Both now ran against Emby Server 4.10.1.0: sign-in, library scan,
  guide build, and a mid-programme join that started Heat at 47 minutes into a
  2:50:00 film and advanced 25s of playhead across 25s of wall clock with no
  stall. The scan only ever touches `/Users/{id}/Views` and `/Items`, and series
  and episodes go through that same `/Items` call with a different
  `IncludeItemTypes`, so a movies-only test library still exercises every HTTP
  path the scan makes. What remains untested on Emby is episode *parsing*, not
  whether an endpoint answers.

**Next.**

- Merge the three branches above.
- Port the web tuner's `StartTimeTicks` removal.
- Exercise an Emby library that contains TV series, to cover episode parsing and
  the per-show grouping the movies-only run could not reach.
