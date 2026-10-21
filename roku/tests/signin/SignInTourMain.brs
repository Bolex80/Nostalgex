' Sign-in tour entry point (scripts/deploy.sh --tour): the connect screens on
' their own, for walking them with a remote and counting presses on a TV, as
' upstream's NostalgexUITests/SignInTourUITests do in the simulator.
'
' A dry run: finishing a Jellyfin or Emby sign-in here asks no server and
' saves nothing (ConnectView.dryRun), so the TV's own sign-in stays as it was.
'
' Launch arguments (ECP: POST /launch/dev?discovery=none):
'   discovery=none|several   stands in for the network search
'                            (upstream's -uiTestDiscovery)
'   picker=1                 the Plex library picker over made-up servers
'   plexerror=1              the made-up Plex code expires after 3 s
' CONNECT TO PLEX shows a made-up plex.tv/link code: the tour runs no Plex
' sign-in.
sub Main(args = invalid as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("SignInTourScene")
    screen.Show()
    if type(args) = "roAssociativeArray" then scene.args = args
    print "TOUR READY"
    while true
        msg = Wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.IsScreenClosed() then return
    end while
end sub
