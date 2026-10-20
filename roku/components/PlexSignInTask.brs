' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "runSignIn"
end sub

sub runSignIn()
    print "plex: sign-in task started"
    token = NxPlexLoadToken()
    ' No saved sign-in: a first run, or the app deleted and installed again.
    fresh = token = ""
    account = invalid
    if token <> "" then
        m.top.status = "checking"
        account = NxPlexAccount(token)
        if account = invalid then
            fail("Can't reach plex.tv. Check the TV's internet connection, then press OK to try again.")
            return
        end if
        if type(account) <> "roAssociativeArray" then
            ' plex.tv rejected the saved token (revoked or expired): start over.
            NxPlexClearAuth()
            token = ""
            fresh = true
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
    if type(account) <> "roAssociativeArray" then account = NxPlexAccount(token)
    ' Caches the deleted app left behind may be another account's library.
    if type(account) = "roAssociativeArray" and account.id <> "" then
        m.top.account = account.name
        if NxClaimAccountCaches(account.id, fresh) then print "plex: cleared the saved library left by another account, or by none recorded"
    else if fresh then
        NxClearAccountCaches()
        print "plex: cleared the saved library: couldn't tell whose it is"
    end if

    ' A TV that already has its servers keeps them: their addresses were
    ' checked when they were first used, and the Apple TV app doesn't probe
    ' again on later launches either.
    if NxPlexRegistry().Read("servers") <> "" then
        m.top.message = "Signed in as " + m.top.account + "."
        m.top.status = "ready"
        print "plex: signed in; using the saved servers"
        return
    end if

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

    ' Every server on the account, owned first, as upstream lists them. No
    ' address is checked here: only the servers picked go on to be checked,
    ' all at once (source/plex/ServerResolve.brs). The list goes in the
    ' registry, not on a node field, since it holds access tokens.
    found = []
    for each owned in [true, false]
        for each s in servers
            if s.owned = owned then found.Push({ name: s.name, machineIdentifier: s.machineIdentifier, owned: s.owned, accessToken: s.accessToken, uri: "", lanUri: "", checked: false })
        end for
    end for
    reg = NxPlexRegistry()
    reg.Write("servers", FormatJson(found))
    ' More than one: the viewer picks which first (MainScene, ServerPickerView).
    ' Kept until they do, so quitting at the picker brings it back.
    if found.Count() > 1 then reg.Write("needsPick", "1")
    reg.Flush()

    m.top.message = "Signed in as " + m.top.account + "."
    m.top.status = "ready"
    print "plex: signed in; servers on the account: "; found.Count()
end sub

sub fail(message as String)
    m.top.message = message
    m.top.status = "error"
    print "plex: "; message
end sub
