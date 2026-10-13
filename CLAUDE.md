# CLAUDE.md — nostalgex-roku repo

Roku port (BrightScript + SceneGraph) of Nostalgex, the retro channel guide for
Plex. [README.md](README.md) covers what it is and how to sideload.
[docs/PORTING.md](docs/PORTING.md) covers what comes from upstream and how
parity is proven. [docs/UPSTREAM.md](docs/UPSTREAM.md) covers the relationship
with the Nostalgex maintainer.

## Rules that are decisions, not oversights

- **Faithful port, upstream is the source of truth.** `channels.json` is
  vendored unchanged. Schedule and filter behaviour must match upstream's
  golden vectors, and a mismatch is a bug here. Don't "improve" channel logic
  in this repo; propose it upstream.
- **Written to be shared.** Expect this to go public and be offered upstream.
  Nothing about one install enters the repo: TV addresses and the developer
  password go in `.env` (git-ignored).
- **Nothing personal, not even on a branch.** Additions for one person's setup
  go in a separate repo that pulls this one in unchanged. This repo goes
  public through a GitHub push mirror, and a push mirror pushes every branch.
- **Keep the MIT notice.** `LICENSE` carries upstream's copyright line, and
  ported files keep it.
- **Upstream clone is read-only.** The local Nostalgex clone's `origin` is the
  maintainer's GitHub, so never push it. Anything for upstream goes out as the
  repo owner's own post or PR, drafted, never sent by a session.
- **Plex first.** Jellyfin and Emby follow once Plex reaches parity.
