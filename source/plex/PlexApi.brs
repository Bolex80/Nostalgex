' Plex sign-in and server discovery: plex.tv's PIN link, as upstream's web
' tuner does it (plex-tuner.html startPlexAuth / discoverServers).
'
' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Security rules for everything in this file:
'   - HTTPS, with certificates verified, to plex.tv. To the Plex server, the
'     server's plain-HTTP home-network address when sign-in found one
'     (NxPlexPickLanVideo), else HTTPS: on networks like the developer's, the
'     public route stalls video and drops library reads, and the secure
'     in-house address doesn't resolve. That address must be private
'     (NxIsPrivateHost); the token then crosses the home network only.
'   - The token lives only in this app's registry section. It is never
'     printed: the debug console (port 8085) is readable by anyone on the
'     network. Print the status, never a URL or header that carries a token.
'   - Sign-out (NxPlexClearAuth) removes everything this file stores.
'
' Network calls block, so these run in a Task node, never the render thread.

' ── Stored state ────────────────────────────────────────────────────────────

function NxPlexRegistry() as Object
    return CreateObject("roRegistrySection", "plex")
end function

' A random identifier per install, which Plex shows in its device list.
function NxPlexClientId() as String
    reg = NxPlexRegistry()
    id = reg.Read("clientId")
    if id = "" then
        id = CreateObject("roDeviceInfo").GetRandomUUID()
        reg.Write("clientId", id)
        reg.Flush()
    end if
    return id
end function

' One playback-session identifier per install and decoding profile, sent
' with every stream. Plex ties a device's streams together by it: a new one
' per stream made it refuse (HTTP 400) to restart a file for minutes after
' stopping it, which broke flipping back to a channel. Plex also fixes its
' transcode decision for a session the first time it sees it, so a change of
' profile (say, HEVC allowed) needs its own identifier.
function NxPlexPlaybackSessionId(profile as String) as String
    reg = NxPlexRegistry()
    key = "playbackSession_" + profile
    id = reg.Read(key)
    if id = "" then
        id = CreateObject("roDeviceInfo").GetRandomUUID()
        reg.Write(key, id)
        reg.Flush()
    end if
    return id
end function

function NxPlexLoadToken() as String
    return NxPlexRegistry().Read("token")
end function

sub NxPlexSaveToken(token as String)
    reg = NxPlexRegistry()
    reg.Write("token", token)
    reg.Flush()
end sub

' Sign out: forget the token, the chosen servers, and the device identifier.
sub NxPlexClearAuth()
    reg = NxPlexRegistry()
    for each key in reg.GetKeyList()
        reg.Delete(key)
    end for
    reg.Flush()
end sub

' ── HTTPS ───────────────────────────────────────────────────────────────────

function NxPlexHeaders(token as String) as Object
    h = {
        "Accept": "application/json",
        "X-Plex-Product": "nostalgex-roku",
        "X-Plex-Version": "0.1",
        "X-Plex-Platform": "Roku",
        "X-Plex-Device": "Roku",
        "X-Plex-Client-Identifier": NxPlexClientId()
    }
    if token <> "" then h["X-Plex-Token"] = token
    return h
end function

' One HTTPS request. Returns { code, json } where code is the HTTP status, or
' a negative curl code (-28 is a timeout), or 0 if the URL was refused.
function NxHttp(method as String, url as String, headers as Object, timeoutMs = 10000 as Integer) as Object
    if LCase(Left(url, 8)) <> "https://" then
        print "nxhttp: refused a non-HTTPS URL"
        return { code: 0, json: invalid }
    end if
    port = CreateObject("roMessagePort")
    xfer = CreateObject("roUrlTransfer")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.EnablePeerVerification(true)
    xfer.EnableHostVerification(true)
    xfer.RetainBodyOnError(true)
    xfer.SetHeaders(headers)
    xfer.SetRequest(method)
    if method = "POST" then
        ok = xfer.AsyncPostFromString("")
    else
        ok = xfer.AsyncGetToString()
    end if
    if not ok then return { code: -1, json: invalid }
    msg = Wait(timeoutMs, port)
    if type(msg) <> "roUrlEvent" then
        xfer.AsyncCancel()
        return { code: -28, json: invalid }
    end if
    code = msg.GetResponseCode()
    if code < 200 or code > 299 then print "nxhttp: "; method; " answered "; code; " "; msg.GetFailureReason()
    body = msg.GetString()
    json = invalid
    if body <> "" then json = ParseJson(body)
    return { code: code, json: json }
end function

' A GET to a Plex server: HTTPS via NxHttp, or plain HTTP only when the host
' is private (the home-network address sign-in found). Anything else is
' refused. Returns { code, json } like NxHttp; code 0 if refused.
function NxPlexServerGet(url as String, token as String, timeoutMs = 15000 as Integer) as Object
    if LCase(Left(url, 8)) = "https://" then return NxHttp("GET", url, NxPlexHeaders(token), timeoutMs)
    if LCase(Left(url, 7)) <> "http://" or not NxIsPrivateHost(NxUrlHost(url)) then
        print "nxhttp: refused plain HTTP to a non-private address"
        return { code: 0, json: invalid }
    end if
    port = CreateObject("roMessagePort")
    xfer = CreateObject("roUrlTransfer")
    xfer.SetMessagePort(port)
    xfer.SetUrl(url)
    xfer.SetHeaders(NxPlexHeaders(token))
    if not xfer.AsyncGetToString() then return { code: -1, json: invalid }
    msg = Wait(timeoutMs, port)
    if type(msg) <> "roUrlEvent" then
        xfer.AsyncCancel()
        return { code: -28, json: invalid }
    end if
    body = msg.GetString()
    json = invalid
    if body <> "" then json = ParseJson(body)
    return { code: msg.GetResponseCode(), json: json }
end function

function NxPlexVideoRequest(url as String, token as String, timeoutMs = 5000 as Integer) as Integer
    return NxPlexServerGet(url, token, timeoutMs).code
end function

function NxUrlHost(url as String) as String
    rest = Mid(url, Instr(1, url, "//") + 2)
    cut = Instr(1, rest, "/")
    if cut > 0 then rest = Left(rest, cut - 1)
    colon = Instr(1, rest, ":")
    if colon > 0 then rest = Left(rest, colon - 1)
    return rest
end function

' ── plex.tv ─────────────────────────────────────────────────────────────────

' A new link PIN: { id, code } or invalid.
function NxPlexCreatePin() as Dynamic
    res = NxHttp("POST", "https://plex.tv/api/v2/pins", NxPlexHeaders(""))
    if res.code < 200 or res.code > 299 or type(res.json) <> "roAssociativeArray" then return invalid
    if res.json.id = invalid or res.json.code = invalid then return invalid
    return { id: res.json.id, code: UCase(res.json.code) }
end function

' The PIN's token once the user has entered the code at plex.tv/link: a
' String, "" while still waiting, or invalid when the PIN has expired.
function NxPlexCheckPin(id as Dynamic) as Dynamic
    res = NxHttp("GET", "https://plex.tv/api/v2/pins/" + NxToStr(id), NxPlexHeaders(""))
    if res.code = 404 then return invalid
    if type(res.json) <> "roAssociativeArray" then return ""
    if NxIsString(res.json.authToken) then return res.json.authToken
    return ""
end function

' The signed-in account's name, "" if the token was rejected, or invalid if
' plex.tv couldn't be reached (so a network blip doesn't sign anyone out).
function NxPlexAccountName(token as String) as Dynamic
    res = NxHttp("GET", "https://plex.tv/api/v2/user", NxPlexHeaders(token))
    if res.code = 401 or res.code = 403 then return ""
    if res.code < 200 or res.code > 299 or type(res.json) <> "roAssociativeArray" then return invalid
    name = res.json.username
    if not NxIsString(name) or name = "" then name = res.json.title
    if not NxIsString(name) then name = "Plex"
    return name
end function

' Servers on the account: [{ name, machineIdentifier, owned, accessToken,
' connections }], or invalid if plex.tv couldn't be reached.
function NxPlexServers(token as String) as Dynamic
    res = NxHttp("GET", "https://plex.tv/api/v2/resources?includeHttps=1&includeRelay=1", NxPlexHeaders(token), 15000)
    if res.code < 200 or res.code > 299 or type(res.json) <> "roArray" then return invalid
    out = []
    for each r in res.json
        if type(r) = "roAssociativeArray" and NxIsString(r.provides) then
            if Instr(1, r.provides, "server") > 0 then
                out.Push({
                    name: NxToStr(r.name),
                    machineIdentifier: NxToStr(r.clientIdentifier),
                    owned: NxTruthy(r.owned),
                    accessToken: NxToStr(r.accessToken),
                    connections: NxList(r.connections)
                })
            end if
        end if
    end for
    return out
end function

' A plain-HTTP address for video on the home network, built from the
' server's local connection (plex.tv lists it as HTTPS; its raw address and
' port are what plain HTTP needs). Only a private address qualifies, and only
' if it answers /identity, which needs no token, so none is sent while
' checking. "" if none.
function NxPlexPickLanVideo(server as Object) as String
    for each c in server.connections
        if type(c) = "roAssociativeArray" and NxTruthy(c.local) and not NxTruthy(c.relay) then
            host = NxToStr(c.address)
            uri = "http://" + host + ":" + NxToStr(c.port)
            if NxIsPrivateHost(host) and NxIsNumber(c.port) then
                xfer = CreateObject("roUrlTransfer")
                port = CreateObject("roMessagePort")
                xfer.SetMessagePort(port)
                xfer.SetUrl(uri + "/identity")
                if xfer.AsyncGetToString() then
                    msg = Wait(3000, port)
                    if type(msg) = "roUrlEvent" then
                        if msg.GetResponseCode() = 200 then return uri
                    else
                        xfer.AsyncCancel()
                    end if
                end if
            end if
        end if
    end for
    return ""
end function

' True for RFC 1918 IPv4 addresses: 10/8, 172.16/12, 192.168/16.
function NxIsPrivateHost(host as String) as Boolean
    parts = host.Split(".")
    if parts.Count() <> 4 then return false
    for each p in parts
        if not CreateObject("roRegex", "^\d{1,3}$", "").IsMatch(p) then return false
    end for
    a = parts[0].ToInt()
    b = parts[1].ToInt()
    if a = 10 then return true
    if a = 192 and b = 168 then return true
    if a = 172 and b >= 16 and b <= 31 then return true
    return false
end function

' The server's first HTTPS connection that answers /identity: direct before
' relay, local before remote, as upstream orders them. Plain-HTTP
' connections are skipped. Returns the base URI, or "" if none answered.
function NxPlexPickConnection(server as Object) as String
    ranked = []
    kinds = ["local", "remote", "relay (local)", "relay"]
    for each rank in [0, 1, 2, 3]
        for each c in server.connections
            if type(c) = "roAssociativeArray" and c.protocol = "https" and NxIsString(c.uri) then
                r = 0
                if NxTruthy(c.relay) then r = r + 2
                if not NxTruthy(c.local) then r = r + 1
                if r = rank then ranked.Push({ uri: c.uri, kind: kinds[r] })
            end if
        end for
    end for
    for each c in ranked
        res = NxHttp("GET", c.uri + "/identity", NxPlexHeaders(server.accessToken), 5000)
        if res.code = 200 then
            print "plex: connected by the "; c.kind; " HTTPS route"
            server.connectionKind = c.kind
            return c.uri
        end if
        print "plex: the "; c.kind; " HTTPS route didn't answer"
    end for
    return ""
end function
