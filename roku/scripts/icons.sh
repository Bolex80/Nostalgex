#!/bin/bash
# Draw the home-screen icons, the splash and the in-app logo into images/
# from the Nostalgex brand: the NOSTALGEX wordmark with a TV for the O, as on
# nostalgex.app (upstream logo/README.md). Roku can't draw SVG, so upstream's
# transparent PNG master (logo/png/nostalgex-white-1600w.png) is scaled
# down, on the panel colour. Needs ImageMagick and the upstream clone
# ($NOSTALGEX_DIR, default ../nostalgex), read at $NOSTALGEX_REF (default
# origin/main), so the working tree it has checked out doesn't matter.
set -euo pipefail
cd "$(dirname "$0")/.."
upstream=${NOSTALGEX_DIR:-../nostalgex}
ref=${NOSTALGEX_REF:-origin/main}
bg="#0B0B1C"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
git -C "$upstream" show "$ref:logo/png/nostalgex-white-1600w.png" >"$work/wordmark.png"
echo "logo from upstream $(git -C "$upstream" rev-parse --short "$ref")"
mkdir -p images
draw() { # width height logo-width file
    magick -size "$1x$2" "xc:$bg" \( "$work/wordmark.png" -resize "$3x" \) \
        -gravity center -composite -depth 8 -strip "images/$4"
}
draw 540 405 440 icon_fhd.png
draw 290 218 236 icon_hd.png
draw 1920 1080 900 splash_fhd.png
draw 1280 720 600 splash_hd.png
# The in-app logo (guide bar, sign-in, progress and picker screens), on
# transparency, at the largest size shown.
magick "$work/wordmark.png" -resize 900x -strip images/logo.png
