' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Layout, type and colour follow the Nostalgex Apple TV app's guide (see
' GuideView.xml). The grid follows its ChannelGuideView: a two-hour window
' from the current half hour, 425 px per 30 minutes, scrolled a slot at a
' time with left/right, up to 22 hours ahead.

sub init()
    m.colX = 220
    m.slotWidth = 425
    m.rowPitch = 81
    m.rowsVisible = 6
    m.windowSec = 7200
    m.focus = 0
    m.top0 = 0
    m.tuned = -1
    m.slotOffset = 0
    m.playing = invalid
    m.fullscreen = false
    m.fonts = {}

    styleLabel("logo", "VT323-Regular", 64, "0xF9E503FF")
    styleLabel("tag", "VT323-Regular", 36, "0xFFFFFFFF")
    styleLabel("title", "DMMono-Medium", 38, "0xFFFFFFFF")
    styleLabel("subtitle", "DMMono-Regular", 22, "0xFFFFFFB3")
    styleLabel("summary", "DMMono-Regular", 20, "0xFFFFFFA6")
    styleLabel("chip", "VT323-Regular", 24, "0xFFFFFFB3")
    styleLabel("clock", "VT323-Regular", 24, "0xFFFFFF8C")
    styleLabel("upNextLabel", "VT323-Regular", 24, "0xFFFFFF80")
    styleLabel("upNext", "DMMono-Regular", 18, "0xFFFFFFBF")
    styleLabel("channelHead", "DMMono-Medium", 18, "0xFFFFFFB3")
    styleLabel("hazeText", "DMMono-Medium", 26, "0xFFFFFF6B")
    styleLabel("bug", "VT323-Regular", 48, "0xFFFFFFFF")
    styleLabel("notice", "DMMono-Regular", 20, "0xFF6B6BFF")
    styleLabel("ccToast", "VT323-Regular", 48, "0xFFFFFFFF")

    m.video = m.top.FindNode("video")
    m.video.ObserveField("state", "onVideoState")
    m.video.ObserveField("bufferingStatus", "onBuffering")
    m.video.ObserveField("availableSubtitleTracks", "applySubtitles")
    m.subs = NxSubtitleSettings()
    m.hasSubs = false
    restoreCaptionMode()
    m.tick = CreateObject("roSGNode", "Timer")
    m.tick.repeat = true
    m.tick.duration = 1
    m.tick.ObserveField("fire", "onTick")
    m.lastWindow = 0
    reg = CreateObject("roRegistrySection", "player")
    m.stopUrl = reg.Read("stopUrl")
    m.stopServer = reg.Read("stopServer").ToInt()
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

sub styleLabel(id as String, font as String, size as Integer, color as String)
    lbl = m.top.FindNode(id)
    lbl.font = fontOf(font, size)
    lbl.color = color
end sub

function newLabel(text as String, font as String, size as Integer, color as String, x as Float, y as Float, width as Float) as Object
    lbl = CreateObject("roSGNode", "Label")
    lbl.text = text
    lbl.font = fontOf(font, size)
    lbl.color = color
    lbl.translation = [x, y]
    if width > 0 then lbl.width = width
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

sub onGuide()
    previous = m.channels
    m.channels = m.top.guide.channels
    if m.channels = invalid or m.channels.Count() = 0 then
        m.top.FindNode("notice").text = "NO CHANNELS AVAILABLE"
        return
    end if
    if previous = invalid then
        m.top.SetFocus(true)
        m.tick.control = "start"
        ' A launch deep link opens on its channel, fullscreen.
        linked = NxDeepLinkChannel(m.channels, m.top.deepLink)
        if linked >= 0 then
            m.focus = linked
            keepFocusVisible()
        end if
        renderGrid()
        if linked >= 0 then
            tune(linked)
            setFullscreen(true)
        else
            tune(0)
        end if
        return
    end if

    ' A refreshed guide (the library changed under the saved one): keep the
    ' tuned channel and focus by id, and retune only if what airs now changed.
    tunedId = invalid
    if m.tuned >= 0 and m.tuned < previous.Count() then tunedId = previous[m.tuned].id
    focusId = invalid
    if m.focus < previous.Count() then focusId = previous[m.focus].id
    m.tuned = 0
    m.focus = 0
    for i = 0 to m.channels.Count() - 1
        if m.channels[i].id = tunedId then m.tuned = i
        if m.channels[i].id = focusId then m.focus = i
    end for
    keepFocusVisible()
    renderGrid()
    renderInfo()
    now = blockAt(m.channels[m.tuned], nowSec())
    same = now <> invalid and m.playing <> invalid
    if same then same = now.ratingKey = m.playing.ratingKey and now.startSec = m.playing.startSec
    if not same then tune(m.tuned)
end sub

' ── Clock ───────────────────────────────────────────────────────────────────

function nowSec() as LongInteger
    dt = CreateObject("roDateTime")
    s& = dt.AsSeconds()
    return s&
end function

function localTimeLabel(epochSec as LongInteger) as String
    dt = CreateObject("roDateTime")
    dt.FromSeconds(epochSec)
    dt.ToLocalTime()
    h = dt.GetHours()
    ampm = "AM"
    if h >= 12 then ampm = "PM"
    h12 = h mod 12
    if h12 = 0 then h12 = 12
    mm = dt.GetMinutes()
    mmStr = mm.ToStr()
    if mm < 10 then mmStr = "0" + mmStr
    return h12.ToStr() + ":" + mmStr + " " + ampm
end function

' h:mm:ss, or m:ss under an hour.
function hms(sec as LongInteger) as String
    if sec < 0 then sec = 0
    h = sec \ 3600
    mm = (sec mod 3600) \ 60
    ss = sec mod 60
    out = ""
    if h > 0 then out = h.ToStr() + ":"
    if mm < 10 and h > 0 then out = out + "0"
    out = out + mm.ToStr() + ":"
    if ss < 10 then out = out + "0"
    return out + ss.ToStr()
end function

' ── Schedule lookups ────────────────────────────────────────────────────────

function blockAt(ch as Object, t as LongInteger) as Dynamic
    for each b in ch.blocks
        if t >= b.startSec and t < b.endSec then return b
    end for
    return invalid
end function

function blockAfter(ch as Object, b as Object) as Dynamic
    for each x in ch.blocks
        if x.startSec >= b.endSec then return x
    end for
    return invalid
end function

function colorOf(hex as String, alpha as String) as String
    h = hex.Replace("#", "")
    if h.Len() <> 6 then h = "FFFFFF"
    return "0x" + UCase(h) + alpha
end function

' ── Grid ────────────────────────────────────────────────────────────────────

function windowStart() as LongInteger
    t = nowSec()
    return (t \ 1800) * 1800 + m.slotOffset * 1800
end function

sub renderGrid()
    t = nowSec()
    wStart& = windowStart()
    wEnd& = wStart& + m.windowSec
    m.lastWindow = (t \ 1800) * 1800
    scale = (m.slotWidth * 4) / m.windowSec

    slots = m.top.FindNode("slots")
    slots.RemoveChildrenIndex(slots.GetChildCount(), 0)
    for i = 0 to 3
        x = m.colX + i * m.slotWidth
        slots.AppendChild(newRect(x, 0, 1, 60, "0xFFFFFF33"))
        slots.AppendChild(newLabel(localTimeLabel(wStart& + i * 1800), "DMMono-Medium", 20, "0xFFFFFFF2", x + 14, 17, 0))
    end for

    rows = m.top.FindNode("rows")
    rows.RemoveChildrenIndex(rows.GetChildCount(), 0)
    last = m.top0 + m.rowsVisible - 1
    if last > m.channels.Count() - 1 then last = m.channels.Count() - 1
    for idx = m.top0 to last
        rows.AppendChild(renderRow(idx, (idx - m.top0) * m.rowPitch, t, wStart&, wEnd&, scale))
    end for

    line = m.top.FindNode("nowLine")
    ' Floats throughout: LongInteger / Integer divides as integers (giving 0
    ' here), and node fields reject a Double.
    elapsed! = t - wStart&
    frac! = elapsed! / m.windowSec
    line.visible = frac! >= 0 and frac! <= 1
    x! = m.colX + frac! * m.slotWidth * 4
    line.translation = [x!, 0]
end sub

function renderRow(idx as Integer, y as Integer, t as LongInteger, wStart& as LongInteger, wEnd& as LongInteger, scale as Float) as Object
    ch = m.channels[idx]
    focused = idx = m.focus
    tuned = idx = m.tuned
    color = colorOf(ch.color, "FF")
    row = CreateObject("roSGNode", "Group")
    row.translation = [0, y]

    if focused then
        row.AppendChild(newRect(0, 0, 1920, 80, colorOf(ch.color, "52")))
    else if idx mod 2 = 0 then
        row.AppendChild(newRect(0, 0, 1920, 80, "0xFFFFFF08"))
    end if
    row.AppendChild(newRect(0, 80, 1920, 1, "0xFFFFFF14"))

    ' Programs, with the now-airing cell in the channel's colour.
    for each b in ch.blocks
        if b.endSec > wStart& and b.startSec < wEnd& then
            s& = b.startSec
            if s& < wStart& then s& = wStart&
            e& = b.endSec
            if e& > wEnd& then e& = wEnd&
            x = m.colX + 1 + (s& - wStart&) * scale
            w = (e& - s&) * scale
            onNow = t >= b.startSec and t < b.endSec
            past = b.endSec <= t
            if onNow then
                fill = colorOf(ch.color, "40")
                if focused then fill = colorOf(ch.color, "8C")
                row.AppendChild(newRect(x, 0, w, 80, fill))
            else if past then
                row.AppendChild(newRect(x, 0, w, 80, "0xFFFFFF05"))
            end if
            row.AppendChild(newRect(x, 0, 1, 80, "0xFFFFFF1F"))
            if w > 40 then
                tc = "0xFFFFFFD9"
                if onNow or focused then
                    tc = "0xFFFFFFFF"
                else if past then
                    tc = "0xFFFFFF80"
                end if
                row.AppendChild(newLabel(b.line, "DMMono-Medium", 20, tc, x + 14, 27, w - 28))
            end if
        end if
    end for

    ' Channel column, drawn over the programs' left edge.
    row.AppendChild(newRect(0, 0, m.colX, 80, "0x0D0D1FFF"))
    if focused then row.AppendChild(newRect(0, 0, m.colX, 80, colorOf(ch.color, "52")))
    if focused or tuned then
        row.AppendChild(newRect(0, 0, 8, 80, color))
    else
        row.AppendChild(newRect(0, 0, 4, 80, colorOf(ch.color, "66")))
    end if
    row.AppendChild(newRect(m.colX, 0, 1, 80, "0xFFFFFF26"))
    numColor = color
    nameColor = colorOf(ch.color, "F2")
    if focused then
        numColor = "0xFFFFFFFF"
        nameColor = "0xFFFFFFFF"
    end if
    x = 16
    if tuned then
        ' The live badge: upstream's bolt, as a small block in the channel colour.
        row.AppendChild(newRect(x, 28, 14, 24, color))
        row.AppendChild(newRect(x + 5, 33, 4, 14, "0x000000F2"))
        x = x + 20
    end if
    num = newLabel(ch.number.ToStr(), "DMMono-Medium", 20, numColor, x, 27, 36)
    num.horizAlign = "right"
    row.AppendChild(num)
    row.AppendChild(newLabel(UCase(ch.name), "DMMono-Medium", 18, nameColor, x + 44, 29, m.colX - x - 52))

    if focused then
        ' 3 px outline in the channel colour, inset 2 px.
        row.AppendChild(newRect(2, 2, 1916, 3, color))
        row.AppendChild(newRect(2, 75, 1916, 3, color))
        row.AppendChild(newRect(2, 2, 3, 76, color))
        row.AppendChild(newRect(1915, 2, 3, 76, color))
    end if
    return row
end function

' ── Info panel: follows focus; for the tuned channel, what is playing ───────

sub renderInfo()
    if m.channels = invalid then return
    ch = m.channels[m.focus]
    t = nowSec()
    b = blockAt(ch, t)
    if m.focus = m.tuned and m.playing <> invalid then b = m.playing
    color = colorOf(ch.color, "FF")
    num = ch.number.ToStr()
    if ch.number < 10 then num = "0" + num
    m.top.FindNode("tag").text = "CH " + num + " — " + UCase(ch.name)
    m.top.FindNode("tag").color = color
    m.top.FindNode("rule").color = colorOf(ch.color, "4D")
    m.top.FindNode("progressFill").color = color

    title = m.top.FindNode("title")
    subtitle = m.top.FindNode("subtitle")
    if b = invalid then
        title.text = "Nothing scheduled"
        subtitle.text = ""
        m.top.FindNode("summary").text = ""
        m.top.FindNode("meta").visible = false
        m.top.FindNode("upNext").text = ""
        return
    end if
    title.text = b.title
    subLine = ""
    if NxTruthy(b.episodeTitle) then
        if b.seasonNumber <> invalid and b.episodeNumber <> invalid then subLine = "S" + NxToStr(b.seasonNumber) + "E" + NxToStr(b.episodeNumber) + "  "
        subLine = subLine + b.episodeTitle
    end if
    subtitle.text = subLine

    ' Stack the panel: title (1-2 lines), subtitle, rule, summary, meta, up next.
    y = 48 + title.boundingRect().height + 10
    if subLine <> "" then
        subtitle.translation = [0, y]
        y = y + 32
    end if
    y = y + 10
    m.top.FindNode("rule").translation = [0, y]
    y = y + 21
    summary = m.top.FindNode("summary")
    summary.text = b.summary
    summary.translation = [0, y]
    if b.summary <> "" then y = y + summary.boundingRect().height + 20

    meta = m.top.FindNode("meta")
    meta.visible = true
    meta.translation = [0, y]
    chip = m.top.FindNode("chip")
    chip.text = b.year
    x = 0
    if b.year <> "" then
        cw = chip.boundingRect().width + 24
        m.top.FindNode("chipBorder").width = cw
        m.top.FindNode("chipFill").width = cw - 2
        x = cw + 14
    end if
    m.top.FindNode("chipBorder").visible = b.year <> ""
    m.top.FindNode("chipFill").visible = b.year <> ""
    clock = m.top.FindNode("clock")
    dur& = b.endSec - b.startSec
    pos& = t - b.startSec
    clock.text = hms(pos&) + " / " + hms(dur&)
    clock.translation = [1100 - 220, 2]
    track = m.top.FindNode("progressTrack")
    barW = 1100 - 220 - 10 - x
    track.translation = [x, 15]
    track.width = barW
    fill = m.top.FindNode("progressFill")
    fill.translation = [x, 15]
    if dur& > 0 then fill.width = barW * pos& / dur& else fill.width = 0

    y = y + 54
    n = blockAfter(ch, b)
    m.top.FindNode("upNextLabel").translation = [0, y]
    m.top.FindNode("upNextLabel").visible = n <> invalid
    up = m.top.FindNode("upNext")
    up.translation = [120, y + 3]
    if n <> invalid then up.text = n.line else up.text = ""
end sub

sub onTick()
    renderInfo()
    t = nowSec()
    if (t \ 1800) * 1800 <> m.lastWindow or t mod 30 = 0 then renderGrid()
    ' Live: when the airing ends, the channel moves on to whatever is on now.
    if m.playing <> invalid and t >= m.playing.endSec then tune(m.tuned)
end sub

' ── Playback ────────────────────────────────────────────────────────────────

' Plex refuses a second transcode for the same device while one runs (HTTP
' 400), so the running one is stopped first and the channel starts when the
' stop has gone through.
sub tune(idx as Integer)
    if m.stopUrl <> invalid and m.stopUrl <> "" then
        m.pendingTune = idx
        stopPrevious()
        return
    end if
    startTune(idx)
end sub

sub startTune(idx as Integer)
    m.tuned = idx
    ch = m.channels[idx]
    t = nowSec()
    b = blockAt(ch, t)
    m.top.FindNode("notice").text = ""
    armHaze()
    renderInfo()
    renderGrid()
    if b = invalid then
        m.playing = invalid
        m.video.control = "stop"
        return
    end if
    stream = NxPlexStreamContent(b, t - b.startSec)
    if stream = invalid then
        m.top.FindNode("notice").text = "Can't play this one: its server isn't set up on this TV."
        return
    end if
    m.playing = b
    m.stopUrl = stream.stopUrl
    m.stopServer = b.serverIndex
    rememberStop()
    NxPlexApplyAuth(m.video, NxPlexStreamToken(b))
    m.video.content = stream.content
    m.video.control = "play"
    print "player: tuned channel "; ch.id; ", "; stream.content.streamFormat; " stream over "; stream.route
end sub

sub onBuffering()
    st = m.video.bufferingStatus
    if st <> invalid then print "player: buffering "; st.percentage; "%"
end sub

' Release the transcode the last airing started, so the NAS stops working
' on a channel nobody is watching.
sub stopPrevious()
    if m.stopUrl = invalid or m.stopUrl = "" then return
    m.video.control = "stop"
    m.stopTask = CreateObject("roSGNode", "PlexStopTask")
    m.stopTask.stopUrl = m.stopUrl
    m.stopTask.serverIndex = m.stopServer
    m.stopTask.ObserveField("state", "onStopDone")
    m.stopTask.control = "run"
    m.stopUrl = ""
    rememberStop()
end sub

sub onStopDone()
    if m.stopTask.state <> "stop" then return
    if m.pendingTune <> invalid then
        idx = m.pendingTune
        m.pendingTune = invalid
        startTune(idx)
    end if
end sub

' The running transcode's stop address (no token in it), kept across
' launches: a transcode left running by the last launch blocks this one's.
sub rememberStop()
    reg = CreateObject("roRegistrySection", "player")
    if m.stopUrl = invalid or m.stopUrl = "" then
        reg.Delete("stopUrl")
    else
        reg.Write("stopUrl", m.stopUrl)
        reg.Write("stopServer", m.stopServer.ToStr())
    end if
    reg.Flush()
end sub

sub onVideoState()
    state = m.video.state
    print "player: "; state
    if state = "playing" then
        m.retried = false
        m.top.FindNode("haze").visible = false
        applySubtitles()
    end if
    if state = "error" then
        print "player: error "; m.video.errorCode; " "; m.video.errorMsg
        e = m.video.errorInfo
        if e <> invalid then print "player: error category "; e.category; " code "; e.errcode; " source "; e.source
        ' One retry, as upstream retries a failed start: Plex can refuse a
        ' stream for a moment while the last one is still winding down.
        if m.retried <> true and m.tuned >= 0 then
            m.retried = true
            m.retryTimer = CreateObject("roSGNode", "Timer")
            m.retryTimer.duration = 3
            m.retryTimer.ObserveField("fire", "onRetry")
            m.retryTimer.control = "start"
            return
        end if
        m.top.FindNode("notice").text = "Playback failed: " + m.video.errorMsg
    end if
end sub

sub onRetry()
    print "player: retrying"
    tune(m.tuned)
end sub

sub setFullscreen(on as Boolean)
    m.fullscreen = on
    m.top.FindNode("panel").visible = not on
    m.top.FindNode("grid").visible = not on
    m.top.FindNode("videoBg").visible = not on
    if on then
        m.video.translation = [0, 0]
        m.video.width = 1920
        m.video.height = 1080
        showBug()
    else
        m.video.translation = [1180, 0]
        m.video.width = 740
        m.video.height = 555
        m.top.FindNode("bug").visible = false
        m.top.FindNode("ccToast").visible = false
    end if
    positionHaze()
    applySubtitles()
end sub

' ── Subtitles ───────────────────────────────────────────────────────────────

' Upstream's applySubtitleSelection: shown in fullscreen only, never over the
' guide; always when SUBTITLES is ALWAYS, and with FOREIGN AUDIO only when no
' audio track is in the TV's language and the subtitles are. Upstream also
' shows forced subtitles when they're off; Roku doesn't say which are forced.
sub applySubtitles()
    tracks = NxList(m.video.availableSubtitleTracks)
    m.hasSubs = tracks.Count() > 0
    show = false
    if m.fullscreen and m.hasSubs then
        want = NxSubPreferredLanguage()
        tags = []
        for each t in tracks
            tags.Push(NxSubComparableTag(t.Language))
        end for
        idx = NxSubPreferredTrackIndex(tags, want)
        if m.subs.always then
            show = true
        else if m.subs.foreign then
            audio = []
            for each a in NxList(m.video.availableAudioTracks)
                audio.Push(NxSubComparableTag(a.Language))
            end for
            ' Wrong-language subtitles are worse than none, as upstream says.
            if NxSubShouldAutoEnable(audio, want) and tags[idx] <> invalid then
                show = NxSubMatches(tags[idx], want)
            end if
        end if
        if show then m.video.subtitleTrack = tracks[idx].TrackName
    end if
    setCaptions(show)
end sub

' Roku draws subtitles only while its caption mode is on, and that mode is the
' TV's own setting. When it is off, it is turned on just while subtitles show
' and put back afterwards. The old value is saved first, so a launch after
' leaving with Home puts it back too.
sub setCaptions(show as Boolean)
    m.video.suppressCaptions = not show
    reg = CreateObject("roRegistrySection", "player")
    if show and m.video.globalCaptionMode <> "On" then
        if not reg.Exists("captionModeBefore") then
            reg.Write("captionModeBefore", m.video.globalCaptionMode)
            reg.Flush()
        end if
        m.video.globalCaptionMode = "On"
    else if not show then
        restoreCaptionMode()
    end if
    tracks = NxList(m.video.availableSubtitleTracks)
    print "player: subtitles "; show; " (tracks "; tracks.Count(); ", caption mode "; m.video.globalCaptionMode; ")"
end sub

sub restoreCaptionMode()
    reg = CreateObject("roRegistrySection", "player")
    if not reg.Exists("captionModeBefore") then return
    m.video.globalCaptionMode = reg.Read("captionModeBefore")
    reg.Delete("captionModeBefore")
    reg.Flush()
end sub

' The CC control of upstream's Now Playing panel, on the * key in fullscreen:
' flips ALWAYS, and says NONE when the airing has no subtitles.
sub toggleCaptions()
    text = "CC  NONE"
    if m.hasSubs then
        m.subs.always = not m.subs.always
        NxSaveSubtitleSettings(m.subs)
        applySubtitles()
        text = "CC  OFF"
        if m.subs.always then text = "CC  ON"
    end if
    toast = m.top.FindNode("ccToast")
    toast.text = text
    toast.visible = true
    if m.toastTimer = invalid then
        m.toastTimer = CreateObject("roSGNode", "Timer")
        m.toastTimer.duration = 3
        m.toastTimer.ObserveField("fire", "onToastTimer")
    end if
    m.toastTimer.control = "stop"
    m.toastTimer.control = "start"
end sub

sub onToastTimer()
    m.top.FindNode("ccToast").visible = false
end sub

' The channel bug, bottom left, in full screen only.
sub showBug()
    if m.tuned < 0 then return
    ch = m.channels[m.tuned]
    bug = m.top.FindNode("bug")
    bug.text = "CH " + ch.number.ToStr() + "  " + UCase(ch.name)
    bug.color = colorOf(ch.color, "FF")
    bug.visible = true
    if m.bugTimer = invalid then
        m.bugTimer = CreateObject("roSGNode", "Timer")
        m.bugTimer.duration = 5
        m.bugTimer.ObserveField("fire", "onBugTimer")
    end if
    m.bugTimer.control = "stop"
    m.bugTimer.control = "start"
end sub

sub onBugTimer()
    m.top.FindNode("bug").visible = false
end sub

' ── Tuning haze: shown when a channel takes more than 0.75 s to start ───────

sub positionHaze()
    bg = m.top.FindNode("hazeBg")
    txt = m.top.FindNode("hazeText")
    if m.fullscreen then
        bg.translation = [0, 0]
        bg.width = 1920
        bg.height = 1080
        txt.translation = [0, 520]
        txt.width = 1920
    else
        bg.translation = [1180, 0]
        bg.width = 740
        bg.height = 555
        txt.translation = [1180, 258]
        txt.width = 740
    end if
end sub

sub armHaze()
    if m.hazeTimer = invalid then
        m.hazeTimer = CreateObject("roSGNode", "Timer")
        m.hazeTimer.duration = 0.75
        m.hazeTimer.ObserveField("fire", "onHazeTimer")
    end if
    m.hazeTimer.control = "stop"
    m.hazeTimer.control = "start"
end sub

sub onHazeTimer()
    if m.video.state = "playing" or m.tuned < 0 then return
    m.top.FindNode("hazeText").text = "TUNING · CH " + m.channels[m.tuned].number.ToStr()
    positionHaze()
    m.top.FindNode("haze").visible = true
end sub

' ── Packages sidebar (Left on the live slot), as the Apple TV app's ─────────

sub openSidebar()
    m.sideTargets = [{ name: "SETTINGS", channel: -1, color: "#FFE500" }]
    for each b in m.top.guide.bundles
        if NxHasValue(m.top.guide.enabledBundles, b.id) then
            ' FRANCHISES jumps to a found franchise when no classic is shown.
            ids = b.channelIDs
            if b.jumpIDs <> invalid then ids = b.jumpIDs
            for i = 0 to m.channels.Count() - 1
                if NxHasValue(ids, m.channels[i].id) then
                    m.sideTargets.Push({ name: b.name, channel: i, color: m.channels[i].color })
                    exit for
                end if
            end for
        end if
    end for
    m.sideFocus = 1
    if m.sideTargets.Count() = 1 then m.sideFocus = 0
    m.sidebarOpen = true
    renderSidebar()
end sub

sub renderSidebar()
    side = m.top.FindNode("sidebar")
    side.RemoveChildrenIndex(side.GetChildCount(), 0)
    side.AppendChild(newRect(0, 0, 380, 525, "0x0A0A14F7"))
    side.AppendChild(newRect(380, 0, 1, 525, "0xFFFFFF26"))
    side.AppendChild(newLabel("PACKAGES", "DMMono-Medium", 22, "0xFFFFFF99", 24, 18, 0))
    first = m.sideFocus - 4
    if first < 0 then first = 0
    y = 64
    for i = first to m.sideTargets.Count() - 1
        if y > 525 - 72 then exit for
        t = m.sideTargets[i]
        focused = i = m.sideFocus
        color = colorOf(t.color, "FF")
        if focused then side.AppendChild(newRect(0, y, 380, 72, colorOf(t.color, "52")))
        if focused then side.AppendChild(newRect(0, y, 8, 72, color)) else side.AppendChild(newRect(0, y, 4, 72, colorOf(t.color, "66")))
        tc = "0xFFFFFFBF"
        if focused then tc = "0xFFFFFFFF"
        side.AppendChild(newLabel(t.name, "DMMono-Medium", 24, tc, 26, y + 22, 340))
        y = y + 74
        if i = 0 then
            side.AppendChild(newRect(16, y, 348, 1, "0xFFFFFF1A"))
            y = y + 7
        end if
    end for
    side.visible = true
end sub

sub closeSidebar()
    m.sidebarOpen = false
    m.top.FindNode("sidebar").visible = false
end sub

function sidebarKey(key as String) as Boolean
    if key = "down" and m.sideFocus < m.sideTargets.Count() - 1 then
        m.sideFocus = m.sideFocus + 1
        renderSidebar()
    else if key = "up" and m.sideFocus > 0 then
        m.sideFocus = m.sideFocus - 1
        renderSidebar()
    else if key = "right" or key = "back" then
        closeSidebar()
    else if key = "OK" then
        t = m.sideTargets[m.sideFocus]
        closeSidebar()
        if t.channel < 0 then
            openSettings()
        else
            m.focus = t.channel
            keepFocusVisible()
            renderGrid()
            renderInfo()
        end if
    end if
    return true
end function

sub openSettings()
    m.settings = CreateObject("roSGNode", "SettingsView")
    m.settings.bundles = m.top.guide.bundles
    m.settings.enabledBundles = m.top.guide.enabledBundles
    franchises = m.top.guide.franchises
    if franchises = invalid then franchises = []
    m.settings.franchises = franchises
    collections = m.top.guide.collections
    if collections = invalid then collections = { rows: [], overCap: 0, scanned: 0, failed: 0 }
    m.settings.collections = collections
    m.settings.ObserveField("result", "onSettingsResult")
    m.top.AppendChild(m.settings)
    m.settings.callFunc("open", invalid)
end sub

sub onSettingsResult()
    result = m.settings.result
    m.top.RemoveChild(m.settings)
    m.settings = invalid
    linkWaiting = m.linkAfterSettings = true
    m.linkAfterSettings = false
    m.top.SetFocus(true)
    m.subs = NxSubtitleSettings()
    applySubtitles()
    if result = "rebuild" or result = "signOut" then
        stopPrevious()
        m.tick.control = "stop"
        m.top.action = result
    else if linkWaiting then
        applyDeepLink()
    end if
end sub

' ── Deep links ──────────────────────────────────────────────────────────────

' A link that comes before the first guide is read by onGuide. One that comes
' while Settings is open waits for it to close; if Settings rebuilds the
' guide, the link is dropped with it.
sub onDeepLink()
    if m.channels = invalid then return
    if m.settings <> invalid then
        m.linkAfterSettings = true
        return
    end if
    applyDeepLink()
end sub

sub applyDeepLink()
    idx = NxDeepLinkChannel(m.channels, m.top.deepLink)
    if idx < 0 then return
    if m.sidebarOpen = true then closeSidebar()
    m.focus = idx
    m.slotOffset = 0
    keepFocusVisible()
    if idx <> m.tuned then
        tune(idx)
    else
        renderGrid()
        renderInfo()
    end if
    setFullscreen(true)
end sub

' ── Remote ──────────────────────────────────────────────────────────────────

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press or m.channels = invalid then return false
    if m.sidebarOpen = true then return sidebarKey(key)
    if m.fullscreen then
        if key = "back" or key = "OK" then
            setFullscreen(false)
            return true
        end if
        if key = "up" or key = "down" then
            ' Channel up/down while watching, as on a TV.
            d = 1
            if key = "up" then d = -1
            idx = (m.tuned + d + m.channels.Count()) mod m.channels.Count()
            m.focus = idx
            keepFocusVisible()
            tune(idx)
            showBug()
            return true
        end if
        if key = "options" then
            toggleCaptions()
            return true
        end if
        return false
    end if
    if key = "up" or key = "down" then
        ' Down off the last channel wraps to channel one; Up off channel one
        ' does not (source/guide/GuideNav.brs).
        idx = NxGuideStep(m.focus, m.channels.Count(), key)
        if idx < 0 then return false
        m.focus = idx
        keepFocusVisible()
        renderGrid()
        renderInfo()
        return true
    end if
    if key = "right" and m.slotOffset < 44 then
        m.slotOffset = m.slotOffset + 1
        renderGrid()
        return true
    end if
    if key = "left" and m.slotOffset > 0 then
        m.slotOffset = m.slotOffset - 1
        renderGrid()
        return true
    end if
    if key = "left" then
        openSidebar()
        return true
    end if
    if key = "OK" then
        if m.focus = m.tuned then setFullscreen(true) else tune(m.focus)
        return true
    end if
    if key = "play" then
        setFullscreen(true)
        return true
    end if
    if key = "back" and (m.focus <> m.tuned or m.slotOffset <> 0) then
        ' Back returns to the live channel, as Menu does on Apple TV.
        m.focus = m.tuned
        m.slotOffset = 0
        keepFocusVisible()
        renderGrid()
        renderInfo()
        return true
    end if
    return false
end function

sub keepFocusVisible()
    ' Keep the focused row away from the edges, as tvOS centres it.
    want = m.focus - 2
    if want < 0 then want = 0
    maxTop = m.channels.Count() - m.rowsVisible
    if maxTop < 0 then maxTop = 0
    if want > maxTop then want = maxTop
    m.top0 = want
end sub
