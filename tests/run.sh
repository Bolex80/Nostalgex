#!/bin/bash
# Run the golden-vector tests off-device in the RokuCommunity brs interpreter.
# The interpreter is a first check only: it gets some LongInteger operations
# wrong, and the port avoids those, but a pass here is confirmed on a TV with
# `scripts/deploy.sh --test`.
#
# Also checks the vectors are current with the upstream clone ($NOSTALGEX_DIR,
# default ../nostalgex), when there is one.
set -euo pipefail
cd "$(dirname "$0")/.."
upstream=${NOSTALGEX_DIR:-../nostalgex}
if [ -d "$upstream/.git" ]; then
    NOSTALGEX_DIR=$upstream node tests/gen-vectors.mjs --check
else
    echo "no upstream clone at $upstream; skipping the staleness check"
fi
# Secrets never reach the debug console, which anyone on the network can read:
# no print statement may output a variable named like a token, URL or header.
# Quoted text is ignored, so a message may say "token".
leaks=$(grep -rnE '^\s*print\b' source components | perl -ne '
    my ($loc, $code) = /^([^:]+:\d+):(.*)$/; $code =~ s/"(?:[^"]|"")*"//g;
    print "$loc\n" if $code =~ /token|\buri\b|\burl\b|header/i;')
if [ -n "$leaks" ]; then
    echo "FAIL a print statement may output a secret:" >&2
    echo "$leaks" >&2
    exit 1
fi

# `m` is BrightScript's implicit this: a variable of that name silently holds
# the component's AA instead. It has cost three debugging rounds; fail fast.
shadow=$(grep -rnE '^\s*(for\s+)?m\s*=[^=]|\bas\s+\w+\s*,?\s*m\s+as\b|\(\s*m\s+as\b' source components tests --include=*.brs || true)
if [ -n "$shadow" ]; then
    echo "FAIL a variable named m (BrightScript's this):" >&2
    echo "$shadow" >&2
    exit 1
fi

out=$(npx -y -p @rokucommunity/brs@0.47.6 brs --root . \
    tests/main.brs tests/ScheduleTests.brs tests/FilterTests.brs tests/LineupTests.brs source/util/*.brs source/schedule/*.brs source/filter/*.brs source/guide/*.brs 2>&1 | grep -v '^npm warn')
echo "$out"
grep -q '^ALL TESTS PASSED' <<<"$out"
