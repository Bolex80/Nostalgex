' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "runSignIn"
end sub

sub runSignIn()
    print "plex: sign-in task started"
    token = NxPlexLoadToken()
    ' No saved sign-in: a first run, or the app deleted and installed again.
    fresh = token = ""
    rejected = false
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
            rejected = true
        end if
    end if

    if token = "" then
        print "plex: requesting a link code"
        out = {}
        pin = NxPlexCreatePin(out)
        if pin = invalid then
            if rejected then
                ' At launch, after plex.tv refused the saved sign-in: MainScene's
                ' own screen, where OK tries again; CONNECT TO PLEX isn't there.
                fail("Can't reach plex.tv. Check the TV's internet connection, then press OK to try again.")
            else
                ' On the first screen (MainScene), where CONNECT TO PLEX is.
                fail(NxSignInPlexMessage(NxNumberOr0(out.code)))
            end if
            return
        end if
        m.top.code = pin.code
        m.top.status = "code"
        ' Poll every 2 s, as upstream does. After 150 polls (5 minutes), or
        ' when plex.tv says the PIN is gone, the code has expired: back to
        ' the first screen, where CONNECT TO PLEX makes a new one.
        attempt = 0
        while token = ""
            Sleep(2000)
            attempt = attempt + 1
            got = ""
            if attempt <= 150 then got = NxPlexCheckPin(pin.id)
            ' Two checks: got may be invalid, which can't be compared to text.
            if got = invalid then
                fail(NxSignInCopy().plexCodeExpired)
                return
            end if
            if NxSignInQuickConnectStep(attempt, got <> "") = "expired" then
                fail(NxSignInCopy().plexCodeExpired)
                return
            end if
            token = got
        end while
    end if
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
        fail(NxSignInCopy().plexCantList)
        return
    end if
    if servers.Count() = 0 then
        fail(NxSignInCopy().plexNoServers)
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
