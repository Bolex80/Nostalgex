' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "runAction"
end sub

sub runAction()
    action = m.top.action
    if action = "discover" then
        m.top.found = NxMbDiscover(m.top.kind)
        print "mediabrowser: "; m.top.found.Count(); " servers answered on this network"
        m.top.status = "found"
    else if action = "connect" then
        connect()
    else if action = "quickConnect" then
        quickConnect()
    else if action = "password" then
        password()
    else if action = "check" then
        check()
    end if
end sub

' The first address for what was typed that answers as a Jellyfin or Emby
' server. A server of the other kind is taken as that kind, as the web tuner
' adopts Emby for a server saved as Jellyfin.
sub connect()
    cands = NxMbAddressCandidates(m.top.address)
    if cands.Count() = 0 then
        fail("That isn't a server address. Try something like 10.0.0.20 or http://10.0.0.20:8096.")
        return
    end if
    refused = false
    for each base in cands
        if not NxMbAllowed(base) then
            refused = true
        else
            info = NxMbPublicInfo(base)
            if info <> invalid then
                print "mediabrowser: found a "; info.kind; " server ("; info.version; ")"
                m.top.server = { name: info.name, kind: info.kind, base: base, id: info.id }
                m.top.status = "connected"
                return
            end if
        end if
    end for
    if refused then
        fail("Nostalgex reaches a server over HTTPS, or over plain HTTP only on your home network. Use the server's home-network address, or an https:// one.")
    else
        fail("No " + NxKindName(m.top.kind) + " server answered at that address. Check it, and that the server is running.")
    end if
end sub

' Whether NxServerRequest would try this address at all.
function NxMbAllowed(base as String) as Boolean
    lower = LCase(base)
    if Left(lower, 8) = "https://" then return true
    return Left(lower, 7) = "http://" and NxIsPrivateHost(NxUrlHost(base))
end function

' Jellyfin's Quick Connect: show the code, wait up to 5 minutes for it to be
' approved (every 2 s, as upstream), then sign in with it.
sub quickConnect()
    s = m.top.server
    start = NxMbQuickConnectStart(s.base)
    ' A String ("off") or an object: BrightScript can't compare an object to text.
    if NxIsString(start) then
        fail("Quick Connect is off on this server. Turn it on in Jellyfin (Dashboard, then General), or sign in with your password.")
        return
    end if
    if start = invalid then
        fail("Could not start Quick Connect. Check the server, or sign in with your password.")
        return
    end if
    m.top.code = start.code
    m.top.status = "code"
    for attempt = 1 to 150
        Sleep(2000)
        if m.top.cancel then return
        ok = NxMbQuickConnectApproved(s.base, start.secret)
        if ok = invalid then
            fail("The Quick Connect code expired. Try again.")
            return
        end if
        if ok then
            finish(NxMbQuickConnectFinish(s.base, start.secret))
            return
        end if
    end for
    fail("The Quick Connect code expired. Try again.")
end sub

' At launch, with the saved guide already up: a token the server now refuses
' sends the TV back to sign in, as a rejected Plex token does.
sub check()
    servers = ParseJson(NxPlexRegistry().Read("servers"))
    if type(servers) <> "roArray" or servers.Count() = 0 then return
    result = NxMbCheckSignIn(servers[0])
    print "mediabrowser: saved sign-in check: "; result
    if result = "rejected" then
        m.top.message = "The " + NxKindName(NxServerKind(servers[0])) + " server no longer accepts this TV's sign-in. Sign in again."
        m.top.status = "rejected"
    end if
end sub

sub password()
    finish(NxMbSignIn(m.top.server.base, m.top.username, m.top.password))
    m.top.password = ""
end sub

sub finish(auth as Dynamic)
    ' Backed out while the server answered: saving now would sign this TV in
    ' to a server the viewer has left, maybe under a Plex sign-in begun since.
    if m.top.cancel then
        print "mediabrowser: sign-in answered after Back; not saved"
        return
    end if
    if auth = invalid then
        fail("Couldn't reach the server to sign in. Try again.")
        return
    end if
    if type(auth) <> "roAssociativeArray" then
        fail("The server didn't accept that username and password.")
        return
    end if
    s = m.top.server
    NxMbSaveSignIn(s.kind, s.base, { name: s.name, id: NxToStr(s.id) }, auth)
    print "mediabrowser: signed in to "; s.kind
    m.top.status = "signedIn"
end sub

sub fail(message as String)
    m.top.message = message
    m.top.status = "error"
    print "mediabrowser: "; message
end sub

' Saves a Jellyfin or Emby sign-in as this TV's only server and clears caches
' another account or server left (NxClaimAccountCaches), as a fresh Plex
' sign-in does.
sub NxMbSaveSignIn(kind as String, base as String, info as Object, auth as Object)
    serverId = auth.serverId
    if serverId = "" then serverId = info.id
    if serverId = "" then serverId = base
    server = {
        kind: kind, name: info.name, machineIdentifier: serverId, uri: base,
        userId: auth.userId, accessToken: auth.token, owned: true, checked: true
    }
    reg = NxPlexRegistry()
    reg.Delete("token")
    reg.Delete("needsPick")
    reg.Delete("serverChoices")
    reg.Write("kind", kind)
    reg.Write("servers", FormatJson([server]))
    reg.Flush()
    if NxClaimAccountCaches(kind + ":" + serverId + ":" + auth.userId, true) then print "mediabrowser: cleared the saved library left by another account, or by none recorded"
end sub
