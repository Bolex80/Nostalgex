' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "warm"
end sub

' Up to 10 minutes each: a server reads the whole video to make the file,
' 96 s for a 6.6 GB film on the test Emby. The address carries no token.
sub warm()
    got = 0
    urls = m.top.urls
    if urls = invalid then urls = []
    for each u in urls
        port = CreateObject("roMessagePort")
        xfer = CreateObject("roUrlTransfer")
        xfer.SetMessagePort(port)
        xfer.SetUrl(u)
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        if xfer.AsyncGetToString() then
            msg = Wait(600000, port)
            if type(msg) = "roUrlEvent" and msg.GetResponseCode() = 200 then got = got + 1
            if msg = invalid then xfer.AsyncCancel()
        end if
    end for
    print "subtitles: "; got; " of "; urls.Count(); " forced subtitle files ready ahead of their airings"
    m.top.done = got
end sub
