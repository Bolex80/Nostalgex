' Runs source/plex/ServerChoice.brs: which servers the guide reads. Owned
' servers by default is the maintainer's call for the Roku (Discussion #8),
' with nothing upstream to match. Returns the failure count.

function NxRunServerChoiceTests() as Integer
    r = { pass: 0, fail: 0 }

    mixed = [
        { machineIdentifier: "a", owned: true },
        { machineIdentifier: "b", owned: false },
        { machineIdentifier: "c", owned: true },
        { machineIdentifier: "d", owned: false },
    ]
    NxCheck(r, "owned by default", FormatJson(NxServersOn(mixed, invalid)), "[true,false,true,false]")
    NxCheck(r, "choice turns shared on", FormatJson(NxServersOn(mixed, { b: true })), "[true,true,true,false]")
    NxCheck(r, "choice turns owned off", FormatJson(NxServersOn(mixed, { a: false })), "[false,false,true,false]")
    NxCheck(r, "all off falls back to all", FormatJson(NxServersOn(mixed, { a: false, c: false })), "[true,true,true,true]")
    NxCheck(r, "choice for a gone server", FormatJson(NxServersOn(mixed, { z: true })), "[true,false,true,false]")
    shared = [{ machineIdentifier: "b", owned: false }, { machineIdentifier: "d", owned: false }]
    NxCheck(r, "only shared: all on", FormatJson(NxServersOn(shared, {})), "[true,true]")
    NxCheck(r, "only shared, one off", FormatJson(NxServersOn(shared, { d: false })), "[true,false]")
    NxCheck(r, "no servers", FormatJson(NxServersOn([], {})), "[]")
    NxCheck(r, "key", NxServersOnKey(mixed, { d: true }), "a,c,d")

    print "server choice cases: "; r.pass; " passed,"; r.fail; " failed"
    return r.fail
end function
