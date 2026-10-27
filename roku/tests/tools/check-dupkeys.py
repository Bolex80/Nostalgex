#!/usr/bin/env python3
"""An associative-array literal that names the same key twice. BrightScript
keeps one of them without saying which, so the other value is silently lost.
A hand-resolved merge makes this by keeping both sides of a conflicting line
(`audioTracks: it.audioTracks, duration: it.duration` beside
`audioTracks: it.audioTracks, forcedSubs: it.forcedSubs`, 2026-10-27), and no
test, parse or static analysis reports it.

Reads each source/ and components/ .brs file with strings and comments blanked,
follows `{` and `}`, and records the keys written as `name:` right after a `{`
or a `,` (keys are case-insensitive, as in BrightScript). Calls and nested
literals have their own scope. Exits 1 and lists each repeat.

  check-dupkeys.py [ROOT]     ROOT is a roku/ directory; default: this one"""
import glob, os, re, sys

os.chdir(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def blank(line):
    line = re.sub(r'"(?:[^"]|"")*"', lambda m: '"' + " " * (len(m.group(0)) - 2) + '"', line)
    i = line.find("'")
    if i >= 0:
        line = line[:i]
    return re.sub(r"^\s*rem\b.*", "", line, flags=re.I)


bad = 0
files = sorted(glob.glob("source/**/*.brs", recursive=True) + glob.glob("components/*.brs"))
for f in files:
    stack = []  # one entry per open `{`: {lowercased key: line} or None for other brackets
    prev = ""  # last significant character before the cursor
    for n, raw in enumerate(open(f, encoding="utf-8", errors="replace").read().split("\n"), 1):
        line = blank(raw)
        i = 0
        while i < len(line):
            c = line[i]
            if c == "{":
                stack.append({})
                prev = "{"
            elif c == "}":
                if stack:
                    stack.pop()
                prev = "}"
            elif c in "([":
                stack.append(None)
                prev = c
            elif c in ")]":
                if stack:
                    stack.pop()
                prev = c
            elif c == '"':
                j = line.find('"', i + 1)
                i = (j if j >= 0 else len(line)) + 1
                prev = '"'
                continue
            elif c.isspace():
                pass
            else:
                m = re.match(r"([A-Za-z_]\w*)\s*:(?!:)", line[i:]) if prev in ("{", ",") else None
                if m and stack and stack[-1] is not None:
                    key = m.group(1).lower()
                    if key in stack[-1]:
                        print(f"FAIL {f}:{n}: key {m.group(1)} is already given on line {stack[-1][key]} of the same literal")
                        bad += 1
                    else:
                        stack[-1][key] = n
                    i += m.end()
                    prev = ":"
                    continue
                prev = c
            i += 1
        # A line break inside a literal starts the next entry (entries may be
        # separated by a comma or by the break alone); elsewhere it starts fresh.
        if not stack:
            prev = ""
        elif isinstance(stack[-1], dict):
            prev = ","
sys.exit(1 if bad else 0)
