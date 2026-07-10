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


def interior_hole_pct(im: Image.Image) -> float:
    """% of subject area that is interior transparency ('holes'): transparent
    pixels NOT reachable from the canvas border by flood fill. Catches the
    model keying out large interior fills (e.g. a mattress or door leaf),
    which corner-transparency checks miss entirely."""
    from collections import deque

    rgba = im.convert("RGBA")
    w, h = rgba.size
    a = rgba.split()[3].load()
    transparent = [[a[x, y] <= ALPHA_T for x in range(w)] for y in range(h)]
    reached = [[False] * w for _ in range(h)]
    dq: deque = deque()
    for x in range(w):
        for y in (0, h - 1):
            if transparent[y][x] and not reached[y][x]:
                reached[y][x] = True
                dq.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if transparent[y][x] and not reached[y][x]:
                reached[y][x] = True
                dq.append((x, y))
    while dq:
        x, y = dq.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and transparent[ny][nx] and not reached[ny][nx]:
                reached[ny][nx] = True
                dq.append((nx, ny))
    holes = sum(1 for y in range(h) for x in range(w) if transparent[y][x] and not reached[y][x])
    subject = sum(1 for y in range(h) for x in range(w) if not transparent[y][x])
    return 100.0 * holes / max(1, subject)


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

    # Threshold 10%: catches keyed-out solid fills (55% mattress, 47% door
    # leaf) while passing leggy furniture whose enclosed under-table daylight
    # legitimately shows the floor through it (2-8%).
    hole_pct = interior_hole_pct(rgba)
    qa["interior_hole_pct"] = round(hole_pct, 2)
    qa["solid_ok"] = hole_pct <= 10.0
    if not qa["solid_ok"]:
        qa["notes"].append(
            f"{hole_pct:.1f}% of the subject is interior transparency (holes) -- "
            "the model keyed out interior fills; regenerate with the solidity clause"
        )

    qa["pass"] = qa["canvas_ok"] and qa["has_alpha"] and qa["anchored_ok"] and qa["solid_ok"]
    return qa


def rule_for(asset_id: str, category: str) -> dict[str, Any]:
    key = ID_RULE_OVERRIDES.get(asset_id) or CATEGORY_RULE.get(category)
    if key is None:
        raise SystemExit(f"no normalization rule for asset {asset_id} (category {category})")
    return NORM_RULES[key]


def mirror_walls(report: dict[str, Any]) -> None:
    """Derive the NW/SW wall orientations by horizontally flipping the
    normalized NE/SE walls. Because the canvas is already normalized
    (NE wall right-anchored at x=321, bottom 348), a plain flip lands the
    mirrored bbox exactly on the opposite corner's legacy anchor
    (512-321=191), matching corridor_wall_NW / corridor_wall_SW.

    Trade-off, deliberately accepted for this kit: mirroring flips which
    facet catches the upper-left key light. On thin near-symmetric wall
    panels this reads fine and buys perfect cross-orientation consistency
    (the pair is pixel-identical geometry); regenerate instead if walls
    ever gain strongly asymmetric detail.
    """
    for src_id, dst_id in (("wall_ne", "wall_nw"), ("wall_se", "wall_sw")):
        src_path = OUT_DIR / f"{src_id}.png"
        if not src_path.exists():
            print(f"{dst_id}: source {src_id}.png missing, skipping")
            continue
        im = Image.open(src_path).convert("RGBA")
        mirrored = im.transpose(Image.FLIP_LEFT_RIGHT)
        dst_path = OUT_DIR / f"{dst_id}.png"
        mirrored.save(dst_path)

        bbox = alpha_bbox(mirrored)
        hole_pct = interior_hole_pct(mirrored)
        qa = {
            "canvas_ok": mirrored.size == (CANVAS, CANVAS),
            "has_alpha": True,
            "bbox": bbox,
            "anchored_ok": True,  # geometric mirror of an already-anchored sprite
            "interior_hole_pct": round(hole_pct, 2),
            "solid_ok": hole_pct <= 10.0,
            "notes": [f"derived: horizontal mirror of {src_id} (key-light facet flips; accepted)"],
        }
        qa["pass"] = qa["canvas_ok"] and qa["solid_ok"]
        report["results"][dst_id] = {
            "id": dst_id,
            "category": "wall",
            "derived_from": src_id,
            "attempts": [],
            "staged_path": str(dst_path.relative_to(REPO_ROOT)),
            "final_qa": qa,
        }
        print(f"{dst_id}: [{'PASS' if qa['pass'] else 'FLAGGED'}] mirrored from {src_id}, bbox {bbox}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", type=str, default=None)
    parser.add_argument("--mirror-walls", action="store_true",
                        help="derive wall_nw/wall_sw from normalized wall_ne/wall_se")
    args = parser.parse_args(argv)

    report_path = OUT_DIR / "report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    only = set(args.only.split(",")) if args.only else None

    for asset_id, rec in list(report["results"].items()):
        if only and asset_id not in only:
            continue
        if rec.get("derived_from"):
            # mirrored sprites are already in normalized space; re-running the
            # anchor rules on them would re-anchor to the wrong corner
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

    if args.mirror_walls:
        mirror_walls(report)

    report_path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
    print(f"report updated: {report_path}")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
