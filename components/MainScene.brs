' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Start-up: when this TV is already signed in, the saved guide goes up at
' once (LibraryTask, useCache) while sign-in is rechecked and the library is
' re-read in the background, as upstream shows its cached library first.
' Otherwise: sign in, then load.

sub init()
    m.prompt = m.top.FindNode("prompt")
    m.code = m.top.FindNode("code")
    m.hint = m.top.FindNode("hint")
    m.top.SetFocus(true)
    if NxPlexLoadToken() <> "" and NxPlexRegistry().Read("servers") <> "" then startLibrary(true)
    startSignIn()
end sub

sub startSignIn()
    m.code.text = ""
    m.prompt.text = "Connecting to Plex…"
    m.hint.text = ""
    m.signIn = CreateObject("roSGNode", "PlexSignInTask")
    m.signIn.ObserveField("status", "onSignInState")
    m.signIn.control = "run"
end sub

sub onSignInState()
    state = m.signIn.status
    m.code.text = ""
    if state = "checking" then
        m.prompt.text = "Checking your Plex sign-in…"
        m.hint.text = ""
    else if state = "code" then
        ' The saved sign-in was rejected: nothing saved stays on screen.
        dropGuide()
        m.prompt.text = "On your phone or computer, go to plex.tv/link and enter this code:"
        m.code.text = m.signIn.code
        m.hint.text = "The code refreshes every few minutes."
        signInShown()
    else if state = "discovering" then
        m.prompt.text = "Signed in as " + m.signIn.account + ". Finding your Plex servers…"
        m.hint.text = ""
        signInDone()
    else if state = "ready" then
        m.prompt.text = m.signIn.message
        m.hint.text = "Press * to sign out of Plex on this TV."
        if m.library = invalid then startLibrary(true)
    else if state = "error" then
        ' A saved guide stays up through a network blip.
        m.prompt.text = m.signIn.message
        m.hint.text = "Press * to sign out of Plex on this TV."
        launchComplete()
    end if
end sub

' Roku certification times each launch to the AppLaunchComplete beacon, sent
' once, when the guide or an error that OK retries is first on screen. A
' plex.tv/link sign-in before that is a login dialog: AppDialogInitiate when
' its code shows, AppDialogComplete when sign-in finishes, so the time spent
' at a phone isn't counted as launch time.
sub signInShown()
    if m.launched = true or m.inSignIn = true then return
    m.inSignIn = true
    m.top.signalBeacon("AppDialogInitiate")
end sub

sub signInDone()
    if m.inSignIn <> true then return
    m.inSignIn = false
    m.top.signalBeacon("AppDialogComplete")
end sub

sub launchComplete()
    if m.launched = true then return
    signInDone()
    m.launched = true
    m.top.signalBeacon("AppLaunchComplete")
end sub

sub startLibrary(useCache = false as Boolean)
    m.library = CreateObject("roSGNode", "LibraryTask")
    m.library.useCache = useCache
    m.library.ObserveField("progress", "onLibraryProgress")
    m.library.ObserveField("status", "onLibraryStatus")
    m.library.control = "run"
end sub

sub onLibraryProgress()
    if m.guide = invalid then m.prompt.text = m.library.progress
end sub

sub onLibraryStatus()
    status = m.library.status
    if status = "error" then
        if m.guide <> invalid then return
        m.prompt.text = m.library.message
        m.hint.text = "Press OK to try again, or * to sign out of Plex on this TV."
        launchComplete()
    else if status = "ready" then
        m.prompt.text = ""
        m.hint.text = ""
        m.top.FindNode("title").visible = false
        first = m.guide = invalid
        if first then
            m.guide = CreateObject("roSGNode", "GuideView")
            m.guide.ObserveField("action", "onGuideAction")
            m.top.AppendChild(m.guide)
        end if
        m.guide.guide = m.library.guide
        if first then m.guide.SetFocus(true)
        launchComplete()
        if m.scheduleTimer = invalid then
            m.scheduleTimer = CreateObject("roSGNode", "Timer")
            m.scheduleTimer.duration = 30
            m.scheduleTimer.repeat = true
            m.scheduleTimer.ObserveField("fire", "onScheduleTimer")
            m.scheduleTimer.control = "start"
        end if
    end if
end sub

sub onScheduleTimer()
    if m.library <> invalid then m.library.reschedule = true
end sub

sub dropGuide()
    if m.library <> invalid then m.library.control = "stop"
    m.library = invalid
    if m.guide <> invalid then
        m.top.RemoveChild(m.guide)
        m.guide = invalid
    end if
    m.top.FindNode("title").visible = true
    m.top.SetFocus(true)
end sub

sub onGuideAction()
    action = m.guide.action
    dropGuide()
    if action = "signOut" then
        signOut()
    else if action = "rebuild" then
        m.prompt.text = "Rebuilding your channels…"
        startLibrary(true)
    end if
end sub

sub signOut()
    if m.signIn <> invalid then m.signIn.control = "stop"
    dropGuide()
    NxPlexClearAuth()
    ' The saved guide and pools and the enrichment cache (which TMDB ids the
    ' library has) are this account's library; they go with the sign-in.
    DeleteFile("cachefs:/nostalgex-guide.json")
    DeleteFile("cachefs:/nostalgex-pools.json")
    DeleteFile("cachefs:/nostalgex-enrichment.json")
    startSignIn()
end sub

function onKeyEvent(key as String, press as Boolean) as Boolean
    if not press then return false
    if key = "options" then
        ' Sign out: stop any sign-in in progress and forget everything stored.
        signOut()
        return true
    end if
    if key = "OK" and m.signIn <> invalid and m.signIn.status = "error" then
        startSignIn()
        return true
    end if
    if key = "OK" and m.library <> invalid and m.library.status = "error" then
        startLibrary(true)
        return true
    end if
    return false
end function
