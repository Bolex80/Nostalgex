' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' The Now Playing panel's poster (#76), as upstream's posterURL(for:)
' (App/AppState+Playback.swift) and PlexAPIService.thumbnailURL: Plex only,
' 300 wide and half again as tall, through the server's thumbnail transcode.
' Upstream puts the token in that URL; here it goes in a header (the request
' is made by components/PosterTask), and the file lands in tmp:.

' What the panel needs to ask for the playing item's poster, or invalid when
' there is none to ask for: not Plex, as upstream's guard backendKind == .plex.
' The saved library keeps no artwork paths, so an item read back from it has
' no thumb, and the item's own thumb address stands in.
function NxPosterRef(b as Dynamic, kind as String) as Dynamic
    if b = invalid or kind <> "plex" then return invalid
    key = NxToStr(b.ratingKey)
    if key = "" or not NxIsNumber(b.serverIndex) then return invalid
    path = NxToStr(b.thumb)
    if path = "" then path = "/library/metadata/" + key + "/thumb"
    return { path: path, serverIndex: b.serverIndex }
end function

' thumbnailURL(for:width:), less the token.
function NxPlexPosterUrl(base as String, path as String, width as Integer) as String
    return base + "/photo/:/transcode?url=" + NxUrlEncode(path) + "&width=" + width.ToStr() + "&height=" + (width * 3 \ 2).ToStr()
end function

' Where a poster is saved, one file per address so a Poster node never shows
' a cached picture for another item. Earlier ones are deleted first.
function NxPosterFile(path as String) as String
    name = ""
    for i = 1 to Len(path)
        c = Mid(path, i, 1)
        if (c >= "0" and c <= "9") or (LCase(c) >= "a" and LCase(c) <= "z") then name = name + c else name = name + "_"
    end for
    return "tmp:/nx-poster-" + Right(name, 80) + ".jpg"
end function
