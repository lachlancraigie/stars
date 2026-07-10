#!/usr/bin/env python3
"""
tools/image_gen/contact_sheet.py
==================================

Builds assets/sprites/gen2/contact_sheet.png: every staged gen2 sprite laid out
in a labeled grid, composited over BOTH a dark checkerboard and a light
checkerboard (stacked as two bands) so transparency and cel-shaded contrast can
be judged on either background at a glance -- the whole point of this pilot is
judging cross-asset consistency, which a single background can flatter or hide.

Reads assets/sprites/gen2/report.json (written by pilot_batch.py) for per-asset
PASS/FLAGGED QA status to annotate under each label; falls back to "no QA data"
if report.json or an entry is missing so this can also be pointed at a folder of
manually-added PNGs.

Usage:
    python contact_sheet.py
    python contact_sheet.py --out-dir ../../assets/sprites/gen2
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
DEFAULT_DIR = REPO_ROOT / "assets" / "sprites" / "gen2"

THUMB = 220  # px, square
LABEL_H = 34
PAD = 14
COLS = 4
CHECKER = 20  # checker cell size
SECTION_H = 34  # header strip inserted whenever the category changes

# Category display order (matches docs/style-bible-v2.md's per-category framing
# table); anything with an unrecognised/missing category sorts last so a typo
# in report.json can't silently vanish from the sheet.
CATEGORY_ORDER = ["floor", "wall", "door", "prop", "crew"]


def category_rank(category: str) -> int:
    try:
        return CATEGORY_ORDER.index(category)
    except ValueError:
        return len(CATEGORY_ORDER)

# Crop window on the 512x512 canvas centered on the grid-contract action area
# (diamond at (256,311), subjects rise above it): x 146..366, y 131..351.
CROP = (146, 131, 366, 351)
# IsoKit floor diamond, in canvas coordinates: 130x65 centered (256,311).
DIAMOND = [(256, 278.5), (321, 311), (256, 343.5), (191, 311)]


def checker_bg(size: tuple[int, int], light: tuple[int, int, int], dark: tuple[int, int, int]) -> Image.Image:
    w, h = size
    im = Image.new("RGB", size, light)
    px = im.load()
    for y in range(h):
        for x in range(w):
            if (x // CHECKER + y // CHECKER) % 2 == 0:
                px[x, y] = dark
    return im


def load_font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype("arial.ttf", size)
    except Exception:
        return ImageFont.load_default()


def band(assets: list[dict], out_dir: Path, *, checker_light, checker_dark, text_color, band_label: str) -> Image.Image:
    # Group by category (already sorted (category_rank, id) by the caller) so
    # the sheet reads as sections -- floor / wall / door / prop / crew -- with
    # a header strip between them, instead of one flat alphabetical grid.
    groups: list[tuple[str, list[dict]]] = []
    for asset in assets:
        cat = asset.get("category") or "(uncategorized)"
        if not groups or groups[-1][0] != cat:
            groups.append((cat, []))
        groups[-1][1].append(asset)

    cell_w = THUMB + PAD * 2
    cell_h = THUMB + LABEL_H * 2 + PAD * 2
    width = cell_w * COLS
    total_rows = sum((len(g) + COLS - 1) // COLS for _, g in groups)
    height = 40 + total_rows * cell_h + len(groups) * SECTION_H

    canvas = checker_bg((width, height), checker_light, checker_dark)
    draw = ImageDraw.Draw(canvas)
    font = load_font(16)
    font_section = load_font(18)
    font_small = load_font(13)
    draw.text((PAD, 8), band_label, fill=text_color, font=font)

    y_cursor = 40
    for cat, group in groups:
        draw.rectangle([0, y_cursor, width, y_cursor + SECTION_H], fill=checker_dark)
        draw.text((PAD, y_cursor + 6), f"{cat.upper()}  ({len(group)})", fill=text_color, font=font_section)
        y_cursor += SECTION_H

        for i, asset in enumerate(group):
            col, row = i % COLS, i // COLS
            cx = col * cell_w + PAD
            cy = y_cursor + row * cell_h + PAD

            png_path = out_dir / f"{asset['id']}.png"
            if png_path.exists():
                sprite = Image.open(png_path).convert("RGBA")
                if sprite.size == (512, 512):
                    # Draw the IsoKit contract diamond under the sprite so anchor
                    # consistency across assets is visible at a glance, then crop
                    # to the action window (the rest of the canvas is empty air).
                    overlay = Image.new("RGBA", sprite.size, (0, 0, 0, 0))
                    odraw = ImageDraw.Draw(overlay)
                    odraw.polygon(DIAMOND, outline=(255, 60, 120, 200))
                    composed = Image.alpha_composite(overlay, sprite)
                    sprite = composed.crop(CROP)
                sprite.thumbnail((THUMB, THUMB), Image.LANCZOS)
                offset = (cx + (THUMB - sprite.width) // 2, cy + (THUMB - sprite.height) // 2)
                canvas.paste(sprite, offset, sprite)
            else:
                draw.rectangle([cx, cy, cx + THUMB, cy + THUMB], outline=text_color)
                draw.text((cx + 8, cy + THUMB // 2), "MISSING", fill=text_color, font=font_small)

            label_y = cy + THUMB + 4
            draw.text((cx, label_y), asset["id"], fill=text_color, font=font_small)
            status = asset.get("qa_status", "no QA data")
            draw.text((cx, label_y + 16), status, fill=text_color, font=font_small)

        rows_in_group = (len(group) + COLS - 1) // COLS
        y_cursor += rows_in_group * cell_h

    return canvas


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_DIR)
    args = parser.parse_args(argv)

    out_dir: Path = args.out_dir
    report_path = out_dir / "report.json"

    assets: list[dict] = []
    if report_path.exists():
        report = json.loads(report_path.read_text(encoding="utf-8"))
        for asset_id, rec in report.get("results", {}).items():
            final_qa = rec.get("final_qa") or {}
            n_attempts = len(rec.get("attempts", []))
            if final_qa.get("pass"):
                status = f"PASS (attempt {n_attempts})"
            elif final_qa:
                status = f"FLAGGED (attempt {n_attempts}): " + "; ".join(final_qa.get("notes", []))[:60]
            else:
                status = "FAILED (no image)"
            assets.append({"id": asset_id, "category": rec.get("category", ""), "qa_status": status})
        assets.sort(key=lambda a: (category_rank(a["category"]), a["id"]))
    else:
        # fall back to whatever PNGs exist on disk
        for png in sorted(out_dir.glob("*.png")):
            if png.name == "contact_sheet.png":
                continue
            assets.append({"id": png.stem, "category": "", "qa_status": "no QA data"})

    if not assets:
        raise SystemExit(f"no assets found in {out_dir} (and no report.json)")

    dark_band = band(
        assets, out_dir,
        checker_light=(40, 40, 44), checker_dark=(28, 28, 32),
        text_color=(235, 235, 240), band_label="DARK background",
    )
    light_band = band(
        assets, out_dir,
        checker_light=(238, 238, 240), checker_dark=(214, 214, 218),
        text_color=(20, 20, 24), band_label="LIGHT background",
    )

    width = max(dark_band.width, light_band.width)
    gap = 16
    sheet = Image.new("RGB", (width, dark_band.height + gap + light_band.height), (10, 10, 10))
    sheet.paste(dark_band, (0, 0))
    sheet.paste(light_band, (0, dark_band.height + gap))

    out_path = out_dir / "contact_sheet.png"
    sheet.save(out_path)
    print(f"saved {out_path} ({sheet.width}x{sheet.height}, {len(assets)} assets)")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
