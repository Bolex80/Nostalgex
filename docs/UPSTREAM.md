# Working with upstream

[Discussion #8 "Roku App"](https://github.com/chadMueller/Nostalgex/discussions/8)
(2026-10-08) asked for Roku. The maintainer replied on 2026-10-09 that it is
not on the roadmap: "Roku needs its own language and I'm one person keeping the
Apple TV app and the web tuner in step." So this port is maintained here, not
by upstream. Where it lives long-term (a companion repo or a surface in theirs)
is the maintainer's call. The Fire TV fork (Discussion #2) is the precedent.

## Draft reply for Discussion #8

Not posted. It goes out under the repo owner's account, when they choose, once
the public mirror exists (the link below).

> Hi! I took this on, and there's now a working Roku port:
> https://github.com/tydude001/nostalgex-roku
>
> It keeps Nostalgex as the source of truth. `channels.json` is vendored
> unchanged, and the schedule builder, channel filters and lineup are ported
> to BrightScript. Like the Fire TV fork, it's checked against golden vectors
> generated from your JS, and the library loader was compared live against
> `plex-tuner.html` on a real library. So a channel shows the same thing at
> the same minute on Roku as on Apple TV. It signs in with a plex.tv link
> code, uses the Apple TV guide layout with packages, plays live, and opens
> on its saved guide in about a second. For now it installs by sideloading.
> Plex only, and MusicBrainz enrichment for music videos isn't ported yet.
>
> It's a separate MIT repo crediting Nostalgex, so it doesn't add to your
> load. Three questions:
>
> 1. Would you rather it stay a separate companion project, or eventually live
>    in this repo as another surface?
> 2. Is the JS in `plex-tuner.html` the reference you'd want parity measured
>    against, or the Swift?
> 3. May the port use the Nostalgex logo artwork? For now the logo, icon and
>    splash show the name in text.
>
> Happy to share the golden vectors back if they're useful for the Fire TV
> work too.
