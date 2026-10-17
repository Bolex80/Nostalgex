' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Upstream's LoadingView with its step rail. The steps are LibraryLoadPhase's
' (App/LibraryLoadPhase.swift), titles, headlines and hints as upstream has
' them. Two differences: Collections is always a step, since the Roku reads
' a server's collections on every scan, not only for a collection package;
' and while channels build, the headline stays BUILDING CHANNELS rather than
' naming each channel.

sub init()
    m.fonts = {}
    m.dots = ""
    m.cyan = "0x00D4FF"
    m.steps = [
        { id: "preparing", title: "Lineup", headline: "PREPARING LINEUP", hint: "Loading channel rules and bundles" },
        { id: "library", title: "Library", headline: "SCANNING PLEX LIBRARY", hint: "Reading movies, shows, and music from your server" },
        { id: "collections", title: "Collections", headline: "DISCOVERING COLLECTIONS", hint: "Finding smart collections in your library" },
        { id: "metadata", title: "Metadata", headline: "ENRICHING METADATA", hint: "TMDB and OMDb power the genre and network channels" },
        { id: "channels", title: "Channels", headline: "BUILDING CHANNELS", hint: "Matching your library to each channel" },
        { id: "finishing", title: "Ready", headline: "TUNING IN", hint: "Almost there" }
    ]
    m.timer = CreateObject("roSGNode", "Timer")
    m.timer.duration = 0.4
    m.timer.repeat = true
    m.timer.ObserveField("fire", "onDots")
    m.timer.control = "start"
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

' A label centred across the screen.
function centred(text as String, font as String, size as Integer, color as String, y as Float) as Object
    lbl = CreateObject("roSGNode", "Label")
    lbl.text = text
    lbl.font = fontOf(font, size)
    lbl.color = color
    lbl.width = 1920
    lbl.horizAlign = "center"
    lbl.translation = [0, y]
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

function newIcon(name as String, x as Float, y as Float, w as Float, h as Float, color as String) as Object
    p = CreateObject("roSGNode", "Poster")
    p.uri = "pkg:/images/look/" + name + ".png"
    p.translation = [x, y]
    p.width = w
    p.height = h
    p.blendColor = color
    return p
end function

sub onTask()
    t = m.top.task
    for each f in ["phase", "progress", "bar", "barCaption", "firstRun"]
        t.ObserveField(f, "render")
    end for
    render()
end sub

sub onDots()
    if Len(m.dots) >= 3 then m.dots = "" else m.dots = m.dots + "."
    if m.headline <> invalid then m.headline.text = m.headlineText + m.dots
end sub

function stepIndex(id as String) as Integer
    for i = 0 to m.steps.Count() - 1
        if m.steps[i].id = id then return i
    end for
    return 0
end function

sub render()
    t = m.top.task
    if t = invalid then return
    current = stepIndex(t.phase)
    st = m.steps[current]
    g = m.top.FindNode("content")
    g.RemoveChildrenIndex(g.GetChildCount(), 0)

    ' The stack, top to bottom, 28 apart, centred on the screen as a whole.
    gap = 28
    h = 120 + 20 + gap + 56 + gap + 42
    if t.firstRun then h = h + 30 + gap
    detail = UCase(NxToStr(t.progress))
    if st.id = "channels" and t.bar >= 0 then detail = ""
    if detail = "" and st.id <> "channels" then detail = UCase(st.hint)
    if detail <> "" then h = h + 30 + gap
    if t.bar >= 0 then h = h + 44 + gap
    y = (1080 - h) / 2

    g.AppendChild(centred("NOSTALGEX", "VT323-Regular", 120, "0xF9E503FF", y))
    y = y + 120 + 20 + gap
    if t.firstRun then
        g.AppendChild(centred("First setup can take a few minutes to scan and build channels.", "DMMono-Regular", 22, "0xFFFFFF8C", y))
        y = y + 30 + gap
    end if
    renderRail(g, y, current)
    y = y + 56 + gap
    m.headlineText = st.headline
    m.headline = centred(m.headlineText + m.dots, "DMMono-Medium", 32, m.cyan + "FF", y)
    g.AppendChild(m.headline)
    y = y + 42 + gap
    if detail <> "" then
        lbl = centred(detail, "DMMono-Regular", 22, "0xFFFFFF73", y)
        lbl.width = 1200
        lbl.translation = [360, y]
        lbl.wrap = false
        lbl.ellipsizeOnBoundary = true
        g.AppendChild(lbl)
        y = y + 30 + gap
    end if
    if t.bar >= 0 then
        value = t.bar
        if value > 1 then value = 1
        x = (1920 - 420) / 2
        g.AppendChild(newRect(x, y, 420, 6, "0xFFFFFF26"))
        if value > 0 then g.AppendChild(newRect(x, y, 420 * value, 6, m.cyan + "FF"))
        g.AppendChild(centred(UCase(NxToStr(t.barCaption)), "DMMono-Regular", 19, "0xFFFFFF66", y + 16))
    end if
end sub

' LibraryLoadStepRail: a circle per step, done ones ticked, the current one
' dotted; short connectors between them, cyan behind a done step.
sub renderRail(g as Object, y as Float, current as Integer)
    n = m.steps.Count()
    connW = 36
    cellW = (900 - (n - 1) * connW) / n
    x = (1920 - 900) / 2
    for i = 0 to n - 1
        if i < current then
            ringColor = m.cyan + "FF"
            labelColor = "0xFFFFFF8C"
        else if i = current then
            ringColor = m.cyan + "FF"
            labelColor = m.cyan + "FF"
        else
            ringColor = "0xFFFFFF40"
            labelColor = "0xFFFFFF4D"
        end if
        cx = x + cellW / 2
        g.AppendChild(newIcon("step_ring", cx - 14, y, 28, 28, ringColor))
        if i < current then
            g.AppendChild(newIcon("step_check", cx - 7, y + 7, 14, 14, m.cyan + "FF"))
        else if i = current then
            g.AppendChild(newIcon("step_dot", cx - 5, y + 9, 10, 10, m.cyan + "FF"))
        end if
        lbl = CreateObject("roSGNode", "Label")
        lbl.text = UCase(m.steps[i].title)
        lbl.font = fontOf("DMMono-Regular", 16)
        lbl.color = labelColor
        lbl.width = cellW
        lbl.horizAlign = "center"
        lbl.translation = [x, y + 36]
        g.AppendChild(lbl)
        x = x + cellW
        if i < n - 1 then
            c = "0xFFFFFF26"
            if i < current then c = m.cyan + "80"
            g.AppendChild(newRect(x, y + 13, connW, 2, c))
            x = x + connW
        end if
    end for
end sub
