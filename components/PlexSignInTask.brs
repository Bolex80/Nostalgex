' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "runSignIn"
end sub

sub runSignIn()
    print "plex: sign-in task started"
    token = NxPlexLoadToken()
    account = invalid
    if token <> "" then
        m.top.status = "checking"
        account = NxPlexAccountName(token)
        if account = invalid then
            fail("Can't reach plex.tv. Check the TV's internet connection, then press OK to try again.")
            return
        end if
        if account = "" then
            ' plex.tv rejected the saved token (revoked or expired): start over.
            NxPlexClearAuth()
            token = ""
        end if
    end if

    while token = ""
        print "plex: requesting a link code"
        pin = NxPlexCreatePin()
        if pin = invalid then
            fail("Can't reach plex.tv. Check the TV's internet connection, then press OK to try again.")
            return
        end if
        m.top.code = pin.code
        m.top.status = "code"
        ' Poll every 2 s for 5 minutes, as upstream does, then show a fresh code.
        for attempt = 1 to 150
            Sleep(2000)
            got = NxPlexCheckPin(pin.id)
            if got = invalid then exit for
            if got <> "" then
                token = got
                exit for
            end if
        end for
    end while
    NxPlexSaveToken(token)
    if account = invalid or account = "" then account = NxPlexAccountName(token)
    if NxIsString(account) then m.top.account = account

    m.top.status = "discovering"
    servers = NxPlexServers(token)
    if servers = invalid then
        fail("Signed in, but can't list your Plex servers. Press OK to try again.")
        return
    end if
    if servers.Count() = 0 then
        fail("This Plex account has no servers. Press OK to try again.")
        return
    end if

    ' Keep each reachable server's HTTPS address and access token, for the
    ' library loader. They go in the registry, not on a node field.
    found = []
    names = []
    unreachable = []
    for each s in servers
        uri = NxPlexPickConnection(s)
        if uri <> "" then
            lanUri = NxPlexPickLanVideo(s)
            if lanUri <> "" then print "plex: video will use the home-network address"
            found.Push({ name: s.name, machineIdentifier: s.machineIdentifier, owned: s.owned, uri: uri, lanUri: lanUri, accessToken: s.accessToken })
            names.Push(s.name)
        else
            unreachable.Push(s.name)
        end if
    end for
    if found.Count() = 0 then
        fail("Found " + servers.Count().ToStr() + " Plex server(s), but none answered over a secure (HTTPS) connection. In Plex, set Settings > Network > Secure connections to Preferred. Press OK to try again.")
        return
    end if
    reg = NxPlexRegistry()
    reg.Write("servers", FormatJson(found))
    reg.Flush()

    msg = "Connected to " + names.Join(", ") + " over HTTPS."
    if unreachable.Count() > 0 then msg = msg + " Not reachable securely: " + unreachable.Join(", ") + "."
    m.top.message = msg
    m.top.status = "ready"
    print "plex: signed in; servers reachable over HTTPS: "; found.Count(); ", unreachable: "; unreachable.Count()
end sub

sub fail(message as String)
    m.top.message = message
    m.top.status = "error"
    print "plex: "; message
end sub
