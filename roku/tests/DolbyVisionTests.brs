' Runs source/guide/DolbyVision.brs, NxPlexDoviOf and NxMbMediaInfo's
' Jellyfin profile (#69): on a display that can't show Dolby Vision, a
' profile 5 file goes on no channel, from Plex, Jellyfin or Emby. The
' fixtures are trimmed real answers (tests/fixtures/dolby-vision.json).
' Returns the failure count.

function NxRunDolbyVisionTests(fixturePath as String) as Integer
    r = { pass: 0, fail: 0 }
    dv5 = { title: "Five", doviProfile: 5 }
    dv8 = { title: "Eight", doviProfile: 8 }
    sdr = { title: "Plain" }
    NxCheck(r, "profile 5, no Dolby Vision display: off", FormatJson(NxLeftOffForDisplay(dv5, false)), "true")
    NxCheck(r, "profile 5, Dolby Vision display: on", FormatJson(NxLeftOffForDisplay(dv5, true)), "false")
    NxCheck(r, "profile 8 stays on", FormatJson(NxLeftOffForDisplay(dv8, false)), "false")
    NxCheck(r, "no profile stays on", FormatJson(NxLeftOffForDisplay(sdr, false)), "false")
    kept = NxOnChannelsForDisplay([dv5, sdr, dv8, dv5], false)
    names = []
    for each it in kept
        names.Push(it.title)
    end for
    NxCheck(r, "filter keeps order", names.Join(","), "Plain,Eight")
    NxCheck(r, "Dolby Vision display keeps all", NxOnChannelsForDisplay([dv5, sdr], true).Count().ToStr(), "2")
    ' The shared rule is unchanged: Emby only, on every display.
    NxCheck(r, "shared rule: plex profile 5", FormatJson(NxIsLeftOffChannels(dv5, "plex")), "false")
    NxCheck(r, "shared rule: emby profile 5", FormatJson(NxIsLeftOffChannels(dv5, "emby")), "true")

    fx = ParseJson(ReadAsciiFile(fixturePath))
    NxCheck(r, "plex: profile from the dovi=1 listing", NxToStr(NxPlexDoviOf(fx.plex)), "5")
    NxCheck(r, "plex: no stream, no profile", FormatJson(NxPlexDoviOf({ Media: [{ Part: [{ key: "/p" }] }] })), "null")
    NxCheck(r, "plex: no media", FormatJson(NxPlexDoviOf({ ratingKey: "1" })), "null")
    mi = NxMbMediaInfo(fx.jellyfin)
    NxCheck(r, "jellyfin: DvProfile read", NxToStr(mi.doviProfile), "5")
    NxCheck(r, "jellyfin: codec still read", NxToStr(mi.videoCodec), "hevc")
    emby = { MediaSources: [{ Id: "e1", MediaStreams: [{ Type: "Video", Codec: "hevc", ExtendedVideoSubType: "DoviProfile81" }] }] }
    NxCheck(r, "emby: ExtendedVideoSubType still wins", NxToStr(NxMbMediaInfo(emby).doviProfile), "8")

    print "dolby vision cases (#69): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
