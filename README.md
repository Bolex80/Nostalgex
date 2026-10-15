# nostalgex-roku

A Roku port of [Nostalgex](https://github.com/chadMueller/Nostalgex), the
retro live-TV channel guide for your own Plex library. The upstream project
ships an Apple TV app and a browser tuner, and Roku is
[not on its roadmap](https://github.com/chadMueller/Nostalgex/discussions/8).
This port fills that gap.

The goal is a faithful port. It uses the same channels, the same schedule (so
a channel shows the same programme at the same minute as on Apple TV) and the
same look, rewritten in BrightScript and SceneGraph.

It signs in to Plex, reads your library, and airs the same channels and
schedules as upstream, in the Apple TV app's guide, with packages and live
playback. Once signed in it opens on its saved guide in under a second and
refreshes in the background. Plex only; Jellyfin and Emby are not ported.

## Install (developer mode)

Until there is a store listing, it installs by sideloading:

1. Enable developer mode on the TV once: press Home ×3, Up ×2, Right, Left,
   Right, Left, Right on the remote, then set a developer password. The TV
   reboots.
2. `cp .env.example .env` and fill in `ROKU_HOSTS` and `ROKU_DEV_PASSWORD`.
3. `scripts/deploy.sh` zips the app, installs it on every TV in `ROKU_HOSTS`
   and launches it.

A Roku holds one sideloaded app at a time, and installing replaces whatever is
there. Debug output is on the TV's port 8085 (`nc <tv> 8085`).

## Security

- **Sign-in is plex.tv's link code.** The TV never sees your Plex password.
- **The Plex token stays on the TV**, in this app's private registry section.
  It is never written to the repo, to logs, or to the debug console (port
  8085), which anyone on the network can read. `tests/run.sh` fails if a
  `print` statement could output a token, URL or header.
- **HTTPS, certificates checked, to plex.tv.** The Plex server itself may be
  reached at its plain-HTTP address on your home network, as Plex's own
  apps do at home, because on some networks a TV's traffic over the public
  address stalls and the secure in-house address doesn't resolve. The app
  only does that for a private address (192.168.x, 10.x, 172.16-31.x), so
  the token never leaves the house unencrypted, and it travels in a header,
  never in a URL. If your server isn't found at all, set Plex's
  *Settings > Network > Secure connections* to *Preferred*.
- **Read-only.** The app never reports playback to Plex and never changes
  watch status or anything else in your library.
- **The saved guide** (`cachefs:`) holds titles and schedules only, and is
  deleted on sign-out.
- **Enrichment is off unless a build turns it on** (`NOSTALGEX_ENRICHMENT` in
  `.env`, see [docs/PORTING.md](docs/PORTING.md)). When on, only TMDB and
  IMDb ids leave the TV, to the Nostalgex relay and its shared cache, as the
  web tuner sends them. Its local cache is deleted on sign-out too.
- **Press \* to sign out.** That removes the token, the server list and the
  device ID the app stored.

## Tests

The port is checked against golden vectors generated from upstream's own
engine (see [docs/PORTING.md](docs/PORTING.md)):

```sh
tests/run.sh               # off-device, in the RokuCommunity brs interpreter
scripts/deploy.sh --test   # on every TV in ROKU_HOSTS; the one that counts
node tests/gen-vectors.mjs # regenerate after following a new upstream commit
```

GitHub Actions (`.github/workflows/ci.yml`) runs `tests/run.sh` on every
push, against a fresh clone of upstream.

## Layout

| Path | What |
|------|------|
| `manifest` | Roku app manifest |
| `source/` | BrightScript entry point (`main.brs`) |
| `components/` | SceneGraph screens (sign-in, guide, settings) and background tasks |
| `source/schedule/` | The daily schedule builder, ported from upstream |
| `source/filter/` | The channel filter, ported from upstream |
| `source/franchise/` | The franchise builder, ported from upstream |
| `source/guide/` | Lineup: bundles, daily shuffle, time restrictions, day schedules; franchise channels and their switches |
| `source/plex/` | Plex sign-in, library loader, playback |
| `source/subtitles/` | Subtitle settings and language matching, ported from upstream |
| `source/util/` | Shared helpers |
| `data/` | Upstream's channel config and franchise dictionary, vendored unchanged (`data/UPSTREAM`) |
| `fonts/` | DM Mono and VT323, with their licenses (`THIRD-PARTY-LICENSES.md`) |
| `images/` | Home-screen icons and splash: text only, drawn by `scripts/icons.sh` |
| `scripts/deploy.sh` | Zip and sideload to every TV (`--test` runs the vectors, `--live` the live check) |
| `tests/` | Golden vectors from upstream's code, and the runner |
| `tests/live/` | Live check against a real Plex server (`plex-link.mjs`, `compare.mjs`) |
| `docs/PORTING.md` | What is ported from where, and how parity is proven |
| `docs/UPSTREAM.md` | Working with the Nostalgex project |

## License

MIT. It includes portions of Nostalgex, copyright Chad Mueller / Muell Haus
Inc., under the same license. See [LICENSE](LICENSE).
