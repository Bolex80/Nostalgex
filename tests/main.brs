' Test entry point. Replaces source/main.brs in the off-device run and in
' `scripts/deploy.sh --test`; never part of a normal build.
sub Main(args = invalid as Dynamic)
    timer = CreateObject("roTimespan")
    failures = NxRunScheduleTests("pkg:/tests/vectors/schedule.json")
    print "  schedule took "; timer.TotalMilliseconds(); " ms"
    timer.Mark()
    failures = failures + NxRunFilterTests("pkg:/tests/vectors/filter.json", "pkg:/data/channels-memberships.json")
    print "  filter took "; timer.TotalMilliseconds(); " ms"
    timer.Mark()
    failures = failures + NxRunLineupTests("pkg:/tests/vectors/lineup.json")
    print "  lineup took "; timer.TotalMilliseconds(); " ms"
    if failures = 0 then print "ALL TESTS PASSED" else print "TESTS FAILED"
end sub
