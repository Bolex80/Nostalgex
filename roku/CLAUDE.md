# CLAUDE.md: roku/ in the Nostalgex repo

Roku port (BrightScript + SceneGraph) of Nostalgex, the retro channel guide for
Plex. It lives at `roku/` in the Nostalgex repo; the repo root's CLAUDE.md
applies here too. Its scripts run from anywhere (`roku/tests/run.sh`); each
one changes into `roku/` first. [README.md](README.md) covers what it is and
how to sideload. [docs/PORTING.md](docs/PORTING.md) covers what comes from
upstream and how parity is proven. Decisions made with the maintainer are on
[Discussion #8](https://github.com/chadMueller/Nostalgex/discussions/8); the
docs link the post where each was made.

## Rules that are decisions, not oversights

- **Faithful port, upstream is the source of truth.** `data/` links to the
  repo root's `channels.json`, `channels-memberships.json` and
  `franchises.json`; never copy them into `roku/`. Schedule and filter
  behaviour must match the golden vectors, which `tests/run.sh` generates
  from the root's JS engine on every run, and a mismatch is a bug in the
  port. Don't "improve" channel logic under `roku/`; change it at the root
  (engine, Swift and data together) in its own pull request.
- **Public.** The repo is public, and so is every branch of a fork. Nothing
  about one install enters it: TV addresses and the developer password go in
  `roku/.env` (git-ignored). `.secrets-allow` lists the known false positives
  of the pre-push secrets gate, by line hash.
- **Nothing personal, not even on a branch.** Additions for one person's setup
  go in a separate repo that pulls this one in unchanged.
- **Keep the MIT notice.** `LICENSE` carries upstream's copyright line, and
  ported files keep it.
- **Changes reach main through pull requests the maintainer merges.** Never
  push to `chadMueller/Nostalgex`. Anything posted publicly (a Discussion, a
  comment, a PR) is drafted, checked claim by claim, and shown to the person
  the session works for first. Re-read the whole thread, replies under
  comments included, just before posting: a follow-up the draft never saw
  went unanswered once. A session posts only when told to post that draft.
  The thread is the record: posts aren't copied into the repo.
- **One kind of server at a time.** A TV is signed in to Plex, or to one
  Jellyfin or Emby server, as the Apple TV app holds one backend
  ([docs/JELLYFIN-EMBY.md](docs/JELLYFIN-EMBY.md)).
