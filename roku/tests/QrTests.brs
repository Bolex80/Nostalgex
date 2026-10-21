' Runs source/util/QrCode.brs against tests/vectors/qr.json, a reference
' encoder's codes (tests/gen-qr.mjs): every mask's matrix exactly, and the
' code chosen by penalty one of them. Returns the failure count. `shard`
' ({ index, count }, from tests/run.sh) checks every `count`th case from
' `index`; invalid checks them all, as on a TV.

function NxRunQrTests(vectorsPath as String, shard = invalid as Dynamic) as Integer
    v = ParseJson(ReadAsciiFile(vectorsPath))
    if v = invalid then
        print "FAIL cannot read "; vectorsPath
        return 1
    end if
    r = { pass: 0, fail: 0 }
    shardIndex = 0
    shardCount = 1
    if shard <> invalid then
        shardIndex = shard.index
        shardCount = shard.count
    end if
    for k = shardIndex to v.cases.Count() - 1 step shardCount
        c = v.cases[k]
        for mask = 0 to 7
            NxCheck(r, "qr " + Left(c.text, 30) + " mask " + mask.ToStr(), NxQrRows(NxQrMatrix(c.text, mask)), c.masks[mask].Join(","))
        end for
        auto = NxQrRows(NxQrMatrix(c.text))
        chosen = "none"
        for mask = 0 to 7
            if c.masks[mask].Join(",") = auto then chosen = mask.ToStr()
        end for
        ' Any of the eight decodes. The reference's own pick can differ: its
        ' finder-like penalty reads the standard differently from Nayuki's,
        ' which this follows (they disagree on "A").
        NxCheck(r, "qr " + Left(c.text, 30) + " chosen mask is a reference code", NxToStr(chosen <> "none"), "true")
    end for
    if shardIndex = 0 then NxCheck(r, "qr too long for version 10", NxToStr(NxQrMatrix(String(214, "z")) = invalid), "true")
    which = ""
    if shardCount > 1 then which = ", cases " + shardIndex.ToStr() + " mod " + shardCount.ToStr()
    print "qr cases (reference qrcode encoder"; which; "):"; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function

function NxQrRows(modules as Dynamic) as String
    if modules = invalid then return "invalid"
    rows = []
    for each row in modules
        s = ""
        for each dark in row
            if dark then s = s + "1" else s = s + "0"
        end for
        rows.Push(s)
    end for
    return rows.Join(",")
end function
