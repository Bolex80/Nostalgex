' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' PLAYBACK INFORMATION (issue #74), after upstream's
' Services/PlaybackInformation.swift and the web tuner's
' scripts/nostalgex-playback-info.js: the same rows, labels and fallback
' sentences, held to the web's module (tests/gen-playback-info.mjs). Like
' both it holds only fixed labels and bounded numbers: never an item, a URL,
' a server address, a token or an error message.
'
' A programme gets a generation; each try at playing it (the first, a step
' down the ladder in source/guide/Fallback.brs, a retry) gets an attempt id.
' Ready is accepted only for the current generation and attempt, so a late
' "playing" from a replaced attempt can't describe the one still loading.

function NxPiBackends() as Object
    return { plex: "Plex", jellyfin: "Jellyfin", emby: "Emby", demo: "Demo" }
end function

function NxPiDelivery() as Object
    return { unknown: "Unknown", directPlay: "Direct Play", serverStream: "Server stream" }
end function

' Observed recovery decisions only, never a guessed cause or a server's text.
function NxPiReasons() as Object
    return {
        none: "No fallback used.",
        serverStreamSelected: "Server streaming was selected for this source.",
        directPlayFailed: "Direct Play failed. Trying a server stream.",
        startupNoPicture: "No picture reached the startup deadline. Trying a different stream.",
        streamStalled: "Playback stopped making progress. Trying a different stream.",
        playerRetry: "The player could not open the stream. Retrying it once."
    }
end function

function NxPiRecoveryRequests() as Object
    return { compatibility1080p: "Compatibility retry, up to 1080p" }
end function

' The panel's note under its title: upstream's evidenceNote, with the Roku's
' player for AVPlayer.
function NxPiEvidenceNote() as String
    return "Source codecs come from library metadata. Player size is reported by the Roku player. Quality is the selection at tune time, not a measured output. Server streams may copy or convert media; the current resolver does not identify which."
end function

' Only these labels cross into the panel: codec fields are server text.
function NxPiCodecLabel(value as Dynamic, video as Boolean) as String
    key = LCase(NxToStr(value).Trim())
    if video then
        known = { h264: "H.264", avc: "H.264", avc1: "H.264", hevc: "HEVC", h265: "HEVC", hev1: "HEVC", hvc1: "HEVC", mpeg2video: "MPEG-2", mpeg4: "MPEG-4", av1: "AV1", vp9: "VP9", vc1: "VC-1" }
    else
        known = { aac: "AAC", ac3: "AC-3", eac3: "E-AC-3", dts: "DTS", dca: "DTS", truehd: "TrueHD", flac: "FLAC", alac: "ALAC", mp3: "MP3", opus: "Opus", vorbis: "Vorbis", pcm: "PCM" }
    end if
    if key <> "" and known.DoesExist(key) then return known[key]
    return "Unknown"
end function

function NxPiSizeLabel(width as Dynamic, height as Dynamic) as String
    if not NxIsNumber(width) or not NxIsNumber(height) then return "Unknown"
    if width < 1 or height < 1 or width > 65536 or height > 65536 then return "Unknown"
    return Int(width + 0.5).ToStr() + " × " + Int(height + 0.5).ToStr()
end function

' QUALITY AT TUNE: what this app asks for. Jellyfin and Emby get the Apple
' TV's Auto (40 Mbps, up to 4K: NxMbVideoQuery); Plex gets no quality
' parameters, so the server's default, the web tuner's wording for the same.
' STREAM QUALITY (#65) will replace this with the level chosen.
function NxPiQualityLabel(kind as String) as String
    if kind = "jellyfin" or kind = "emby" then return "Auto"
    if kind = "plex" then return "Server default"
    return "Unknown"
end function

' opts: { generation, backend, qualityAtTune, videoCodec, audioCodec }.
function NxPiCreate(opts as Object) as Object
    backend = "Unknown"
    backends = NxPiBackends()
    key = NxToStr(opts.backend)
    if key <> "" and backends.DoesExist(key) then backend = backends[key]
    quality = "Unknown"
    q = NxToStr(opts.qualityAtTune)
    ' The Apple TV's level names, and the Plex label above.
    if NxHasValue(["Auto", "Maximum", "High", "Medium", "Low", "Server default"], q) then quality = q
    return {
        generation: opts.generation, backend: backend, quality: quality,
        video: NxPiCodecLabel(opts.videoCodec, true), audio: NxPiCodecLabel(opts.audioCodec, false),
        delivery: "unknown", reason: "none", recovery: invalid, ready: false, attemptId: invalid, seq: 0
    }
end function

' A replaced player's ready state and size must not describe the one loading.
sub NxPiInvalidate(info as Object)
    info.attemptId = invalid
    info.ready = false
end sub

' Starts a try at playing this programme: its id, or invalid for a stale
' generation. An unknown delivery or reason reads as unknown or none; a
' recovery request, once made, stays for the programme.
function NxPiBeginAttempt(info as Object, generation as Dynamic, delivery as String, reason = "none" as String, recovery = "" as String) as Dynamic
    if generation <> info.generation then return invalid
    info.seq = info.seq + 1
    info.attemptId = info.seq
    info.ready = false
    if NxPiDelivery().DoesExist(delivery) then info.delivery = delivery else info.delivery = "unknown"
    if NxPiReasons().DoesExist(reason) then info.reason = reason else info.reason = "none"
    if recovery <> "" and NxPiRecoveryRequests().DoesExist(recovery) then info.recovery = recovery
    return info.attemptId
end function

function NxPiMarkReady(info as Object, generation as Dynamic, attemptId as Dynamic) as Boolean
    if generation <> info.generation or attemptId = invalid or info.attemptId = invalid then return false
    if attemptId <> info.attemptId then return false
    info.ready = true
    return true
end function

function NxPiRows(info as Object, width as Dynamic, height as Dynamic) as Object
    playback = "Loading"
    size = "Unknown"
    if info.ready then
        playback = NxPiDelivery()[info.delivery]
        size = NxPiSizeLabel(width, height)
    end if
    rows = [
        { id: "backend", label: "BACKEND", value: info.backend },
        { id: "delivery", label: "PLAYBACK", value: playback },
        { id: "quality", label: "QUALITY AT TUNE", value: info.quality }
    ]
    if info.recovery <> invalid then rows.Push({ id: "recovery", label: "RECOVERY REQUEST", value: NxPiRecoveryRequests()[info.recovery] })
    rows.Push({ id: "presentation", label: "PLAYER SIZE", value: size })
    rows.Push({ id: "source", label: "SOURCE METADATA", value: "Video: " + info.video + " · Audio: " + info.audio })
    rows.Push({ id: "reason", label: "FALLBACK", value: NxPiReasons()[info.reason] })
    return rows
end function

' ── The Roku's ladder, in upstream's words ──────────────────────────────────

' An attempt's delivery: the file as stored, or the server's stream.
function NxPiDeliveryFor(rung as String) as String
    if rung = "direct" then return "directPlay"
    return "serverStream"
end function

' The first attempt's reason, as upstream's startup: none for direct play, a
' server stream chosen up front says so.
function NxPiFirstReason(rung as String) as String
    if rung = "direct" then return "none"
    return "serverStreamSelected"
end function

' A step down the ladder (Fallback.brs NxFallbackNext, NxStarvedNext): the
' reason and recovery request upstream gives the same step. was is the rung
' that failed, event "error", "nopicture" or "starved", nxt the next attempt.
' Returns { reason, recovery }.
'   - the same request again (retryLoad): playerRetry.
'   - a direct play that errored (fallbackToTranscode): directPlayFailed.
'   - no picture (handleWatchdogNoPicture): startupNoPicture.
'   - starved (handleStarvation): streamStalled.
'   - onto the 1080p stream: also the compatibility request.
' One Roku difference: a Jellyfin or Emby server stream that errors goes to
' the 1080p stream where upstream retries the same request (Fallback.brs);
' it reads playerRetry, upstream's word for a server stream that errored.
function NxPiStepReason(was as String, event as String, nxt as Object) as Object
    reason = "playerRetry"
    if nxt.retry = true then
        ' playerRetry, as set
    else if event = "nopicture" then
        reason = "startupNoPicture"
    else if event = "starved" then
        reason = "streamStalled"
    else if was = "direct" then
        reason = "directPlayFailed"
    end if
    recovery = ""
    if nxt.rung = "capped" then recovery = "compatibility1080p"
    return { reason: reason, recovery: recovery }
end function
