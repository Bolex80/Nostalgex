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
the repo owner to the project Discord.

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
  in its Docker image. Enrichment stays unported until the relay accepts
  `roku`.
- **An official app:** they would like to publish it as the official Nostalgex
  app for Roku, under the Nostalgex name with full credit to the repo owner,
  and offered to talk about how to work on it together.

[Replied](https://github.com/chadMueller/Nostalgex/discussions/8#discussioncomment-18954700)
on 2026-10-15: yes, and asked where the code lives (PRs or commit access to
`roku/`), whether the store listing goes on their Roku developer account, how
the credit should appear, and whether it may use the logo. Also reported that
franchise channels are in, and asked for `roku` on the relay and which
Supabase URL and anon key Roku builds should use.

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
