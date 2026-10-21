' Plex sign-in and server discovery: plex.tv's PIN link, as upstream's web
' tuner does it (plex-tuner.html startPlexAuth / discoverServers).
'
' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Security rules for everything in this file:
'   - HTTPS, with certificates verified, to plex.tv. To the Plex server, the
'     server's plain-HTTP home-network address when one answered as that
'     server (source/plex/ServerResolve.brs), else HTTPS: on networks like
'     the developer's, the public route stalls video and drops library
'     reads, and the secure in-house address doesn't resolve. That address
'     must be private (NxIsPrivateHost); the token then crosses the home
'     network only.
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
    ' A dry run of the sign-in (MediaBrowserSignInTask) sets one for its own
    ' thread, so it neither saves an id nor shares the app's.
    dry = GetGlobalAA().nxDryRunClientId
    if NxIsString(dry) then
        if dry <> "" then return dry
    end if
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
    return NxServerRequest("GET", url, NxPlexHeaders(token), "", timeoutMs)
end function

' Several GETs to one Plex server, up to `width` in flight at once, under the
' same rules as NxPlexServerGet. Returns { code, json } per URL, in order.
function NxPlexServerGetMany(urls as Object, token as String, width as Integer, timeoutMs = 15000 as Integer) as Object
    return NxServerGetMany(urls, NxPlexHeaders(token), width, timeoutMs)
end function

' One request to a media server (Plex, Jellyfin or Emby): HTTPS with
' verification, or plain HTTP only when the host is private. Anything else is
' refused. A POST sends `body`. Returns { code, json } like NxHttp; code 0 if
' refused.
function NxServerRequest(method as String, url as String, headers as Object, body = "" as String, timeoutMs = 15000 as Integer) as Object
    xfer = NxServerTransfer(url, headers)
    if xfer = invalid then return { code: 0, json: invalid }
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    xfer.SetRequest(method)
    if method = "GET" then
        ok = xfer.AsyncGetToString()
    else
        ok = xfer.AsyncPostFromString(body)
    end if
    if not ok then return { code: -1, json: invalid }
    msg = Wait(timeoutMs, port)
    if type(msg) <> "roUrlEvent" then
        xfer.AsyncCancel()
        return { code: -28, json: invalid }
    end if
    return { code: msg.GetResponseCode(), json: NxParseJsonBody(msg.GetString()) }
end function

' Several GETs to one server, up to `width` in flight at once, under the
' same rules as NxServerRequest. Returns { code, json } per URL, in order.
function NxServerGetMany(urls as Object, headers as Object, width as Integer, timeoutMs = 15000 as Integer) as Object
    out = []
    for i = 1 to urls.Count()
        out.Push({ code: -1, json: invalid })
    end for
    port = CreateObject("roMessagePort")
    live = {}
    nextIdx = 0
    pending = 0
    while nextIdx < urls.Count() or pending > 0
        while pending < width and nextIdx < urls.Count()
            xfer = NxServerTransfer(urls[nextIdx], headers)
            if xfer = invalid then
                out[nextIdx] = { code: 0, json: invalid }
            else
                xfer.SetMessagePort(port)
                if xfer.AsyncGetToString() then
                    live[xfer.GetIdentity().ToStr()] = { xfer: xfer, index: nextIdx }
                    pending = pending + 1
                end if
            end if
            nextIdx = nextIdx + 1
        end while
        if pending = 0 then exit while
        msg = Wait(timeoutMs, port)
        if type(msg) = "roUrlEvent" then
            id = msg.GetSourceIdentity().ToStr()
            job = live[id]
            if job <> invalid then
                live.Delete(id)
                pending = pending - 1
                out[job.index] = { code: msg.GetResponseCode(), json: NxParseJsonBody(msg.GetString()) }
            end if
        else if msg = invalid then
            ' Nothing answered in time: what's still out timed out.
            for each id in live
                live[id].xfer.AsyncCancel()
                out[live[id].index] = { code: -28, json: invalid }
            end for
            live.Clear()
            pending = 0
        end if
    end while
    return out
end function

' A response body as JSON, or invalid. Only a body that starts as JSON is
' parsed: an error page or plain text ("Access token is invalid or expired.")
' would put a ParseJSON error in the log.
function NxParseJsonBody(text as String) as Dynamic
    t = text.Trim()
    if t = "" then return invalid
    first = Left(t, 1)
    if first <> "{" and first <> "[" then return invalid
    return ParseJson(t)
end function

' A transfer for one server request, or invalid when the URL is refused:
' HTTPS with verification, or plain HTTP to a private address only.
function NxServerTransfer(url as String, headers as Object) as Dynamic
    xfer = CreateObject("roUrlTransfer")
    if LCase(Left(url, 8)) = "https://" then
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.EnablePeerVerification(true)
        xfer.EnableHostVerification(true)
    else if LCase(Left(url, 7)) <> "http://" or not NxIsPrivateHost(NxUrlHost(url)) then
        print "nxhttp: refused plain HTTP to a non-private address"
        return invalid
    end if
    xfer.RetainBodyOnError(true)
    xfer.SetUrl(url)
    xfer.SetHeaders(headers)
    return xfer
end function

' A transfer for one Plex GET, or invalid when the URL is refused.
function NxPlexTransfer(url as String, token as String) as Dynamic
    return NxServerTransfer(url, NxPlexHeaders(token))
end function

function NxPlexVideoRequest(url as String, token as String, timeoutMs = 5000 as Integer) as Integer
    return NxPlexServerGet(url, token, timeoutMs).code
end function

' Percent-encodes all but A-Z a-z 0-9 - _ . ~, byte by byte in UTF-8, as
' roUrlTransfer.Escape does. That component is task-only on Roku OS 16, and
' this runs on the render thread, where creating it crashed the app.
function NxUrlEncode(s as String) as String
    bytes = CreateObject("roByteArray")
    bytes.FromAsciiString(s)
    hex = "0123456789ABCDEF"
    out = ""
    for each b in bytes
        if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or (b >= 48 and b <= 57) or b = 45 or b = 95 or b = 46 or b = 126 then
            out = out + Chr(b)
        else
            out = out + "%" + Mid(hex, (b >> 4) + 1, 1) + Mid(hex, (b and 15) + 1, 1)
        end if
    end for
    return out
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
' A new plex.tv/link PIN as { id, code }, or invalid. out, when given, gets
' the request's code (an HTTP status, or curl's when nothing answered).
function NxPlexCreatePin(out = invalid as Dynamic) as Dynamic
    res = NxHttp("POST", "https://plex.tv/api/v2/pins", NxPlexHeaders(""))
    if out <> invalid then out.code = res.code
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

' The signed-in account as { name, id }, "" if the token was rejected, or
' invalid if plex.tv couldn't be reached (so a network blip doesn't sign
' anyone out). id is the account's uuid, or its number when there is none.
function NxPlexAccount(token as String) as Dynamic
    res = NxHttp("GET", "https://plex.tv/api/v2/user", NxPlexHeaders(token))
    if res.code = 401 or res.code = 403 then return ""
    if res.code < 200 or res.code > 299 or type(res.json) <> "roAssociativeArray" then return invalid
    name = res.json.username
    if not NxIsString(name) or name = "" then name = res.json.title
    if not NxIsString(name) then name = "Plex"
    id = NxToStr(res.json.uuid)
    if id = "" then id = NxToStr(res.json.id)
    return { name: name, id: id }
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
