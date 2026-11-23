# Subtitle converter

`bolextv-subs.py` turns a Plex subtitle stream into WebVTT for the tuner.

Plex on this server answers `/library/streams/<id>` with **501**, so the tuner cannot download a
subtitle the way it can from a stock server. The service resolves the track through Plex metadata
and serves WebVTT instead:

* **external** sidecars (`<name>.en.srt` beside the video) are read off disk and converted in
  process — instant, no ffmpeg.
* **embedded** tracks are extracted with ffmpeg using the subtitle-relative index.
* image-based tracks (pgs, vobsub) cannot become a text track; they are refused with 404.

    GET /subs?rk=<ratingKey>&stream=<plexStreamId>&token=<plexToken>   -> text/vtt

Run it on the machine that holds the media, reachable from the tuner. The tuner's nginx proxies
`/subs` to it, so the TV only ever talks to its own origin:

    location /subs { proxy_pass http://<media-host>:8099; }

Environment: `PLEX_URL`, `CACHE_DIR`, `MEDIA_ROOT`, `PLEX_PATH_PREFIX` -> `HOST_PATH_PREFIX`
(how Plex's paths map onto the host), `PORT`. No credentials are stored: the token arrives with
each request.
