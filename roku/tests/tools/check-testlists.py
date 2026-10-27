#!/usr/bin/env python3
"""The three places a test file has to be listed agree, and nothing is listed
twice. A merge of two branches that each add a test file conflicts in these
lists, and a hand resolution can drop one file or repeat a line. A dropped
file is a suite that quietly never runs; a repeated one runs twice.

  scripts/deploy.sh         the `cp tests/... "$stage"/source/` line (on a TV)
  tests/run.sh              the `files=(tests/... source/...)` array (off-device)
  tests/main.brs            one call to each NxRun...Tests function, once

For every tests/*Tests.brs: its file name appears exactly once in the deploy.sh
list and once in the run.sh list, and every NxRun*Tests function it defines is
called once at most in main.brs. A function main.brs doesn't call has to be
called by another test file (a suite running its sub-suites), and a file
none of whose functions main.brs reaches runs nothing. Also: every NxRun*Tests
call in main.brs is defined by some test file, no NxTestWants("name") is used
twice, and every file a list names exists.

  check-testlists.py [ROOT]     ROOT is a roku/ directory; default: this one
Exits 1 and lists each problem."""
import glob, os, re, sys

os.chdir(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
bad = []


def read(p):
    return open(p).read()


deploy = read("scripts/deploy.sh")
run = read("tests/run.sh")
main = read("tests/main.brs")

# deploy.sh: the cp line of the `test` mode; run.sh: the files=( ... ) array.
m = re.search(r"^\s*cp (tests/main\.brs[^\n]*)\n", deploy, re.M)
deploy_list = m.group(1).split() if m else None
m = re.search(r"^files=\((tests/main\.brs[^\n]*)\)\s*$", run, re.M)
run_list = m.group(1).split() if m else None
if deploy_list is None:
    bad.append("scripts/deploy.sh: no `cp tests/main.brs ...` line found")
    deploy_list = []
if run_list is None:
    bad.append("tests/run.sh: no `files=(tests/main.brs ...)` array found")
    run_list = []


def dups(tokens):
    seen, out = set(), []
    for t in tokens:
        if t in seen and t not in out:
            out.append(t)
        seen.add(t)
    return out


for name, toks in (("scripts/deploy.sh", deploy_list), ("tests/run.sh", run_list)):
    for t in dups(toks):
        bad.append(f"{name}: {t} is listed more than once")

defined = {}
test_files = sorted(glob.glob("tests/*Tests.brs"))
for f in test_files:
    code = read(f)
    code = re.sub(r"^\s*'.*$", "", code, flags=re.M)
    defined[f] = re.findall(r"^\s*function\s+(NxRun\w+Tests)\s*\(", code, re.M | re.I)
    if f not in deploy_list:
        bad.append(f"scripts/deploy.sh: {f} is not in the TV test list")
    if f not in run_list:
        bad.append(f"tests/run.sh: {f} is not in the off-device file list")
    if not defined[f]:
        bad.append(f"{f}: defines no NxRun...Tests function for main.brs to call")

main_code = re.sub(r"^\s*'.*$", "", main, flags=re.M)
calls = re.findall(r"\b(NxRun\w+Tests)\s*\(", main_code)
all_defined = {n.lower(): f for f, ns in defined.items() for n in ns}
# A suite function may also be called from inside a test file (a suite that
# runs its sub-suites), so it counts as run when any test file or main.brs
# calls it. A file whose functions main.brs never reaches runs nothing.
inner = set()
for f in test_files:
    code = re.sub(r"^\s*'.*$", "", read(f), flags=re.M)
    code = re.sub(r"^\s*function\s+NxRun\w+Tests\s*\(", "", code, flags=re.M | re.I)
    inner |= {n.lower() for n in re.findall(r"\b(NxRun\w+Tests)\s*\(", code)}
for f, names in defined.items():
    if names and not any(n.lower() in {c.lower() for c in calls} for n in names):
        bad.append(f"tests/main.brs: calls nothing from {f} ({', '.join(names)}), so none of it runs")
    for n in names:
        c = sum(1 for x in calls if x.lower() == n.lower())
        if c > 1:
            bad.append(f"tests/main.brs: {n} is called {c} times")
        elif c == 0 and n.lower() not in inner:
            bad.append(f"{f}: {n} is defined and never called")
for n in sorted(set(calls)):
    if n.lower() not in all_defined:
        bad.append(f"tests/main.brs: calls {n}, which no tests/*Tests.brs defines")

wants = re.findall(r'NxTestWants\("([a-z0-9-]+)"\)', main_code)
for w in dups(wants):
    bad.append(f'tests/main.brs: NxTestWants("{w}") is used more than once')

# Every file named in a list exists.
for name, toks in (("scripts/deploy.sh", deploy_list), ("tests/run.sh", run_list)):
    for t in toks:
        if t.startswith("tests/") and t.endswith(".brs") and not os.path.exists(t):
            bad.append(f"{name}: lists {t}, which does not exist")

for b in bad:
    print("FAIL " + b)
sys.exit(1 if bad else 0)
