#!/bin/bash
# Time the channel build over a saved library, off-device:
#
#   node tests/bench/dump-library.mjs      # once: out/bench/library.json
#   tests/bench/run.sh [out/bench/<name>.log]
#
# The log holds every channel's pool; diff two runs' POOL lines to prove a
# change leaves the build identical. The interpreter is far slower than a TV,
# so compare its times with each other, not with the TV's.
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -f out/bench/library.json ] || { echo "no out/bench/library.json; run tests/bench/dump-library.mjs" >&2; exit 1; }
log=${1:-out/bench/run.log}
npx -y -p @rokucommunity/brs@0.47.6 brs --root . \
    tests/bench/BenchMain.brs source/util/*.brs source/filter/*.brs source/enrich/*.brs 2>&1 |
    grep -v '^npm warn' >"$log"
grep '^BENCH' "$log" || { tail -20 "$log" >&2; exit 1; }
