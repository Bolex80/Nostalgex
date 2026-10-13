# Working with upstream

[Discussion #8 "Roku App"](https://github.com/chadMueller/Nostalgex/discussions/8)
(2026-10-08) asked for Roku. The maintainer replied on 2026-10-09 that it is
not on the roadmap: "Roku needs its own language and I'm one person keeping the
Apple TV app and the web tuner in step." So this port is maintained here, not
by upstream. Where it lives long-term (a companion repo or a surface in theirs)
is the maintainer's call. The Fire TV fork (Discussion #2) is the precedent.

## Draft reply for Discussion #8

Not posted. It goes out under the repo owner's account, when they choose.

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
