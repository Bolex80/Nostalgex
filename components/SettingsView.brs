' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.focus = 0
    m.top0 = 0
    m.rowsVisible = 10
    m.fonts = {}
    m.changed = false
    m.franchisesChanged = false
    ' The first OK on SIGN OUT OF PLEX only arms it; a second one signs out.
    m.signOutArmed = false
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

' Rows: every package, with the franchise list under FRANCHISES while it is
' on (upstream's BundleManagerView), then subtitles, then sign-out.
sub open(unused = invalid as Dynamic)
    m.enabled = []
    m.enabled.Append(m.top.enabledBundles)
    m.subs = NxSubtitleSettings()
    m.choices = NxSavedFranchiseChoices()
    reg = NxPlexRegistry()
    m.servers = ParseJson(reg.Read("servers"))
    if type(m.servers) <> "roArray" then m.servers = []
    m.serversOn = NxServersOn(m.servers, ParseJson(reg.Read("serverChoices")))
    m.serversChanged = false
    buildRows()
    m.top.SetFocus(true)
    render()
end sub

' The row list: { kind: bundle | franchiseAll | franchise | server |
' subtitles | signOut }. Server rows show only when the account has more
' than one server.
' The franchise rows are the last guide build's, so they show once the
' package was on for a build.
sub buildRows()
    m.rows = []
    for i = 0 to m.top.bundles.Count() - 1
        b = m.top.bundles[i]
        m.rows.Push({ kind: "bundle", index: i })
        if b.id = NxFranchisesBundleID() and NxHasValue(m.enabled, b.id) and m.top.franchises.Count() > 0 then
            m.rows.Push({ kind: "franchiseAll" })
            for each f in m.top.franchises
                m.rows.Push({ kind: "franchise", franchise: f })
            end for
        end if
    end for
    if m.servers.Count() > 1 then
        for i = 0 to m.servers.Count() - 1
            m.rows.Push({ kind: "server", index: i })
        end for
    end if
    m.rows.Push({ kind: "subtitles" })
    m.rows.Push({ kind: "signOut" })
end sub

function rowCount() as Integer
    return m.rows.Count()
end function

' A row's switch: the viewer's choice since the last build, else the build's.
function franchiseOn(f as Object) as Boolean
    if m.choices.enabled.DoesExist(f.id) then return true
    if m.choices.disabled.DoesExist(f.id) then return false
    return f.enabled
end function

function anyFranchiseOff() as Boolean
    for each f in m.top.franchises
        if not franchiseOn(f) then return true
    end for
    return false
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
        row = m.rows[i]
        indent = 0
        if row.kind = "bundle" then
            b = m.top.bundles[row.index]
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
        else if row.kind = "franchiseAll" then
            indent = 40
            label = "YOUR FRANCHISES"
            detail = "Every franchise below at once"
            state = "REMOVE ALL"
            if anyFranchiseOff() then state = "ADD ALL"
            stateColor = "0xFFE500FF"
        else if row.kind = "franchise" then
            indent = 40
            f = row.franchise
            label = f.name
            detail = f.countLabel
            if f.channelNumber <> invalid then detail = detail + " · CH " + f.channelNumber.ToStr()
            state = "OFF"
            stateColor = "0xFFFFFF59"
            if franchiseOn(f) then
                state = "ON"
                stateColor = "0xFFE500FF"
            end if
        else if row.kind = "server" then
            s = m.servers[row.index]
            label = "SERVER · " + UCase(NxToStr(s.name))
            detail = "Shared with you"
            if NxTruthy(s.owned) then detail = "Your server"
            state = "OFF"
            stateColor = "0xFFFFFF59"
            if m.serversOn[row.index] then
                state = "ON"
                stateColor = "0xFFE500FF"
            end if
        else if row.kind = "subtitles" then
            label = "SUBTITLES"
            detail = subtitleModeExplanation()
            state = subtitleModeLabel()
            stateColor = "0xFFFFFF59"
            if state <> "OFF" then stateColor = "0xFFE500FF"
        else
            label = "SIGN OUT OF PLEX"
            detail = "Forget this TV's Plex sign-in"
            if m.signOutArmed then
                label = "PRESS OK AGAIN TO SIGN OUT"
                detail = "Up, Down or BACK cancels"
            end if
            state = ""
            stateColor = "0xFFFFFFFF"
            accent = "0xFF6B6B"
        end if
        if focused then page.AppendChild(newRect(indent, y, 1680 - indent, 72, accent + "52"))
        if focused then
            page.AppendChild(newRect(indent, y, 8, 72, accent + "FF"))
        else
            page.AppendChild(newRect(indent, y, 4, 72, accent + "66"))
        end if
        nameColor = "0xFFFFFFBF"
        if focused then nameColor = "0xFFFFFFFF"
        page.AppendChild(newLabel(label, "DMMono-Medium", 24, nameColor, indent + 30, y + 10))
        page.AppendChild(newLabel(detail, "VT323-Regular", 24, "0xFFFFFF80", indent + 30, y + 40))
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
    if m.signOutArmed and key <> "OK" then
        m.signOutArmed = false
        render()
    end if
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
        row = m.rows[m.focus]
        if row.kind = "bundle" then
            id = m.top.bundles[row.index].id
            kept = []
            found = false
            for each x in m.enabled
                if x = id then found = true else kept.Push(x)
            end for
            if not found then kept.Push(id)
            m.enabled = kept
            m.changed = true
            buildRows()
            if m.focus > rowCount() - 1 then m.focus = rowCount() - 1
            render()
        else if row.kind = "franchiseAll" then
            ' setAllFranchises: one explicit choice for every row.
            turnOn = anyFranchiseOff()
            for each f in m.top.franchises
                NxFranchiseRecordChoice(m.choices, f.id, turnOn)
            end for
            m.franchisesChanged = true
            render()
        else if row.kind = "franchise" then
            NxFranchiseRecordChoice(m.choices, row.franchise.id, not franchiseOn(row.franchise))
            m.franchisesChanged = true
            render()
        else if row.kind = "server" then
            ' The last server on stays on, as upstream's picker keeps one.
            onCount = 0
            for each x in m.serversOn
                if x then onCount = onCount + 1
            end for
            if not m.serversOn[row.index] or onCount > 1 then
                m.serversOn[row.index] = not m.serversOn[row.index]
                m.serversChanged = true
                render()
            end if
        else if row.kind = "subtitles" then
            cycleSubtitleMode()
            render()
        else if m.signOutArmed then
            m.top.result = "signOut"
        else
            m.signOutArmed = true
            render()
        end if
        return true
    end if
    if key = "back" or key = "left" then
        if m.serversChanged then
            ' Every server's switch is saved, so a later default can't move it.
            choices = {}
            for i = 0 to m.servers.Count() - 1
                choices[NxToStr(m.servers[i].machineIdentifier)] = m.serversOn[i]
            end for
            plex = NxPlexRegistry()
            plex.Write("serverChoices", FormatJson(choices))
            plex.Flush()
        end if
        if m.changed or m.franchisesChanged or m.serversChanged then
            reg = CreateObject("roRegistrySection", "guide")
            if m.changed then reg.Write("bundles", FormatJson(m.enabled))
            if m.franchisesChanged then
                lists = NxFranchiseChoiceLists(m.choices)
                reg.Write("franchisesOn", FormatJson(lists.enabled))
                reg.Write("franchisesOff", FormatJson(lists.disabled))
            end if
            reg.Flush()
            m.top.result = "rebuild"
        else
            m.top.result = "close"
        end if
        return true
    end if
    return true
end function
