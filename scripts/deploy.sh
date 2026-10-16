#!/bin/bash
# Zip the channel and sideload it to every TV in ROKU_HOSTS (from .env), then
# launch it. Each TV holds one sideloaded channel; installing replaces it.
#
#   scripts/deploy.sh          the app
#   scripts/deploy.sh --test   a test build: tests/main.brs replaces the app's
#                              entry point, runs the golden vectors on the TV,
#                              and the result is read from its debug console
#                              (port 8085). Exits non-zero unless every TV passes.
#   scripts/deploy.sh --live   a live-check build: tests/live/LiveMain.brs loads
#                              the signed-in Plex library and prints fingerprints
#                              to out/live-<tv>.log for tests/live/compare.mjs.
set -euo pipefail
cd "$(dirname "$0")/.."
test_build=false
mode=app
case "${1:-}" in
    --test) test_build=true; mode=test ;;
    --live) test_build=true; mode=live ;;
esac
wait_s=${TEST_TIMEOUT:-600} # seconds to wait for a TV's test result
[ -f .env ] || { echo "no .env — copy .env.example" >&2; exit 1; }
# shellcheck source=/dev/null
. ./.env
: "${ROKU_HOSTS:?set ROKU_HOSTS in .env}" "${ROKU_DEV_PASSWORD:?set ROKU_DEV_PASSWORD in .env}"

stage=out/stage
rm -rf "$stage" out/nostalgex-roku.zip
mkdir -p "$stage"
cp -r manifest source components "$stage"/
for d in images data fonts; do [ -d "$d" ] && cp -r "$d" "$stage"/; done
# Enrichment (source/enrich/Enrichment.brs) is in a build only when .env turns
# it on and gives the Supabase project; the values go into the zip, never the
# repo. Without them the app runs with no enrichment, as before.
rm -f "$stage"/data/enrichment.json
if [ "${NOSTALGEX_ENRICHMENT:-off}" = on ]; then
    url=${NOSTALGEX_SUPABASE_URL:-} key=${NOSTALGEX_SUPABASE_ANON_KEY:-}
    [[ $url =~ ^https://[A-Za-z0-9.-]+/?$ ]] || { echo "NOSTALGEX_ENRICHMENT=on needs NOSTALGEX_SUPABASE_URL (https://<project>.supabase.co)" >&2; exit 1; }
    [[ $key =~ ^[A-Za-z0-9._-]+$ ]] || { echo "NOSTALGEX_ENRICHMENT=on needs NOSTALGEX_SUPABASE_ANON_KEY" >&2; exit 1; }
    printf '{"supabaseURL":"%s","anonKey":"%s"}\n' "$url" "$key" >"$stage"/data/enrichment.json
    echo "build: enrichment on"
fi
if [ "$mode" = test ]; then
    cp tests/main.brs tests/runtime-device.brs tests/ScheduleTests.brs tests/FilterTests.brs tests/LineupTests.brs tests/FranchiseTests.brs tests/FranchiseGuideTests.brs tests/EnrichmentTests.brs tests/SubtitleTests.brs tests/GuideNavTests.brs tests/DeepLinkTests.brs tests/CollectionTests.brs tests/ServerChoiceTests.brs "$stage"/source/
    mkdir -p "$stage"/tests && cp -r tests/vectors "$stage"/tests/
elif [ "$mode" = live ]; then
    cp tests/live/LiveMain.brs "$stage"/source/main.brs
fi
(cd "$stage" && zip -qr ../nostalgex-roku.zip .)

failed=0
for host in $ROKU_HOSTS; do
    if $test_build; then
        # Connect to the debug console before installing, because installing
        # launches the app. On connect the console replays recent output, which
        # can hold an older run's result, so only what arrives after the replay
        # (past $mark) counts.
        log=out/$mode-"$host".log
        timeout "$((wait_s + 10))" bash -c 'exec 3<>"/dev/tcp/$0/8085" && cat <&3' "$host" >"$log" 2>&1 &
        listener=$!
        sleep 3
        mark=$(stat -c %s "$log")
    fi
    code=$(curl -s -o out/install-"$host".html -w '%{http_code}' --digest \
        -u "rokudev:$ROKU_DEV_PASSWORD" -F mysubmit=Install \
        -F "archive=@out/nostalgex-roku.zip" "http://$host/plugin_install")
    if [ "$code" != 200 ] || ! grep -qiE 'Install Success|Identical to previous' out/install-"$host".html; then
        echo "$host: install failed (HTTP $code) — see out/install-$host.html" >&2
        $test_build && kill "$listener" 2>/dev/null
        failed=1
        continue
    fi
    # Installing starts the app on most TVs; a second launch would race it.
    sleep 2
    if ! curl -s -m 5 "http://$host:8060/query/active-app" | grep -q 'id="dev"'; then
        curl -s -o /dev/null -X POST "http://$host:8060/launch/dev"
    fi
    if ! $test_build; then
        echo "$host: installed and launched"
        continue
    fi
    fresh() { tail -c +"$((mark + 1))" "$log" | tr -d '\r'; }
    for _ in $(seq 1 "$wait_s"); do
        fresh | grep -qE 'ALL TESTS PASSED|TESTS FAILED|LIVE DONE|LIVE FAILED|BrightScript Micro Debugger' && break
        sleep 1
    done
    kill "$listener" 2>/dev/null || true
    fresh | grep -E '^FAIL|^    (want|got)| vectors | took |filter: |TESTS|^LIVE |Micro Debugger|runtime error' | sed "s/^/$host: /" || true
    if ! fresh | grep -qE 'ALL TESTS PASSED|LIVE DONE'; then
        echo "$host: tests did not pass — full console in $log" >&2
        failed=1
    fi
done
exit $failed
