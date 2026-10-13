#!/bin/bash
# Run the golden-vector tests off-device in the RokuCommunity brs interpreter.
# The interpreter is a first check only: it gets some LongInteger operations
# wrong, and the port avoids those, but a pass here is confirmed on a TV with
# `scripts/deploy.sh --test`.
#
# Also checks, against the upstream clone ($NOSTALGEX_DIR, default ../nostalgex)
# when there is one, that data/ and the vectors match the commit pinned in
# data/UPSTREAM, and warns when the clone's origin/main has moved past it.
set -euo pipefail
cd "$(dirname "$0")/.."
upstream=${NOSTALGEX_DIR:-../nostalgex}
pinned=$(sed -nE 's/^commit ([0-9a-f]{40}).*/\1/p' data/UPSTREAM)
if [ -d "$upstream/.git" ]; then
    git -C "$upstream" cat-file -e "$pinned^{commit}" 2>/dev/null || {
        echo "FAIL the upstream clone lacks the pinned commit ${pinned:0:7}; fetch it" >&2
        exit 1
    }
    # A throwaway checkout of the pin, so the check doesn't depend on, or move,
    # whatever the clone has checked out.
    pin_dir=$(mktemp -d)
    trap 'rm -rf "$pin_dir"' EXIT
    git clone -q --shared --no-checkout "$upstream" "$pin_dir"
    git -C "$pin_dir" checkout -q "$pinned"
    for f in channels.json channels-memberships.json; do
        cmp -s "$pin_dir/$f" "data/$f" || { echo "FAIL data/$f differs from upstream ${pinned:0:7}" >&2; exit 1; }
    done
    NOSTALGEX_DIR=$pin_dir node tests/gen-vectors.mjs --check
    if ahead=$(git -C "$upstream" rev-list --count "$pinned..origin/main" 2>/dev/null) && [ "$ahead" -gt 0 ]; then
        echo "note: upstream origin/main is $ahead commits past the pinned ${pinned:0:7} (as of the clone's last fetch)"
    fi
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
    tests/main.brs tests/runtime-interpreter.brs tests/ScheduleTests.brs tests/FilterTests.brs tests/LineupTests.brs source/util/*.brs source/schedule/*.brs source/filter/*.brs source/guide/*.brs 2>&1 | grep -v '^npm warn')
echo "$out"
grep -q '^ALL TESTS PASSED' <<<"$out"
