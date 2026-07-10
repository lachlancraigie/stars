#!/usr/bin/env python3
"""
tools/image_gen/crew_sheet_gen.py
===================================

Crew animation-matrix generator, built to solve what tools/image_gen/
crew_facings.py proved broken: single-sprite reference-anchoring (S facing
generated, then E/N/W each generated fresh with S as an input_reference)
still drifted -- assets/sprites/gen2/report.json's crew_astronaut_idle_{e,n,w}
attempts each independently reinterpreted the suit/hair tones. See
docs/style-bible-v2.md's consistency strategy (three legs):

  A) SHEET-BASED GENERATION (this file): every frame that needs to share
     identity is requested INSIDE ONE image -- a strict grid, one full-body
     pose per cell -- because within-image consistency is something these
     models are actually good at (it's cross-CALL consistency that drifts).
     Sliced apart with PIL after the fact (slice_cells below).
  B) PALETTE SNAP (palette_snap.py): every sliced-and-normalized cell gets
     its opaque pixels nearest-neighbor snapped onto ONE fixed character
     palette. This is the mechanical belt: even if a sheet's own rendering
     drifts slightly from a previous sheet's, both collapse onto identical
     hex values afterward.
  C) REFERENCE ANCHOR (belt AND braces): every non-base sheet is also
     generated with input_references=[the approved base sheet's S-facing
     cell], on top of A+B, not instead of them -- (C) alone is exactly what
     crew_facings.py already showed doesn't hold up by itself.

Pipeline per job: compose a grid prompt (compose_sheet_prompt) -> generate
one image (generate_sheet) -> pad to square if needed -> slice into
cols x rows cells (slice_cells) -> per cell: trim to its own alpha bbox,
normalize onto the 512x512 crew contract via the SAME normalize()/
qa_normalized() functions normalize_gen2.py uses for the rest of the kit
(NORM_RULES below adds "stand"/"seated"/"prone" contracts, all still
bottom-anchored at the existing crew feet-anchor point (256,320) --
scripts/ship/iso_kit.gd's ANCHOR_OFFSET is pose-agnostic, so every state
must register identically for frame-swap animation to not visibly jump) ->
palette_snap.snap_image -> save as
assets/sprites/gen2/crew/crew_{state}_{facing}_{frame}.png.

Usage:
    python crew_sheet_gen.py --list-jobs
    python crew_sheet_gen.py --dry-run --job idle_base
    python crew_sheet_gen.py --job idle_base                 # generate + process
    python crew_sheet_gen.py --job walk_s_se --reference      # anchor on base sheet
    python crew_sheet_gen.py --probe                          # cheap slicing-reliability test, not saved as a real job
    python crew_sheet_gen.py --total-spend                    # sum report.json + crew/sheet_report.json cost
"""

from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image

import generate as gen
import pilot_batch as pb
import palette_snap as psnap
from normalize_gen2 import alpha_bbox, interior_hole_pct, normalize, qa_normalized

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
GEN2_DIR = REPO_ROOT / "assets" / "sprites" / "gen2"
CREW_DIR = GEN2_DIR / "crew"
MAIN_REPORT = GEN2_DIR / "report.json"
SHEET_REPORT = CREW_DIR / "sheet_report.json"
BASE_SHEET_RAW = CREW_DIR / "_base_idle_sheet_raw.png"
BASE_ANCHOR_CELL = CREW_DIR / "crew_idle_s_0.png"  # the approved reference-anchor image once it exists

MODEL = gen.DEFAULT_MODEL
CANVAS = 512

# ---------------------------------------------------------------------------
# Normalization contracts. "stand" reuses the exact same bottom-anchor point
# as the rest of the kit's crew rule (normalize_gen2.NORM_RULES["crew"]:
# height 70, anchor center-bottom (256,320)). "seated"/"prone" are new but
# keep the SAME anchor point (256,320) deliberately -- iso_kit.gd's
# ANCHOR_OFFSET is one constant for every crew sprite regardless of state, so
# every pose has to register at the same point on the 512 canvas or a state
# swap (idle -> dead, walk -> injured_walk) would visibly jump the sprite.
# ---------------------------------------------------------------------------
NORM_RULES: dict[str, dict[str, Any]] = {
    "stand":  {"mode": "height", "height": 70, "anchor": ("center", 256, 320)},
    "seated": {"mode": "fit_within", "max_w": 100, "max_h": 62, "anchor": ("center", 256, 320)},
    "prone":  {"mode": "fit_within", "max_w": 160, "max_h": 95, "anchor": ("center", 256, 320)},
}

FACING_DESC: dict[str, str] = {
    "s":  "facing the camera (south/front view)",
    "se": "facing toward lower-right (southeast, three-quarter front)",
    "e":  "facing right (east), full side profile",
    "ne": "facing toward upper-right (northeast, three-quarter back)",
    "n":  "facing away from the camera (north/back view)",
    "nw": "facing toward upper-left (northwest, three-quarter back)",
    "w":  "facing left (west), full side profile",
    "sw": "facing toward lower-left (southwest, three-quarter front)",
}

CHARACTER_SUBJECT = (
    "A ship crew member in a simple utilitarian jumpsuit, off-white body with "
    "steel-gray trim, simplified featureless face, short dark cropped hair -- "
    "bare-headed in every single cell of the sheet, exactly the same haircut "
    "each time. Never wearing any cap, hat, hood, helmet, or other headwear in "
    "any cell, even from behind or from a three-quarter-back angle -- headwear "
    "choice must not vary from pose to pose."
)

GRID_CLAUSE_TMPL = (
    "Arrange the sheet as EXACTLY {cols} equal columns by {rows} equal rows in a strict "
    "uniform grid -- EXACTLY {n} cells total, no more and no fewer, EXACTLY {cols} characters "
    "per row (count them: {col_count_words}), EXACTLY {rows} rows (reading order left-to-right "
    "then top-to-bottom). Do NOT add an extra in-between pose anywhere -- there are only "
    "{n} poses listed below and the sheet must contain precisely those {n}, nothing added. "
    "Each cell contains exactly ONE full-body pose of the SAME character -- identical "
    "jumpsuit color and trim, identical hair/cap, identical body proportions, identical "
    "cel-shading and outline weight in every cell, only the pose/facing changes as listed "
    "below. Leave a wide clear empty transparent gap of at least one head-width between "
    "adjacent cells in every row so no cell's subject overlaps or touches a neighboring "
    "cell's subject. Do not draw grid lines, cell borders, or dividers -- only empty "
    "transparent space separates the cells. Cells, in reading order:\n"
)

REF_CLAUSE = (
    " This must be EXACTLY the same character as the reference image: identical jumpsuit "
    "color and trim, identical body proportions, identical head/hair, identical outline "
    "weight, identical cel shading style -- only the pose/facing changes."
)


_NUM_WORDS = {1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight"}


def compose_sheet_prompt(job: dict[str, Any]) -> str:
    cols, rows = job["grid"]
    n = cols * rows
    lines = []
    for i, cell in enumerate(job["cells"]):
        r, c = divmod(i, cols)
        facing_desc = FACING_DESC[cell["facing"]]
        lines.append(f"  Cell (row {r+1}, col {c+1}): {cell['pose']}, {facing_desc}.")
    col_count_words = ", ".join(_NUM_WORDS.get(i, str(i)) for i in range(1, cols + 1))
    grid_clause = GRID_CLAUSE_TMPL.format(cols=cols, rows=rows, n=n, col_count_words=col_count_words) + "\n".join(lines)
    parts = [pb.STYLE_LOCK, CHARACTER_SUBJECT, job["pose_common"], grid_clause, pb.NEGATIVE]
    prompt = " ".join(parts)
    if job.get("reference"):
        prompt += REF_CLAUSE
    return prompt


# ---------------------------------------------------------------------------
# Generation + slicing
# ---------------------------------------------------------------------------


def pad_to_square(im: Image.Image) -> Image.Image:
    im = im.convert("RGBA")
    if im.width == im.height:
        return im
    side = max(im.size)
    padded = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    padded.paste(im, ((side - im.width) // 2, (side - im.height) // 2))
    return padded


def slice_cells(im: Image.Image, cols: int, rows: int, margin_frac: float = 0.05) -> list[Image.Image]:
    """Even grid division (PIL owns geometry, not the model -- style-bible
    pipeline note #3) with a small inset margin per cell to avoid bleed from
    a neighbor's outline, returned in row-major reading order.

    Kept as the fallback strategy for slice_cells_auto() below -- correct only
    when the model actually rendered exactly cols*rows evenly-spaced poses.
    """
    im = pad_to_square(im)
    w, h = im.size
    cw, ch = w / cols, h / rows
    mx, my = cw * margin_frac, ch * margin_frac
    cells = []
    for r in range(rows):
        for c in range(cols):
            x0 = c * cw + mx
            y0 = r * ch + my
            x1 = (c + 1) * cw - mx
            y1 = (r + 1) * ch - my
            cells.append(im.crop((int(x0), int(y0), int(x1), int(y1))))
    return cells


def _content_runs(flags: list[int], min_gap: int, min_run: int) -> list[tuple[int, int]]:
    """Given a 0/1 presence sequence (a PIL getprojection() axis), return
    (start, end) pixel runs of content, merging runs separated by a gap
    shorter than min_gap (stray disconnected pixels -- e.g. an outstretched
    hand in a side-profile pose -- must not read as a whole extra column) and
    dropping runs shorter than min_run (rendering noise, not a real pose)."""
    raw: list[tuple[int, int]] = []
    start = None
    for x, f in enumerate(flags):
        if f and start is None:
            start = x
        elif not f and start is not None:
            raw.append((start, x))
            start = None
    if start is not None:
        raw.append((start, len(flags)))

    merged: list[tuple[int, int]] = []
    for s, e in raw:
        if merged and s - merged[-1][1] < min_gap:
            merged[-1] = (merged[-1][0], e)
        else:
            merged.append((s, e))
    return [(s, e) for s, e in merged if e - s >= min_run]


def detect_grid_bounds(im: Image.Image, cols: int, rows: int, alpha_threshold: int = 20,
                        ) -> tuple[list[tuple[int, int]], list[tuple[int, int]], bool]:
    """Detect actual pose column/row boundaries from the sheet's own alpha
    channel (a real transparent gap between characters, not an assumed even
    division -- see slice_cells_auto docstring). Returns (col_bounds,
    row_bounds, matched) where matched is True only if the detected count
    equals the job's declared grid; callers fall back to even division when
    it doesn't, since a bound-count mismatch means we can't trust which
    detected run maps to which requested cell.
    """
    w, h = im.size
    alpha = im.split()[3].point(lambda a: 255 if a > alpha_threshold else 0)
    col_flags, row_flags = alpha.getprojection()
    # A real inter-pose gap should be a meaningful fraction of a cell's width/height;
    # a stray disconnected limb pixel-cluster is much narrower than that.
    min_gap_x = max(4, int(w / cols * 0.15))
    min_gap_y = max(4, int(h / rows * 0.15))
    min_run_x = max(4, int(w / cols * 0.10))
    min_run_y = max(4, int(h / rows * 0.10))
    col_runs = _content_runs(list(col_flags), min_gap_x, min_run_x)
    row_runs = _content_runs(list(row_flags), min_gap_y, min_run_y)
    matched = len(col_runs) == cols and len(row_runs) == rows
    return col_runs, row_runs, matched


def slice_cells_auto(im: Image.Image, cols: int, rows: int, margin_px: int = 6,
                      ) -> tuple[list[Image.Image], bool]:
    """Preferred slicing path: detect each pose's actual bounding gap from the
    sheet's alpha channel (detect_grid_bounds) instead of assuming the model
    hit an exact even division -- crew_facings.py already proved single-call
    generation drifts, and this run of idle_base proved the model can ALSO
    silently miscount cells within a single sheet (asked for 4 columns, drew
    5), which breaks fixed-fraction slicing with visible neighbor bleed. When
    the detected run count doesn't match the declared grid we can't safely
    map runs to requested cells, so we fall back to the old even-division
    slice_cells() (with a printed warning -- the job's cell records will
    still carry per-cell QA that catches a bad slice's mangled proportions).
    Returns (cells_in_reading_order, used_auto_detection).
    """
    im = pad_to_square(im)
    col_runs, row_runs, matched = detect_grid_bounds(im, cols, rows)
    if not matched:
        return slice_cells(im, cols, rows), False

    cells = []
    for (ry0, ry1) in row_runs:
        for (cx0, cx1) in col_runs:
            x0 = max(0, cx0 - margin_px)
            y0 = max(0, ry0 - margin_px)
            x1 = min(im.width, cx1 + margin_px)
            y1 = min(im.height, ry1 + margin_px)
            cells.append(im.crop((x0, y0, x1, y1)))
    return cells, True


def generate_sheet(job: dict[str, Any], api_key: str, *, quality: str = "high",
                    references: list[Path] | None = None) -> dict[str, Any]:
    prompt = compose_sheet_prompt(job)
    result = gen.generate_image(
        prompt, model=MODEL, background="transparent", quality=quality,
        input_references=references, api_key=api_key,
    )
    return {"prompt": prompt, "png_bytes": result["png_bytes"], "usage": result.get("usage")}


# ---------------------------------------------------------------------------
# Per-cell processing: trim -> normalize -> palette-snap -> QA -> save
# ---------------------------------------------------------------------------


def process_cell(raw_cell: Image.Image, contract: str) -> tuple[Image.Image, dict[str, Any]]:
    rule = NORM_RULES[contract]
    bbox = alpha_bbox(raw_cell)
    if bbox is None:
        canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        return canvas, {"error": "empty cell -- no opaque pixels found after slicing"}
    trimmed = raw_cell.crop(bbox)
    normalized, info = normalize(trimmed, rule)
    snapped = psnap.snap_image(normalized)
    qa = qa_normalized(snapped, rule, info)
    return snapped, {"normalize": info, "qa": qa}


def run_job(job: dict[str, Any], api_key: str, *, quality: str = "high",
            reference: bool = False, dry_run: bool = False) -> dict[str, Any]:
    cols, rows = job["grid"]
    n_expected = cols * rows
    if len(job["cells"]) != n_expected:
        raise SystemExit(f"job {job['id']}: {len(job['cells'])} cells declared but grid is {cols}x{rows}={n_expected}")

    prompt = compose_sheet_prompt(job)
    if dry_run:
        print(f"--- {job['id']} ({cols}x{rows} = {n_expected} cells) ---")
        print(prompt)
        print()
        return {"dry_run": True}

    references = [BASE_ANCHOR_CELL] if (reference and BASE_ANCHOR_CELL.exists()) else None
    if reference and references is None:
        print(f"  [warn] --reference requested but {BASE_ANCHOR_CELL} doesn't exist yet -- generating unanchored")

    print(f"generating sheet '{job['id']}' ({cols}x{rows} grid, quality={quality}, "
          f"anchored={'yes' if references else 'no'}) ...")
    gen_result = generate_sheet(job, api_key, quality=quality, references=references)
    usage = gen_result.get("usage") or {}
    print(f"  usage: cost=${usage.get('cost', 0):.4f} image_tokens="
          f"{(usage.get('completion_tokens_details') or {}).get('image_tokens')}")

    raw_im = Image.open(io.BytesIO(gen_result["png_bytes"])).convert("RGBA")
    CREW_DIR.mkdir(parents=True, exist_ok=True)
    raw_path = CREW_DIR / f"_raw_{job['id']}.png"
    raw_im.save(raw_path)

    raw_cells, used_auto = slice_cells_auto(raw_im, cols, rows)
    if used_auto:
        print(f"  slicing: auto-detected {cols}x{rows} pose boundaries from the alpha channel")
    else:
        print(f"  [warn] slicing: alpha-gap detection didn't find exactly {cols}x{rows} poses "
              f"(model likely mis-counted the grid) -- fell back to even division, which can "
              f"bleed between cells; inspect cell QA below closely")
    if len(raw_cells) != n_expected:
        raise SystemExit(f"job {job['id']}: sliced {len(raw_cells)} cells but {n_expected} were declared")

    cell_records = []
    for cell_spec, raw_cell in zip(job["cells"], raw_cells):
        out_name = f"crew_{job['state']}_{cell_spec['facing']}_{cell_spec['frame']}.png"
        processed, info = process_cell(raw_cell, job["contract"])
        out_path = CREW_DIR / out_name
        processed.save(out_path)
        info["file"] = out_name
        info["facing"] = cell_spec["facing"]
        info["frame"] = cell_spec["frame"]
        info["pose"] = cell_spec["pose"]
        cell_records.append(info)
        qa = info.get("qa", {})
        status = "PASS" if qa.get("pass") else ("ERROR" if "error" in info else "FLAGGED")
        print(f"  [{status}] {out_name}  holes={qa.get('interior_hole_pct')}  notes={qa.get('notes')}")

    record = {
        "id": job["id"], "state": job["state"], "grid": [cols, rows],
        "contract": job["contract"], "prompt": gen_result["prompt"], "usage": usage,
        "raw_path": str(raw_path.relative_to(REPO_ROOT)), "sliced_with_auto_detection": used_auto,
        "cells": cell_records,
    }
    return record


# ---------------------------------------------------------------------------
# Job definitions -- the animation matrix, priority order per the mission
# brief. Facing pairing for multi-facing sheets favors ADJACENT compass
# directions (visually similar poses land in the same generate call, which
# empirically gives the model an easier within-sheet consistency job than
# pairing opposites).
# ---------------------------------------------------------------------------


def _walk_cells(facings: list[str], poses: list[str]) -> list[dict[str, str]]:
    cells = []
    for facing in facings:
        for i, pose in enumerate(poses):
            cells.append({"facing": facing, "frame": str(i), "pose": pose})
    return cells


WALK_POSES = [
    "walking mid-stride, left leg forward, right arm forward",
    "walking with legs passing together (contact pose), weight centered",
    "walking mid-stride, right leg forward, left arm forward",
    "walking with legs passing together (contact pose), weight centered, mirrored arm swing from the previous pose",
]

INJURED_WALK_POSES = [
    "limping walk, favoring the left leg, hunched forward slightly, one hand clutching the side",
    "limping walk, weight on the right leg, hunched forward slightly, one hand clutching the side",
    "limping walk, dragging the left leg, hunched forward slightly, one hand clutching the side",
    "limping walk, weight recovering on the right leg, hunched forward slightly, one hand clutching the side",
]

FLOAT_POSES = [
    "zero-gravity floating drift, loose relaxed limbs, body tilted slightly, no ground contact, no contact shadow",
    "zero-gravity floating drift, limbs drifted to a different loose angle, body tilted the other way, no ground contact, no contact shadow",
    "zero-gravity floating drift, limbs drifted to a third loose angle, slight body rotation, no ground contact, no contact shadow",
]

MELEE_POSES = [
    "melee combat stance, winding up a punch/strike, weight on the back leg",
    "melee combat mid-swing, arm extended forward at full reach",
    "melee combat follow-through, arm across the body after the strike",
]

CARRY_WALK_POSES = [
    "walking while carrying a small cargo crate held against the chest with both arms, left leg forward",
    "walking while carrying a small cargo crate held against the chest with both arms, legs passing together",
    "walking while carrying a small cargo crate held against the chest with both arms, right leg forward",
    "walking while carrying a small cargo crate held against the chest with both arms, legs passing together, mirrored",
]

IDLE_POSE = ["standing idle, arms relaxed at sides, feet shoulder-width apart"]


def _idle_job(facings: tuple[str, str]) -> dict[str, Any]:
    return {
        "id": f"idle_{facings[0]}_{facings[1]}", "state": "idle", "grid": (2, 1), "contract": "stand",
        "pose_common": "Standing idle pose, arms relaxed at sides, feet shoulder-width apart, "
                        "small flat contact shadow directly under the feet, no floor tile, no platform.",
        "cells": _walk_cells(list(facings), IDLE_POSE),
    }


JOBS: dict[str, dict[str, Any]] = {
    # --- 1. BASE -----------------------------------------------------------
    # Split into 4 paired-facing sheets (2 cells each) rather than one 8-cell
    # sheet: the idle_base 8-facings-in-one-image test (assets/sprites/gen2/
    # crew/_test/) proved the model won't reliably hit an exact 8-pose count
    # in a single call (drew 10, then 9, then 6 across three attempts), while
    # this file's OWN walk_s_se job -- 2 facings, same small-grid shape --
    # nailed its exact count on the first try. Small paired grids are the
    # proven-reliable shape; a lone 8-facing grid is not.
    "idle_s_se": _idle_job(("s", "se")),
    "idle_e_ne": _idle_job(("e", "ne")),
    "idle_n_nw": _idle_job(("n", "nw")),
    "idle_w_sw": _idle_job(("w", "sw")),

    # --- 2. WALK (4x2 sheets of 2-facing frame-pairs) --------------------
    "walk_s_se": {
        "id": "walk_s_se", "state": "walk", "grid": (4, 2), "contract": "stand",
        "pose_common": "A 4-frame walk cycle, small flat contact shadow under the forward foot each frame, "
                        "no floor tile, no platform.",
        "cells": _walk_cells(["s", "se"], WALK_POSES),
    },
    "walk_e_ne": {
        "id": "walk_e_ne", "state": "walk", "grid": (4, 2), "contract": "stand",
        "pose_common": "A 4-frame walk cycle, small flat contact shadow under the forward foot each frame, "
                        "no floor tile, no platform.",
        "cells": _walk_cells(["e", "ne"], WALK_POSES),
    },
    "walk_n_nw": {
        "id": "walk_n_nw", "state": "walk", "grid": (4, 2), "contract": "stand",
        "pose_common": "A 4-frame walk cycle, small flat contact shadow under the forward foot each frame, "
                        "no floor tile, no platform.",
        "cells": _walk_cells(["n", "nw"], WALK_POSES),
    },
    "walk_w_sw": {
        "id": "walk_w_sw", "state": "walk", "grid": (4, 2), "contract": "stand",
        "pose_common": "A 4-frame walk cycle, small flat contact shadow under the forward foot each frame, "
                        "no floor tile, no platform.",
        "cells": _walk_cells(["w", "sw"], WALK_POSES),
    },

    # --- 3. SLEEPING (side view + mirror) --------------------------------
    "sleeping": {
        "id": "sleeping", "state": "sleeping", "grid": (2, 1), "contract": "prone",
        "pose_common": "Lying flat on their back in a bunk, seen from the side, eyes closed, arms resting "
                        "at the sides, a 2-frame breathing loop (chest rises and falls slightly between "
                        "frames), no bunk/bed furniture drawn -- only the character and a small flat contact "
                        "shadow beneath them, no floor tile, no platform.",
        "cells": [
            {"facing": "e", "frame": "0", "pose": "lying down, chest at rest (breathing out)"},
            {"facing": "e", "frame": "1", "pose": "lying down, chest slightly raised (breathing in)"},
        ],
    },

    # --- 4. DEAD (S + E, mirror the rest) --------------------------------
    "dead": {
        "id": "dead", "state": "dead", "grid": (2, 2), "contract": "prone",
        "pose_common": "A collapsed, motionless body on the ground, two distinct poses (rows) each shown "
                        "from two facings (columns), small flat contact shadow, no floor tile, no platform.",
        "cells": [
            {"facing": "s", "frame": "0", "pose": "sprawled face-up, limbs splayed outward, motionless"},
            {"facing": "e", "frame": "0", "pose": "sprawled face-up, limbs splayed outward, motionless, side view"},
            {"facing": "s", "frame": "1", "pose": "slumped face-down, one arm tucked under the body, motionless"},
            {"facing": "e", "frame": "1", "pose": "slumped face-down, one arm tucked under the body, motionless, side view"},
        ],
    },

    # --- 5. INJURED --------------------------------------------------------
    "injured_walk_s_e": {
        "id": "injured_walk_s_e", "state": "injured_walk", "grid": (4, 2), "contract": "stand",
        "pose_common": "A 4-frame limping walk cycle for an injured crew member, small flat contact shadow "
                        "under the forward foot each frame, no floor tile, no platform.",
        "cells": _walk_cells(["s", "e"], INJURED_WALK_POSES),
    },
    "injured_walk_n_w": {
        "id": "injured_walk_n_w", "state": "injured_walk", "grid": (4, 2), "contract": "stand",
        "pose_common": "A 4-frame limping walk cycle for an injured crew member, small flat contact shadow "
                        "under the forward foot each frame, no floor tile, no platform.",
        "cells": _walk_cells(["n", "w"], INJURED_WALK_POSES),
    },
    "injured_idle": {
        "id": "injured_idle", "state": "injured_idle", "grid": (2, 2), "contract": "stand",
        "pose_common": "Standing hunched, clutching their side/ribs with one hand as if wounded, small flat "
                        "contact shadow under the feet, no floor tile, no platform.",
        "cells": [{"facing": f, "frame": "0", "pose": "standing hunched, clutching side"} for f in
                  ["s", "e", "n", "w"]],
    },

    # --- 6. FLOATING (zero-g) ---------------------------------------------
    "float_s_e": {
        "id": "float_s_e", "state": "floating", "grid": (3, 2), "contract": "prone",
        "pose_common": "A 3-frame zero-gravity drift loop, no contact shadow at all (fully weightless), "
                        "no floor tile, no platform.",
        "cells": _walk_cells(["s", "e"], FLOAT_POSES),
    },
    "float_n_w": {
        "id": "float_n_w", "state": "floating", "grid": (3, 2), "contract": "prone",
        "pose_common": "A 3-frame zero-gravity drift loop, no contact shadow at all (fully weightless), "
                        "no floor tile, no platform.",
        "cells": _walk_cells(["n", "w"], FLOAT_POSES),
    },

    # --- 7. FIGHTING --------------------------------------------------------
    "fight_melee_s_e": {
        "id": "fight_melee_s_e", "state": "fight_melee", "grid": (3, 2), "contract": "stand",
        "pose_common": "A 3-frame melee combat swing, small flat contact shadow under the feet, no floor "
                        "tile, no platform, no weapon prop (bare-handed strike).",
        "cells": _walk_cells(["s", "e"], MELEE_POSES),
    },
    "fight_melee_n_w": {
        "id": "fight_melee_n_w", "state": "fight_melee", "grid": (3, 2), "contract": "stand",
        "pose_common": "A 3-frame melee combat swing, small flat contact shadow under the feet, no floor "
                        "tile, no platform, no weapon prop (bare-handed strike).",
        "cells": _walk_cells(["n", "w"], MELEE_POSES),
    },
    "fight_ranged": {
        "id": "fight_ranged", "state": "fight_ranged", "grid": (4, 2), "contract": "stand",
        "pose_common": "A 2-frame ranged-aim pose, both hands raised holding a small sidearm aimed forward, "
                        "small flat contact shadow under the feet, no floor tile, no platform.",
        "cells": (
            [{"facing": f, "frame": "0", "pose": "aiming a sidearm forward, steady stance"} for f in
             ["s", "e", "n", "w"]] +
            [{"facing": f, "frame": "1", "pose": "aiming a sidearm forward, slight recoil/muzzle-flash moment"} for f in
             ["s", "e", "n", "w"]]
        ),
    },

    # --- 8. CARRYING --------------------------------------------------------
    "carry_walk_s_e": {
        "id": "carry_walk_s_e", "state": "carry_walk", "grid": (4, 2), "contract": "stand",
        "pose_common": "A 4-frame walk cycle carrying a small cargo crate, small flat contact shadow under "
                        "the forward foot each frame, no floor tile, no platform.",
        "cells": _walk_cells(["s", "e"], CARRY_WALK_POSES),
    },
    "carry_walk_n_w": {
        "id": "carry_walk_n_w", "state": "carry_walk", "grid": (4, 2), "contract": "stand",
        "pose_common": "A 4-frame walk cycle carrying a small cargo crate, small flat contact shadow under "
                        "the forward foot each frame, no floor tile, no platform.",
        "cells": _walk_cells(["n", "w"], CARRY_WALK_POSES),
    },
    "carry_idle": {
        "id": "carry_idle", "state": "carry_idle", "grid": (2, 2), "contract": "stand",
        "pose_common": "Standing still, holding a small cargo crate against the chest with both arms, small "
                        "flat contact shadow under the feet, no floor tile, no platform.",
        "cells": [{"facing": f, "frame": "0", "pose": "standing, holding a crate"} for f in
                  ["s", "e", "n", "w"]],
    },

    # --- 9. Extras -----------------------------------------------------------
    "repairing": {
        "id": "repairing", "state": "repairing", "grid": (3, 1), "contract": "seated",
        "pose_common": "Kneeling and working on a floor panel with a handheld tool, 3-frame repair-motion "
                        "loop, side view, small flat contact shadow, no floor tile, no platform.",
        "cells": [
            {"facing": "se", "frame": "0", "pose": "kneeling, tool raised"},
            {"facing": "se", "frame": "1", "pose": "kneeling, tool applied to the panel"},
            {"facing": "se", "frame": "2", "pose": "kneeling, tool lifted again, sparks/spark-flash"},
        ],
    },
    "eating": {
        "id": "eating", "state": "eating", "grid": (2, 1), "contract": "seated",
        "pose_common": "Seated on a bench eating from a small tray, 2-frame loop (bite motion), side view, "
                        "small flat contact shadow, no floor tile, no platform, no bench/table furniture drawn.",
        "cells": [
            {"facing": "e", "frame": "0", "pose": "seated, tray at chest height"},
            {"facing": "e", "frame": "1", "pose": "seated, hand raised toward mouth"},
        ],
    },
    "panicking": {
        "id": "panicking", "state": "panicking", "grid": (4, 2), "contract": "stand",
        "pose_common": "A frantic panicked pose, 2-frame loop (arms flailing/shaking), small flat contact "
                        "shadow under the feet, no floor tile, no platform.",
        "cells": (
            [{"facing": f, "frame": "0", "pose": "frantic, arms raised defensively, wide stance"} for f in
             ["s", "e", "n", "w"]] +
            [{"facing": f, "frame": "1", "pose": "frantic, arms flailing to the other side, wide stance"} for f in
             ["s", "e", "n", "w"]]
        ),
    },
}

JOB_ORDER = list(JOBS.keys())


# ---------------------------------------------------------------------------
# Budget tracking
# ---------------------------------------------------------------------------


def _sum_report_cost(path: Path) -> float:
    if not path.exists():
        return 0.0
    report = json.loads(path.read_text(encoding="utf-8"))
    total = 0.0
    for rec in report.get("results", {}).values():
        for a in rec.get("attempts", []):
            total += (a.get("usage") or {}).get("cost") or 0.0
        if isinstance(rec.get("usage"), dict):  # sheet_report shape
            total += rec["usage"].get("cost") or 0.0
    return total


def total_spend() -> float:
    return _sum_report_cost(MAIN_REPORT) + _sum_report_cost(SHEET_REPORT)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def load_sheet_report() -> dict[str, Any]:
    if SHEET_REPORT.exists():
        return json.loads(SHEET_REPORT.read_text(encoding="utf-8"))
    return {"model": MODEL, "jobs": {}}


def save_sheet_report(report: dict[str, Any]) -> None:
    CREW_DIR.mkdir(parents=True, exist_ok=True)
    SHEET_REPORT.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--job", type=str, help="job id from JOBS")
    parser.add_argument("--list-jobs", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--quality", default="high", choices=["auto", "low", "medium", "high"])
    parser.add_argument("--reference", action="store_true", help="anchor on the approved base sheet cell too")
    parser.add_argument("--total-spend", action="store_true")
    args = parser.parse_args(argv)

    if args.list_jobs:
        for jid, job in JOBS.items():
            cols, rows = job["grid"]
            print(f"{jid:20s} state={job['state']:14s} grid={cols}x{rows} contract={job['contract']} "
                  f"cells={len(job['cells'])}")
        return 0

    if args.total_spend:
        print(f"total reported API cost so far: ${total_spend():.4f}")
        return 0

    if not args.job:
        parser.error("pass --job <id> (see --list-jobs) or --total-spend")

    job = JOBS.get(args.job)
    if job is None:
        raise SystemExit(f"unknown job id {args.job!r} -- see --list-jobs")

    if args.dry_run:
        run_job(job, api_key="", quality=args.quality, reference=args.reference, dry_run=True)
        return 0

    api_key = gen.load_api_key()
    before = total_spend()
    record = run_job(job, api_key, quality=args.quality, reference=args.reference, dry_run=False)

    report = load_sheet_report()
    report.setdefault("jobs", {})[job["id"]] = record
    save_sheet_report(report)

    after = total_spend()
    print()
    print(f"job '{job['id']}' cost ${after - before:.4f}  (session total now ${after:.4f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
