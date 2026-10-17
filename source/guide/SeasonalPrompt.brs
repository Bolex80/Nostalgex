' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' The seasonal invite, after the Apple TV app's SeasonalPrompt.swift: a
' seasonal package is never switched on for anyone. While one is in season,
' off and not silenced, a row above channel one offers it; "not this year"
' holds until next year's season, "don't ask again" for good. Config order
' wins when two qualify, so one thing is asked at a time.

' The package to offer, or invalid. `silenced` answers
' NxSeasonalSilenced(id, year) or a stand-in for tests.
function NxSeasonalOffer(bundles as Object, enabled as Object, month as Integer, year as Integer, silenced as Object) as Dynamic
    for each b in bundles
        if type(b.activeMonths) = "roArray" then
            if NxHasValue(b.activeMonths, month) and not NxHasValue(enabled, b.id) and not silenced.isSilenced(b.id, year) then return b
        end if
    end for
    return invalid
end function

' The answers as the TV keeps them: per package for "never", per package and
' year for "not this year".
function NxSeasonalRegistry() as Object
    return {
        reg: CreateObject("roRegistrySection", "guide"),
        isSilenced: function(id as String, year as Integer) as Boolean
            if m.reg.Read("seasonalNever_" + id) = "1" then return true
            return m.reg.Read("seasonalDismissed_" + id + "_" + year.ToStr()) = "1"
        end function,
        record: function(answer as String, id as String, year as Integer) as Boolean
            if answer = "yes" then return true
            if answer = "never" then
                m.reg.Write("seasonalNever_" + id, "1")
            else
                m.reg.Write("seasonalDismissed_" + id + "_" + year.ToStr(), "1")
            end if
            m.reg.Flush()
            return false
        end function
    }
end function

' The invite's headline and colour (SeasonalInviteRow).
function NxSeasonalHeadline(b as Object) as String
    if b.id = "seasonal" then return "IT'S OCTOBER. ARE YOU READY TO SCREAM?"
    if b.id = "tis-the-season" then return "IT'S DECEMBER. DECK THE CHANNELS."
    return UCase(NxToStr(b.name)) + " IS IN SEASON."
end function

function NxSeasonalAccent(b as Object) as String
    if b.id = "seasonal" then return "#FF6B00"
    if b.id = "tis-the-season" then return "#E74C3C"
    return "#FFE500"
end function
