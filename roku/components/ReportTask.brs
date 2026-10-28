' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.top.functionName = "runEvents"
end sub

sub runEvents()
    port = CreateObject("roMessagePort")
    m.top.ObserveField("event", port)
    ex = NxReportExecutor()
    net = NxReportNet()
    done = 0
    while true
        msg = Wait(0, port)
        if type(msg) = "roSGNodeEvent" and msg.GetField() = "event" then
            ev = msg.GetData()
            if type(ev) = "roAssociativeArray" then
                what = NxReportRun(ex, ev, m.top.scope, net)
                ' Never the address or the token.
                print "report: "; ev.kind; " "; ev.backend; " item "; ev.ratingKey; ": "; what
            end if
            done = done + 1
            m.top.processed = done
        end if
    end while
end sub

' The transport: the saved servers (as playback reads them) and one request
' at a time, 12 s each, as upstream's report session. A Plex answer (sent
' with NxPlexHeaders) is repaired first, as WatchStateGuard's reads are.
function NxReportNet() as Object
    return {
        server: function(index as Dynamic) as Dynamic
            raw = NxPlexRegistry().Read("servers")
            if raw = "" or not NxIsNumber(index) then return invalid
            list = ParseJson(raw)
            if type(list) <> "roArray" or index < 0 or index >= list.Count() then return invalid
            s = list[index]
            if type(s) <> "roAssociativeArray" then return invalid
            base = NxToStr(s.uri)
            if NxTruthy(s.lanUri) then base = NxToStr(s.lanUri)
            if base = "" then return invalid
            return { kind: NxServerKind(s), base: base, token: NxToStr(s.accessToken), userId: NxToStr(s.userId) }
        end function,
        send: function(method as String, url as String, headers as Object, body as String) as Object
            return NxServerRequest(method, url, headers, body, 12000, headers.DoesExist("X-Plex-Client-Identifier"))
        end function,
        sleep: sub(ms as Integer)
            Sleep(ms)
        end sub
    }
end function
