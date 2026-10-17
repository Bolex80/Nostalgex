#!/bin/bash
# Time the channel build over a saved library, off-device:
#
#   node tests/bench/dump-library.mjs      # once: out/bench/library.json
#   tests/bench/run.sh [out/bench/<name>.log]            every channel's pool
#   tests/bench/run.sh franchise [out/bench/<name>.log]  the franchise step
#
# The log holds every result (POOL lines, or the franchise step's); diff two
# runs' logs, BENCH line aside, to prove a change leaves the build identical.
# The interpreter is far slower than a TV, so compare its times with each
# other, not with the TV's.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -f out/bench/library.json ] || { echo "no out/bench/library.json; run tests/bench/dump-library.mjs" >&2; exit 1; }
main=tests/bench/BenchMain.brs
if [ "${1:-}" = franchise ]; then main=tests/bench/BenchFranchise.brs; shift; fi
log=${1:-out/bench/run.log}
npx -y -p @rokucommunity/brs@0.47.6 brs --root . \
    "$main" source/util/*.brs source/filter/*.brs source/enrich/*.brs source/franchise/*.brs source/guide/*.brs 2>&1 |
    grep -v '^npm warn' >"$log"
grep '^BENCH' "$log" || { tail -20 "$log" >&2; exit 1; }
