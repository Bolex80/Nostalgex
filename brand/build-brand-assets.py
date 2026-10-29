#!/usr/bin/env python3
"""Build the BolexTV brand assets: three mark options, exports, banner, contact sheets.

One source of truth for geometry. The SVG master and every PNG are generated from the
same numbers, so a corrected coordinate cannot drift between the vector and the raster.

Usage:  python3 brand/build-brand-assets.py
Output: brand/assets/
"""

from __future__ import annotations

import pathlib
import subprocess

from PIL import Image, ImageDraw, ImageFont

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "assets"
V = "20261029-v1"          # household convention: -YYYYMMDD-vN

# --- palette: one brand colour, one neutral, one accent. Nothing else. -------------
AMBER = "#E9A13B"          # brand
INK = "#12151A"            # neutral
CREAM = "#F2EAE1"          # accent

FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_BOOK = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"

MASTER = 1024
TILE = (112, 112, 800, 800, 224)   # x, y, w, h, rx


def _svg(body: str, w: int = MASTER, h: int = MASTER) -> str:
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
        f'viewBox="0 0 {w} {h}" role="img">\n{body}\n</svg>\n'
    )


def _tile(fill: str) -> str:
    x, y, w, h, rx = TILE
    return f'  <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"/>'


def mark_guide_play() -> str:
    """Play triangle + schedule rows: a channel playing inside a guide."""
    # Content block spans x 232..786, y 358..666: bars 76 tall with 40 gutters, so the
    # row stack still resolves at 40 px (3.0 px bars, 1.6 px gaps) rather than merging.
    return _svg(
        _tile(AMBER) + "\n"
        # play triangle, optically centred against the row stack
        f'  <path d="M232 358 L232 666 L470 512 Z" fill="{INK}"/>\n'
        # guide rows, longest first — reads as a schedule listing
        f'  <rect x="506" y="358" width="280" height="76" rx="18" fill="{INK}"/>\n'
        f'  <rect x="506" y="474" width="280" height="76" rx="18" fill="{INK}"/>\n'
        f'  <rect x="506" y="590" width="188" height="76" rx="18" fill="{INK}"/>'
    )


def mark_tuner_dial() -> str:
    """A set-top tuner knob: ring, needle, hub. The nostalgic reading."""
    return _svg(
        _tile(INK) + "\n"
        f'  <circle cx="512" cy="512" r="212" fill="{AMBER}"/>\n'
        f'  <circle cx="512" cy="512" r="150" fill="{INK}"/>\n'
        f'  <line x1="512" y1="512" x2="634" y2="390" stroke="{CREAM}" '
        f'stroke-width="48" stroke-linecap="round"/>\n'
        f'  <circle cx="512" cy="512" r="34" fill="{CREAM}"/>'
    )


def mark_epg_grid() -> str:
    """Programme blocks on a guide grid; the cream block is what is on now."""
    # row y positions: 3 rows of 140 with 36 gutters, centred on 512
    ys = [266, 442, 618]
    blocks = [
        (0, 192, 300, AMBER), (0, 524, 308, AMBER),
        (1, 192, 404, CREAM), (1, 628, 204, AMBER),
        (2, 192, 236, AMBER), (2, 460, 372, AMBER),
    ]
    parts = [_tile(INK)]
    for row, x, w, fill in blocks:
        parts.append(
            f'  <rect x="{x}" y="{ys[row]}" width="{w}" height="140" rx="28" fill="{fill}"/>'
        )
    return _svg("\n".join(parts))


OPTIONS = {
    "guide-play": (mark_guide_play, "Guide Play"),
    "tuner-dial": (mark_tuner_dial, "Tuner Dial"),
    "epg-grid": (mark_epg_grid, "EPG Grid"),
}
RECOMMENDED = "guide-play"


def render(svg: pathlib.Path, png: pathlib.Path, w: int, h: int) -> None:
    subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), "-o", str(png), str(svg)],
                   check=True)


def build_banner(mark_png: pathlib.Path, out: pathlib.Path) -> None:
    """Android TV launcher banner: 320x180, mark left, wordmark right."""
    W, H = 320, 180
    img = Image.new("RGBA", (W, H), INK)
    d = ImageDraw.Draw(img)

    # subtle guide baseline so the banner is not a flat black rectangle
    d.rectangle([0, H - 6, W, H - 3], fill=AMBER)

    mark = Image.open(mark_png).convert("RGBA").resize((112, 112), Image.Resampling.LANCZOS)
    img.alpha_composite(mark, (24, (H - 112) // 2 - 3))

    # wordmark: "Bolex" cream + "TV" amber, auto-fitted to the remaining width
    room = W - (24 + 112 + 22) - 18
    size = 44
    while size > 18:
        f = ImageFont.truetype(FONT_BOLD, size)
        if d.textlength("BolexTV", font=f) <= room:
            break
        size -= 1
    f = ImageFont.truetype(FONT_BOLD, size)
    x0 = 24 + 112 + 22
    baseline_y = (H - size) // 2 - 4
    d.text((x0, baseline_y), "Bolex", font=f, fill=CREAM)
    x1 = x0 + d.textlength("Bolex", font=f)
    d.text((x1, baseline_y), "TV", font=f, fill=AMBER)

    img.convert("RGB").save(out)


def _circle(im: Image.Image, size: int) -> Image.Image:
    im = im.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    return out


def build_contact_sheet(pngs: dict[str, pathlib.Path], out: pathlib.Path, dark: bool) -> None:
    bg = INK if dark else "#F7F7F7"
    fg = CREAM if dark else INK
    W, ROW = 980, 210
    img = Image.new("RGB", (W, 60 + ROW * len(pngs)), bg)
    d = ImageDraw.Draw(img)
    d.text((30, 18), "BolexTV mark candidates — real size, circular crops", font=
           ImageFont.truetype(FONT_BOLD, 19), fill=fg)

    sizes = [160, 96, 64, 40]
    xs = {160: 470, 96: 650, 64: 766, 40: 850}
    for i, (key, path) in enumerate(pngs.items()):
        top = 60 + i * ROW
        label = OPTIONS[key][1] + ("  ★" if key == RECOMMENDED else "")
        d.text((30, top + 78), label, font=ImageFont.truetype(FONT_BOLD, 17), fill=fg)
        base = Image.open(path).convert("RGBA")
        big = base.resize((180, 180), Image.Resampling.LANCZOS)
        img.paste(big, (262, top + 10), big)
        for s in sizes:
            c = _circle(base, s)
            img.paste(c, (xs[s], top + 10 + (180 - s) // 2), c)
        for s in sizes:
            d.text((xs[s], top + 196), f"{s}px", font=ImageFont.truetype(FONT_BOOK, 11), fill=fg)

    img.save(out)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    pngs: dict[str, pathlib.Path] = {}

    for key, (fn, _label) in OPTIONS.items():
        svg = OUT / f"bolextv-logo-{key}-{V}.svg"
        svg.write_text(fn(), encoding="utf-8")
        png = OUT / f"bolextv-logo-{key}-{V}.png"
        render(svg, png, MASTER, MASTER)
        pngs[key] = png
        print(f"  {svg.name}\n  {png.name}")

    rec = pngs[RECOMMENDED]
    icon = OUT / f"bolextv-icon-512-{V}.png"
    render(OUT / f"bolextv-logo-{RECOMMENDED}-{V}.svg", icon, 512, 512)
    banner = OUT / f"bolextv-banner-320x180-{V}.png"
    build_banner(rec, banner)

    dark_sheet = OUT / f"bolextv-contact-sheet-dark-{V}.png"
    light_sheet = OUT / f"bolextv-contact-sheet-light-{V}.png"
    build_contact_sheet(pngs, dark_sheet, dark=True)
    build_contact_sheet(pngs, light_sheet, dark=False)

    for p in (icon, banner, dark_sheet, light_sheet):
        print(f"  {p.name}")


if __name__ == "__main__":
    main()
