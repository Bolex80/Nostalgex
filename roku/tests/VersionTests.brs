' Runs source/util/AppVersion.brs: the VERSION line, with and without the
' manifest's nx_build. Returns the failure count.

function NxRunVersionTests() as Integer
    r = { pass: 0, fail: 0 }
    NxCheck(r, "version and build", NxFormatVersionLabel("1", "0", "2", "cca0d38a1b2c"), "VERSION 1.0.2 (cca0d38a1b2c)")
    NxCheck(r, "no nx_build", NxFormatVersionLabel("1", "0", "2", ""), "VERSION 1.0.2")
    NxCheck(r, "padded build_version", NxFormatVersionLabel("1", "0", "00002", ""), "VERSION 1.0.2")
    NxCheck(r, "missing number", NxFormatVersionLabel("", "0", "2", " "), "VERSION ?.0.2")
    print "version cases:"; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
