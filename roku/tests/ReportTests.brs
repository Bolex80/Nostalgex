' Runs SHOW NOW PLAYING and MARK WATCHED (issue #72): source/guide/
' PlaybackReport.brs and ReportExecutor.brs. The cleanup plans and the
' backoff against upstream's scripts/nostalgex-watch-state.js and
' scripts/watch-cleanup-golden.json (tests/gen-watch.mjs); the gate, the
' tracker and what goes to the server on a synthetic clock with a fake
' transport, after PlaybackReportingControlsTests.swift and
' PlexActivitySyncTests.swift. Returns the failure count.

function NxRunReportTests(vectorsPath as String, goldenPath as String) as Integer
    r = { pass: 0, fail: 0 }
    v = ParseJson(ReadAsciiFile(vectorsPath))
    g = ParseJson(ReadAsciiFile(goldenPath))
    if v = invalid or g = invalid then
        print "FAIL cannot read "; vectorsPath; " or "; goldenPath
        return 1
    end if

    ' ── The plans, against the golden file ──
    for each c in g.cases
        if c.backend = "plex" then steps = NxPlexCleanupPlan(c.prior, c.counted) else steps = NxMediaServerCleanupPlan(c.prior, c.counted)
        NxCheck(r, "golden: " + c.name, NxRpSteps(steps), NxRpJoin(c.steps))
    end for
    for each c in v.plans
        if c.backend = "plex" then steps = NxPlexCleanupPlan(c.prior, c.counted) else steps = NxMediaServerCleanupPlan(c.prior, c.counted)
        NxCheck(r, "plan " + c.backend + " " + FormatJson(c.prior) + " counted " + NxToStr(c.counted), NxRpSteps(steps), NxRpJoin(c.steps))
    end for

    ' ── PulseBackoff, against upstream's ──
    for each c in v.backoff
        b = NxPulseBackoff()
        answers = []
        for each s in c.steps
            if s = "pulse" then
                answers.Push(NxToStr(NxPulseAllow(b)))
            else
                NxPulseRecord(b, s = "ok")
            end if
        end for
        NxCheck(r, "backoff: " + c.name, answers.Join(" | "), NxRpJoin(c.answers))
    end for

    ' ── The gate ──
    NxCheck(r, "gate: tuned in at 15% exactly", NxToStr(NxReportEligible(900, 100)), "true")
    NxCheck(r, "gate: tuned in at 15.1%", NxToStr(NxReportEligible(906, 100)), "false")
    NxCheck(r, "gate: no runtime", NxToStr(NxReportEligible(0, 0)), "false")
    NxCheck(r, "gate: 75% watched", NxToStr(NxReportCounted(4500.0, 100)), "true")
    NxCheck(r, "gate: 74.9% watched", NxToStr(NxReportCounted(4494.0, 100)), "false")

    ' A client id of the tests' own (the sign-in dry run's hook): no registry
    ' off the TV, and a TV's run must not touch the app's.
    g = GetGlobalAA()
    keepId = g.nxDryRunClientId
    g.nxDryRunClientId = "nx-report-test"
    NxRpPlexCases(r)
    NxRpMediaServerCases(r)
    NxRpChoiceCases(r)
    g.nxDryRunClientId = keepId

    print "report cases (upstream watch state, PlaybackTracker): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

' ── Plex ────────────────────────────────────────────────────────────────────

sub NxRpPlexCases(r as Object)
    film = { ratingKey: "101", partKey: "/library/parts/9/file.mkv", type: "movie", duration: 100, startSec: 1000, serverIndex: 0 }

    ' Both off: the stop and the cleanup run, and nothing is sent.
    h = NxRpHarness("plex", NxRpScope(false, false), film, 300, "s1")
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportTick(h.t, h.scope, 10.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 6000.0))
    NxCheck(r, "plex, both off: nothing sent", h.net.calls.Join(" | "), "")

    ' Now Playing only: position-free reports, a stop, no scrobble even after
    ' a full watch, no reads for a film.
    h = NxRpHarness("plex", NxRpScope(true, false), film, 0, "s2")
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportTick(h.t, h.scope, 10.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 6000.0))
    want = [
        "PUT http://plex:32400/:/timeline?ratingKey=101&key=/library/metadata/101&state=playing [session s2]",
        "PUT http://plex:32400/:/timeline?ratingKey=101&key=/library/metadata/101&state=playing [session s2]",
        "PUT http://plex:32400/:/timeline?ratingKey=101&key=/library/metadata/101&state=stopped [session s2]"
    ]
    NxCheck(r, "plex, now playing only: timeline, no time, no scrobble", h.net.calls.Join(" | "), want.Join(" | "))

    ' Mark Watched only: no timeline at all; the scrobble once at 75%.
    h = NxRpHarness("plex", NxRpScope(false, true), film, 300, "s3")
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportTick(h.t, h.scope, 4400.0))
    NxCheck(r, "plex, mark only: nothing before 75%", h.net.calls.Join(" | "), "")
    NxRpRun(h, NxReportTick(h.t, h.scope, 4510.0))
    NxRpRun(h, NxReportTick(h.t, h.scope, 4520.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 6000.0))
    NxCheck(r, "plex, mark only: one scrobble with the bare key", h.net.calls.Join(" | "), "GET http://plex:32400/:/scrobble?key=101&identifier=com.plexapp.plugins.library")

    ' Joined at 20%: never counted.
    h = NxRpHarness("plex", NxRpScope(false, true), film, 1200, "s4")
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 6000.0))
    NxCheck(r, "plex: joined at 20%, not counted", h.net.calls.Join(" | "), "")

    ' A counted episode whose show wasn't in Continue Watching: its next-up
    ' entry, which Plex adds a moment later, is removed.
    ep = { ratingKey: "201", type: "episode", duration: 22, startSec: 0, serverIndex: 0 }
    h = NxRpHarness("plex", NxRpScope(false, true), ep, 0, "s5")
    h.net.answers["GET http://plex:32400/library/metadata/201"] = [{ code: 200, json: { MediaContainer: { Metadata: [{ ratingKey: "201", type: "episode", grandparentRatingKey: "77" }] } } }]
    ' Before tune-in: another show. Then twice without the next-up entry, then with it.
    h.net.answers["GET http://plex:32400/hubs/continueWatching/items?count=200"] = [
        { code: 200, json: { MediaContainer: { Metadata: [{ ratingKey: "900", grandparentRatingKey: "55" }] } } },
        { code: 200, json: { MediaContainer: { Metadata: [] } } },
        { code: 200, json: { MediaContainer: { Metadata: [{ ratingKey: "202", grandparentRatingKey: "77" }] } } }
    ]
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 1000.0))
    want = [
        "GET http://plex:32400/library/metadata/201",
        "GET http://plex:32400/hubs/continueWatching/items?count=200",
        "GET http://plex:32400/:/scrobble?key=201&identifier=com.plexapp.plugins.library",
        "GET http://plex:32400/hubs/continueWatching/items?count=200",
        "sleep 1000",
        "GET http://plex:32400/hubs/continueWatching/items?count=200",
        "PUT http://plex:32400/actions/removeFromContinueWatching?ratingKey=202"
    ]
    NxCheck(r, "plex episode counted: next-up removed after a retry", h.net.calls.Join(" | "), want.Join(" | "))

    ' The same with the show already in Continue Watching: left alone.
    h = NxRpHarness("plex", NxRpScope(false, true), ep, 0, "s6")
    h.net.answers["GET http://plex:32400/library/metadata/201"] = [{ code: 200, json: { MediaContainer: { Metadata: [{ ratingKey: "201", type: "episode", grandparentRatingKey: "77" }] } } }]
    h.net.answers["GET http://plex:32400/hubs/continueWatching/items?count=200"] = [{ code: 200, json: { MediaContainer: { Metadata: [{ ratingKey: "200", grandparentRatingKey: "77" }] } } }]
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 1000.0))
    NxCheck(r, "plex episode counted, show already there: no removal", NxRpCount(h.net.calls, "removeFromContinueWatching"), "0")

    ' A server that stops answering: fewer pulses, never a changed choice.
    h = NxRpHarness("plex", NxRpScope(true, false), film, 0, "s7")
    h.net.fail = true
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    for i = 1 to 6
        NxRpRun(h, NxReportTick(h.t, h.scope, i * 10.0))
    end for
    ' Ready fails (skip 1); pulse 1 skipped; pulse 2 fails (skip 2); 3, 4
    ' skipped; pulse 5 fails (skip 4); 6 skipped.
    NxCheck(r, "plex, no answers: pulses back off", NxRpCount(h.net.calls, "state=playing"), "3")
    NxCheck(r, "plex, no answers: the choice stays on", NxToStr(h.scope.nowPlaying), "true")
    NxRpRun(h, NxReportStop(h.t, h.scope, 70.0))
    NxCheck(r, "plex, no answers: the stop still goes out", NxRpCount(h.net.calls, "state=stopped"), "1")

    ' The request itself, as heartbeatRequest builds it.
    srv = { kind: "plex", base: "https://plex.example:32400", token: "t0k", userId: "" }
    req = NxPlexTimelineRequest(srv, "101", "buffering", "abc")
    NxCheck(r, "plex timeline: url", req.url, "https://plex.example:32400/:/timeline?ratingKey=101&key=/library/metadata/101&state=buffering")
    NxCheck(r, "plex timeline: method and session", req.method + " " + req.headers["X-Plex-Session-Identifier"], "PUT abc")
    NxCheck(r, "plex timeline: a state upstream refuses", FormatJson(NxPlexTimelineRequest(srv, "101", "ended", "abc")), "null")
    NxCheck(r, "plex timeline: a key that isn't a number", FormatJson(NxPlexTimelineRequest(srv, "10a", "playing", "abc")), "null")

    ' Player states reach Plex at once; Jellyfin and Emby wait for the pulse.
    h = NxRpHarness("plex", NxRpScope(true, false), film, 0, "s8")
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportPlayerState(h.t, h.scope, "buffering"))
    NxRpRun(h, NxReportPlayerState(h.t, h.scope, "buffering"))
    NxRpRun(h, NxReportPlayerState(h.t, h.scope, "playing"))
    NxCheck(r, "plex: a stall shows once, then playing", NxRpCount(h.net.calls, "state=buffering") + "/" + NxRpCount(h.net.calls, "state=playing"), "1/2")
end sub

' ── Jellyfin and Emby ───────────────────────────────────────────────────────

sub NxRpMediaServerCases(r as Object)
    film = { ratingKey: "abc", partKey: "src1", type: "movie", duration: 100, startSec: 0, serverIndex: 0 }
    never = { code: 200, json: { UserData: { PlaybackPositionTicks: 0, PlayCount: 0, Played: false } } }

    ' Now Playing only, never played before: the reading, the session at the
    ' real position, the stop short of completion, then put back unplayed.
    h = NxRpHarness("emby", NxRpScope(true, false), film, 60, "e1")
    h.net.answers["GET http://emby:8096/Users/u1/Items/abc"] = [never]
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportTick(h.t, h.scope, 10.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 6000.0))
    want = [
        "GET http://emby:8096/Users/u1/Items/abc",
        "POST http://emby:8096/Sessions/Playing {""ItemId"":""abc"",""PlaySessionId"":""e1"",""MediaSourceId"":""src1"",""PositionTicks"":600000000,""IsPaused"":false}",
        "POST http://emby:8096/Sessions/Playing/Progress {""ItemId"":""abc"",""PlaySessionId"":""e1"",""MediaSourceId"":""src1"",""PositionTicks"":700000000,""IsPaused"":false}",
        "POST http://emby:8096/Sessions/Playing/Stopped {""ItemId"":""abc"",""PlaySessionId"":""e1"",""MediaSourceId"":""src1"",""PositionTicks"":53400000000,""IsPaused"":false}",
        "DELETE http://emby:8096/Users/u1/PlayedItems/abc"
    ]
    NxCheck(r, "emby, now playing only: read, report, stop at 89%, put back", h.net.calls.Join(" | "), want.Join(" | "))

    ' No reading: no session, no mark, nothing put back.
    h = NxRpHarness("jellyfin", NxRpScope(true, true), film, 0, "e2")
    h.net.answers["GET http://emby:8096/Users/u1/Items/abc"] = [{ code: 500, json: invalid }]
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportTick(h.t, h.scope, 5000.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 6000.0))
    NxCheck(r, "jellyfin, unreadable: only the reading", h.net.calls.Join(" | "), "GET http://emby:8096/Users/u1/Items/abc")

    ' Counted: the explicit mark, then one counted watch on top of the prior.
    h = NxRpHarness("emby", NxRpScope(false, true), film, 0, "e3")
    h.net.answers["GET http://emby:8096/Users/u1/Items/abc"] = [{ code: 200, json: { UserData: { PlaybackPositionTicks: 0, PlayCount: 2, Played: true, LastPlayedDate: "2026-01-02T03:04:05.0000000Z" } } }]
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportTick(h.t, h.scope, 4600.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 4700.0))
    want = [
        "GET http://emby:8096/Users/u1/Items/abc",
        "POST http://emby:8096/Users/u1/PlayedItems/abc",
        "POST http://emby:8096/Users/u1/Items/abc/UserData {""PlayCount"":3,""PlaybackPositionTicks"":0,""Played"":true}"
    ]
    NxCheck(r, "emby, mark only, counted: mark, then one count", h.net.calls.Join(" | "), want.Join(" | "))

    ' Surfed past a part-watched film: its position and date come back.
    h = NxRpHarness("emby", NxRpScope(true, false), film, 0, "e4")
    h.net.answers["GET http://emby:8096/Users/u1/Items/abc"] = [{ code: 200, json: { UserData: { PlaybackPositionTicks: 12000000000, PlayCount: 1, Played: false, LastPlayedDate: "2026-01-02T03:04:05.0000000Z" } } }]
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportStop(h.t, h.scope, 30.0))
    NxCheck(r, "emby surf: prior state back", h.net.calls[h.net.calls.Count() - 1], "POST http://emby:8096/Users/u1/Items/abc/UserData {""LastPlayedDate"":""2026-01-02T03:04:05.0000000Z"",""PlayCount"":1,""PlaybackPositionTicks"":12000000000,""Played"":false}")
end sub

' ── Changing a choice ───────────────────────────────────────────────────────

sub NxRpChoiceCases(r as Object)
    film = { ratingKey: "abc", partKey: "src1", type: "movie", duration: 100, startSec: 0, serverIndex: 0 }
    never = { code: 200, json: { UserData: { PlaybackPositionTicks: 0, PlayCount: 0, Played: false } } }

    ' Now Playing turned off mid-programme: a stop and the item put back; the
    ' clock goes on.
    h = NxRpHarness("emby", NxRpScope(true, false), film, 0, "c1")
    h.net.answers["GET http://emby:8096/Users/u1/Items/abc"] = [never]
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    was = { nowPlaying: true, markWatched: false }
    NxReportScopeUpdate(h.scope, { nowPlaying: false, markWatched: false })
    NxRpRun(h, NxReportUpdate(h.t, was, h.scope))
    NxRpRun(h, NxReportTick(h.t, h.scope, 20.0))
    NxCheck(r, "now playing off: stop and put back", NxRpCount(h.net.calls, "Stopped") + "/" + NxRpCount(h.net.calls, "PlayedItems"), "1/1")
    NxCheck(r, "now playing off: no more reports", NxRpCount(h.net.calls, "Progress"), "0")
    NxCheck(r, "now playing off: the clock goes on", NxToStr(Int(h.t.activeSec)), "20")

    ' Queued under an old epoch: dropped, even after the choice comes back on.
    h = NxRpHarness("plex", NxRpScope(true, false), { ratingKey: "101", type: "movie", duration: 100, startSec: 0, serverIndex: 0 }, 0, "c2")
    queued = NxReportReady(h.t, h.scope, 0.0)
    NxReportScopeUpdate(h.scope, { nowPlaying: false, markWatched: false })
    NxReportScopeUpdate(h.scope, { nowPlaying: true, markWatched: false })
    NxRpRun(h, queued)
    NxCheck(r, "off then on: queued work stays dropped", h.net.calls.Join(" | "), "")

    ' A mark already sent is never sent again when Mark Watched comes back.
    h = NxRpHarness("plex", NxRpScope(false, true), { ratingKey: "101", type: "movie", duration: 100, startSec: 0, serverIndex: 0 }, 0, "c3")
    NxRpRun(h, NxReportReady(h.t, h.scope, 0.0))
    NxRpRun(h, NxReportTick(h.t, h.scope, 4600.0))
    was = { nowPlaying: false, markWatched: true }
    NxReportScopeUpdate(h.scope, { nowPlaying: false, markWatched: false })
    NxRpRun(h, NxReportUpdate(h.t, was, h.scope))
    was = { nowPlaying: false, markWatched: false }
    NxReportScopeUpdate(h.scope, { nowPlaying: false, markWatched: true })
    NxRpRun(h, NxReportUpdate(h.t, was, h.scope))
    NxRpRun(h, NxReportTick(h.t, h.scope, 4700.0))
    NxCheck(r, "mark off then on: one scrobble", NxRpCount(h.net.calls, "scrobble"), "1")

    ' Saved choices: off until turned on.
    NxCheck(r, "same airing: a retry keeps its tracker", NxToStr(NxReportSameAiring(h.t, { ratingKey: "101", startSec: 0, serverIndex: 0 })), "true")
    NxCheck(r, "same airing: the next one doesn't", NxToStr(NxReportSameAiring(h.t, { ratingKey: "101", startSec: 6000, serverIndex: 0 })), "false")
end sub

' ── Harness ─────────────────────────────────────────────────────────────────

function NxRpScope(nowPlaying as Boolean, markWatched as Boolean) as Object
    return NxReportScope({ nowPlaying: nowPlaying, markWatched: markWatched })
end function

function NxRpHarness(kind as String, scope as Object, b as Object, offset as Integer, session as String) as Object
    base = "http://plex:32400"
    if kind <> "plex" then base = "http://emby:8096"
    return {
        t: NxReportTracker(b, offset, kind, session), scope: scope, ex: NxReportExecutor(),
        net: NxRpNet({ kind: kind, base: base, token: "tok", userId: "u1" })
    }
end function

sub NxRpRun(h as Object, events as Object)
    for each ev in events
        NxReportRun(h.ex, ev, h.scope, h.net)
    end for
end sub

' The fake transport: records each request (with Plex's session header and a
' body when there is one) and answers from `answers`, a list per request,
' the last answer repeating; 200 otherwise, or nothing when `fail`.
function NxRpNet(srv as Object) as Object
    return {
        srv: srv, calls: [], answers: {}, fail: false,
        server: function(index as Dynamic) as Dynamic
            return m.srv
        end function,
        send: function(method as String, url as String, headers as Object, body as String) as Object
            line = method + " " + url
            if headers["X-Plex-Session-Identifier"] <> invalid then line = line + " [session " + headers["X-Plex-Session-Identifier"] + "]"
            if body <> "" then line = line + " " + body
            m.calls.Push(line)
            if m.fail then return { code: -28, json: invalid }
            list = m.answers[method + " " + url]
            if list = invalid then return { code: 200, json: invalid }
            a = list[0]
            if list.Count() > 1 then list.Shift()
            return a
        end function,
        sleep: sub(ms as Integer)
            m.calls.Push("sleep " + ms.ToStr())
        end sub
    }
end function

function NxRpSteps(steps as Object) as String
    out = []
    for each s in steps
        out.Push(NxCleanupDescribe(s))
    end for
    return out.Join(" | ")
end function

function NxRpJoin(list as Dynamic) as String
    out = []
    for each x in NxList(list)
        out.Push(NxToStr(x))
    end for
    return out.Join(" | ")
end function

function NxRpCount(calls as Object, part as String) as String
    n = 0
    for each c in calls
        if Instr(1, c, part) > 0 then n = n + 1
    end for
    return n.ToStr()
end function
