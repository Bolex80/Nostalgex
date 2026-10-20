#!/bin/bash
# Run Roku's Static Channel Analysis, the check a Channel Store submission
# runs, on the app as deploy.sh would package it (without enrichment keys).
# Needs podman; the tool and a Java 21 image are fetched on first use. The
# report goes to out/sca/report.txt; exits non-zero when it lists an [ERROR].
set -euo pipefail
cd "$(dirname "$0")/.."
tool=${SCA_DIR:-$HOME/.cache/roku-sca}
if [ ! -f "$tool/tool/sca-cmd/lib/sca-cmd.jar" ]; then
    mkdir -p "$tool"
    curl -sSfL -o "$tool/sca-cmd.zip" https://devtools.web.roku.com/static-channel-analysis/sca-cmd.zip
    rm -rf "$tool/tool" && mkdir -p "$tool/tool" && unzip -q "$tool/sca-cmd.zip" -d "$tool/tool"
fi
rm -rf out/sca && mkdir -p out/sca/stage
cp -r manifest source components "out/sca/stage/"
# The MIT notice and the fonts' licences travel with the app (the Channel
# Store needs them; Discussion #8, item 6).
# The third-party notices go under licenses/: at the zip's root the static
# analysis calls the file extraneous (the maintainer's sca-cmd run, Discussion #8).
cp LICENSE out/sca/stage/
mkdir -p out/sca/stage/licenses
cp THIRD-PARTY-LICENSES.md out/sca/stage/licenses/THIRD-PARTY-LICENSES.txt
for d in images data fonts; do [ -d "$d" ] && cp -r "$d" out/sca/stage/; done
rm -f out/sca/stage/data/enrichment.json
(cd out/sca/stage && zip -qr ../app.zip .)
podman run --rm -v "$tool/tool/sca-cmd/lib:/tool:ro,Z" -v "$PWD/out/sca:/work:ro,Z" \
    docker.io/library/eclipse-temurin:21-jre java -jar /tool/sca-cmd.jar /work/app.zip --severity info \
    >out/sca/report.txt 2>&1
grep -E '^\[(ERROR|WARNING)\]' out/sca/report.txt || true
! grep -q '^\[ERROR\]' out/sca/report.txt
