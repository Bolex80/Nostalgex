# Working with upstream

[Discussion #8 "Roku App"](https://github.com/chadMueller/Nostalgex/discussions/8)
(2026-10-08) asked for Roku. The maintainer replied on 2026-10-09 that it is
not on the roadmap: "Roku needs its own language and I'm one person keeping the
Apple TV app and the web tuner in step." So this port is maintained here, not
by upstream. Where it lives long-term (a companion repo or a surface in theirs)
is the maintainer's call. The Fire TV fork (Discussion #2) is the precedent.

## Reply posted to Discussion #8

[Posted](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18901675)
on 2026-10-13.

> Hi! Since Roku isn't on the roadmap, I built a port:
> https://github.com/tydude001/nostalgex-roku
>
> It treats Nostalgex as the source of truth. `channels.json` is vendored
> unchanged, and the schedule builder, channel filter and lineup are ported to
> BrightScript and tested against golden vectors generated from your JS. The
> library loader was also compared with `plex-tuner.html` on a real Plex
> library, and the results matched. It signs in with a plex.tv link code and
> has the Apple TV guide layout, packages and playback. It's Plex only, installs
> by sideloading for now, and doesn't have the MusicBrainz/Deezer music-video
> enrichment yet.
>
> It's a separate MIT repo that credits Nostalgex, so it adds nothing to your
> load. Three questions:
>
> 1. Should it stay a separate project, or would you eventually want it in
>    this repo?
> 2. I measured parity against the JS (`plex-tuner.html` and the `scripts/`
>    modules). Is that the reference you want, or the Swift?
> 3. May it use the Nostalgex logo? For now the logo, icon and splash are text.

## The maintainer's answer

[Replied](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18907140) on
2026-10-13. They read the code, and said checking the filter against vectors
from their filter script is how they want parity checked.

1. **Where it lives:** undecided, so it stays a separate repo for now. Longer
   term they could see it in their repo as `roku/`, reading the same
   `channels.json`, memberships and franchise files directly. If so, the repo
   owner is credited and invited to co-maintain.
2. **Reference:** the JS — `scripts/nostalgex-channel-filter.cjs` and the
   shared JSON files. They pointed at FRANCHISES (`franchises.json`,
   `scripts/nostalgex-franchise-builder.js`, golden file
   `scripts/franchise-golden.json`) as new since the posted snapshot
   (c2f32e6). It is ported, engine only ([PORTING.md](PORTING.md)).
3. **Logo:** held until where the port lives is settled.

They plan to try it on a Roku and give feedback in the discussion, and invited
the repo owner to the project Discord. The owner keeps it to GitHub, so
drafts don't offer Discord.

[Followed up](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18908210)
the same day: a separate repo is fine, the builder is ported and passes
`franchise-golden.json`, and should the Roku guide show franchise channels
now, following the Apple TV app, or wait for the web tuner?

[Asked](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18937338)
on 2026-10-14, in the same thread: may the Roku app use upstream's TMDB/OMDb
relay and shared `media_enrichments` cache as `nostalgex-enrichment.js` does,
and under which `X-Nostalgex-Client` value?

[Answered](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18953180)
on 2026-10-15:

- **Franchises:** the Roku follows the Apple TV app and shows franchise
  channels now. Done ([PORTING.md](PORTING.md)).
- **Enrichment:** yes, through the relay and the shared cache, as
  `X-Nostalgex-Client: roku`. On 2026-10-15 the relay still answered `roku`
  with 403, since `api/tmdb.js` accepts only `tvos`, `web` and `selfhost`. The
  Supabase URL and anon key are build settings upstream, not in its repo, as
  in its Docker image. The port's enrichment stays out of builds until the
  relay accepts `roku` ([PORTING.md](PORTING.md)).
- **An official app:** they would like to publish it as the official Nostalgex
  app for Roku, under the Nostalgex name with full credit to the repo owner,
  and offered to talk about how to work on it together.

[Replied](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18954700)
on 2026-10-15: yes, and asked where the code lives (PRs or commit access to
`roku/`), whether the store listing goes on their Roku developer account, how
the credit should appear, and whether it may use the logo. Also reported that
franchise channels are in, and asked for `roku` on the relay and which
Supabase URL and anon key Roku builds should use.

[Answered](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18961197)
on 2026-10-15, on enrichment only; the four official-app questions are still
open:

- **Relay:** accepts `X-Nostalgex-Client: roku` now (upstream bfb4453). Four
  read-only TMDB routes (`movie/{id}` and `tv/{id}` with
  `append_to_response=keywords`, `collection/{id}`, `search/collection`) plus
  `omdb/{imdbID}`, cached at the edge, nothing logged. `roUrlTransfer` sends
  no Origin, so no CORS handling is needed.
- **Cache first:** read the shared Supabase cache with the anon key and hit
  the relay only on a miss, as the Apple TV app and web tuner do.
- **OMDb:** the free tier is 1,000 requests a day across every client
  together, so cache aggressively.

They said the anon key is "already in the repo"; it isn't, upstream's source
has only placeholders. The URL and key are in the built web tuner, in the
`nostalgex-supabase-url` and `nostalgex-supabase-anon-key` meta tags of
`https://www.nostalgex.app/plex-tuner` (project `ljlhreomwcsyhiytqipm`, JWT
role `anon`).

[Replied](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18963114)
on 2026-10-15 with the first TV run ([PORTING.md](PORTING.md)), asked whether
Roku builds should read that Supabase project or a separate one, and withdrew
the logo question: the owner keeps the port's own logo, icon and splash.

[Answered](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18982798)
on 2026-10-16, after installing it on a Roku Stick Plus (OS 15.3.4). The
vectors pass on that device, the schedule matches the web tuner, and
enrichment through the relay works. The official-app questions are settled:

- **Where the code lives:** `roku/` in upstream's repo, with PRs from the
  repo owner's fork to start.
- **Who publishes:** the store listing goes on the maintainer's Roku developer
  account, and the repo owner prepares the builds.
- **Credit:** to the repo owner, in the app and in the listing.
- **Supabase:** the web tuner's project. The maintainer confirmed the anon key
  was never in the repo.

They reported six problems from their device, biggest first: transcoded
streams start from zero, a memory crash with 45 channels on
(`EXIT_CHANNEL_MEM_LIMIT_FG` while saving), every server on the account is
loaded instead of owned ones, the sign-in code never refreshes on screen,
deep links never match on a real Roku (the id arrives as `roInteger`), and
`*` in the guide signs out with no confirmation. They want the look as close
to the Apple TV app as it can get, guide first, from the App Store shots,
nostalgex.app/screens and `Nostalgex/Nostalgex/Views` (both 1920x1080).

[Followed up](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18982978)
12 minutes later, as a reply under that comment, with a seventh problem and
the bar for the Channel Store. Seventh: turning a package on re-reads the
whole library from every server (3.5 minutes for them) instead of rebuilding
from the saved library as the Apple TV app does. The bar, on a normal
library:

- the guide ready in under 2 minutes on a first run, owned servers only;
- converted (transcoded) channels starting in under 10 seconds, mid-programme
  included;
- no crash with every package on, and no rescan when one is switched;
- the guide looking like the Apple TV one: layout, fonts and colours.

The Apple TV app's versions to look at: the library saved in chunks
(`LibrarySnapshotStore.swift`), transcodes started at the offset server side,
owned servers only. They put every pushed build on their stick and report
within a day, console log on request.

[Replied](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18984559)
on 2026-10-16: all six fixed (`f237f6c`, memory also `62dc326`), saying which
were checked on a TV and which weren't (the server rows, the sign-in code,
the sign-out confirmation). It reported the saved pools file going from 30 MB
to 3.5 MB, asked for the `saved the pools` console line from their larger
library, agreed to `roku/` via PRs and the listing on their account, and said
the Apple TV look comes next, guide first, then the PRs. It missed the
follow-up above, posted two hours before it.

[Followed up](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18984628)
the same day: took the four points as the bar for the Channel Store, said
where each stands (the rescan not fixed, the first run and transcode start
not timed, every package on not tried, the look after those), and asked for
their `saved the pools` line and a converted channel's start time.

## Channel ideas: Discussion #29

[Posted](https://github.com/chadMueller/Nostalgex/discussions/29) on
2026-10-14: a year-round horror package (FRIGHT NIGHT, NOSTALGEX HORROR,
SLASHER, FOUND FOOTAGE, HORROR COMEDY, WORLD HORROR), plus MYSTERY BOX TV in
CASE FILES, CRINGE TV in PRIME TIME and A24 in NETWORKS. It notes that SCREAM
is October-only and that an exclusive rule keeps "Halloween" and "Scream"
titles on SCREAM ADULTS. `channels.json` here stays unchanged until upstream
adopts something.

[Answered](https://github.com/chadMueller/Nostalgex/discussions/29#discussioncomment-18953112)
on 2026-10-15. They liked SLASHER and FOUND FOOTAGE most and will post back
once they have worked out which channels fit as a package. Horror will be
available outside October as a bundle that can be switched on or off, and so
will the Christmas bundle.
