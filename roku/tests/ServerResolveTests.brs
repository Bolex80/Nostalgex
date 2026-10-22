' Runs source/plex/ServerResolve.brs's rules: upstream's address order
' (PlexAPIService.bestReachableURI: local, remote, relay; lowest reachable
' wins), the home-network grace period, the identity check, and which hosts
' count as home (NxRunHomeHostTests). Returns the failure count.

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
    return r.fail + NxRunHomeHostTests()
end function

' source/plex/PlexApi.brs's NxIsPrivateHost, the one rule for where plain
' HTTP may go (the home-network route above among them), and
' NxServerUrlAllowed, which NxServerTransfer asks, refusing the rest.
' Returns the failure count.

function NxRunHomeHostTests() as Integer
    r = { pass: 0, fail: 0 }
    home = [
        "10.0.0.20", "172.16.0.1", "172.31.255.255", "192.168.1.20",
        "100.64.0.1", "100.101.102.103", "100.127.255.255",
        "nas.local", "NAS.Local", "nas.local.", "media.lan", "server.home.arpa",
        "nas.tail1234.ts.net", "nas", "jellyfin-box", "4kserver"
    ]
    for each h in home
        NxCheck(r, "home " + h, NxBoolStr(NxIsPrivateHost(h)), "true")
    end for
    away = [
        "8.8.8.8", "172.15.0.1", "172.32.0.1", "100.63.255.255", "100.128.0.1", "192.169.0.1",
        "010.0.0.1", "10.0.0", "10.0.0.1.2", "134744072", "0x8080808", "3232235777",
        "example.com", "plex.direct", "evil.com.local.example", "x.ts.net.evil.com",
        "nas.local@evil.com", "evil.com@nas", "-nas", "nas-", "", ".", "my_nas.lan"
    ]
    for each h in away
        NxCheck(r, "away " + h, NxBoolStr(NxIsPrivateHost(h)), "false")
    end for

    ' The host as the callers take it from a URL, then the rule on a whole URL.
    NxCheck(r, "url host", NxUrlHost("http://nas.local:8096/jellyfin"), "nas.local")
    NxCheck(r, "allowed: plain http, private", NxBoolStr(NxServerUrlAllowed("http://192.168.1.20:32400/identity")), "true")
    NxCheck(r, "allowed: not http at all", NxBoolStr(not NxServerUrlAllowed("ftp://nas.local/")), "true")
    NxCheck(r, "url host after user info", NxUrlHost("http://10.0.0.1:80@example.com/"), "example.com")
    NxCheck(r, "url host before a query", NxUrlHost("http://nas?x=@example.com"), "nas")
    NxCheck(r, "allowed: refuses user info to a public host", NxBoolStr(not NxServerUrlAllowed("http://10.0.0.1:80@example.com/")), "true")
    NxCheck(r, "allowed: to a home name", NxBoolStr(NxServerUrlAllowed("http://nas.local:8096/System/Info/Public")), "true")
    NxCheck(r, "allowed: to tailscale", NxBoolStr(NxServerUrlAllowed("http://100.101.102.103:8096/System/Info/Public")), "true")
    NxCheck(r, "allowed: refuses public http", NxBoolStr(not NxServerUrlAllowed("http://example.com:8096/System/Info/Public")), "true")
    NxCheck(r, "allowed: refuses userinfo trick", NxBoolStr(not NxServerUrlAllowed("http://nas.local@example.com/")), "true")
    NxCheck(r, "allowed: takes public https", NxBoolStr(NxServerUrlAllowed("https://example.com/")), "true")
    print "home host cases:"; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

function NxBoolStr(b as Boolean) as String
    if b then return "true"
    return "false"
end function
