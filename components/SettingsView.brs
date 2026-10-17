' Copyright (c) 2026 nostalgex-roku contributors, MIT License.

sub init()
    m.focus = 0
    m.scroll = 0
    ' The list's height on the page, under the SETTINGS title.
    m.listTop = 100
    m.listH = 800
    m.fonts = {}
    m.changed = false
    m.franchisesChanged = false
    ' The first OK on SIGN OUT OF PLEX only arms it; a second one signs out.
    m.signOutArmed = false
    m.collectionsChanged = false
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
' on (upstream's BundleManagerView), then RETRO MODE and subtitles (its
' PLAYBACK section), then sign-out.
sub open(unused = invalid as Dynamic)
    m.enabled = []
    m.enabled.Append(m.top.enabledBundles)
    m.subs = NxSubtitleSettings()
    m.choices = NxSavedFranchiseChoices()
    m.collectionKeys = NxSavedCollectionKeys()
    reg = NxPlexRegistry()
    m.servers = ParseJson(reg.Read("servers"))
    if type(m.servers) <> "roArray" then m.servers = []
    m.serversOn = NxServersOn(m.servers, NxSavedServerChoices())
    m.serversChanged = false
    m.collectionsOpen = false
    buildRows()
    m.focus = nextFocusable(-1, 1)
    m.scroll = 0
    m.top.SetFocus(true)
    render()
end sub

' The row list, in the order of upstream's SettingsPageView
' (Views/BundleManagerView.swift): SUPPORT NOSTALGEX, CONNECTION (the servers,
' then sign-out), PLAYBACK, CHANNEL PACKAGES, then MY COLLECTIONS folded
' closed behind one SHOW/HIDE row, as its CollectionAccordionHeaderRow. Kinds:
'   header, subheader, info: text only, never focused
'   support, server, signOut, retro, subtitles, bundle, franchiseAll,
'   franchise, collectionsToggle, collection: rows
' The franchise rows are the last guide build's, so they show once the
' package was on for a build. Every collection here is upstream's "custom"
' category: the franchise ones fold into FRANCHISES.
sub buildRows()
    m.rows = []
    m.rows.Push({ kind: "header", title: "SUPPORT NOSTALGEX", subtitle: "News, help and the Apple TV app are on its site" })
    m.rows.Push({ kind: "support" })

    m.rows.Push({ kind: "header", title: "CONNECTION", subtitle: "" })
    m.rows.Push({ kind: "subheader", text: "SERVERS" })
    for i = 0 to m.servers.Count() - 1
        m.rows.Push({ kind: "server", index: i })
    end for
    m.rows.Push({ kind: "signOut" })

    m.rows.Push({ kind: "header", title: "PLAYBACK", subtitle: "Picture and subtitles" })
    m.rows.Push({ kind: "retro" })
    m.rows.Push({ kind: "subtitles" })

    m.rows.Push({ kind: "header", title: "CHANNEL PACKAGES", subtitle: "Toggle packages to customize your lineup" })
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

    m.rows.Push({ kind: "header", title: "MY COLLECTIONS", subtitle: "Turn the server collections you want into channels, from CH 500" })
    c = m.top.collections
    rows = []
    if c <> invalid then rows = NxList(c.rows)
    note = collectionsNote()
    if note <> "" then m.rows.Push({ kind: "info", text: note })
    if rows.Count() > 0 then
        m.rows.Push({ kind: "collectionsToggle" })
        if m.collectionsOpen = true then
            for each row in rows
                m.rows.Push({ kind: "collection", collection: row })
            end for
        end if
    end if
end sub

function focusable(row as Object) as Boolean
    return row.kind <> "header" and row.kind <> "subheader" and row.kind <> "info" and row.kind <> "support"
end function

' The next row focus can land on from i, going d (1 or -1); i if none.
function nextFocusable(i as Integer, d as Integer) as Integer
    j = i + d
    while j >= 0 and j < rowCount()
        if focusable(m.rows[j]) then return j
        j = j + d
    end while
    return i
end function

function rowHeight(row as Object) as Integer
    if row.kind = "header" then
        if row.subtitle = "" then return 84
        return 112
    end if
    if row.kind = "subheader" or row.kind = "info" then return 44
    return 74
end function

function rowCount() as Integer
    return m.rows.Count()
end function

' A row's switch: the viewer's choice since the last build, else the build's.
function franchiseOn(f as Object) as Boolean
    if m.choices.enabled.DoesExist(f.id) then return true
    if m.choices.disabled.DoesExist(f.id) then return false
    return f.enabled
end function

function collectionOn(row as Object) as Boolean
    return m.collectionKeys.DoesExist(row.id)
end function

' A line under MY COLLECTIONS when there is something to say beyond the
' accordion's count: none found, a read that failed, or channels past CH 699.
function collectionsNote() as String
    c = m.top.collections
    if c = invalid then return ""
    rows = NxList(c.rows)
    if NxNumberOr0(c.failed) > 0 and rows.Count() = 0 then return "COULD NOT READ COLLECTIONS FROM YOUR SERVER"
    if rows.Count() = 0 then
        if NxNumberOr0(c.scanned) > 0 then return "NO COLLECTIONS WITH 3 OR MORE MOVIES OR EPISODES"
        return "Your server's collections show here after the library is read"
    end if
    if NxNumberOr0(c.overCap) > 0 then return c.overCap.ToStr() + " SWITCHED ON PAST CH 699, NOT ON AIR"
    return ""
end function

' The accordion's "n/m ON AIR", counting this visit's switches.
function collectionsOnAir() as String
    rows = NxList(m.top.collections.rows)
    onAir = 0
    for each row in rows
        if collectionOn(row) then onAir = onAir + 1
    end for
    return onAir.ToStr() + "/" + rows.Count().ToStr() + " ON AIR"
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

    ' Where each row sits in the whole list, then a scroll that keeps the
    ' focused row in view, with the headings just above it when they fit.
    tops = []
    y = 0
    for each row in m.rows
        tops.Push(y)
        y = y + rowHeight(row)
    end for
    top = tops[m.focus]
    bottom = top + rowHeight(m.rows[m.focus])
    k = m.focus - 1
    while k >= 0 and not focusable(m.rows[k]) and bottom - tops[k] <= m.listH
        top = tops[k]
        k = k - 1
    end while
    if top < m.scroll then m.scroll = top
    if bottom > m.scroll + m.listH then m.scroll = bottom - m.listH

    for i = 0 to rowCount() - 1
        row = m.rows[i]
        rt = tops[i]
        if rt >= m.scroll and rt + rowHeight(row) <= m.scroll + m.listH then
            y = m.listTop + rt - m.scroll
            if row.kind = "header" then
                ' A thin divider between sections, as settingsDivider.
                if i > 0 then page.AppendChild(newRect(0, y + 8, 1680, 1, "0xFFFFFF0F"))
                page.AppendChild(newLabel(row.title, "DMMono-Medium", 28, "0xFFFFFFCC", 0, y + 28))
                if row.subtitle <> "" then page.AppendChild(newLabel(row.subtitle, "DMMono-Regular", 20, "0xFFFFFFB3", 0, y + 68))
            else if row.kind = "subheader" or row.kind = "info" then
                page.AppendChild(newLabel(row.text, "DMMono-Regular", 20, "0xFFFFFFB3", 0, y + 8))
            else if row.kind = "support" then
                page.AppendChild(newLabel("NOSTALGEX.APP", "DMMono-Medium", 24, "0xFFFFFFBF", 30, y + 10))
                page.AppendChild(newLabel("Open it on a phone or computer", "VT323-Regular", 24, "0xFFFFFF80", 30, y + 40))
                page.AppendChild(newRect(0, y, 4, 72, "0xFFE50066"))
            else
                drawRow(page, i, row, y)
            end if
        end if
    end for
    page.AppendChild(newLabel("OK toggles · BACK returns to the guide", "DMMono-Regular", 20, "0xFFFFFF59", 0, m.listTop + m.listH + 24))
end sub

function serversOnCount() as Integer
    n = 0
    for each x in m.serversOn
        if x then n = n + 1
    end for
    return n
end function

sub drawRow(page as Object, i as Integer, row as Object, y as Float)
    focused = i = m.focus
    accent = "0xFFE500"
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
    else if row.kind = "collectionsToggle" then
        label = "OTHER COLLECTIONS"
        detail = "Actors, directors and your own themed sets · " + collectionsOnAir()
        if m.collectionsChanged then detail = "Changes air when you go back to the guide · " + collectionsOnAir()
        state = "SHOW"
        if m.collectionsOpen = true then state = "HIDE"
        stateColor = "0xFFE500FF"
    else if row.kind = "collection" then
        indent = 40
        cr = row.collection
        label = cr.title
        detail = cr.detail
        if cr.channelNumber <> invalid then detail = detail + " · CH " + cr.channelNumber.ToStr()
        state = "OFF"
        stateColor = "0xFFFFFF59"
        if collectionOn(cr) then
            state = "ON"
            stateColor = "0xFFE500FF"
        end if
    else if row.kind = "server" then
        ' Upstream's server rows: INCLUDED or OFF, and no switch on the
        ' only server that is on, which can't be turned off.
        s = m.servers[row.index]
        label = UCase(NxToStr(s.name))
        detail = "Shared with you"
        if NxTruthy(s.owned) then detail = "Your server"
        state = "OFF"
        stateColor = "0xFFFFFF59"
        if m.serversOn[row.index] then
            state = "INCLUDED"
            stateColor = "0xFFE500FF"
            if serversOnCount() <= 1 then
                detail = detail + " · only connected server"
                state = ""
            end if
        end if
    else if row.kind = "retro" then
        label = "RETRO MODE"
        detail = "CRT scanlines, vignette, VHS glitch, 4:3 aspect ratio"
        state = "OFF"
        stateColor = "0xFFFFFF59"
        if NxRetroMode() then
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
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if m.signOutArmed and key <> "OK" then
        m.signOutArmed = false
        render()
    end if
    if key = "down" or key = "up" then
        d = 1
        if key = "up" then d = -1
        m.focus = nextFocusable(m.focus, d)
        ' Up from the first row shows the headings above it again.
        if key = "up" and nextFocusable(m.focus, -1) = m.focus then m.scroll = 0
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
        else if row.kind = "collection" then
            ' toggleCollection: switch one on and it airs from CH 500.
            id = row.collection.id
            if m.collectionKeys.DoesExist(id) then m.collectionKeys.Delete(id) else m.collectionKeys[id] = true
            m.collectionsChanged = true
            render()
        else if row.kind = "collectionsToggle" then
            m.collectionsOpen = not (m.collectionsOpen = true)
            buildRows()
            render()
        else if row.kind = "server" then
            ' The last server on stays on, as upstream's picker keeps one.
            if not m.serversOn[row.index] or serversOnCount() > 1 then
                m.serversOn[row.index] = not m.serversOn[row.index]
                m.serversChanged = true
                render()
            end if
        else if row.kind = "retro" then
            NxSaveRetroMode(not NxRetroMode())
            render()
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
        if m.changed or m.franchisesChanged or m.collectionsChanged or m.serversChanged then
            reg = CreateObject("roRegistrySection", "guide")
            if m.changed then reg.Write("bundles", FormatJson(m.enabled))
            if m.franchisesChanged then
                lists = NxFranchiseChoiceLists(m.choices)
                reg.Write("franchisesOn", FormatJson(lists.enabled))
                reg.Write("franchisesOff", FormatJson(lists.disabled))
            end if
            reg.Flush()
            if m.collectionsChanged then NxSaveCollectionKeys(m.collectionKeys)
            m.top.result = "rebuild"
        else
            m.top.result = "close"
        end if
        return true
    end if
    return true
end function
