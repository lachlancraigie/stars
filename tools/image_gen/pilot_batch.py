#!/usr/bin/env python3
"""
tools/image_gen/pilot_batch.py
================================

Orchestrates the gen2 pilot batch: composes prompts from docs/style-bible-v2.md's
locked style block, calls generate.py's OpenRouter client, normalizes each result
onto the game's 512x512 canvas, QAs it against the grid contract
(scripts/ship/iso_kit.gd: 130x65 floor diamond centered at canvas (256,311)),
retries once with a corrective prompt on QA failure, and writes:

  assets/sprites/gen2/<id>.png       -- staged sprite (gitignored? NO -- see note)
  assets/sprites/gen2/report.json    -- per-asset prompt/QA/cost record
  assets/sprites/gen2/contact_sheet.png -- labeled grid, dark+light checker bands

This is a *pilot*, not the production generator: the 14-asset list below is
hardcoded (no manifest.json yet -- see tools/asset_gen/manifest.json for what a
grown-up version of this would look like once the style bible is validated).

Cost/call budget: 14 assets, retry-once-on-fail policy -> hard cap of 40 total
generate_image() calls (enforced below; the run stops and flags remaining
assets as "not attempted" if the cap is hit, rather than silently overspending).

Usage:
    python pilot_batch.py                 # run the full pilot
    python pilot_batch.py --only tile_corridor,crew_astronaut_idle_s
    python pilot_batch.py --dry-run        # print composed prompts, no API calls
"""

from __future__ import annotations

import argparse
import io
import json
import sys
import time
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

import generate as gen
from normalize_gen2 import interior_hole_pct

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
OUT_DIR = REPO_ROOT / "assets" / "sprites" / "gen2"

CANVAS = 512
DIAMOND_CENTER = (256, 311)
DIAMOND_SIZE = (130, 65)

# Coarse centroid sanity window, per docs/style-bible-v2.md pipeline note #3.
CENTROID_TARGET = (256, 280)
CENTROID_TOL = (90, 110)

MAX_GENERATE_CALLS = 40
MODEL = gen.DEFAULT_MODEL  # openai/gpt-image-1-mini

# ---------------------------------------------------------------------------
# Style block -- kept in literal sync with docs/style-bible-v2.md's
# "Master prompt template" section. If you edit the wording here, mirror it
# there (and vice versa) so the doc stays true to what actually runs.
# ---------------------------------------------------------------------------

STYLE_LOCK = (
    # Camera clause: "VB / grid-locked" wording -- won the 2026-07-10 A/B test
    # against explicit-angle phrasing (VA); see docs/style-bible-v2.md.
    "Clean cel-shaded game sprite drawn locked to a 2:1 isometric pixel-art grid: "
    "the ground plane is a grid of flat diamonds exactly twice as wide as they are "
    "tall, the object's footprint and every horizontal edge align to those diamond "
    "diagonals, vertical edges stay strictly vertical, and the camera is never "
    "steeper than 27 degrees above the horizon. Flat frontal key light from the "
    "upper-left only. Two to three flat color tones per surface with hard "
    "edges between them, absolutely no gradients, no soft shading, no ambient "
    "occlusion blur, no texture noise, no painterly brushwork, no photographic "
    "detail. Thin uniform-weight dark outline (#14171C) around the silhouette and "
    "between color facets, constant thickness. Restrict all colors strictly to this "
    "palette: outline #14171C; structure grays #C7CED6 / #8B95A1 / #4E5661 / "
    "#2A2F36; off-white #EDEFF2; warm accent #FFC857 / #C9822A; cool accent "
    "#6FE3E0 / #2C9A98. Do not introduce any other hues. Chunky simple readable "
    "silhouette, no fine detail smaller than necessary to read at small size."
)

NEGATIVE = (
    "Avoid: gradients, soft shadows, blur, glow/bloom haze, film grain, painterly "
    "texture, realistic/photographic rendering, top-down 90-degree flat view, any "
    "camera angle other than the specified 2:1 dimetric, fisheye or perspective "
    "distortion, multiple copies of the subject, collage or grid layout, background "
    "scenery beyond the subject and its immediate contact shadow, text, watermark, "
    "logo, signature, frame/border. Transparent background. Single subject only. "
    # Solidity clause: added after the hole audit found the model keying out
    # large interior fills (mattress 55%, door leaf 47% transparent) when asked
    # for a transparent background. QA flood-fills for interior holes.
    "The subject itself must be completely solid and fully opaque everywhere -- "
    "no see-through parts, no transparent windows or glass, no cut-out holes; "
    "only the area OUTSIDE the subject's silhouette is transparent."
)

FRAMING = {
    "floor": (
        "Isometric floor tile filling the 2:1 diamond footprint exactly: the tile's "
        "diamond silhouette is centered horizontally in the frame and centered "
        "vertically at 61% down from the top (not the frame's vertical center), "
        "spanning the middle 25% of the frame width. Surface detail (panels, "
        "markings, equipment) stays within the diamond, flush with the floor, no "
        "vertical walls, no ceiling, designed to tile edge-to-edge with identical "
        "floor tiles."
    ),
    "wall": (
        "A single upright wall segment standing vertically like a thin fence panel, "
        "uniform height, running diagonally at the isometric angle, base line at 61% "
        "down the frame. The wall panel is the ONLY object in the image: absolutely "
        "no floor, no ground plate, no base slab, no platform beneath or around it -- "
        "the panel stands alone on a fully transparent background, as if cut out."
    ),
    "door": (
        "An upright closed sliding door/hatch standing vertically, seen at the "
        "isometric angle, base aligned to 61% down the frame, centered horizontally. "
        "The door is the ONLY object in the image: absolutely no floor, no ground "
        "plate, no base slab, no platform beneath it, no surrounding wall or room "
        "box -- the isolated door stands alone on a fully transparent background."
    ),
    "prop": (
        "A single freestanding object standing on the floor diamond's center point: "
        "its base/contact shadow sits at 61% down the frame, centered horizontally, "
        "the object extending upward from that point within the frame -- no floor "
        "tile needs to be drawn under it, only the object and its small flat "
        "contact shadow."
    ),
    "crew": (
        "A full-body character standing upright, feet at 61% down the frame, "
        "centered horizontally, body extending upward, facing {DIRECTION}, chunky "
        "simplified proportions (large head-to-body ratio is fine, no fine facial "
        "detail), standing idle pose, arms at sides. The character is the ONLY "
        "thing in the image: absolutely no floor, no ground plate, no tile, no "
        "platform beneath the feet -- only a small flat contact shadow directly "
        "under the feet, on a fully transparent background."
    ),
}

# ---------------------------------------------------------------------------
# The 14-asset pilot list
# ---------------------------------------------------------------------------

ASSETS: list[dict[str, Any]] = [
    {
        "id": "tile_corridor",
        "category": "floor",
        "subject": "Ship corridor floor tile: metal deck plating with panel seams and a "
        "thin painted directional walkway stripe.",
    },
    {
        "id": "tile_medbay",
        "category": "floor",
        "subject": "Medbay floor tile: clean white-grey clinical deck plating with a "
        "small cyan cross painted flat on the floor surface. The tile is completely "
        "flat and empty -- no bed, no furniture, no equipment, no 3D object standing "
        "on it, only the painted floor surface itself.",
    },
    {
        "id": "tile_engine_room",
        "category": "floor",
        "subject": "Engine room floor tile: heavy-duty grated deck plating with amber "
        "hazard-stripe edging and a visible power conduit line.",
    },
    {
        "id": "tile_cargo",
        "category": "floor",
        "subject": "Cargo hold floor tile: plain reinforced deck plating with yellow-amber "
        "stowage grid markings painted on the floor.",
    },
    {
        "id": "wall_ne",
        "category": "wall",
        "subject": "Ship hull wall segment for the NE-facing diamond edge: slate-grey "
        "structural paneling with rivets and a single horizontal seam.",
    },
    {
        "id": "wall_se",
        "category": "wall",
        "subject": "Ship hull wall segment for the SE-facing diamond edge: slate-grey "
        "structural paneling with rivets and a single amber conduit stripe running "
        "along its base.",
    },
    {
        "id": "door_gate",
        "category": "door",
        "subject": "Sci-fi sliding blast door / bulkhead hatch, closed, with a small cyan "
        "status light panel beside it.",
    },
    {
        "id": "prop_medbay_bed",
        "category": "prop",
        "subject": "A single medical bay bed: simple flat frame with a white-grey mattress "
        "and a small cyan monitor panel at the head end.",
    },
    {
        "id": "prop_mess_table",
        "category": "prop",
        "subject": "A single mess-hall table with two attached benches, plain steel-gray, "
        "seen at the isometric angle.",
    },
    {
        "id": "prop_cargo_crate_stack",
        "category": "prop",
        "subject": "A stack of three sci-fi cargo crates, off-white and steel-gray with "
        "amber hazard corner markings.",
    },
    {
        "id": "prop_reactor_core",
        "category": "prop",
        "subject": "A ship reactor core: a chunky cylindrical containment housing with a "
        "glowing cyan core visible through a small viewport, steel-gray casing.",
    },
    {
        "id": "prop_ai_core_pillar",
        "category": "prop",
        "subject": "An AI core server pillar: a tall chunky steel-gray column with "
        "vertical rows of small cyan status lights and one amber warning light.",
    },
    {
        "id": "prop_bridge_console",
        "category": "prop",
        "subject": "A ship bridge control console: an angled steel-gray control panel "
        "with a small cyan screen and a row of amber buttons.",
    },
    {
        "id": "crew_astronaut_idle_s",
        "category": "crew",
        "subject": "A ship crew member in a simple utilitarian jumpsuit, off-white body "
        "with steel-gray trim, standing idle, no helmet, simplified featureless face.",
        "direction": "toward the camera (south/front view)",
    },
]

assert len(ASSETS) == 14, "pilot batch is specced as 14 assets"


# ---------------------------------------------------------------------------
# Prompt composition
# ---------------------------------------------------------------------------


def compose_prompt(asset: dict[str, Any], *, corrective: str | None = None) -> str:
    framing = FRAMING[asset["category"]]
    if asset["category"] == "crew":
        framing = framing.format(DIRECTION=asset.get("direction", "toward the camera"))
    parts = [STYLE_LOCK, asset["subject"], framing, NEGATIVE]
    if corrective:
        parts.append(corrective)
    return " ".join(parts)


# ---------------------------------------------------------------------------
# Normalization: 1024x1024 model output -> 512x512 game canvas
# ---------------------------------------------------------------------------


def normalize_to_canvas(png_bytes: bytes) -> Image.Image:
    im = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    if im.width != im.height:
        # The model sometimes picks a portrait/landscape canvas (1024x1536 /
        # 1536x1024) despite the square subject framing. Pad with transparency
        # to a centered square -- never stretch, which would distort the
        # subject's projection angles (normalize_gen2.py only ever scales the
        # bbox uniformly afterwards, so a distortion here would be permanent).
        side = max(im.size)
        padded = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        padded.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
        im = padded
    if im.size != (CANVAS, CANVAS):
        im = im.resize((CANVAS, CANVAS), Image.LANCZOS)
    return im


# ---------------------------------------------------------------------------
# QA
# ---------------------------------------------------------------------------


def opaque_centroid(im: Image.Image, alpha_threshold: int = 10) -> tuple[float, float] | None:
    w, h = im.size
    px = im.load()
    sum_x = sum_y = count = 0
    for y in range(0, h, 2):  # stride 2 for speed; plenty dense for a centroid
        for x in range(0, w, 2):
            if px[x, y][3] > alpha_threshold:
                sum_x += x
                sum_y += y
                count += 1
    if count == 0:
        return None
    return (sum_x / count, sum_y / count)


def run_qa(im: Image.Image) -> dict[str, Any]:
    qa: dict[str, Any] = {"notes": []}

    qa["canvas_ok"] = im.size == (CANVAS, CANVAS)
    if not qa["canvas_ok"]:
        qa["notes"].append(f"canvas size {im.size} != {(CANVAS, CANVAS)}")

    rgba = im.convert("RGBA")
    corners = [
        rgba.getpixel((0, 0)),
        rgba.getpixel((CANVAS - 1, 0)),
        rgba.getpixel((0, CANVAS - 1)),
        rgba.getpixel((CANVAS - 1, CANVAS - 1)),
    ]
    transparent_corners = sum(1 for px in corners if px[3] <= 25)
    qa["has_alpha"] = transparent_corners >= 3
    if not qa["has_alpha"]:
        qa["notes"].append(
            f"expected a transparent surround, only {transparent_corners}/4 corners are transparent"
        )

    centroid = opaque_centroid(rgba)
    qa["centroid"] = centroid
    if centroid is None:
        qa["centroid_ok"] = False
        qa["notes"].append("no opaque pixels found at all (blank/fully transparent image)")
    else:
        cx, cy = centroid
        tx, ty = CENTROID_TARGET
        tol_x, tol_y = CENTROID_TOL
        centroid_ok = abs(cx - tx) <= tol_x and abs(cy - ty) <= tol_y
        qa["centroid_ok"] = centroid_ok
        if not centroid_ok:
            qa["notes"].append(
                f"centroid {centroid} outside tolerance window "
                f"({tx}+-{tol_x}, {ty}+-{tol_y})"
            )

    # Threshold 10%: solid objects with keyed-out fills (a 55%-transparent
    # mattress, a 47%-transparent door leaf) fail; leggy furniture whose
    # enclosed under-table daylight legitimately shows the floor (2-8%) passes.
    hole_pct = interior_hole_pct(rgba)
    qa["interior_hole_pct"] = round(hole_pct, 2)
    qa["solid_ok"] = hole_pct <= 10.0
    if not qa["solid_ok"]:
        qa["notes"].append(
            f"{hole_pct:.1f}% of subject area is interior transparency (holes)"
        )

    qa["pass"] = qa["canvas_ok"] and qa["has_alpha"] and qa["centroid_ok"] and qa["solid_ok"]
    return qa


def corrective_prompt_for(qa: dict[str, Any]) -> str:
    clauses = []
    if not qa["has_alpha"]:
        clauses.append(
            "CORRECTION: the previous attempt did not have a transparent background -- "
            "the background MUST be fully transparent (alpha=0), do not fill it with any "
            "color, texture, vignette, or ground plane."
        )
    if qa.get("centroid") and not qa["centroid_ok"]:
        cx, cy = qa["centroid"]
        tx, ty = CENTROID_TARGET
        dx, dy = cx - tx, cy - ty
        horiz = "left" if dx > 0 else "right"
        vert = "up" if dy > 0 else "down"
        clauses.append(
            "CORRECTION: the previous attempt was off-center -- move the entire subject "
            f"{horiz} and {vert} so its base/footprint sits centered horizontally and at "
            "61% down from the top of the frame, with no cropping."
        )
    if qa.get("solid_ok") is False:
        clauses.append(
            "CORRECTION: the previous attempt had transparent see-through areas INSIDE "
            "the subject -- every part of the subject must be painted fully opaque with "
            "solid palette colors; no interior region may be left transparent."
        )
    return " ".join(clauses)


# ---------------------------------------------------------------------------
# Generation loop
# ---------------------------------------------------------------------------


def generate_one(asset: dict[str, Any], api_key: str, call_budget: list[int]) -> dict[str, Any]:
    record: dict[str, Any] = {"id": asset["id"], "category": asset["category"], "attempts": []}

    corrective = None
    final_im = None
    final_qa = None
    for attempt in (1, 2):
        if call_budget[0] >= MAX_GENERATE_CALLS:
            record["notes"] = "generation call budget exhausted before this attempt"
            break
        prompt = compose_prompt(asset, corrective=corrective)
        print(f"  attempt {attempt}: generating ({MODEL})...")
        call_budget[0] += 1
        try:
            result = gen.generate_image(prompt, model=MODEL, background="transparent", api_key=api_key)
        except gen.GenerationError as exc:
            record["attempts"].append({"attempt": attempt, "prompt": prompt, "error": str(exc)})
            print(f"    [error] {exc}")
            continue

        im = normalize_to_canvas(result["png_bytes"])
        qa = run_qa(im)
        record["attempts"].append(
            {
                "attempt": attempt,
                "prompt": prompt,
                "usage": result.get("usage"),
                "qa": qa,
            }
        )
        print(f"    QA: {'PASS' if qa['pass'] else 'FLAGGED'} centroid={qa.get('centroid')} notes={qa['notes']}")

        final_im, final_qa = im, qa
        if qa["pass"]:
            break
        corrective = corrective_prompt_for(qa)

    record["final_qa"] = final_qa
    record["image"] = final_im
    return record


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", type=str, default=None, help="comma-separated asset ids")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    assets = ASSETS
    if args.only:
        wanted = set(args.only.split(","))
        by_id = {a["id"]: a for a in ASSETS}
        missing = wanted - by_id.keys()
        if missing:
            raise SystemExit(f"unknown asset id(s): {sorted(missing)}")
        assets = [by_id[i] for i in wanted]
        order = {a["id"]: idx for idx, a in enumerate(ASSETS)}
        assets.sort(key=lambda a: order[a["id"]])

    if args.dry_run:
        for asset in assets:
            print(f"--- {asset['id']} ({asset['category']}) ---")
            print(compose_prompt(asset))
            print()
        print(f"[dry-run] {len(assets)} asset(s), up to {len(assets) * 2} generate_image() calls "
              f"(cap {MAX_GENERATE_CALLS})")
        return 0

    api_key = gen.load_api_key()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    report_path = OUT_DIR / "report.json"
    if report_path.exists():
        # Merge into the existing report so an interrupted run can resume via
        # --only for the missing ids without clobbering completed records.
        report: dict[str, Any] = json.loads(report_path.read_text(encoding="utf-8"))
        report.setdefault("results", {})
        report["model"] = MODEL
    else:
        report = {"model": MODEL, "results": {}}
    call_budget = [0]

    for asset in assets:
        print(f"generating {asset['id']} ({asset['category']}) ...")
        record = generate_one(asset, api_key, call_budget)

        image = record.pop("image")
        if image is not None:
            out_path = OUT_DIR / f"{asset['id']}.png"
            image.save(out_path)
            record["staged_path"] = str(out_path.relative_to(REPO_ROOT))
            print(f"  saved {out_path}")
        else:
            record["staged_path"] = None
            print("  [no image produced]")

        report["results"][asset["id"]] = record
        report_path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")

    total_cost = 0.0
    for rec in report["results"].values():
        for a in rec.get("attempts", []):
            usage = a.get("usage") or {}
            total_cost += usage.get("cost") or 0.0

    print()
    print(f"generate_image() calls used: {call_budget[0]}/{MAX_GENERATE_CALLS}")
    print(f"total reported API cost this run: ${total_cost:.4f}")
    print(f"report written to {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
