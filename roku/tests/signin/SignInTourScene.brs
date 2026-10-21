' The sign-in tour's scene. ConnectView reports "plex" for CONNECT TO PLEX;
' here that shows a made-up code instead of MainScene's plex.tv sign-in.

sub init()
    m.connect = m.top.FindNode("connect")
    m.connect.ObserveField("done", "onDone")
    m.connect.ObserveField("plexCancel", "onPlexCancel")
    m.connect.SetFocus(true)
end sub

sub onArgs()
    a = m.top.args
    m.connect.discoveryFixture = NxToStr(a.discovery)
    ' plexerror=1: the made-up code expires after 3 s, and the error goes
    ' back to the connect screen as MainScene sends a Plex sign-in error.
    m.plexError = NxToStr(a.plexerror) = "1"
    print "TOUR args: discovery "; m.connect.discoveryFixture
    ' picker=1: the Plex library picker (ServerPickerView) over made-up
    ' servers, for its look; nothing is saved from it here.
    if NxToStr(a.picker) = "1" then
        m.picker = CreateObject("roSGNode", "ServerPickerView")
        m.picker.ObserveField("choices", "onPicked")
        m.top.AppendChild(m.picker)
        m.picker.servers = [
            { name: "Living Room", machineIdentifier: "tour-1", owned: true },
            { name: "Basement NAS", machineIdentifier: "tour-2", owned: true },
            { name: "Mom's Plex", machineIdentifier: "tour-3", owned: false }
        ]
        m.picker.SetFocus(true)
    end if
end sub

sub onPicked()
    print "TOUR picked: "; FormatJson(m.picker.choices)
end sub

sub onDone()
    done = m.connect.done
    if done = "plex" then
        m.connect.plexCode = "TOUR"
        m.connect.plexState = "code"
        if m.plexError = true then
            m.expiry = CreateObject("roSGNode", "Timer")
            m.expiry.duration = 3
            m.expiry.ObserveField("fire", "onExpired")
            m.top.AppendChild(m.expiry)
            m.expiry.control = "start"
        end if
    else
        print "TOUR SIGNED IN to "; done
    end if
end sub

' As MainScene's onSignInState for "error" with the connect screen up.
sub onExpired()
    m.connect.plexState = ""
    m.connect.notice = NxSignInCopy().plexCodeExpired
    print "TOUR plex code expired"
end sub

sub onPlexCancel()
    m.connect.plexState = ""
end sub
