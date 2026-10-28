' Runs source/guide/PlaybackInfo.brs (issue #74): codec labels, sizes and
' sequences of attempts against upstream's scripts/nostalgex-playback-info.js
' (tests/gen-playback-info.mjs); then, hand-written, the Roku ladder's steps
' in the reasons upstream's AppState+Playback.swift gives the same steps, and
' QUALITY AT TUNE. Returns the failure count.

function NxRunPlaybackInfoTests(vectorsPath as String) as Integer
    r = { pass: 0, fail: 0 }
    v = ParseJson(ReadAsciiFile(vectorsPath))
    if v = invalid then
        print "FAIL cannot read "; vectorsPath
        return 1
    end if

    for each c in v.codecs
        NxCheck(r, "codec " + FormatJson(c.value) + " video " + NxToStr(c.video), NxPiCodecLabel(c.value, c.video), c.label)
    end for
    for each c in v.sizes
        NxCheck(r, "size " + FormatJson(c.w) + " x " + FormatJson(c.h), NxPiSizeLabel(c.w, c.h), c.label)
    end for
    for each c in v.sequences
        info = NxPiCreate(c.create)
        ids = []
        for i = 0 to c.steps.Count() - 1
            s = c.steps[i]
            want = c.answers[i]
            name = c.name + " (" + NxToStr(c.create.backend) + " gen " + NxToStr(c.create.generation) + ") step " + i.ToStr()
            if s.op = "begin" then
                id = NxPiBeginAttempt(info, s.gen, NxToStr(s.delivery), NxToStr(s.reason), NxToStr(s.recovery))
                if id <> invalid then ids.Push(id)
                NxCheck(r, name + " begin", FormatJson(id <> invalid), FormatJson(want))
            else if s.op = "ready" then
                id = invalid
                if s.which = "latest" and ids.Count() > 0 then id = ids[ids.Count() - 1]
                if s.which = "previous" and ids.Count() > 1 then id = ids[ids.Count() - 2]
                NxCheck(r, name + " ready", FormatJson(NxPiMarkReady(info, s.gen, id)), FormatJson(want))
            else if s.op = "invalidate" then
                NxPiInvalidate(info)
            else
                NxCheck(r, name + " rows", NxPiRowsText(NxPiRows(info, s.w, s.h)), NxPiRowsText(want))
            end if
        end for
    end for

    ' ── The Roku ladder in upstream's words (AppState+Playback.swift) ──
    NxCheck(r, "direct is Direct Play", NxPiDeliveryFor("direct"), "directPlay")
    NxCheck(r, "server is a server stream", NxPiDeliveryFor("server"), "serverStream")
    NxCheck(r, "capped is a server stream", NxPiDeliveryFor("capped"), "serverStream")
    NxCheck(r, "first: direct play, no fallback", NxPiFirstReason("direct"), "none")
    NxCheck(r, "first: a server stream chosen", NxPiFirstReason("server"), "serverStreamSelected")
    NxCheck(r, "direct play errors", FormatJson(NxPiStepReason("direct", "error", { rung: "server", retry: false })), FormatJson({ reason: "directPlayFailed", recovery: "" }))
    NxCheck(r, "direct play, no picture", FormatJson(NxPiStepReason("direct", "nopicture", { rung: "server", retry: false })), FormatJson({ reason: "startupNoPicture", recovery: "" }))
    NxCheck(r, "direct play starves", FormatJson(NxPiStepReason("direct", "starved", { rung: "server", retry: false })), FormatJson({ reason: "streamStalled", recovery: "" }))
    NxCheck(r, "server stream retried", FormatJson(NxPiStepReason("server", "error", { rung: "server", retry: true })), FormatJson({ reason: "playerRetry", recovery: "" }))
    NxCheck(r, "server stream, no picture: 1080p", FormatJson(NxPiStepReason("server", "nopicture", { rung: "capped", retry: false })), FormatJson({ reason: "startupNoPicture", recovery: "compatibility1080p" }))
    NxCheck(r, "server stream starves: 1080p", FormatJson(NxPiStepReason("server", "starved", { rung: "capped", retry: false })), FormatJson({ reason: "streamStalled", recovery: "compatibility1080p" }))
    NxCheck(r, "Jellyfin/Emby server stream errors: 1080p", FormatJson(NxPiStepReason("server", "error", { rung: "capped", retry: false })), FormatJson({ reason: "playerRetry", recovery: "compatibility1080p" }))
    ' Each step of the ladder itself (Fallback.brs), named as above.
    nxt = NxFallbackNext(NxFirstAttempt("direct"), "error", "plex")
    NxCheck(r, "ladder: Plex direct play errors", FormatJson(NxPiStepReason("direct", "error", nxt)), FormatJson({ reason: "directPlayFailed", recovery: "" }))
    nxt = NxFallbackNext(NxFirstAttempt("server"), "error", "plex")
    NxCheck(r, "ladder: Plex server stream errors", FormatJson(NxPiStepReason("server", "error", nxt)), FormatJson({ reason: "playerRetry", recovery: "" }))
    nxt = NxFallbackNext(NxFirstAttempt("server"), "error", "emby")
    NxCheck(r, "ladder: Emby server stream errors", FormatJson(NxPiStepReason("server", "error", nxt)), FormatJson({ reason: "playerRetry", recovery: "compatibility1080p" }))
    nxt = NxFallbackNext(NxFirstAttempt("server"), "nopicture", "jellyfin")
    NxCheck(r, "ladder: Jellyfin no picture", FormatJson(NxPiStepReason("server", "nopicture", nxt)), FormatJson({ reason: "startupNoPicture", recovery: "compatibility1080p" }))

    ' ── QUALITY AT TUNE, the STREAM QUALITY level by its Apple TV name ──
    for each c in [["auto", "Auto"], ["maximum", "Maximum"], ["high", "High"], ["medium", "Medium"], ["low", "Low"], ["", "Auto"], ["turbo", "Auto"]]
        NxCheck(r, "quality: level " + FormatJson(c[0]), NxPiQualityLabel(c[0]), c[1])
        NxCheck(r, "quality: " + c[1] + " shows", NxPiCreate({ generation: 1, backend: "plex", qualityAtTune: c[1] }).quality, c[1])
    end for
    NxCheck(r, "quality: the web's Plex label doesn't", NxPiCreate({ generation: 1, backend: "plex", qualityAtTune: "Server default" }).quality, "Unknown")
    NxCheck(r, "quality: anything else doesn't", NxPiCreate({ generation: 1, backend: "emby", qualityAtTune: "http://x" }).quality, "Unknown")
    print "playback info cases (upstream nostalgex-playback-info.js):"; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

function NxPiRowsText(rows as Dynamic) as String
    parts = []
    for each row in NxList(rows)
        parts.Push(NxToStr(row.label) + "=" + NxToStr(row.value))
    end for
    return parts.Join(" | ")
end function
