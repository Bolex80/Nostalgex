' Runs source/guide/TuneQueue.brs against upstream's tune ownership rule
' (scripts/web-tune-ownership-smoke.mjs, 7485d71): only the latest press
' starts. Transcribed from the rule, not generated. Returns the failure count.

function NxRunTuneQueueTests() as Integer
    r = { pass: 0, fail: 0 }

    q = NxTuneQueue()
    NxCheck(r, "nothing running starts", NxTuneAsk(q, 3, false), "start")
    NxCheck(r, "running stops first", NxTuneAsk(q, 4, true), "stop")
    NxCheck(r, "stopped starts it", NxTuneStopped(q).ToStr(), "4")
    NxCheck(r, "nothing left waiting", NxTuneStopped(q).ToStr(), "-1")

    ' Quick flips while the stop goes through: Down, Down, Up, then OK.
    q = NxTuneQueue()
    NxCheck(r, "flip one stops", NxTuneAsk(q, 5, true), "stop")
    NxCheck(r, "flip two waits", NxTuneAsk(q, 6, false), "wait")
    NxCheck(r, "flip three waits", NxTuneAsk(q, 5, false), "wait")
    NxCheck(r, "ok waits", NxTuneAsk(q, 9, false), "wait")
    NxCheck(r, "only the latest starts", NxTuneStopped(q).ToStr(), "9")
    NxCheck(r, "older presses never land", NxTuneStopped(q).ToStr(), "-1")
    NxCheck(r, "after the stop, starts", NxTuneAsk(q, 2, false), "start")

    q = NxTuneQueue()
    NxTuneAsk(q, 7, true)
    NxTuneDrop(q)
    NxCheck(r, "dropped never starts", NxTuneStopped(q).ToStr(), "-1")

    ' A new guide lands while a tune waits on the stop: the channel waiting
    ' moved from 7 to 2 in the new list.
    q = NxTuneQueue()
    NxTuneAsk(q, 7, true)
    NxTuneMoved(q, 2)
    NxCheck(r, "a moved channel starts where it is now", NxTuneStopped(q).ToStr(), "2")
    q = NxTuneQueue()
    NxTuneMoved(q, 2)
    NxCheck(r, "a new guide starts nothing that wasn't waiting", NxTuneStopped(q).ToStr(), "-1")

    print "tune queue cases (upstream tune ownership): "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
