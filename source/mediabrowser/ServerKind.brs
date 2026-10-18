' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Which kind of server a saved one is, and the library steps that differ by
' kind. A TV is signed in to one kind at a time, as the Apple TV app holds
' one backend: Plex (any number of servers on the account), or one Jellyfin
' or Emby server. The registry's `plex` section holds either, and its `kind`
' key says which ("" for Plex, as every sign-in before Jellyfin was).
'
' A saved Jellyfin or Emby server: { kind, name, machineIdentifier (the
' server's Id), uri, userId, accessToken, owned: true, checked: true }, so the
' server choices and Plex's address check (NxPlexResolveSaved) pass it by.

function NxServerKind(server as Dynamic) as String
    if type(server) = "roAssociativeArray" then
        if server.kind = "jellyfin" or server.kind = "emby" then return server.kind
    end if
    return "plex"
end function

' The kind this TV is signed in to: plex, jellyfin or emby.
function NxSignedInKind() as String
    kind = NxPlexRegistry().Read("kind")
    if kind = "jellyfin" or kind = "emby" then return kind
    return "plex"
end function

' The name to show for a kind.
function NxKindName(kind as String) as String
    if kind = "jellyfin" then return "Jellyfin"
    if kind = "emby" then return "Emby"
    return "Plex"
end function
