' Copyright (c) 2026 nostalgex-roku contributors, MIT License.
'
' Finding each server's address, once, after the viewer has picked which
' servers are on, as the Apple TV app keeps one verified address per server
' (PlexAPIService.bestReachableURI) and never probes again on later launches.
' Every address of every server is tried at once, not one after another: on
' the maintainer's stick, three shared servers' home-network addresses tried
' in turn were most of a 114 s first run (Discussion #8).
'
' Two addresses per server, as before:
'   - uri: the first HTTPS connection in upstream's order (local, remote,
'     relay on the local side, relay) that answers.
'   - lanUri: a plain-HTTP home-network address for video and library reads
'     (see source/plex/PlexApi.brs), or "".
' An answer counts only when /identity names this server's machine
' identifier: a shared server's private address can be some other Plex
' server on this TV's network, the viewer's own, which once took its video.
'
' A home-network address that hasn't answered within the grace period is
' given up on, so a shared server's address on someone else's network costs
' seconds, not a timeout per server.

' Each address to try for a server, best first within each use, from
' plex.tv's connections. Every candidate starts with status "" (waiting);
' the driver sets "ok" or "fail".
function NxResolveCandidates(connections as Object) as Object
    out = []
    kinds = ["local", "remote", "relay (local)", "relay"]
    for each rank in [0, 1, 2, 3]
        for each c in connections
            if type(c) = "roAssociativeArray" and c.protocol = "https" and NxIsString(c.uri) then
                r = 0
                if NxTruthy(c.relay) then r = r + 2
                if not NxTruthy(c.local) then r = r + 1
                if r = rank then out.Push({ use: "uri", url: c.uri, kind: kinds[r], local: r = 0, status: "" })
            end if
        end for
    end for
    for each c in connections
        if type(c) = "roAssociativeArray" and NxTruthy(c.local) and not NxTruthy(c.relay) then
            host = NxToStr(c.address)
            if NxIsPrivateHost(host) and NxIsNumber(c.port) then
                url = "http://" + host + ":" + NxToStr(c.port)
                dup = false
                for each o in out
                    if o.url = url then dup = true
                end for
                if not dup then out.Push({ use: "lan", url: url, kind: "home network", local: true, status: "" })
            end if
        end if
    end for
    return out
end function

' What the candidates say so far: { settled, uri, kind, lanUri }. Settled
' once nothing still waiting could change the answer. A waiting candidate
' counts as failed once over (local addresses after graceMs, the rest when
' expired is true).
function NxResolveOutcome(cands as Object, elapsedMs as Integer, graceMs as Integer, expired as Boolean) as Object
    out = { settled: false, uri: "", kind: "", lanUri: "" }
    uriSettled = true
    for each c in cands
        if c.use = "uri" and out.uri = "" then
            st = NxResolveStatus(c, elapsedMs, graceMs, expired)
            if st = "ok" then
                out.uri = c.url
                out.kind = c.kind
            else if st = "" then
                ' A better address may still answer; stop looking further down.
                uriSettled = false
                exit for
            end if
        end if
    end for
    lanSettled = true
    lanWaiting = false
    for each c in cands
        if c.use = "lan" and out.lanUri = "" then
            st = NxResolveStatus(c, elapsedMs, graceMs, expired)
            if st = "ok" then out.lanUri = c.url
            if st = "" then lanWaiting = true
        end if
    end for
    if out.lanUri = "" and lanWaiting then lanSettled = false
    out.settled = uriSettled and lanSettled
    return out
end function

function NxResolveStatus(c as Object, elapsedMs as Integer, graceMs as Integer, expired as Boolean) as String
    if c.status <> "" then return c.status
    if expired or (c.local and elapsedMs >= graceMs) then return "fail"
    return ""
end function

' Whether an /identity answer is this server's: { MediaContainer: {
' machineIdentifier } } with the same identifier.
function NxIdentityMatches(json as Dynamic, machineIdentifier as String) as Boolean
    if type(json) <> "roAssociativeArray" then return false
    mc = json.MediaContainer
    if type(mc) <> "roAssociativeArray" then return false
    return machineIdentifier <> "" and NxToStr(mc.machineIdentifier) = machineIdentifier
end function

' Tries every candidate of every server at once. jobs: [{ id, connections }].
' Returns one outcome per job, in order (see NxResolveOutcome). No token is
' sent: /identity needs none.
function NxPlexResolveServers(jobs as Object, deadlineMs = 10000 as Integer, graceMs = 3000 as Integer) as Object
    port = CreateObject("roMessagePort")
    clock = CreateObject("roTimespan")
    live = {}
    all = []
    for j = 0 to jobs.Count() - 1
        cands = NxResolveCandidates(jobs[j].connections)
        all.Push(cands)
        for each c in cands
            xfer = NxPlexTransfer(c.url + "/identity", "")
            if xfer = invalid then
                c.status = "fail"
            else
                xfer.SetMessagePort(port)
                if xfer.AsyncGetToString() then
                    live[xfer.GetIdentity().ToStr()] = { xfer: xfer, cand: c, id: jobs[j].id }
                else
                    c.status = "fail"
                end if
            end if
        end for
    end for
    while true
        expired = clock.TotalMilliseconds() >= deadlineMs
        done = true
        for each cands in all
            if not NxResolveOutcome(cands, clock.TotalMilliseconds(), graceMs, expired).settled then done = false
        end for
        if done or expired then exit while
        msg = Wait(250, port)
        if type(msg) = "roUrlEvent" then
            key = msg.GetSourceIdentity().ToStr()
            job = live[key]
            if job <> invalid then
                live.Delete(key)
                json = invalid
                if msg.GetResponseCode() = 200 and msg.GetString() <> "" then json = ParseJson(msg.GetString())
                if NxIdentityMatches(json, job.id) then
                    job.cand.status = "ok"
                else
                    job.cand.status = "fail"
                    if msg.GetResponseCode() = 200 then print "plex: an address answered as a different server; skipped"
                end if
            end if
        end if
    end while
    for each key in live
        live[key].xfer.AsyncCancel()
    end for
    out = []
    for each cands in all
        out.Push(NxResolveOutcome(cands, clock.TotalMilliseconds(), graceMs, true))
    end for
    print "plex: checked "; jobs.Count(); " servers' addresses in "; clock.TotalMilliseconds(); " ms"
    return out
end function

' Finds an address for each server that is on and has no checked one yet
' (a first load after sign-in, a server switched on in Settings, or a list
' saved before addresses were checked), and saves the list. plex.tv is asked
' for the connections only when something needs them. Returns the names of
' servers on that still have no address, or invalid if plex.tv couldn't be
' reached for them.
function NxPlexResolveSaved(servers as Object, serversOn as Object) as Dynamic
    need = []
    for i = 0 to servers.Count() - 1
        if serversOn[i] and not NxTruthy(servers[i].checked) then need.Push(i)
    end for
    if need.Count() = 0 then return []
    listed = NxPlexServers(NxPlexLoadToken())
    if listed = invalid then return invalid
    byId = {}
    for each s in listed
        byId[s.machineIdentifier] = s
    end for
    jobs = []
    for each i in need
        s = byId[NxToStr(servers[i].machineIdentifier)]
        conns = []
        if s <> invalid then
            conns = s.connections
            ' plex.tv's token is the current one for a shared server.
            if s.accessToken <> "" then servers[i].accessToken = s.accessToken
        end if
        jobs.Push({ id: NxToStr(servers[i].machineIdentifier), connections: conns })
    end for
    found = NxPlexResolveServers(jobs)
    missing = []
    for k = 0 to need.Count() - 1
        s = servers[need[k]]
        r = found[k]
        if r.uri <> "" then
            s.uri = r.uri
            s.lanUri = r.lanUri
            s.checked = true
            route = "HTTPS (" + r.kind + ")"
            if r.lanUri <> "" then route = "the home network"
            print "plex: server "; need[k]; " reached over "; route
        else
            s.uri = ""
            s.lanUri = ""
            missing.Push(NxToStr(s.name))
            print "plex: server "; need[k]; " didn't answer over HTTPS"
        end if
    end for
    reg = NxPlexRegistry()
    reg.Write("servers", FormatJson(servers))
    reg.Flush()
    return missing
end function
