' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' The decisions behind the connect screens (components/ConnectView.brs), after
' upstream's Views/SignInFlow.swift from the Apple TV sign-in redesign: what
' the network search leads to, which way in a server gets first, what an
' address says about itself before anyone types, where focus starts, and the
' screens' words. Pure where it can be, so tests/SignInFlowTests.brs holds it
' to SignInFlowTests.swift's cases.
'
' Sign-in itself is unchanged: NxMbSignIn and the Quick Connect calls in
' MediaBrowserApi.brs, given the address this check found.

' ── Discovery ───────────────────────────────────────────────────────────────
' One reply is read by NxMbDiscoveryReply (MediaBrowserApi.brs).

' The first server heard for each Id, in arrival order: one server answering
' on two interfaces, or to both probes, is still one server.
function NxSignInDedupe(servers as Object) as Object
    seen = {}
    seen.SetModeCaseSensitive()
    out = []
    for each s in servers
        if not seen.DoesExist(s.id) then
            seen[s.id] = true
            out.Push(s)
        end if
    end for
    return out
end function

' { kind, servers }: kind "none" (offer the typed address), "single" (go
' straight to it, no pick) or "several" (list them). SignInFlow.outcome.
function NxSignInOutcome(servers as Object) as Object
    unique = NxSignInDedupe(servers)
    kind = "several"
    if unique.Count() = 0 then
        kind = "none"
    else if unique.Count() = 1 then
        kind = "single"
    end if
    return { kind: kind, servers: unique }
end function

' A fixed answer for the sign-in tour (tests/signin), as upstream's
' -uiTestDiscovery: "none" or "several", so the screens one test network
' never produces can still be looked at. invalid otherwise: search for real.
function NxSignInDiscoveryFixture(fixture as String) as Dynamic
    if fixture = "none" then return []
    if fixture = "several" then
        return [
            { name: "Living Room", address: "http://192.0.2.10:8096", id: "fixture-1" },
            { name: "Basement NAS", address: "http://192.0.2.11:8096", id: "fixture-2" }
        ]
    end if
    return invalid
end function

' ── Which way in ────────────────────────────────────────────────────────────

function NxSignInIsBool(v as Dynamic) as Boolean
    return type(v) = "Boolean" or type(v) = "roBoolean"
end function

' Quick Connect first on a Jellyfin server that says it is switched on: no
' typing, the viewer approves a code on their phone. Emby has none.
' quickConnect is true, false, or invalid when the server wouldn't say.
function NxSignInPreferredMethod(kind as String, quickConnect as Dynamic) as String
    if kind = "jellyfin" and NxSignInIsBool(quickConnect) then
        if quickConnect then return "quickConnect"
    end if
    return "password"
end function

' Whether the password screen offers Quick Connect as the other way in.
' Hidden only when the server said it is off, so an older server that can't
' say still gets it (and starting it explains itself if it fails).
function NxSignInOffersQuickConnect(kind as String, quickConnect as Dynamic) as Boolean
    if kind <> "jellyfin" then return false
    if NxSignInIsBool(quickConnect) then return quickConnect
    return true
end function

' ── What the server says about itself ───────────────────────────────────────

' /System/Info/Public as { id, name, kind }, or invalid. Jellyfin names itself
' in ProductName; Emby 4.x leaves it out. A page without an Id (a router, a
' web UI) is not a server.
function NxSignInPublicInfo(j as Dynamic) as Dynamic
    if type(j) <> "roAssociativeArray" or not NxIsString(j.Id) then return invalid
    id = j.Id.Trim()
    if id = "" then return invalid
    kind = "emby"
    if NxIsString(j.ProductName) then
        if Instr(1, LCase(j.ProductName), "jellyfin") > 0 then kind = "jellyfin"
    end if
    name = ""
    if NxIsString(j.ServerName) then name = j.ServerName.Trim()
    if name = "" then name = NxKindName(kind)
    return { id: id, name: name, kind: kind }
end function

' /QuickConnect/Enabled answers a bare JSON true or false. Anything else (404
' on servers that predate it, a web page) is "can't say": invalid.
function NxSignInQuickConnectEnabled(code as Integer, text as String) as Dynamic
    if code < 200 or code > 299 then return invalid
    t = LCase(text.Trim())
    if t = "true" then return true
    if t = "false" then return false
    return invalid
end function

' /Users/Public: the users a server shows on its own login screen, as
' [{ id, name, hasPassword }]. Picking one saves typing the name on a TV
' keyboard; one with no password signs in on the spot.
function NxSignInPublicUsers(j as Dynamic) as Object
    out = []
    if type(j) <> "roArray" then return out
    for each e in j
        if type(e) = "roAssociativeArray" and NxIsString(e.Id) and NxIsString(e.Name) then
            name = e.Name.Trim()
            if e.Id <> "" and name <> "" then
                hasPassword = true
                if NxSignInIsBool(e.HasPassword) then hasPassword = e.HasPassword
                out.Push({ id: e.Id, name: name, hasPassword: hasPassword })
            end if
        end if
    end for
    return out
end function

' Asks an address who it is before anyone types (SignInFlow.check): a wrong
' address fails on the address screen, a Jellyfin server opens on Quick
' Connect, an Emby server shows its users. A bare address tries :8096 first,
' as sign-in does (NxMbAddressCandidates).
'
' send.fetch(url) does one GET with Accept: application/json and returns
' { code, text }: code 0 when NxServerTransfer refuses the URL, a negative
' curl code when nothing answered. NxSignInLiveSend is the real one; the
' tests pass a fake.
'
' Returns { server, reason, code }: server { kind, url, name, id,
' quickConnect, users } on success, else invalid with reason "notAServer",
' "refused" or "unreachable" (and the curl code) for NxSignInCheckMessage.
function NxSignInCheck(address as String, send as Object) as Object
    cands = NxMbAddressCandidates(address)
    if cands.Count() = 0 then return { server: invalid, reason: "notAServer", code: 0 }
    info = invalid
    base = ""
    refused = 0
    for i = 0 to cands.Count() - 1
        last = i = cands.Count() - 1
        res = send.fetch(cands[i] + "/System/Info/Public")
        if res.code = 0 then
            refused = refused + 1
        else
            if res.code >= 200 and res.code <= 299 then info = NxSignInPublicInfo(NxParseJsonBody(res.text))
            if info <> invalid then
                base = cands[i]
                exit for
            end if
            if res.code > 0 then
                ' Something answered, but not as a server: the next address,
                ' or on the last, not a server.
                if last then return { server: invalid, reason: "notAServer", code: res.code }
            else if res.code <> -7 or last then
                ' -7 is curl's "couldn't connect": nothing on this port, so
                ' the next address. Anything else is the network's answer.
                return { server: invalid, reason: "unreachable", code: res.code }
            end if
        end if
    end for
    if info = invalid then
        if refused > 0 then return { server: invalid, reason: "refused", code: 0 }
        return { server: invalid, reason: "notAServer", code: 0 }
    end if

    quickConnect = invalid
    if info.kind = "jellyfin" then
        res = send.fetch(base + "/QuickConnect/Enabled")
        quickConnect = NxSignInQuickConnectEnabled(res.code, res.text)
    end if
    users = []
    res = send.fetch(base + "/Users/Public")
    if res.code >= 200 and res.code <= 299 then users = NxSignInPublicUsers(NxParseJsonBody(res.text))
    server = { kind: info.kind, url: base, name: info.name, id: info.id, users: users }
    ' A node field drops an invalid value, so "can't say" is simply absent.
    if quickConnect <> invalid then server.quickConnect = quickConnect
    return { server: server, reason: "", code: 0 }
end function

' What the viewer reads when the check fails. The unreachable lines are
' upstream's AppState.serverUnreachableMessage, by curl code in place of
' URLError, with the Roku named where it names the Apple TV.
function NxSignInCheckMessage(reason as String, code as Integer, kind as String) as String
    name = NxKindName(kind)
    if reason = "notAServer" then return NxSignInCopy().notAServer
    if reason = "refused" then return "Nostalgex reaches a server over HTTPS, or over plain HTTP only on your home network. Use the server's home-network address, or an https:// one."
    if code = -6 then return "Could not find that host. Check the address."
    if code = -7 then return "Nothing answered at that address and port. Check the port (Jellyfin and Emby default to 8096)."
    if code = -28 then return "The " + name + " server took too long to answer. Check the address, or that the Roku can reach it."
    if code = -35 or code = -51 or code = -53 or code = -58 or code = -59 or code = -60 or code = -77 or code = -83 then
        return "The server's HTTPS certificate is not trusted by the Roku (error " + code.ToStr() + ")."
    end if
    return "Could not reach the " + name + " server (error " + code.ToStr() + "). Check the URL."
end function

' The real send: GETs through NxServerTransfer (HTTPS, or plain HTTP to a
' private address only), 8 s each, as upstream's check session.
function NxSignInLiveSend() as Object
    return { fetch: NxSignInLiveFetch }
end function

function NxSignInLiveFetch(url as String) as Object
    xfer = NxServerTransfer(url, { "Accept": "application/json" })
    if xfer = invalid then return { code: 0, text: "" }
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if not xfer.AsyncGetToString() then return { code: -1, text: "" }
    msg = Wait(8000, port)
    if type(msg) <> "roUrlEvent" then
        xfer.AsyncCancel()
        return { code: -28, text: "" }
    end if
    return { code: msg.GetResponseCode(), text: msg.GetString() }
end function

' ── Quick Connect ───────────────────────────────────────────────────────────

' Polling as upstream's startJellyfinQuickConnect: every 2 s, up to 150 polls
' (5 minutes). A poll that fails is not an answer, so it waits on; past the
' last poll the code has expired. attempt counts from 1; res is
' NxMbQuickConnectApproved's true, false or invalid.
function NxSignInQuickConnectStep(attempt as Integer, approved as Dynamic) as String
    if attempt > 150 then return "expired"
    if NxSignInIsBool(approved) then
        if approved then return "approved"
    end if
    return "waiting"
end function

' ── Focus ───────────────────────────────────────────────────────────────────

' The control a screen starts on (upstream's defaultFocusID), so the remote
' always starts somewhere visible. s: { screen, auth, discovery, picked,
' users, typingName }: screen "picker", "find", "type" or "signin"; auth ""
' or "checking", "quick", "signing", "plex"; discovery "idle", "searching",
' "several" or "none"; picked true when a user tile was picked; users the
' server's public user count.
function NxSignInDefaultFocus(s as Object) as String
    if s.auth = "quick" then return "usePassword"
    if s.auth = "checking" or s.auth = "signing" or s.auth = "plex" then return "cancel"
    if s.screen = "find" then
        if s.discovery = "several" then return "found-0"
        if s.discovery = "none" then return "type"
        return "find"
    end if
    if s.screen = "type" then return "address"
    if s.screen = "signin" then
        if s.picked then return "password"
        if s.users > 0 and not s.typingName then return "user-0"
        return "username"
    end if
    return "plex"
end function

' ── Copy ────────────────────────────────────────────────────────────────────

' Every fixed line these screens put up, upstream's SignInFlow.Copy and
' LANServerDiscovery.Copy, with the Roku named where they name the Apple TV.
' tests/SignInFlowTests.brs checks them for em dashes.
function NxSignInCopy() as Object
    return {
        screenTitle: "CONNECT YOUR SERVER",
        screenBody: "Nostalgex builds a retro channel guide from your own library. Connect Plex, Jellyfin, or Emby to get started.",
        connectPlex: "CONNECT TO PLEX",
        orConnectWith: "OR CONNECT WITH",
        findButton: "FIND MY SERVER",
        searching: "SEARCHING...",
        searchAgain: "SEARCH AGAIN",
        noneFound: "No server answered. Check the Roku and the server are on the same network, or type its address.",
        typeAddress: "TYPE AN ADDRESS",
        pickServer: "PICK YOUR SERVER",
        addressTitle: "SERVER ADDRESS",
        addressHint: "The address and port, like 192.168.1.10:8096",
        addressPlaceholder: "192.168.1.10:8096",
        connect: "CONNECT",
        pressToType: "Press to type",
        signInTo: "SIGN IN TO",
        whoIsWatching: "WHO'S WATCHING?",
        someoneElse: "SOMEONE ELSE",
        username: "USERNAME",
        password: "PASSWORD",
        signIn: "SIGN IN",
        useQuickConnect: "USE QUICK CONNECT",
        usePassword: "SIGN IN WITH A PASSWORD",
        back: "BACK",
        cancel: "CANCEL",
        quickConnectTitle: "APPROVE THIS TV IN JELLYFIN",
        quickConnectSteps: "On your phone or computer, open Jellyfin, then your profile, then Quick Connect, and enter this code.",
        waitingForApproval: "WAITING FOR APPROVAL",
        signingIn: "SIGNING IN",
        notAServer: "That address answered, but it isn't a Jellyfin or Emby server. Check the port (both use 8096 unless you changed it).",
        codeExpired: "Code expired. Tap Connect to try again.",
        quickConnectOff: "Quick Connect is off on this server. Turn it on in Jellyfin (Dashboard, then General), or sign in with your password.",
        quickConnectFailed: "Could not start Quick Connect. Check the server address, or sign in with your password.",
        quickConnectNotJellyfin: "That address answered, but it isn't Jellyfin. Check the address and port (Jellyfin uses 8096).",
        incorrectPassword: "Incorrect username or password.",
        plexGoTo: "GO TO plex.tv/link AND ENTER:",
        plexScan: "SCAN TO CONNECT",
        plexConnecting: "CONNECTING TO PLEX.TV",
        plexWaiting: "WAITING FOR AUTHORIZATION",
        plexFinding: "FINDING YOUR SERVERS"
    }
end function

function NxSignInConnectTitle(kind as String) as String
    return "CONNECT TO " + UCase(NxKindName(kind))
end function

function NxSignInFindIntro(kind as String) as String
    return "Nostalgex can look for your " + NxKindName(kind) + " server on this network. Or type its address."
end function

function NxSignInConnecting(label as String) as String
    return "CONNECTING TO " + UCase(label)
end function

function NxSignInSwitchedKind(kind as String) as String
    name = NxKindName(kind)
    return "That address is a " + name + " server, so this is a " + name + " sign-in."
end function
