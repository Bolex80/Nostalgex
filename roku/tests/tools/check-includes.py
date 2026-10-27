#!/usr/bin/env python3
"""Every Nx* function a component's scripts call is defined in a script that
component includes. BrightScript resolves a call only when it runs, so a call
into a file the component doesn't load passes every test and crashes on the
TV ("Function is not defined in component's namespace"). It did, 2026-10-18:
NxOr from the Jellyfin sign-in task. Exits 1 and lists each miss."""
import glob, os, re, sys

os.chdir(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))  # a roku/ directory, else this one
defs = {}
for f in glob.glob("source/**/*.brs", recursive=True) + glob.glob("components/*.brs"):
    defs[f] = {n.lower() for n in re.findall(r"^\s*(?:function|sub)\s+(\w+)", open(f).read(), re.M)}
bad = 0
for xml in sorted(glob.glob("components/*.xml")):
    scripts = [u.replace("pkg:/", "") for u in re.findall(r'uri="(pkg:/[^"]+\.brs)"', open(xml).read())]
    have = set().union(*(defs.get(s, set()) for s in scripts)) if scripts else set()
    for s in scripts:
        code = open(s).read()
        code = re.sub(r'"[^"\n]*"', '""', code)
        code = re.sub(r"'.*", "", code)
        for name in sorted(set(re.findall(r"\b(Nx\w+)\s*\(", code))):
            if name.lower() not in have:
                print(f"FAIL {xml}: {s} calls {name}, which none of its scripts define")
                bad += 1
sys.exit(1 if bad else 0)
