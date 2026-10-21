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
    failures = failures + NxRunFilterGoldenTests("pkg:/tests/vectors/filter-golden.json", "pkg:/data/channels.json", "pkg:/data/channels-memberships.json")
    timer.Mark()
    failures = failures + NxRunLineupTests("pkg:/tests/vectors/lineup.json")
    print "  lineup took "; timer.TotalMilliseconds(); " ms"
    timer.Mark()
    failures = failures + NxRunScheduleDSTGoldenTests("pkg:/tests/vectors/schedule-dst-golden.json", "pkg:/tests/vectors/schedule-dst-zones.json")
    print "  schedule dst took "; timer.TotalMilliseconds(); " ms"
    timer.Mark()
    failures = failures + NxRunFranchiseTests("pkg:/tests/vectors/franchise-golden.json", "pkg:/tests/vectors/franchise.json", "pkg:/data/franchises.json")
    print "  franchise took "; timer.TotalMilliseconds(); " ms"
    timer.Mark()
    failures = failures + NxRunFranchiseGuideTests("pkg:/data/channels.json", "pkg:/data/franchises.json")
    print "  franchise guide took "; timer.TotalMilliseconds(); " ms"
    timer.Mark()
    failures = failures + NxRunEnrichmentTests("pkg:/tests/vectors/enrichment.json")
    print "  enrichment took "; timer.TotalMilliseconds(); " ms"
    timer.Mark()
    failures = failures + NxRunCollectionTests("pkg:/tests/vectors/collections.json", "pkg:/data/channels.json", "pkg:/data/franchises.json")
    print "  collections took "; timer.TotalMilliseconds(); " ms"
    failures = failures + NxRunSubtitleTests()
    failures = failures + NxRunGuideNavTests()
    failures = failures + NxRunTuneQueueTests()
    failures = failures + NxRunAdvanceTests()
    failures = failures + NxRunSleepTimerTests()
    failures = failures + NxRunDeepLinkTests()
    failures = failures + NxRunServerChoiceTests()
    failures = failures + NxRunServerResolveTests()
    failures = failures + NxRunSnapshotTests()
    failures = failures + NxRunSeasonalTests("pkg:/tests/vectors/season-golden.json", "pkg:/data/channels.json")
    failures = failures + NxRunMediaBrowserTests("pkg:/tests/vectors/mediabrowser.json", "pkg:/tests/fixtures/mediabrowser-server.json")
    failures = failures + NxRunQrTests("pkg:/tests/vectors/qr.json")
    if failures = 0 then print "ALL TESTS PASSED" else print "TESTS FAILED"
end sub
