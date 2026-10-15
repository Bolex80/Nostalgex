' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.focus = 0
    m.top0 = 0
    m.rowsVisible = 10
    m.fonts = {}
    m.changed = false
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

' Rows: every package, subtitles, then sign-out.
sub open(unused = invalid as Dynamic)
    m.enabled = []
    m.enabled.Append(m.top.enabledBundles)
    m.subs = NxSubtitleSettings()
    m.top.SetFocus(true)
    render()
end sub

function rowCount() as Integer
    return m.top.bundles.Count() + 2
end function

' Upstream's SUBTITLES row (BundleManagerView): one setting for both flags.
function subtitleModeLabel() as String
    if m.subs.always then return "ALWAYS"
    if m.subs.foreign then return "FOREIGN AUDIO"
    return "OFF"
end function

function subtitleModeExplanation() as String
    if m.subs.always then return "Shown in fullscreen whenever the video has them"
    if m.subs.foreign then return "Shown in fullscreen when the audio isn't in your language"
    return "Never shown. Press to change"
end function

' Off, then foreign audio only, then always, then back to off.
sub cycleSubtitleMode()
    if m.subs.always then
        m.subs.always = false
        m.subs.foreign = false
    else if m.subs.foreign then
        m.subs.always = true
    else
        m.subs.foreign = true
    end if
    NxSaveSubtitleSettings(m.subs)
end sub

sub render()
    page = m.top.FindNode("page")
    page.RemoveChildrenIndex(page.GetChildCount(), 0)
    page.AppendChild(newLabel("SETTINGS", "VT323-Regular", 56, "0xFFE500FF", 0, 0))
    page.AppendChild(newLabel("CHANNEL PACKAGES", "DMMono-Medium", 24, "0xFFFFFFB3", 0, 90))
    page.AppendChild(newLabel("Toggle packages to customize your lineup", "DMMono-Regular", 20, "0xFFFFFF80", 0, 124))

    if m.focus < m.top0 then m.top0 = m.focus
    if m.focus > m.top0 + m.rowsVisible - 1 then m.top0 = m.focus - m.rowsVisible + 1
    last = m.top0 + m.rowsVisible - 1
    if last > rowCount() - 1 then last = rowCount() - 1
    y = 180
    for i = m.top0 to last
        focused = i = m.focus
        accent = "0xFFE500"
        if i < m.top.bundles.Count() then
            b = m.top.bundles[i]
            on = NxHasValue(m.enabled, b.id)
            label = b.name
            detail = b.channelIDs.Count().ToStr() + " CHANNELS"
            if NxTruthy(b.activeMonths) then detail = detail + " · SEASONAL"
            state = "OFF"
            stateColor = "0xFFFFFF59"
            if on then
                state = "ON"
                stateColor = "0xFFE500FF"
            end if
        else if i = m.top.bundles.Count() then
            label = "SUBTITLES"
            detail = subtitleModeExplanation()
            state = subtitleModeLabel()
            stateColor = "0xFFFFFF59"
            if state <> "OFF" then stateColor = "0xFFE500FF"
        else
            label = "SIGN OUT OF PLEX"
            detail = "Forget this TV's Plex sign-in"
            state = ""
            stateColor = "0xFFFFFFFF"
            accent = "0xFF6B6B"
        end if
        if focused then page.AppendChild(newRect(0, y, 1680, 72, accent + "52"))
        if focused then
            page.AppendChild(newRect(0, y, 8, 72, accent + "FF"))
        else
            page.AppendChild(newRect(0, y, 4, 72, accent + "66"))
        end if
        nameColor = "0xFFFFFFBF"
        if focused then nameColor = "0xFFFFFFFF"
        page.AppendChild(newLabel(label, "DMMono-Medium", 24, nameColor, 30, y + 10))
        page.AppendChild(newLabel(detail, "VT323-Regular", 24, "0xFFFFFF80", 30, y + 40))
        if state <> "" then
            stateLabel = newLabel(state, "DMMono-Medium", 24, stateColor, 1260, y + 22)
            stateLabel.width = 380
            stateLabel.horizAlign = "right"
            page.AppendChild(stateLabel)
        end if
        y = y + 74
    end for
    page.AppendChild(newLabel("OK toggles · BACK returns to the guide", "DMMono-Regular", 20, "0xFFFFFF59", 0, y + 24))
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "down" and m.focus < rowCount() - 1 then
        m.focus = m.focus + 1
        render()
        return true
    end if
    if key = "up" and m.focus > 0 then
        m.focus = m.focus - 1
        render()
        return true
    end if
    if key = "OK" then
        if m.focus < m.top.bundles.Count() then
            id = m.top.bundles[m.focus].id
            kept = []
            found = false
            for each x in m.enabled
                if x = id then found = true else kept.Push(x)
            end for
            if not found then kept.Push(id)
            m.enabled = kept
            m.changed = true
            render()
        else if m.focus = m.top.bundles.Count() then
            cycleSubtitleMode()
            render()
        else
            m.top.result = "signOut"
        end if
        return true
    end if
    if key = "back" or key = "left" then
        if m.changed then
            reg = CreateObject("roRegistrySection", "guide")
            reg.Write("bundles", FormatJson(m.enabled))
            reg.Flush()
            m.top.result = "rebuild"
        else
            m.top.result = "close"
        end if
        return true
    end if
    return true
end function
