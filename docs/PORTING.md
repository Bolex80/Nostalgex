# Porting from Nostalgex

Upstream: [chadMueller/Nostalgex](https://github.com/chadMueller/Nostalgex)
(MIT). Its tvOS app and web tuner share one channel config and one schedule
algorithm. This port is a third consumer of both.

## What comes from where

Upstream keeps its schedule and filter engines in two standalone JS modules,
which it holds identical to the Swift with golden vectors made by the real
Swift. Those modules are the port's source. They are small, self-contained
and already pinned to the Apple TV.

| Upstream | Here | State |
|----------|------|-------|
| `channels.json`, `channels-memberships.json` | `data/`, unchanged | vendored; commit in `data/UPSTREAM` |
| `scripts/nostalgex-daily-manifest.js` (Swift: `SchedulePoolOrdering.swift`, `DailyManifestScheduler.swift`) | `source/schedule/DailyManifest.brs` | ported, passing on device |
| `scripts/nostalgex-channel-filter.cjs` (Swift: `AppState+Channels.swift` `filterItems`) | `source/filter/ChannelFilter.brs` | ported, passing on device |
| `plex-tuner.html`: `getTimeFilteredPool`, bundles, `minItems` | BrightScript | with the guide |
| `plex-tuner.html` PIN sign-in and server discovery | `source/plex/PlexApi.brs` | ported; HTTPS only (below) |
| `plex-tuner.html` `scanOnePlexServer` and helpers; `parseMusicVideoFromPlex` | `source/plex/PlexLibrary.brs` | ported; checked live against upstream (below) |
| MusicBrainz/Deezer music-video enrichment | — | not yet; affects music videos only |
| `scripts/nostalgex-enrichment.js`: TMDB/OMDb enrichment through upstream's shared cache and relay (web, since 43f6ee7) | — | not ported; it calls upstream's own hosted services |
| `scripts/nostalgex-collections.js`: server collections as channels from CH 500 (web, since 43f6ee7) | — | not ported |
| Playback | BrightScript | Roku's Video node over Plex; with the guide |
| Guide look: the Apple TV app's TunerView, InfoPanelView, ChannelGuideView | `components/GuideView.*` | recreated to its measurements; DM Mono and VT323 bundled (`THIRD-PARTY-LICENSES.md`). The logo, home-screen icons and splash (`scripts/icons.sh`) are text until the maintainer says the artwork may be used |

Start-up follows upstream's cached-library path. The last build's guide is
saved on the TV and shown at once when a fresh build would give the same
result: same local day, same UTC day (the pool shuffle's seed), same packages
and same app version. The library is then re-read in the background, and the
guide is swapped only if it changed. The build task stays running with the
pools and re-checks schedules every 30 seconds, as upstream's
`rebuildAllSchedules` does, so time restrictions and day changes re-pack as
they would upstream.

Not ported from the schedule module: its manifest cache (`localStorage`).
The caller caches a day's blocks in the Roku registry instead, which is the
same role in a different medium, as upstream's own notes allow.

Not ported from the filter module: `filterPool`'s `shows` summary and the
animation flags on its rows, which only devtools read. Two changes don't
affect results:

- The clock is an argument. Upstream reads `new Date()` for the current year
  and the `releasedWithinMonths` cutoff. The port takes the local date and
  time from `NxFilterClock`, so tests can pin it. JS's month arithmetic,
  where Mar 31 minus one month is Mar 3, is reproduced with day serials.
- Rule lists are lowercased and title patterns compiled once per channel
  (`NxFilterChannel`), and item fields once per item (`NxFilterItem`).
  Upstream redoes both on every call.

The filter runs with no TMDB/OMDb enrichment. The web tuner did the same until
upstream 43f6ee7, which added enrichment through upstream's hosted cache and
relay. Rules that need it behave as on an Apple TV with no enrichment
record: keyword and network matches don't fire, production companies match on Plex's studio alone,
and the IMDb gates leave FOREIGN FILMS and CULT CLASSICS empty.

**Cost on device:** about 0.16 ms per item-channel check (186,144 in 29.7 s on
a TCL 55R617). A 5,000-item library across 131 channels is roughly 100 s, so
the app has to filter in a Task node and cache pools between launches.

## Parity is proven, not eyeballed

When someone built a Fire TV fork, upstream checked its ordering and day-packing
against the JS "byte for byte". Its channel filter diverged on 22 channels, and
upstream asked for filter golden vectors before deciding where the fork would
live (upstream `docs/DEVLOG.md`, 2026-10). This port does the same from the start:

- `tests/gen-vectors.mjs` runs upstream's own engine from the clone
  (`$NOSTALGEX_DIR`, default `../nostalgex`) and writes
  `tests/vectors/schedule.json`. It carries upstream's Swift-made vectors
  verbatim, refusing to run if the JS no longer agrees with them, and adds
  its own: the RNG on its own, premiere slots (non-ASCII keys included), every
  ordering stage on a pool built to reach each branch, and twelve whole days
  through `packDay`, filler loop and both seams included. `tests/gen-filter.mjs`
  writes `tests/vectors/filter.json`: every real channel, plus synthetic ones
  from upstream's filter smoke test, over a library built from the channels'
  own rules (a match, a near miss and real manifest claims for each), under
  two pinned clocks. It reaches every reachable line of upstream's filter.
- `tests/run.sh` runs them in the off-device interpreter. It fails if
  `data/` or the vectors don't match the commit pinned in `data/UPSTREAM`,
  and notes when the clone's `origin/main` has moved past it.
- `scripts/deploy.sh --test` runs the same suite on each TV in `ROKU_HOSTS`.
  **The TV run is the one that counts**, for the reason below.
- A divergence is a bug here, never a fix to the vectors. Regenerating is only
  for following a new upstream commit.

## Checked live, against the real server

Vectors prove the logic. They can't prove that the TV reads Plex the way the
web tuner does, so `tests/live/` checks that against a real server:

- `tests/live/plex-link.mjs` links this computer to Plex by plex.tv/link code
  and keeps the token in `.env` (git-ignored, mode 600).
- `scripts/deploy.sh --live` puts `tests/live/LiveMain.brs` on the TV. It
  loads the signed-in library and prints fingerprints: a SHA-1 prefix per
  item, and one per channel for its pool and today's schedule. It prints no
  token, URL or metadata.
- `tests/live/compare.mjs` runs upstream's own loader, lifted unchanged from
  `plex-tuner.html`, against the same server, then upstream's filter and
  schedule at the TV's clock, and diffs the two.

The loader differs from upstream only where no result depends on it. Items
carry a server index, not the server's token. The display string `meta` is
built by the guide. Requests run one at a time, in upstream's order.

One difference does change results. The loader never asks Plex for
`includeGuids=1`, so most items have no TMDB id and the membership manifest
seldom applies. Upstream behaved the same way until 43f6ee7. It now asks for
the ids and gives episodes their show's TMDB id. So until this loader follows,
`compare.mjs` run against a clone at 43f6ee7 or later will report a
divergence.

## BrightScript notes

- **64-bit math.** The RNG and premiere hash are unsigned 64-bit in Swift.
  BrightScript's `LongInteger` is signed, has no XOR, and its `<<` / `>>` gave
  wrong answers in the off-device interpreter (`>> 30` of a negative value
  returned `1`; `<< 13` truncated to 32 bits). The port relies only on wrapping
  multiply and add, `and` / `or` / `not`, and integer division, and builds the
  logical shifts and XOR from those (`NxShl`, `NxShr`, `NxXor`). The stock
  `brs` package is worse: it misparses `&h…&` literals and doesn't wrap. Use
  `@rokucommunity/brs`.
- `m` is the implicit `this` object, so a variable or parameter named `m`
  is an AA, not what was assigned to it. `pos` is a reserved word.
- Regex patterns must mean the same in PCRE (device) and JS (interpreter):
  no `\z`, so "absolute end" is `(?![\s\S])`.
- AAs ignore key case unless `SetModeCaseSensitive()` is called. Swift groups
  shows case-sensitively ("The Wire" and "the wire" are two groups), so every
  AA keyed on titles or ratingKeys sets it.
- `Abs()` returns a Float. Array indexes must be `Integer`, not `LongInteger`.
- Every Task node already has a `state` field (`init`/`run`/`stop`/`done`).
  An interface field of the same name never reaches its observer, so use
  another name (`status`).
- `LongInteger / Integer` divides as integers, so a fraction comes out 0;
  convert to a Float first. Node fields such as `translation` reject a Double,
  so use `!` (Float) variables for anything a node receives.
- Plex: send one `X-Plex-Session-Identifier` per install with every stream.
  With a new one per stream, Plex refuses to restart a file for 2-4 minutes
  after stopping it (HTTP 400), which breaks flipping back to a channel. It
  also refuses a second stream from a device while one runs, so the app stops
  the last stream (and remembers it across launches) before starting the next.
- Plex also fixes its transcode decision for a playback session the first
  time it sees it, so the session ID is per decoding profile. On a TV that
  decodes HEVC, `X-Plex-Client-Profile-Extra` with
  `add-transcode-target-codec(...videoCodec=hevc)` makes Plex copy HEVC rather
  than re-encode it. Files with subtitles on by default are still re-encoded,
  to burn the subtitles in. An equivalent hint for AAC audio was ignored, so
  audio still converts to MP3, which costs little.
- System fonts go on a Label's `font` attribute. A `<Font uri="font:…">`
  child draws nothing: the label goes blank with no error.

## Alternatives considered

- **[Tunarr](https://github.com/chrisbenincasa/tunarr):** builds channels server-side and shows
  them through Plex's own Live TV guide. It works on any Plex client with no
  app, but it has Plex's look, not Nostalgex's. That look is the reason this
  port exists.
