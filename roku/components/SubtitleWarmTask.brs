' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "warm"
end sub

' Up to 10 minutes each: a server reads the whole video to make the file,
' 96 s for a 6.6 GB film on the test Emby. The address carries no token,
' and isn't printed: each file's line gives its place in the batch, the
' server's answer and how long it took, so the load shows in the console.
sub warm()
    got = 0
    urls = m.top.urls
    if urls = invalid then urls = []
    for n = 0 to urls.Count() - 1
        port = CreateObject("roMessagePort")
        xfer = CreateObject("roUrlTransfer")
        xfer.SetMessagePort(port)
        xfer.SetUrl(urls[n])
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        clock = CreateObject("roTimespan")
        code = "not sent"
        if xfer.AsyncGetToString() then
            msg = Wait(600000, port)
            if type(msg) = "roUrlEvent" then
                code = msg.GetResponseCode().ToStr()
                if msg.GetResponseCode() = 200 then got = got + 1
            else
                code = "no answer"
                xfer.AsyncCancel()
            end if
        end if
        print "subtitles: forced file "; n + 1; " of "; urls.Count(); ", "; code; " in "; clock.TotalMilliseconds(); " ms"
    end for
    print "subtitles: "; got; " of "; urls.Count(); " forced subtitle files ready ahead of their airings"
    m.top.done = got
end sub
