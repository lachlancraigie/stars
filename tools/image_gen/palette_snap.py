#!/usr/bin/env python3
"""
tools/image_gen/palette_snap.py
=================================

Mechanical palette enforcement for the gen2 crew set (docs/style-bible-v2.md
consistency strategy, part B "PALETTE SNAP"): every generated crew sprite's
OPAQUE pixels are nearest-neighbor snapped onto ONE fixed character palette,
independent of whatever shade the model actually painted. This is what turns
cross-sheet identity into a mechanical guarantee instead of a prompt-
compliance hope -- two sheets that drift toward slightly different
grays/tans still collapse onto identical palette entries after this pass, so
a diff between two snapped, same-region crops is either exactly zero or a
real error, never "close enough to eyeball".

CHARACTER_PALETTE below was picked from the approved base idle 8-facing sheet
(assets/sprites/gen2/crew/_base_idle_sheet_raw.png) via `--extract` band
sampling (head/torso/legs bands on the alpha bbox): the suit tones landed
almost exactly on three of the style bible's existing 10 hex values (Steel
Light/Mid/Dark), so those were snapped onto the bible's own hex codes exactly
(crew now visually matches the gen2 environment set's material language, per
the bible's "crew are generated in the neutral Off-White/Steel family" note).
The bible has no skin/hair hex (it only speaks to structure/accent colors,
not a human figure), so SKIN and HAIR are new fixed entries picked from the
base sheet's own head band -- held constant from here on, not drift.

Usage:
    python palette_snap.py --extract path/to/sheet.png [--bands 5]
        Prints per-vertical-band dominant colors (rounded/quantized) on the
        image's opaque bbox, to choose or sanity-check CHARACTER_PALETTE.

    python palette_snap.py --in path/to/sprite.png --out path/to/out.png
        Snap one sprite in place (or to --out).

    python palette_snap.py --in-dir DIR --out-dir DIR
        Snap every *.png in DIR to OUT_DIR (same filenames).

    python palette_snap.py --delta a.png b.png [--region x0,y0,x1,y1]
        Report the mean-color delta between two (already snapped or raw)
        images over a region -- the QA-gate number: should be ~0 after
        snapping if both frames are the same character/region.
"""

from __future__ import annotations

import argparse
import math
from collections import Counter
from pathlib import Path

from PIL import Image

ALPHA_T = 10

# ---------------------------------------------------------------------------
# THE fixed character palette (RGB). Order doesn't matter for snapping; kept
# grouped/labeled for human readability. Outline + the four Steel tones + the
# Off-White are the style bible's own hex values verbatim (docs/style-
# bible-v2.md's "Locked palette" table) -- reused for the suit so crew match
# the gen2 environment kit's material language. Skin/hair/cyan-accent are new
# fixed entries (the bible has no figure-specific hues); amber is kept
# available for any warm accent detail (patches, tool belts) but the base
# sheet didn't use it saliently.
# ---------------------------------------------------------------------------
CHARACTER_PALETTE: dict[str, tuple[int, int, int]] = {
    "outline":        (0x14, 0x17, 0x1C),  # bible Outline
    "suit_light":     (0xC7, 0xCE, 0xD6),  # bible Steel Light -- suit lit facets
    "suit_mid":       (0x8B, 0x95, 0xA1),  # bible Steel Mid -- suit base/shadow facets
    "suit_dark":      (0x4E, 0x56, 0x61),  # bible Steel Dark -- boots, cap/hair, deep shadow
    "suit_deepest":   (0x2A, 0x2F, 0x36),  # bible Steel Deepest -- creases, AO pockets
    "trim_offwhite":  (0xED, 0xEF, 0xF2),  # bible Off-White -- small trim/panel accents
    "skin":           (0xE0, 0xB8, 0x98),  # new: base skin tone (base-sheet head band)
    "skin_shadow":    (0xB8, 0x89, 0x5F),  # new: skin shadow tone (cel-shading the face/hands)
    "accent_cyan_lt": (0x6F, 0xE3, 0xE0),  # bible Cyan Light -- reserved (visor/patch/device)
    "accent_cyan_dk": (0x2C, 0x9A, 0x98),  # bible Cyan Dark -- shadow tone for the above
    "accent_amber_lt": (0xFF, 0xC8, 0x57), # bible Amber Light -- reserved (tool/warning detail)
    "accent_amber_dk": (0xC9, 0x82, 0x2A), # bible Amber Dark -- shadow tone for the above
}

PALETTE_LIST: list[tuple[int, int, int]] = list(CHARACTER_PALETTE.values())


def _nearest(rgb: tuple[int, int, int], palette: list[tuple[int, int, int]]) -> tuple[int, int, int]:
    best = palette[0]
    best_d = math.inf
    r, g, b = rgb
    for pr, pg, pb in palette:
        d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
        if d < best_d:
            best_d = d
            best = (pr, pg, pb)
    return best


def snap_image(im: Image.Image, palette: list[tuple[int, int, int]] | None = None,
                alpha_threshold: int = ALPHA_T) -> Image.Image:
    """Nearest-neighbor snap every opaque pixel's RGB onto `palette`. Alpha is
    untouched (including partial-alpha edge/AA pixels, so silhouette edges
    stay smooth); pixels at/under alpha_threshold are left alone entirely
    (background noise, harmless either way since alpha hides them)."""
    palette = palette or PALETTE_LIST
    rgba = im.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a <= alpha_threshold:
                continue
            key = (r, g, b)
            snapped = cache.get(key)
            if snapped is None:
                snapped = _nearest(key, palette)
                cache[key] = snapped
            if snapped != key:
                px[x, y] = (snapped[0], snapped[1], snapped[2], a)
    return rgba


# ---------------------------------------------------------------------------
# Extraction: band-sampled dominant colors, used to pick/verify the palette.
# ---------------------------------------------------------------------------


def alpha_bbox(im: Image.Image, alpha_threshold: int = ALPHA_T) -> tuple[int, int, int, int] | None:
    alpha = im.convert("RGBA").split()[3]
    return alpha.point(lambda a: 255 if a > alpha_threshold else 0).getbbox()


def extract_bands(im: Image.Image, bands: int = 5, top_n: int = 6) -> list[list[tuple[tuple[int, int, int], int]]]:
    rgba = im.convert("RGBA")
    bbox = alpha_bbox(rgba)
    if bbox is None:
        return []
    x0, y0, x1, y1 = bbox
    bh = (y1 - y0) / bands
    px = rgba.load()
    out = []
    for band in range(bands):
        by0 = int(y0 + band * bh)
        by1 = int(y0 + (band + 1) * bh)
        c: Counter = Counter()
        for y in range(by0, by1):
            for x in range(x0, x1):
                r, g, b, a = px[x, y]
                if a > 200:
                    c[(r // 8 * 8, g // 8 * 8, b // 8 * 8)] += 1
        out.append(c.most_common(top_n))
    return out


# ---------------------------------------------------------------------------
# Delta: mean-color comparison over a region, for the cross-sheet QA gate.
# ---------------------------------------------------------------------------


def mean_color(im: Image.Image, region: tuple[int, int, int, int] | None = None,
                alpha_threshold: int = ALPHA_T) -> tuple[float, float, float] | None:
    rgba = im.convert("RGBA")
    if region:
        rgba = rgba.crop(region)
    px = rgba.load()
    w, h = rgba.size
    sr = sg = sb = n = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > alpha_threshold:
                sr += r
                sg += g
                sb += b
                n += 1
    if n == 0:
        return None
    return (sr / n, sg / n, sb / n)


def color_delta(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--extract", type=Path, help="print band-sampled dominant colors for this image")
    parser.add_argument("--bands", type=int, default=5)
    parser.add_argument("--in", dest="in_path", type=Path)
    parser.add_argument("--out", dest="out_path", type=Path)
    parser.add_argument("--in-dir", dest="in_dir", type=Path)
    parser.add_argument("--out-dir", dest="out_dir", type=Path)
    parser.add_argument("--delta", nargs=2, type=Path, metavar=("A", "B"))
    parser.add_argument("--region", type=str, default=None, help="x0,y0,x1,y1 for --delta")
    args = parser.parse_args(argv)

    if args.extract:
        im = Image.open(args.extract)
        bands = extract_bands(im, bands=args.bands)
        print(f"{args.extract} bbox={alpha_bbox(im)}")
        for i, band in enumerate(bands):
            print(f" band {i}:")
            for color, count in band:
                print(f"   #{color[0]:02x}{color[1]:02x}{color[2]:02x}  n={count}")
        return 0

    if args.delta:
        a_path, b_path = args.delta
        region = None
        if args.region:
            region = tuple(int(v) for v in args.region.split(","))
        ma = mean_color(Image.open(a_path), region)
        mb = mean_color(Image.open(b_path), region)
        print(f"{a_path.name}: mean {ma}")
        print(f"{b_path.name}: mean {mb}")
        if ma and mb:
            print(f"delta: {color_delta(ma, mb):.2f}")
        return 0

    if args.in_dir and args.out_dir:
        args.out_dir.mkdir(parents=True, exist_ok=True)
        for p in sorted(args.in_dir.glob("*.png")):
            im = Image.open(p)
            snapped = snap_image(im)
            snapped.save(args.out_dir / p.name)
            print(f"snapped {p.name}")
        return 0

    if args.in_path:
        im = Image.open(args.in_path)
        snapped = snap_image(im)
        out = args.out_path or args.in_path
        snapped.save(out)
        print(f"snapped -> {out}")
        return 0

    parser.error("nothing to do -- pass --extract, --delta, --in/--out, or --in-dir/--out-dir")
    return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
