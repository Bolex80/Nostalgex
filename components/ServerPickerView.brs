' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Upstream's ServerPickerView: branding and the explanation on the left, the
' servers and CONTINUE on the right. Owned servers start included, or all of
' them when none is owned; OK on a row switches it; CONTINUE needs at least
' one. Rounded outlines are square here.

sub init()
    m.fonts = {}
    m.focus = 0
    m.top0 = 0
    m.cyan = "0x00D4FF"
    m.rowH = 100
    m.rowGap = 12
    m.rowsVisible = 5
    m.colX = 1000
    m.colW = 820
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

' A box outline: four thin rectangles.
sub outline(g as Object, x as Float, y as Float, w as Float, h as Float, t as Float, color as String)
    g.AppendChild(newRect(x, y, w, t, color))
    g.AppendChild(newRect(x, y + h - t, w, t, color))
    g.AppendChild(newRect(x, y, t, h, color))
    g.AppendChild(newRect(x + w - t, y, t, h, color))
end sub

sub render()
    if m.on = invalid then
        anyOwned = false
        for each s in m.top.servers
            if NxTruthy(s.owned) then anyOwned = true
        end for
        m.on = []
        for each s in m.top.servers
            m.on.Push(NxTruthy(s.owned) or not anyOwned)
        end for
        renderLeft()
        m.top.SetFocus(true)
    end if
    renderList()
end sub

sub renderLeft()
    g = m.top.FindNode("left")
    g.AppendChild(newLabel("NOSTALGEX", "VT323-Regular", 96, "0xF9E503FF", 0, 0))
    g.AppendChild(newLabel("CHOOSE YOUR LIBRARIES", "DMMono-Medium", 40, "0xFFFFFFE6", 0, 140))
    body = newLabel("Your account can reach more than one Plex server. Pick which libraries Nostalgex should build channels from. You can change this later in Settings.", "DMMono-Regular", 22, "0xFFFFFF73", 0, 218)
    body.width = 560
    body.wrap = true
    body.lineSpacing = 4
    g.AppendChild(body)
    g.translation = [100, 540 - 180]
end sub

function continueIndex() as Integer
    return m.top.servers.Count()
end function

function anyOn() as Boolean
    return NxHasValue(m.on, true)
end function

sub renderList()
    servers = m.top.servers
    shown = servers.Count()
    if shown > m.rowsVisible then shown = m.rowsVisible
    listH = shown * m.rowH + (shown - 1) * m.rowGap
    contH = 80
    top = (1080 - (listH + 24 + contH)) / 2

    g = m.top.FindNode("list")
    g.RemoveChildrenIndex(g.GetChildCount(), 0)
    if m.focus < continueIndex() then
        if m.focus < m.top0 then m.top0 = m.focus
        if m.focus >= m.top0 + m.rowsVisible then m.top0 = m.focus - m.rowsVisible + 1
    end if
    y = top
    last = m.top0 + shown - 1
    for i = m.top0 to last
        s = servers[i]
        focused = i = m.focus
        on = m.on[i]
        bg = "0xFFFFFF08"
        if focused then bg = m.cyan + "1A"
        g.AppendChild(newRect(m.colX, y, m.colW, m.rowH, bg))
        if focused then
            outline(g, m.colX, y, m.colW, m.rowH, 2.5, m.cyan + "99")
        else
            outline(g, m.colX, y, m.colW, m.rowH, 1, "0xFFFFFF14")
        end if
        nameColor = "0xFFFFFF8C"
        if on then nameColor = "0xFFFFFFFF"
        g.AppendChild(newLabel(NxToStr(s.name), "DMMono-Medium", 28, nameColor, m.colX + 32, y + 22))
        kind = "Shared with you"
        if NxTruthy(s.owned) then kind = "Your server"
        g.AppendChild(newLabel(kind, "DMMono-Regular", 18, "0xFFFFFF66", m.colX + 32, y + 60))
        state = newLabel("OFF", "DMMono-Medium", 22, "0xFFFFFF59", m.colX + 32, y + 36)
        if on then
            state.text = "INCLUDED"
            state.color = m.cyan + "FF"
        end if
        state.width = m.colW - 64
        state.horizAlign = "right"
        g.AppendChild(state)
        y = y + m.rowH + m.rowGap
    end for

    c = m.top.FindNode("cont")
    c.RemoveChildrenIndex(c.GetChildCount(), 0)
    cy = top + listH + 24
    focused = m.focus = continueIndex()
    if focused then c.AppendChild(newRect(m.colX, cy, m.colW, contH, m.cyan + "1F"))
    if not anyOn() then
        outline(c, m.colX, cy, m.colW, contH, 1.5, "0xFFFFFF26")
    else if focused then
        outline(c, m.colX, cy, m.colW, contH, 2.5, m.cyan + "FF")
    else
        outline(c, m.colX, cy, m.colW, contH, 1.5, m.cyan + "8C")
    end if
    color = m.cyan + "FF"
    if not anyOn() then color = "0xFFFFFF4D"
    lbl = newLabel("CONTINUE", "DMMono-Medium", 30, color, m.colX, cy + 22)
    lbl.width = m.colW
    lbl.horizAlign = "center"
    c.AppendChild(lbl)
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "down" and m.focus < continueIndex() then
        m.focus = m.focus + 1
        ' CONTINUE can't take focus while it's disabled, as on tvOS.
        if m.focus = continueIndex() and not anyOn() then m.focus = m.focus - 1
        renderList()
        return true
    end if
    if key = "up" and m.focus > 0 then
        m.focus = m.focus - 1
        renderList()
        return true
    end if
    if key = "OK" then
        if m.focus < continueIndex() then
            m.on[m.focus] = not m.on[m.focus]
            renderList()
        else if anyOn() then
            choices = {}
            for i = 0 to m.top.servers.Count() - 1
                choices[NxToStr(m.top.servers[i].machineIdentifier)] = m.on[i]
            end for
            m.top.choices = choices
        end if
        return true
    end if
    ' Back and * are MainScene's (sign out from here).
    return false
end function
