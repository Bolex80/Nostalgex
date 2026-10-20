' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Upstream's NowPlayingPanel: the info zone (channel, what's on, rating, up
' next) and two control columns, one for the program (CAPTIONS, AUDIO) and
' one for the device (PICTURE, SLEEP TIMER, PLAYBACK INFORMATION). Left and
' Right move between the columns, Up and Down within one. PLAYBACK
' INFORMATION opens in place of the columns; Back closes it, then the panel.
'
' Left out, for what the Roku has: STREAM QUALITY and the language pickers
' (no quality setting here, and Plex sends one subtitle track), and OPEN IN
' PLEX. Rounded corners are square; the shade is flat where upstream's fades.

sub init()
    m.fonts = {}
    m.col = 0
    m.idx = [0, 0]
    m.infoOpen = false
    m.colX = [992, 1452]
    m.colW = 420
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

function newLabel(text as String, font as String, size as Integer, color as String, x as Float, y as Float, width as Float) as Object
    lbl = CreateObject("roSGNode", "Label")
    lbl.text = text
    lbl.font = fontOf(font, size)
    lbl.color = color
    lbl.translation = [x, y]
    if width > 0 then
        lbl.width = width
        lbl.ellipsizeOnBoundary = true
    end if
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

function tint(color as String, alpha as String) as String
    return Left(color, 8) + alpha
end function

sub open(unused = invalid as Dynamic)
    m.col = 0
    m.idx = [0, 0]
    m.infoOpen = false
    ' Upstream opens on CC (focusedControl = .cc) even with no subtitles,
    ' where it's greyed out; here it opens on the next row that does
    ' something instead: an audio track, else RETRO MODE (Discussion #8).
    if m.top.state <> invalid then
        cols = columns()
        f = focusables(cols[0])
        if f.Count() > 0 and cols[0][f[0]].disabled = true then
            if f.Count() > 1 then m.idx[0] = 1 else m.col = 1
        end if
    end if
    render()
    m.top.SetFocus(true)
end sub

' The two columns as lists of { kind: hdr | row, label, value, active,
' disabled, id }; only rows with an id take focus.
function columns() as Object
    s = m.top.state
    prog = []
    prog.Push({ kind: "hdr", label: "CAPTIONS" })
    cc = "NONE"
    if s.hasSubs then
        cc = "OFF"
        if s.ccOn then cc = "ON"
    end if
    ' Always focusable, as upstream's, so the panel always opens on it.
    prog.Push({ kind: "row", label: "CC", value: cc, active: s.hasSubs and s.ccOn, disabled: not s.hasSubs, id: "cc" })
    if s.hasSubs then
        v = "OFF"
        if s.autoOn then v = "ON"
        prog.Push({ kind: "row", label: "AUTO SUBTITLES (FOREIGN AUDIO)", value: v, active: s.autoOn, id: "auto" })
    end if
    prog.Push({ kind: "hdr", label: "AUDIO" })
    tracks = NxList(s.audio)
    if tracks.Count() <= 1 then
        name = "SINGLE TRACK"
        if tracks.Count() = 1 then name = tracks[0].name
        prog.Push({ kind: "row", label: name, value: "", disabled: true })
    else
        for i = 0 to tracks.Count() - 1
            v = ""
            if tracks[i].active then v = "ACTIVE"
            prog.Push({ kind: "row", label: tracks[i].name, value: v, active: tracks[i].active, id: "audio:" + i.ToStr() })
        end for
    end if

    dev = []
    dev.Push({ kind: "hdr", label: "PICTURE" })
    v = "OFF"
    if s.retro then v = "ON"
    dev.Push({ kind: "row", label: "RETRO MODE", value: v, active: s.retro, id: "retro" })
    dev.Push({ kind: "hdr", label: "SLEEP TIMER" })
    armed = s.sleepMinutes
    v = ""
    if armed <= 0 then v = "ACTIVE"
    dev.Push({ kind: "row", label: "OFF", value: v, active: armed <= 0, id: "sleep:0" })
    for each minutes in NxSleepOffered(armed)
        on = armed = minutes
        v = ""
        if on then v = NxSleepCountdown(s.sleepLeft)
        dev.Push({ kind: "row", label: NxSleepLabel(minutes), value: v, active: on, id: "sleep:" + minutes.ToStr() })
    end for
    dev.Push({ kind: "row", label: "PLAYBACK INFORMATION", value: "VIEW", id: "info" })
    return [prog, dev]
end function

function focusables(col as Object) as Object
    out = []
    for i = 0 to col.Count() - 1
        if col[i].id <> invalid then out.Push(i)
    end for
    return out
end function

sub render()
    s = m.top.state
    if s = invalid then return
    renderInfo(s)
    g = m.top.FindNode("controls")
    g.RemoveChildrenIndex(g.GetChildCount(), 0)
    bottom = 0
    if m.infoOpen then
        bottom = renderInformation(g, s)
    else
        cols = columns()
        for c = 0 to 1
            y = 40
            f = focusables(cols[c])
            if m.idx[c] > f.Count() - 1 then m.idx[c] = f.Count() - 1
            for i = 0 to cols[c].Count() - 1
                e = cols[c][i]
                if e.kind = "hdr" then
                    g.AppendChild(newLabel(e.label, "DMMono-Medium", 16, "0xFFFFFF99", m.colX[c], y + 6, 0))
                    y = y + 34
                else
                    focused = c = m.col and f.Count() > 0 and f[m.idx[c]] = i
                    drawRow(g, m.colX[c], y, e, focused, s.color)
                    y = y + 58
                end if
            end for
            if y > bottom then bottom = y
        end for
    end if
    infoBottom = 40 + 340
    if bottom < infoBottom then bottom = infoBottom
    m.top.FindNode("shade").height = bottom + 32
end sub

sub drawRow(g as Object, x as Float, y as Float, e as Object, focused as Boolean, color as String)
    fill = "0xFFFFFF24"
    if focused then fill = "0x0D0D12FF"
    g.AppendChild(newRect(x, y, m.colW, 48, fill))
    border = "0xFFFFFF38"
    if e.active = true then border = tint(color, "80")
    t = 1
    if focused then
        border = color
        t = 2
    end if
    outline(g, x, y, m.colW, 48, t, border)
    labelColor = "0xFFFFFFFF"
    if e.disabled = true then labelColor = "0xFFFFFF59"
    g.AppendChild(newLabel(e.label, "DMMono-Medium", 20, labelColor, x + 16, y + 11, m.colW - 140))
    if NxToStr(e.value) <> "" then
        valueColor = "0xFFFFFFBF"
        if e.active = true then valueColor = color
        v = newLabel(e.value, "DMMono-Regular", 18, valueColor, x + 16, y + 13, m.colW - 32)
        v.horizAlign = "right"
        g.AppendChild(v)
    end if
end sub

' PLAYBACK INFORMATION in place of the columns, with BACK under it.
function renderInformation(g as Object, s as Object) as Integer
    x = m.colX[0]
    w = m.colW * 2 + 40
    g.AppendChild(newLabel("PLAYBACK INFORMATION", "DMMono-Medium", 16, "0xFFFFFF99", x, 46, 0))
    y = 80
    rows = NxList(s.info)
    if rows.Count() = 0 then
        g.AppendChild(newLabel("Playback information is unavailable.", "DMMono-Regular", 20, "0xFFFFFFCC", x, y, 0))
        y = y + 40
    end if
    for each r in rows
        g.AppendChild(newLabel(UCase(r.label), "DMMono-Medium", 17, "0xFFFFFF99", x, y + 3, 220))
        g.AppendChild(newLabel(NxToStr(r.value), "DMMono-Regular", 21, "0xFFFFFFFF", x + 236, y, w - 236))
        y = y + 38
    end for
    drawRow(g, x, y + 8, { label: "BACK", value: "" }, true, s.color)
    return y + 8 + 58
end function

sub renderInfo(s as Object)
    g = m.top.FindNode("info")
    g.RemoveChildrenIndex(g.GetChildCount(), 0)
    x = 48
    y = 40
    g.AppendChild(newRect(x, y, 48, 4, s.color))
    y = y + 12
    g.AppendChild(newLabel("CH " + NxToStr(s.number), "DMMono-Medium", 23, s.color, x, y, 0))
    y = y + 36
    g.AppendChild(newLabel(NxToStr(s.name), "DMMono-Medium", 30, "0xFFFFFFFF", x, y, 640))
    y = y + 46
    now = newLabel(NxToStr(s.nowLine), "DMMono-Regular", 25, "0xFFFFFFE6", x, y, 0)
    now.width = 640
    now.wrap = true
    now.maxLines = 2
    g.AppendChild(now)
    y = y + now.boundingRect().height + 8
    if NxToStr(s.rating) <> "" then
        g.AppendChild(newLabel(UCase(s.rating), "DMMono-Regular", 18, "0xFFFFFFB3", x, y, 0))
        y = y + 30
    end if
    if NxToStr(s.upNext) <> "" then g.AppendChild(newLabel("UP NEXT: " + s.upNext, "DMMono-Regular", 18, "0xFFFFFFB3", x, y + 4, 640))
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.infoOpen then
        ' Back, or OK on BACK, returns to the columns, on the information row.
        if key = "back" or key = "OK" then
            m.infoOpen = false
            render()
        end if
        return true
    end if
    cols = columns()
    f = focusables(cols[m.col])
    if key = "up" and m.idx[m.col] > 0 then
        m.idx[m.col] = m.idx[m.col] - 1
        render()
    else if key = "down" and m.idx[m.col] < f.Count() - 1 then
        m.idx[m.col] = m.idx[m.col] + 1
        render()
    else if (key = "left" and m.col = 1) or (key = "right" and m.col = 0) then
        ' To the other column, at about the same height.
        other = 1 - m.col
        of = focusables(cols[other])
        target = 0
        here = f[m.idx[m.col]]
        for k = 0 to of.Count() - 1
            if of[k] <= here then target = k
        end for
        m.col = other
        m.idx[other] = target
        render()
    else if key = "OK" then
        id = cols[m.col][f[m.idx[m.col]]].id
        if id = "info" then
            m.infoOpen = true
            render()
        else
            m.top.action = id
        end if
    else if key = "back" then
        m.top.closed = true
    end if
    return true
end function
