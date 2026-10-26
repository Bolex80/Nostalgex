' Runs NxPlexAudioExtra and NxPlexAudioKey (source/plex/PlexPlayback.brs):
' the audio a Plex server stream may carry (#68), after upstream's
' clientProfileExtra and eac3ChannelCap (PlexAPIService.swift). Hand-written
' cases. Returns the failure count.

function NxRunPlexAudioTests() as Integer
    r = { pass: 0, fail: 0 }
    ac3 = "+add-transcode-target-audio-codec(type=videoProfile&context=streaming&protocol=hls&audioCodec=ac3)"
    eac3 = "+add-transcode-target-audio-codec(type=videoProfile&context=streaming&protocol=hls&audioCodec=eac3)"
    cap = "+add-limitation(scope=videoAudioCodec&scopeName=eac3&type=upperBound&name=audio.channels&value=6)"
    NxCheck(r, "stereo TV: nothing offered", NxPlexAudioExtra(false, false), "")
    NxCheck(r, "AC3 only", NxPlexAudioExtra(true, false), ac3)
    NxCheck(r, "both, E-AC-3 capped at 6 (eac3ChannelCap)", NxPlexAudioExtra(true, true), ac3 + eac3 + cap)
    NxCheck(r, "E-AC-3 only", NxPlexAudioExtra(false, true), eac3 + cap)
    NxCheck(r, "cap is scope videoAudioCodec", FormatJson(Instr(1, cap, "scope=videoAudioCodec&") > 0), "true")
    NxCheck(r, "session key: none", NxPlexAudioKey(false, false), "")
    NxCheck(r, "session key: both", NxPlexAudioKey(true, true), "-ac3-eac3")
    NxCheck(r, "session key: ac3", NxPlexAudioKey(true, false), "-ac3")
    print "plex audio cases (upstream clientProfileExtra): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
