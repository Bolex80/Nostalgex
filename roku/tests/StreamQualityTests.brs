' Runs source/util/StreamQuality.brs (issue #65): the five levels against
' upstream's scripts/stream-quality-golden.json, copied byte for byte, which
' the Apple TV's StreamQualityGoldenTests and the web tuner's smoke test read
' too; then, hand-written, what each level asks Plex, Jellyfin and Emby for,
' the direct-play ceilings and which hosts count as home. Returns the
' failure count.

function NxRunStreamQualityTests(goldenPath as String) as Integer
    r = { pass: 0, fail: 0 }
    g = ParseJson(ReadAsciiFile(goldenPath))
    if g = invalid then
        print "FAIL cannot read "; goldenPath
        return 1
    end if

    ' ── The table: same ids, same order, same numbers ──
    levels = NxSqLevels()
    NxCheck(r, "golden: level count", levels.Count().ToStr(), g.levels.Count().ToStr())
    for i = 0 to g.levels.Count() - 1
        want = g.levels[i]
        got = NxSqLevel(want.id)
        if i < levels.Count() then NxCheck(r, "golden: level " + i.ToStr() + " is " + want.id, levels[i].id, want.id)
        NxCheck(r, "golden: " + want.id + " name", got.name, want.displayName)
        NxCheck(r, "golden: " + want.id + " kbps", got.maxBitrateKbps.ToStr(), want.maxBitrateKbps.ToStr())
        NxCheck(r, "golden: " + want.id + " width", got.width.ToStr(), want.width.ToStr())
        NxCheck(r, "golden: " + want.id + " height", got.height.ToStr(), want.height.ToStr())
        NxCheck(r, "golden: " + want.id + " videoQuality", got.videoQualityIndex.ToStr(), want.videoQualityIndex.ToStr())
    end for
    NxCheck(r, "golden: the default", NxSqLevel("").id, g.default)
    NxCheck(r, "an unknown id is the default", NxSqLevel("turbo").id, g.default)
    NxCheck(r, "invalid is the default", NxSqLevel(invalid).id, g.default)

    ' ── Plex: High, Medium and Low add the Apple TV's four parameters ──
    for each l in g.levels
        want = ""
        if NxHasValue(["high", "medium", "low"], l.id) then
            want = "&maxVideoBitrate=" + l.maxBitrateKbps.ToStr() + "&videoQuality=" + l.videoQualityIndex.ToStr()
            want = want + "&videoResolution=" + l.width.ToStr() + "x" + l.height.ToStr() + "&autoAdjustQuality=0"
        end if
        NxCheck(r, "plex query: " + l.id, NxSqPlexQuery(l.id), want)
    end for
    NxCheck(r, "plex query: unknown is Auto's", NxSqPlexQuery("turbo"), "")
    NxCheck(r, "plex session: Auto adds nothing", NxSqSessionKey("auto", "server"), "")
    NxCheck(r, "plex session: Maximum adds nothing", NxSqSessionKey("maximum", "server"), "")
    NxCheck(r, "plex session: Low has its own", NxSqSessionKey("low", "server"), "-low")
    NxCheck(r, "plex session: the 1080p rung sends no level", NxSqSessionKey("low", "capped"), "")

    ' ── Jellyfin and Emby: the level's bitrate and width, no wider than the TV ──
    NxCheck(r, "mb video: Auto as before", NxMbVideoQuery(19269, "server", 3840, "auto"), "&VideoBitrate=40000000&MaxWidth=3840")
    NxCheck(r, "mb video: Maximum as Auto", NxMbVideoQuery(29000, "server", 1920, "maximum"), "&VideoBitrate=40000000&MaxWidth=1920&AllowVideoStreamCopy=false")
    NxCheck(r, "mb video: High on a 4K TV", NxMbVideoQuery(8000, "server", 3840, "high"), "&VideoBitrate=12000000&MaxWidth=1920")
    NxCheck(r, "mb video: Medium, heavy file", NxMbVideoQuery(29000, "server", 3840, "medium"), "&VideoBitrate=4000000&MaxWidth=1280&AllowVideoStreamCopy=false")
    NxCheck(r, "mb video: Low", NxMbVideoQuery(invalid, "server", 1920, "low"), "&VideoBitrate=1500000&MaxWidth=854")
    NxCheck(r, "mb video: High on a 720p TV is 1280 wide", NxMbVideoQuery(8000, "server", 1280, "high"), "&VideoBitrate=12000000&MaxWidth=1280")
    NxCheck(r, "mb video: the 1080p rung whatever the level", NxMbVideoQuery(1000, "capped", 3840, "low"), "&VideoBitrate=8000000&MaxWidth=1920&AllowVideoStreamCopy=false")

    ' ── Direct play under the ceiling; kbps; an unknown bitrate plays ──
    cases = [
        ' kind, level, kbps, at home, allowed
        ["plex", "auto", 50000, true, true]
        ["plex", "low", 50000, true, true]
        ["plex", "auto", 20000, false, true]
        ["plex", "auto", 20001, false, false]
        ["plex", "maximum", 90000, false, true]
        ["plex", "high", 12001, false, false]
        ["plex", "medium", 4000, false, true]
        ["plex", "low", 1501, false, false]
        ["plex", "low", invalid, false, true]
        ["plex", "low", 0, false, true]
        ["jellyfin", "auto", 50000, true, true]
        ["jellyfin", "maximum", 50000, true, true]
        ["jellyfin", "high", 12001, true, false]
        ["emby", "high", 12000, true, true]
        ["emby", "low", 2000, true, false]
        ["emby", "auto", 20001, false, false]
        ["emby", "maximum", 90000, false, true]
        ["jellyfin", "medium", invalid, true, true]
    ]
    for each c in cases
        name = "direct: " + c[0] + " " + c[1] + " " + FormatJson(c[2]) + " kbps, home " + FormatJson(c[3])
        NxCheck(r, name, FormatJson(NxSqDirectPlayAllowed(c[0], c[1], c[2], c[3])), FormatJson(c[4]))
    end for

    ' ── Home, as the Apple TV's isLikelyLocalServer ──
    hosts = [
        ["192.168.1.50", true], ["10.0.0.5", true], ["172.16.0.1", true], ["172.31.255.1", true],
        ["172.32.0.1", false], ["127.0.0.1", true], ["169.254.10.2", true], ["localhost", true],
        ["nas.local", true], ["NAS.LOCAL", true], ["192-168-1-50.0123abcd.plex.direct", true],
        ["98-12-1-50.0123abcd.plex.direct", false], ["100.64.1.2", false], ["server.tail1234.ts.net", false],
        ["media.example.com", false], ["203.0.113.5", false], ["10.0.0", false], ["", false]
    ]
    for each h in hosts
        NxCheck(r, "home: " + h[0], FormatJson(NxSqIsLocalHost(h[0])), FormatJson(h[1]))
    end for

    print "stream quality cases (upstream stream-quality-golden.json):"; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
