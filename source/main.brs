' A deep link (source/guide/DeepLink.brs) comes in the launch args, or later
' as an roInput event; either way it goes to the scene to tune.
sub Main(args = invalid as Dynamic)
    screen = CreateObject("roSGScreen")
    port = CreateObject("roMessagePort")
    screen.SetMessagePort(port)
    scene = screen.CreateScene("MainScene")
    screen.Show()
    link = NxDeepLinkFrom(args)
    if link <> invalid then scene.deepLink = link
    input = CreateObject("roInput")
    input.SetMessagePort(port)
    while true
        msg = Wait(0, port)
        if type(msg) = "roSGScreenEvent" and msg.IsScreenClosed() then return
        if type(msg) = "roInputEvent" and msg.IsInput() then
            link = NxDeepLinkFrom(msg.GetInfo())
            if link <> invalid then scene.deepLink = link
        end if
    end while
end sub
