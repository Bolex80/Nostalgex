' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Steps: choose (Plex, Jellyfin, Emby), finding (the network broadcast),
' servers (those that answered, and TYPE AN ADDRESS), connecting, method
' (Jellyfin: Quick Connect or password), code (the Quick Connect code),
' signing. Back goes a step back; at choose it is MainScene's.

sub init()
    m.fonts = {}
    m.cyan = "0x00D4FF"
    m.rowH = 100
    m.rowGap = 12
    m.rowsVisible = 5
    m.colX = 1000
    m.colW = 820
    m.kind = ""
    m.error = ""
    m.task = invalid
    m.server = invalid
    show("choose")
    m.top.SetFocus(true)
end sub

function fontOf(name as String, size as Integer) as Object
    key = name + size.ToStr()
    if m.fonts[key] = invalid then
        f = CreateObject("roSGNode", "Font")
        f.uri = "pkg:/fonts/" + name + ".ttf"
        f.size = size
        m.fonts[key] = f
    end if
    return m.fonts[key]
end function

function newLabel(text as String, font as String, size as Integer, color as String, x as Float, y as Float) as Object
    lbl = CreateObject("roSGNode", "Label")
    lbl.text = text
    lbl.font = fontOf(font, size)
    lbl.color = color
    lbl.translation = [x, y]
    return lbl
end function

function newRect(x as Float, y as Float, w as Float, h as Float, color as String) as Object
    r = CreateObject("roSGNode", "Rectangle")
    r.translation = [x, y]
    r.width = w
    r.height = h
    r.color = color
    return r
end function

sub outline(g as Object, x as Float, y as Float, w as Float, h as Float, t as Float, color as String)
    g.AppendChild(newRect(x, y, w, t, color))
    g.AppendChild(newRect(x, y + h - t, w, t, color))
    g.AppendChild(newRect(x, y, t, h, color))
    g.AppendChild(newRect(x + w - t, y, t, h, color))
end sub

sub onNotice()
    m.error = m.top.notice
    render()
end sub

' Goes to a step: its rows ({ id, title, detail }) and words.
sub show(stepName as String)
    m.step = stepName
    m.focus = 0
    m.top0 = 0
    name = NxKindName(m.kind)
    m.rows = []
    m.code = ""
    if stepName = "choose" then
        m.title = "CONNECT YOUR LIBRARY"
        m.body = "Nostalgex builds TV channels from your own media server. Which one do you use?"
        m.rows = [
            { id: "plex", title: "PLEX", detail: "Sign in with a code at plex.tv/link" },
            { id: "jellyfin", title: "JELLYFIN", detail: "A server on your home network" },
            { id: "emby", title: "EMBY", detail: "A server on your home network" }
        ]
    else if stepName = "finding" then
        m.title = "CONNECT TO " + UCase(name)
        m.body = "Looking for " + name + " servers on your network…"
    else if stepName = "servers" then
        m.title = "CONNECT TO " + UCase(name)
        if m.found.Count() = 0 then
            m.body = "No " + name + " server answered on this network. Type its address instead: the one you open " + name + " at in a browser."
        else
            m.body = "Pick your " + name + " server, or type its address."
        end if
        for each s in m.found
            m.rows.Push({ id: "found", title: UCase(s.name), detail: s.address, address: s.address })
        end for
        m.rows.Push({ id: "type", title: "TYPE AN ADDRESS", detail: "Like 10.0.0.20 or http://10.0.0.20:8096" })
    else if stepName = "connecting" then
        m.title = "CONNECT TO " + UCase(name)
        m.body = "Connecting to " + m.address + "…"
    else if stepName = "method" then
        m.title = "SIGN IN TO " + UCase(m.server.name)
        if m.server.kind = "jellyfin" then
            m.body = "Quick Connect signs this TV in with a code you approve in Jellyfin, with no password to type."
            m.rows.Push({ id: "quick", title: "USE QUICK CONNECT", detail: "Approve a code in Jellyfin" })
        else
            m.body = "Sign in with your " + name + " username and password."
        end if
        m.rows.Push({ id: "password", title: "SIGN IN WITH PASSWORD", detail: "Type your " + name + " username and password" })
    else if stepName = "code" then
        m.title = "SIGN IN TO " + UCase(m.server.name)
        m.body = "In Jellyfin, open your profile, then Quick Connect, and enter this code. It lasts five minutes. Press Back to sign in another way."
    else if stepName = "signing" then
        m.title = "SIGN IN TO " + UCase(m.server.name)
        m.body = "Signing in…"
    end if
    render()
end sub

sub render()
    g = m.top.FindNode("left")
    g.RemoveChildrenIndex(g.GetChildCount(), 0)
    logo = CreateObject("roSGNode", "Poster")
    logo.uri = "pkg:/images/logo.png"
    logo.width = 440
    logo.height = 58
    g.AppendChild(logo)
    g.AppendChild(newLabel(m.title, "DMMono-Medium", 40, "0xFFFFFFE6", 0, 86))
    body = newLabel(m.body, "DMMono-Regular", 22, "0xFFFFFF73", 0, 164)
    body.width = 760
    body.wrap = true
    body.lineSpacing = 4
    g.AppendChild(body)
    if m.error <> "" then
        err = newLabel(m.error, "DMMono-Regular", 22, "0xFF6B6BFF", 0, 340)
        err.width = 760
        err.wrap = true
        err.lineSpacing = 4
        g.AppendChild(err)
    end if
    g.translation = [100, 540 - 180]

    l = m.top.FindNode("list")
    l.RemoveChildrenIndex(l.GetChildCount(), 0)
    if m.step = "code" then
        code = newLabel(m.code, "DMMono-Medium", 96, m.cyan + "FF", m.colX, 470)
        code.width = m.colW
        code.horizAlign = "center"
        l.AppendChild(code)
        return
    end if
    if m.rows.Count() = 0 then return
    shown = m.rows.Count()
    if shown > m.rowsVisible then shown = m.rowsVisible
    if m.focus < m.top0 then m.top0 = m.focus
    if m.focus >= m.top0 + m.rowsVisible then m.top0 = m.focus - m.rowsVisible + 1
    listH = shown * m.rowH + (shown - 1) * m.rowGap
    y = (1080 - listH) / 2
    for i = m.top0 to m.top0 + shown - 1
        row = m.rows[i]
        focused = i = m.focus
        bg = "0xFFFFFF08"
        if focused then bg = m.cyan + "1A"
        l.AppendChild(newRect(m.colX, y, m.colW, m.rowH, bg))
        if focused then
            outline(l, m.colX, y, m.colW, m.rowH, 2.5, m.cyan + "99")
        else
            outline(l, m.colX, y, m.colW, m.rowH, 1, "0xFFFFFF14")
        end if
        color = "0xFFFFFFB3"
        if focused then color = "0xFFFFFFFF"
        l.AppendChild(newLabel(row.title, "DMMono-Medium", 28, color, m.colX + 32, y + 22))
        l.AppendChild(newLabel(row.detail, "DMMono-Regular", 18, "0xFFFFFF66", m.colX + 32, y + 60))
        y = y + m.rowH + m.rowGap
    end for
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.keyboard <> invalid then return false
    if key = "down" and m.focus < m.rows.Count() - 1 then
        m.focus = m.focus + 1
        render()
        return true
    end if
    if key = "up" and m.focus > 0 then
        m.focus = m.focus - 1
        render()
        return true
    end if
    if key = "OK" and m.rows.Count() > 0 then
        choose(m.rows[m.focus])
        return true
    end if
    if key = "back" and m.step <> "choose" then
        goBack()
        return true
    end if
    return false
end function

sub goBack()
    stopTask()
    m.error = ""
    if m.step = "code" or m.step = "signing" then
        show("method")
    else if m.step = "method" or m.step = "connecting" then
        show("servers")
    else
        m.kind = ""
        show("choose")
    end if
end sub

sub choose(row as Object)
    m.error = ""
    if m.step = "choose" then
        if row.id = "plex" then
            m.top.done = "plex"
            return
        end if
        m.kind = row.id
        m.found = []
        show("finding")
        runTask("discover")
    else if m.step = "servers" then
        if row.id = "type" then
            askText("address", NxKindName(m.kind) + " server address", "The address you open " + NxKindName(m.kind) + " at in a browser, like 10.0.0.20:8096.", "", false)
        else
            connectTo(row.address)
        end if
    else if m.step = "method" then
        if row.id = "quick" then
            show("signing")
            runTask("quickConnect")
        else
            askText("username", NxKindName(m.server.kind) + " username", "", "", false)
        end if
    end if
end sub

sub connectTo(address as String)
    m.address = address
    show("connecting")
    runTask("connect")
end sub

' The on-screen keyboard, for an address, a username or a password.
sub askText(purpose as String, title as String, message as String, text as String, secret as Boolean)
    kb = CreateObject("roSGNode", "StandardKeyboardDialog")
    kb.title = title
    if message <> "" then kb.message = [message]
    kb.buttons = ["OK", "Cancel"]
    kb.text = text
    if secret then kb.textEditBox.secureMode = true
    kb.ObserveField("buttonSelected", "onKeyboardButton")
    kb.ObserveField("wasClosed", "onKeyboardClosed")
    m.keyboardPurpose = purpose
    m.keyboard = kb
    m.top.GetScene().dialog = kb
end sub

sub onKeyboardButton()
    kb = m.keyboard
    if kb = invalid then return
    text = kb.text
    ok = kb.buttonSelected = 0
    closeKeyboard()
    if not ok then return
    purpose = m.keyboardPurpose
    if purpose = "address" then
        if text.Trim() <> "" then connectTo(text.Trim())
    else if purpose = "username" then
        m.username = text
        askText("password", NxKindName(m.server.kind) + " password", "For " + text + ".", "", true)
    else if purpose = "password" then
        show("signing")
        runTask("password", text)
    end if
end sub

sub onKeyboardClosed()
    if m.keyboard <> invalid then closeKeyboard()
end sub

sub closeKeyboard()
    if m.keyboard = invalid then return
    ' Its closing notice arrives after the next keyboard (the password one)
    ' may be up, and would close that one too.
    m.keyboard.UnobserveField("buttonSelected")
    m.keyboard.UnobserveField("wasClosed")
    m.keyboard.close = true
    m.keyboard = invalid
    m.top.SetFocus(true)
end sub

sub runTask(action as String, secret = "" as String)
    stopTask()
    t = CreateObject("roSGNode", "MediaBrowserSignInTask")
    t.action = action
    t.kind = m.kind
    if action = "connect" then t.address = m.address
    if m.server <> invalid then t.server = m.server
    if action = "password" then
        t.username = m.username
        t.password = secret
    end if
    t.ObserveField("status", "onTaskStatus")
    m.task = t
    t.control = "run"
end sub

sub stopTask()
    if m.task = invalid then return
    m.task.UnobserveField("status")
    m.task.cancel = true
    m.task = invalid
end sub

sub onTaskStatus()
    t = m.task
    if t = invalid then return
    status = t.status
    if status = "found" then
        m.found = []
        for each s in t.found
            m.found.Push(s)
        end for
        show("servers")
    else if status = "connected" then
        m.server = t.server
        if m.server.kind <> m.kind then print "mediabrowser: the server is "; m.server.kind; ", not "; m.kind
        m.kind = m.server.kind
        show("method")
    else if status = "code" then
        show("code")
        m.code = t.code
        render()
    else if status = "signedIn" then
        stopTask()
        m.top.done = m.kind
    else if status = "error" then
        m.error = t.message
        stopTask()
        if m.step = "connecting" or m.server = invalid then
            show("servers")
        else
            show("method")
        end if
    end if
end sub
