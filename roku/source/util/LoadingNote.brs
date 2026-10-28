' The line under the logo on the loading screen while the library is read
' for the first time on this TV.
'
' A first-ever setup says what is happening. When a library was saved
' before (the registry's librarySaved flag, which outlasts cachefs:) and
' the saved copy is gone, the TV cleared it: cachefs: lives in RAM, so a
' restart empties it. The line says so, and gives no time, since a small
' library is read in seconds and a big one takes longer. Nothing is shown
' once the library has been read before and is still saved.
function NxLoadingNote(firstRun as Boolean, savedBefore as Boolean) as String
    if not firstRun then return ""
    if savedBefore then return "The TV cleared the saved library, so it's being read again."
    return "First setup can take a few minutes to scan and build channels."
end function
