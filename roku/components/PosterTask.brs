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
    if s = invalid or NxServerKind(s) <> "plex" then
        m.top.file = ""
        return
    end if
    ' The same address rule as every other Plex request (NxServerTransfer):
    ' HTTPS, or plain HTTP to a home-network address. The token is a header.
    xfer = NxPlexTransfer(NxPlexPosterUrl(NxToStr(s.uri), ref.path, 300), NxToStr(s.accessToken))
    if xfer = invalid then
        m.top.file = ""
        return
    end if
    out = NxPosterFile(NxToStr(ref.path))
    for each f in ListDir("tmp:/")
        if Left(f, 10) = "nx-poster-" then DeleteFile("tmp:/" + f)
    end for
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
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
