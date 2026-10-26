' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' A TV left on for a day keeps a current library (#67), as upstream's
' startDailyRefresh (App/AppState+Schedule.swift): every 15 minutes, once
' the library last loaded 6 hours ago or more (LibrarySnapshotStore
' .refreshAfterSeconds) and the last check was as long ago, the library is
' read again behind the guide. There, as upstream's refreshLibraryIfChanged,
' a Plex server whose library signature is unchanged and whose save is under
' a day old (its forceRefreshAfterSeconds) isn't scanned again
' (NxSnapshotFresh); Jellyfin and Emby have no signature and are.

function NxDailyRefreshCheckSec() as Integer
    return 900
end function

function NxDailyRefreshAfterSec() as Integer
    return 21600
end function

' Whether the 15-minute check reads the library again now.
function NxDailyRefreshDue(nowSec as LongInteger, lastLoadSec as LongInteger, lastCheckSec as LongInteger) as Boolean
    after = NxDailyRefreshAfterSec()
    return nowSec - lastLoadSec >= after and nowSec - lastCheckSec >= after
end function
