#!/usr/bin/env python3
"""A plain variable that an `if`, `else if` or `while` condition reads, in a
function that never assigns it. BrightScript reads such a name as
uninitialized and stops the app only when that line runs ("Use of
uninitialized variable", &he9), so no test and no static analysis catches it
until a TV reaches the line: SettingsView's package rows read `isOn` after a
rename left only `on` assigned (2026-10-27, release candidate 1.0.6).

Deliberately narrow, so a hit is real: only simple names in conditions, only
assignments made earlier in the same function (`name =` at a statement start,
`for`, `for each`, parameters, an inner function's parameters). Inside an
if / else if / else chain a branch sees only what came before the chain, not
what a sibling branch assigned: that is the 2026-10-27 bug (the package rows'
branch read `isOn`, which only the reporting rows' branch assigned). After
`end if` every branch's assignments count, so nothing is flagged for a name
that at least one branch set. Names with a dot or call are skipped. Exits 1
and lists each miss."""
import glob, os, re, sys

os.chdir(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))  # a roku/ directory, else this one
KEYWORDS = {
    "if", "then", "else", "elseif", "end", "and", "or", "not", "true", "false", "invalid", "mod",
    "while", "for", "each", "in", "to", "step", "function", "sub", "return", "as", "stop", "print",
    "exit", "goto", "dim", "run", "m", "object", "string", "integer", "boolean", "dynamic", "float",
    "double", "longinteger", "void", "type", "box", "rem",
}


def strip(line):
    line = re.sub(r'"(?:[^"]|"")*"', '""', line)
    line = re.sub(r"&h[0-9A-Fa-f]+", "0", line)
    return re.sub(r"'.*", "", line)


def functions(text):
    """(name, line number, parameter names, [(line number, code)]) per function."""
    out, cur, depth = [], None, 0
    for n, raw in enumerate(text.split("\n"), 1):
        code = strip(raw)
        m = re.match(r"\s*(?:function|sub)\s+(\w+)\s*\((.*)\)", code, re.I)
        if m:
            params = set(re.findall(r"(\w+)\s*(?:=[^,)]*)?\s+as\b|(\w+)\s*(?:=[^,)]*)?(?:,|$)", m.group(2)))
            names = {a or b for a, b in params}
            cur = [m.group(1), n, {x.lower() for x in names}, []]
            continue
        if re.match(r"\s*end\s+(function|sub)\b", code, re.I):
            if depth > 0:
                depth -= 1
                continue
            if cur:
                out.append(tuple(cur))
            cur = None
            continue
        if cur is not None:
            # An anonymous function or sub inside this one (a callback in a
            # record): its parameters count as assigned here.
            for anon in re.finditer(r"\b(?:function|sub)\s*\(([^)]*)\)", code, re.I):
                depth += 1
                cur[2] |= {w.lower() for w in re.findall(r"(\w+)\s*(?:=[^,)]*)?\s+as\b|(\w+)\s*(?:,|$)", anon.group(1)) for w in w if w}
            cur[3].append((n, code))
    return out


def assignments(code):
    found = set()
    for m in re.finditer(r"(?:^|\bthen\b|\belse\b|:)\s*([A-Za-z_]\w*)[%!#$&]?\s*(?:=(?!=)|\+=|-=|\*=|/=)", code, re.I):
        found.add(m.group(1).lower())
    for m in re.finditer(r"\bfor\s+each\s+(\w+)", code, re.I):
        found.add(m.group(1).lower())
    for m in re.finditer(r"\bfor\s+(\w+)[%!#$&]?\s*=", code, re.I):
        found.add(m.group(1).lower())
    return found


def check(path, name, params, body):
    bad = 0
    assigned = set(params)
    frames = []  # (snapshot at the if, union of the branches so far)
    for n, code in body:
        low = code.strip().lower()
        cond = None
        if re.match(r"end\s+if\b", low):
            if frames:
                snap, union = frames.pop()
                assigned = union | assigned
            continue
        m = re.match(r"(else\s*if|elseif)\b(.*?)(?:\bthen\b.*)?$", code.strip(), re.I)
        if m:
            if frames:
                snap, union = frames[-1]
                frames[-1] = (snap, union | assigned)
                assigned = set(snap)
            cond = m.group(2)
        elif re.match(r"else\s*$", low):
            if frames:
                snap, union = frames[-1]
                frames[-1] = (snap, union | assigned)
                assigned = set(snap)
            continue
        else:
            m = re.match(r"\s*(?:if|while)\b(.*?)(?:\bthen\b(.*))?$", code, re.I)
            if m:
                cond = m.group(1)
                rest = (m.group(2) or "").strip()
                if re.match(r"\s*if\b", low) and not rest:
                    frames.append((set(assigned), set()))
        if cond is not None:
            for t in re.finditer(r"(?<![\w.])([A-Za-z_]\w*)(?![\w(.\[%!#$&])", cond):
                word = t.group(1).lower()
                if word in KEYWORDS or word in assigned:
                    continue
                print(f"FAIL {path}({n}): {name}() reads {t.group(1)} in a condition before assigning it on this path")
                bad += 1
        assigned |= assignments(code)
    return bad


bad = 0
for path in sorted(glob.glob("source/**/*.brs", recursive=True) + glob.glob("components/*.brs")):
    for name, start, params, body in functions(open(path).read()):
        bad += check(path, name, params, body)
sys.exit(1 if bad else 0)
