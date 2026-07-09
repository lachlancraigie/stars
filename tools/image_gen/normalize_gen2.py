#!/usr/bin/env python3
"""
tools/image_gen/normalize_gen2.py
===================================

Deterministic post-normalization: rescale/re-anchor each staged gen2 sprite's
opaque bounding box onto the exact IsoKit grid contract (512x512 canvas,
130x65 floor diamond centered at (256,311) -- scripts/ship/iso_kit.gd).

WHY THIS EXISTS: the pilot run proved that gpt-image-1-mini gets the *style*
right but cannot hit a pixel contract by prompt alone -- e.g. floor tiles come
back as a 1:1 square diamond filling the frame instead of a 2:1 diamond
spanning the middle 25%. Prompt-side correction of geometry is a losing game
(that's the drift that killed the Reve set). So the pipeline splits duties:
the prompt owns style, PIL owns geometry. Every asset is bbox-detected and
affine-mapped onto per-category anchor targets measured from the legacy
Kenney kit, so gen2 sprites anchor identically to the sprites the game
already positions correctly.

Legacy-kit anchor measurements (alpha>10 bbox on the 512x512 canvases):
    corridor_NE (floor):    bbox (191,210)-(321,348) -> width exactly 130,
                            x-span 256+-65, bottom 348 (65px diamond + 3D lip)
    corridor_wall_NE:       bbox (249,248)-(321,348) -> 72 wide, right edge at
                            the diamond's right corner x=321, bottom 348
    corridor_wall_SE:       bbox (191,248)-(263,348) -> mirrored: left edge at
                            the diamond's left corner x=191, bottom 348
    astronautA_S (crew):    bbox 46x70, feet at y=320, centered x=256
    barrel_NE (prop):       bottom y=320, centered x=256

Category rules (see NORM_RULES):
    floor  -> bbox mapped (non-uniformly) to exactly 130x65 at (256,311).
              Non-uniform is CORRECT here: squashing a 45-degree plan-view
              diamond to 2:1 is precisely how classic 2:1 isometric floor art
              is constructed; the surface detail lands in proper dimetric.
    wall_ne/wall_se/door/prop/crew -> uniform scale (3D volumes must not be
              squashed) + bottom-anchored placement per the table.

Usage:
    python normalize_gen2.py            # normalize everything in report.json
    python normalize_gen2.py --only tile_corridor,door_gate
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
OUT_DIR = REPO_ROOT / "assets" / "sprites" / "gen2"

CANVAS = 512
ALPHA_T = 10

# Per-asset normalization rules. Modes:
#   fit_exact:   map bbox to the exact target rect (non-uniform, floors only)
#   width:       uniform scale to target width, then anchor
#   height:      uniform scale to target height, then anchor
#   fit_within:  uniform scale to fit max_w x max_h (whichever binds), anchor
# Anchors: (anchor_x_mode, x_value, bottom_y)
#   anchor_x_mode in {"center", "left", "right"}
NORM_RULES: dict[str, dict[str, Any]] = {
    "floor": {"mode": "fit_exact", "rect": (191, 279, 321, 344)},  # 130x65 @ (256,311)
    "wall_ne": {"mode": "width", "width": 72, "anchor": ("right", 321, 348)},
    "wall_se": {"mode": "width", "width": 72, "anchor": ("left", 191, 348)},
    "door": {"mode": "width", "width": 84, "anchor": ("center", 256, 343)},
    "prop": {"mode": "fit_within", "max_w": 124, "max_h": 180, "anchor": ("center", 256, 330)},
    "crew": {"mode": "height", "height": 70, "anchor": ("center", 256, 320)},
}

# Map pilot asset ids to a norm rule where the category alone is ambiguous
# (the two wall segments share category "wall" but anchor to opposite corners).
ID_RULE_OVERRIDES = {
    "wall_ne": "wall_ne",
    "wall_se": "wall_se",
}
CATEGORY_RULE = {"floor": "floor", "door": "door", "prop": "prop", "crew": "crew", "wall": "wall_ne"}


def alpha_bbox(im: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = im.convert("RGBA").split()[3]
    return alpha.point(lambda a: 255 if a > ALPHA_T else 0).getbbox()


def normalize(im: Image.Image, rule: dict[str, Any]) -> tuple[Image.Image, dict[str, Any]]:
    rgba = im.convert("RGBA")
    bbox = alpha_bbox(rgba)
    if bbox is None:
        return rgba, {"error": "no opaque pixels"}

    subject = rgba.crop(bbox)
    sw, sh = subject.size
    info: dict[str, Any] = {"source_bbox": bbox, "source_size": [sw, sh]}

    if rule["mode"] == "fit_exact":
        x0, y0, x1, y1 = rule["rect"]
        tw, th = x1 - x0, y1 - y0
        scaled = subject.resize((tw, th), Image.LANCZOS)
        paste_at = (x0, y0)
        info["scale"] = [tw / sw, th / sh]
    else:
        if rule["mode"] == "width":
            s = rule["width"] / sw
        elif rule["mode"] == "height":
            s = rule["height"] / sh
        else:  # fit_within
            s = min(rule["max_w"] / sw, rule["max_h"] / sh)
        tw, th = max(1, round(sw * s)), max(1, round(sh * s))
        scaled = subject.resize((tw, th), Image.LANCZOS)
        mode, x_val, bottom_y = rule["anchor"]
        if mode == "center":
            px = round(x_val - tw / 2)
        elif mode == "left":
            px = x_val
        else:  # right
            px = x_val - tw
        paste_at = (px, bottom_y - th)
        info["scale"] = [s, s]

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(scaled, paste_at, scaled)
    info["target_bbox"] = [paste_at[0], paste_at[1], paste_at[0] + scaled.width, paste_at[1] + scaled.height]
    return canvas, info


def qa_normalized(im: Image.Image, rule: dict[str, Any], info: dict[str, Any]) -> dict[str, Any]:
    """Post-normalization QA: exact contract assertions, replacing the loose
    pre-normalization centroid heuristic."""
    qa: dict[str, Any] = {"notes": []}
    qa["canvas_ok"] = im.size == (CANVAS, CANVAS)

    rgba = im.convert("RGBA")
    corners = [rgba.getpixel(p) for p in [(0, 0), (CANVAS - 1, 0), (0, CANVAS - 1), (CANVAS - 1, CANVAS - 1)]]
    qa["has_alpha"] = sum(1 for px in corners if px[3] <= 25) >= 3

    bbox = alpha_bbox(rgba)
    qa["bbox"] = bbox
    if bbox is None:
        qa["anchored_ok"] = False
        qa["notes"].append("no opaque pixels after normalization")
    else:
        target = info.get("target_bbox")
        tol = 2
        qa["anchored_ok"] = target is not None and all(abs(b - t) <= tol for b, t in zip(bbox, target))
        if not qa["anchored_ok"]:
            qa["notes"].append(f"bbox {bbox} != normalization target {target} (+-{tol})")

    qa["pass"] = qa["canvas_ok"] and qa["has_alpha"] and qa["anchored_ok"]
    return qa


def rule_for(asset_id: str, category: str) -> dict[str, Any]:
    key = ID_RULE_OVERRIDES.get(asset_id) or CATEGORY_RULE.get(category)
    if key is None:
        raise SystemExit(f"no normalization rule for asset {asset_id} (category {category})")
    return NORM_RULES[key]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", type=str, default=None)
    args = parser.parse_args(argv)

    report_path = OUT_DIR / "report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    only = set(args.only.split(",")) if args.only else None

    for asset_id, rec in report["results"].items():
        if only and asset_id not in only:
            continue
        staged = rec.get("staged_path")
        if not staged:
            print(f"{asset_id}: no staged image, skipping")
            continue
        path = REPO_ROOT / staged
        if not path.exists():
            print(f"{asset_id}: {path} missing, skipping")
            continue

        rule = rule_for(asset_id, rec.get("category", ""))
        im = Image.open(path)
        normalized, info = normalize(im, rule)
        qa = qa_normalized(normalized, rule, info)
        normalized.save(path)

        rec["normalize"] = info
        rec["final_qa"] = qa
        status = "PASS" if qa["pass"] else "FLAGGED"
        print(f"{asset_id}: [{status}] {info.get('source_size')} -> bbox {qa.get('bbox')} notes={qa['notes']}")

    report_path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
    print(f"report updated: {report_path}")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
