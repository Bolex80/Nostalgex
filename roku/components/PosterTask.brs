' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "fetchPoster"
end sub

sub fetchPoster()
    ref = m.top.ref
    s = invalid
    raw = NxPlexRegistry().Read("servers")
    if ref <> invalid and raw <> "" then
        servers = ParseJson(raw)
        if type(servers) = "roArray" and NxIsNumber(ref.serverIndex) then
            if ref.serverIndex >= 0 and ref.serverIndex < servers.Count() then s = servers[ref.serverIndex]
        end if
    end if
    if s = invalid or NxServerKind(s) <> "plex" or LCase(Left(NxToStr(s.uri), 8)) <> "https://" then
        m.top.file = ""
        return
    end if
    out = NxPosterFile(NxToStr(ref.path))
    for each f in ListDir("tmp:/")
        if Left(f, 10) = "nx-poster-" then DeleteFile("tmp:/" + f)
    end for
    port = CreateObject("roMessagePort")
    xfer = CreateObject("roUrlTransfer")
    xfer.SetMessagePort(port)
    xfer.SetUrl(NxPlexPosterUrl(NxToStr(s.uri), ref.path, 300))
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.EnablePeerVerification(true)
    xfer.EnableHostVerification(true)
    xfer.SetHeaders(NxPlexHeaders(NxToStr(s.accessToken)))
    code = -1
    if xfer.AsyncGetToFile(out) then
        msg = Wait(10000, port)
        if type(msg) = "roUrlEvent" then
            code = msg.GetResponseCode()
        else
            xfer.AsyncCancel()
            code = -28
        end if
    end if
    print "nowplaying: poster answered "; code
    if code = 200 then m.top.file = out else m.top.file = ""
end sub
