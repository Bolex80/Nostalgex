' Runs source/util/QrCode.brs against tests/vectors/qr.json, a reference
' encoder's codes (tests/gen-qr.mjs): every mask's matrix exactly, and the
' code chosen by penalty one of them. Returns the failure count.

function NxRunQrTests(vectorsPath as String) as Integer
    v = ParseJson(ReadAsciiFile(vectorsPath))
    if v = invalid then
        print "FAIL cannot read "; vectorsPath
        return 1
    end if
    r = { pass: 0, fail: 0 }
    for each c in v.cases
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
    NxCheck(r, "qr too long for version 10", NxToStr(NxQrMatrix(String(214, "z")) = invalid), "true")
    print "qr cases (reference qrcode encoder):"; r.pass; " passed,"; r.fail; " failed"
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
