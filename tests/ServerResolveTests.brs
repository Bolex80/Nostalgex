' Runs source/plex/ServerResolve.brs's rules: upstream's address order
' (PlexAPIService.bestReachableURI: local, remote, relay; lowest reachable
' wins), the home-network grace period, and the identity check. Returns the
' failure count.

function NxRunServerResolveTests() as Integer
    r = { pass: 0, fail: 0 }
    conns = [
        { protocol: "https", uri: "https://relay.plex.direct:8443", local: false, relay: true },
        { protocol: "https", uri: "https://remote.plex.direct:32400", local: false, relay: false },
        { protocol: "https", uri: "https://local.plex.direct:32400", local: true, relay: false, address: "10.0.0.20", port: 32400 },
        { protocol: "http", uri: "http://10.0.0.20:32400", local: true, relay: false, address: "10.0.0.20", port: 32400 },
        { protocol: "https", uri: "https://public.plex.direct:32400", local: true, relay: false, address: "8.8.8.8", port: 32400 }
    ]
    c = NxResolveCandidates(conns)
    order = []
    for each x in c
        order.Push(x.use + ":" + x.kind)
    end for
    NxCheck(r, "order", order.Join(","), "uri:local,uri:local,uri:remote,uri:relay,lan:home network")
    NxCheck(r, "lan url", c[4].url, "http://10.0.0.20:32400")

    ' Nothing back yet: waiting.
    NxCheck(r, "waiting", NxBoolStr(NxResolveOutcome(c, 100, 3000, false).settled), "false")

    ' Remote answers, local still waiting inside the grace period: keep waiting.
    c[2].status = "ok"
    NxCheck(r, "remote early waits", NxBoolStr(NxResolveOutcome(c, 1000, 3000, false).settled), "false")
    ' After the grace period the local addresses count as failed.
    o = NxResolveOutcome(c, 3000, 3000, false)
    NxCheck(r, "grace settles", NxBoolStr(o.settled), "true")
    NxCheck(r, "grace uri", o.uri, "https://remote.plex.direct:32400")
    NxCheck(r, "grace kind", o.kind, "remote")
    NxCheck(r, "grace no lan", o.lanUri, "")

    ' Local answers: best wins at once, with the home-network address.
    c = NxResolveCandidates(conns)
    c[0].status = "ok"
    c[4].status = "ok"
    o = NxResolveOutcome(c, 200, 3000, false)
    NxCheck(r, "local settles", NxBoolStr(o.settled), "true")
    NxCheck(r, "local uri", o.uri, "https://local.plex.direct:32400")
    NxCheck(r, "local lan", o.lanUri, "http://10.0.0.20:32400")

    ' Relay waits on remote until the deadline.
    c = NxResolveCandidates(conns)
    c[0].status = "fail"
    c[1].status = "fail"
    c[3].status = "ok"
    NxCheck(r, "relay waits on remote", NxBoolStr(NxResolveOutcome(c, 5000, 3000, false).settled), "false")
    o = NxResolveOutcome(c, 10000, 3000, true)
    NxCheck(r, "deadline relay", o.uri, "https://relay.plex.direct:8443")

    ' Nothing answers.
    c = NxResolveCandidates(conns)
    o = NxResolveOutcome(c, 10000, 3000, true)
    NxCheck(r, "none settles", NxBoolStr(o.settled), "true")
    NxCheck(r, "none uri", o.uri, "")

    ' Two remote addresses: one answering settles it while the other waits.
    two = [
        { protocol: "https", uri: "https://remote-a.plex.direct:32400", local: false, relay: false },
        { protocol: "https", uri: "https://remote-b.plex.direct:32400", local: false, relay: false }
    ]
    c = NxResolveCandidates(two)
    c[1].status = "ok"
    o = NxResolveOutcome(c, 400, 3000, false)
    NxCheck(r, "sibling settles", NxBoolStr(o.settled), "true")
    NxCheck(r, "sibling uri", o.uri, "https://remote-b.plex.direct:32400")

    NxCheck(r, "no connections", NxResolveCandidates([]).Count().ToStr(), "0")

    NxCheck(r, "identity match", NxBoolStr(NxIdentityMatches({ MediaContainer: { machineIdentifier: "abc" } }, "abc")), "true")
    NxCheck(r, "identity other server", NxBoolStr(NxIdentityMatches({ MediaContainer: { machineIdentifier: "xyz" } }, "abc")), "false")
    NxCheck(r, "identity no body", NxBoolStr(NxIdentityMatches(invalid, "abc")), "false")
    NxCheck(r, "identity no id", NxBoolStr(NxIdentityMatches({ MediaContainer: {} }, "")), "false")

    print "server resolve cases (upstream bestReachableURI order): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

function NxBoolStr(b as Boolean) as String
    if b then return "true"
    return "false"
end function
