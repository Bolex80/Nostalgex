' The packages the viewer has switched on, shared by the library load,
' Settings and the guide.
'
' Port copyright (c) 2026 nostalgex-roku contributors, MIT License.

' Switched-on bundles: saved on the TV, upstream's default until changed.
function NxEnabledBundles() as Object
    raw = NxRegSection("guide").Read("bundles")
    if raw <> "" then
        saved = ParseJson(raw)
        if type(saved) = "roArray" then return saved
    end if
    return ["nostalgex"]
end function

' ── A first run that fills no channel (#60) ─────────────────────────────────

' upstream's autoEnableBundlesWithContent, its candidates: every package not
' on, not seasonal (offered by the seasonal invite, never switched on
' unasked) and not a collection one.
function NxAutoEnableCandidates(bundles as Object, enabled as Object) as Object
    out = []
    for each b in NxList(bundles)
        id = NxToStr(b.id)
        if not NxHasValue(enabled, id) and Left(id, 12) <> "collections-" and b.activeMonths = invalid then out.Push(id)
    end for
    return out
end function

' Of `candidates`, the packages with at least one channel that has content:
' a built channel with enough items (`channels` as buildGuide makes them).
function NxBundlesWithContent(bundles as Object, candidates as Object, channels as Object) as Object
    filled = {}
    for each ch in NxList(channels)
        if ch.built = true and ch.enabled = true then filled[NxToStr(ch.id)] = true
    end for
    out = []
    for each b in NxList(bundles)
        id = NxToStr(b.id)
        if NxHasValue(candidates, id) then
            for each cid in NxList(b.channelIDs)
                if filled.DoesExist(NxToStr(cid)) then
                    out.Push(id)
                    exit for
                end if
            end for
        end if
    end for
    return out
end function

sub NxSaveEnabledBundles(ids as Object)
    reg = CreateObject("roRegistrySection", "guide")
    reg.Write("bundles", FormatJson(ids))
    reg.Flush()
end sub
