#!/bin/bash
# Draw the home-screen icons and splash into images/ (needs ImageMagick).
# Text only, in the guide panel's logo style (GuideView: VT323, yellow on the
# panel colour), until the maintainer says upstream's artwork may be used.
set -euo pipefail
cd "$(dirname "$0")/.."
bg="#0B0B1C"
fg="#F9E503"
font=fonts/VT323-Regular.ttf
mkdir -p images
draw() { # width height pointsize file
    magick -size "$1x$2" "xc:$bg" -font "$font" -fill "$fg" -pointsize "$3" \
        -gravity center -annotate +0+0 "NOSTALGEX" -depth 8 -strip "images/$4"
}
draw 540 405 120 icon_fhd.png
draw 336 210 76 icon_hd.png
draw 1920 1080 260 splash_fhd.png
