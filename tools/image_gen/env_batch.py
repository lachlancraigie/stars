#!/usr/bin/env python3
"""
tools/image_gen/env_batch.py
==============================

Full ENVIRONMENT manifest for the gen2 kit: everything ShipLayoutGen
(scripts/procedural/ship_layout_gen.gd) draws from the Kenney kit, generated
as 1:1 replacements so the eventual swap is a data change:

  - Floor tiles: one per room type in FLOOR_TILE_BY_TYPE (bridge, corridor,
    medbay, mess, quarters, cargo, engine_room, life_support, ai_core,
    airlock). Semantic names (tile_<type>.png): the game maps room type ->
    tile via the FLOOR_TILE_BY_TYPE const, so per-type tiles slot in with a
    one-line-per-type value edit there (and make the per-type tint hack
    optional). 4 of the 10 already exist from the pilot.
  - Props: every distinct sprite name referenced in PROP_POOLS /
    CENTERPIECE_BY_TYPE, saved under the EXACT Kenney name
    (e.g. desk_computerScreen_SE.png) so PROP_POOLS needs zero edits.
    Direction variants: _SW derived by mirroring _SE (and _NW from _NE)
    where the object is near-symmetric; genuinely view-dependent props
    (chairs seen from behind) get their own generation.
  - Walls: pilot already produced wall_ne/se/nw/sw; this script emits
    exact-name copies (corridor_wall_NE.png etc.) for WALL_SPRITE_FOR_EDGE.
  - Door states: ONE neutral door sprite (pilot's door_gate); the game
    already recolours door gates by lock state at runtime (see CLAUDE.md),
    which is cheaper and more consistent than baked state variants.

Generation counts: 6 floors + 23 prop generations (22 base + chairArms back
view) = 29 calls first-pass, plus auto-retries; derivatives are free (PIL
mirror/copy). Spend is logged per run.

Usage:
    python env_batch.py --dry-run
    python env_batch.py                # generate everything missing
    python env_batch.py --only barrel_SE,desk_chair_SE
    python env_batch.py --derive-only  # just rebuild mirrors/copies
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image

import generate as gen
import pilot_batch as pb
from normalize_gen2 import alpha_bbox, interior_hole_pct, normalize, qa_normalized

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
OUT_DIR = REPO_ROOT / "assets" / "sprites" / "gen2"

MAX_CALLS = 60  # this script's own cap; coordinator budget is ~150 overall
MODEL = pb.MODEL

# ---------------------------------------------------------------------------
# Floor tiles (semantic names; category "floor" reuses pilot framing + rules)
# ---------------------------------------------------------------------------

FLOOR_ASSETS: list[dict[str, Any]] = [
    {
        "id": "tile_bridge",
        "category": "floor",
        "subject": "Bridge command-deck floor tile: dark steel plating with a subtle "
        "painted cyan chevron pointing toward one corner and thin panel seams. "
        "Completely flat and empty -- no consoles, no chairs, no 3D objects, only "
        "the painted floor surface.",
    },
    {
        "id": "tile_mess",
        "category": "floor",
        "subject": "Mess hall floor tile: off-white galley plating with a warm amber "
        "trim line along the panel seams. Completely flat and empty -- no tables, "
        "no furniture, no 3D objects, only the painted floor surface.",
    },
    {
        "id": "tile_quarters",
        "category": "floor",
        "subject": "Crew quarters floor tile: quiet steel plating with two large "
        "off-white inset floor panels. Completely flat and empty -- no bunks, no "
        "furniture, no 3D objects, only the painted floor surface.",
    },
    {
        "id": "tile_life_support",
        "category": "floor",
        "subject": "Life support room floor tile: steel plating with a painted cyan "
        "oxygen-line marking and one flush vent grate drawn flat into the surface. "
        "Completely flat and empty -- no machines, no tanks, no 3D objects, only "
        "the painted floor surface.",
    },
    {
        "id": "tile_ai_core",
        "category": "floor",
        "subject": "AI core room floor tile: dark steel plating with thin glowing "
        "cyan data-trace lines running across it like circuit paths. Completely "
        "flat and empty -- no server pillars, no 3D objects, only the painted "
        "floor surface.",
    },
    {
        "id": "tile_airlock",
        "category": "floor",
        "subject": "Airlock floor tile: heavy reinforced plating with an amber-and-"
        "dark chevron hazard border painted around its edge. Completely flat and "
        "empty -- no hatch mechanism, no 3D objects, only the painted floor "
        "surface.",
    },
]

# ---------------------------------------------------------------------------
# Props. Exact Kenney names from ship_layout_gen.gd PROP_POOLS.
# "width"/"height" pick the normalize target (Kenney props are small relative
# to the 130px tile: barrel 18px -- gen2 sizes chosen slightly chunkier for
# readability but still room-scaled). "facing" feeds the crew-style direction
# clause for orientation-sensitive furniture.
# ---------------------------------------------------------------------------

PROP_ASSETS: list[dict[str, Any]] = [
    {"id": "desk_computer_SE", "subject": "A compact sci-fi computer desk workstation with a small angled terminal screen on top, facing the lower-right (south-east)", "width": 88},
    {"id": "desk_computerScreen_SE", "subject": "A sci-fi computer desk with one large upright monitor screen showing a small cyan display, facing the lower-right (south-east)", "width": 88, "mirror_to": "desk_computerScreen_SW"},
    {"id": "desk_computerCorner_SE", "subject": "An L-shaped corner computer desk with a small terminal screen, facing the lower-right (south-east)", "width": 96, "mirror_to": "desk_computerCorner_SW"},
    {"id": "desk_chair_SE", "subject": "A simple sci-fi swivel desk chair, facing the lower-right (south-east)", "width": 44},
    {"id": "desk_chairArms_SE", "subject": "A sci-fi office chair with armrests, facing the lower-right (south-east)", "width": 48, "mirror_to": "desk_chairArms_SW"},
    {"id": "desk_chairArms_NW", "subject": "A sci-fi office chair with armrests, facing away from the camera toward the upper-left (north-west), seen from behind so its backrest faces the viewer", "width": 48},
    {"id": "desk_chairStool_NW", "subject": "A low round work stool, seen from slightly behind at the isometric angle", "width": 40},
    {"id": "barrel_SE", "subject": "A single sci-fi storage barrel drum with a lid ring", "width": 36, "mirror_to": "barrel_SW"},
    {"id": "barrels_SE", "subject": "A tight cluster of three sci-fi storage barrel drums", "width": 70, "mirror_to": "barrels_NW", "copy_to": "barrels_NE"},
    {"id": "barrels_rail_SE", "subject": "Two sci-fi storage barrels secured behind a low safety railing", "width": 90},
    {"id": "machine_barrel_NE", "subject": "A barrel-shaped machine tank with a small gauge panel and a pipe stub on top", "width": 55, "mirror_to": "machine_barrel_NW"},
    {"id": "machine_barrelLarge_SW", "subject": "A large industrial cylindrical tank machine with pipes and a gauge cluster", "width": 95, "copy_to": "machine_barrelLarge_NW"},
    {"id": "machine_generator_SE", "subject": "A compact generator machine unit with side vents and a small status light", "width": 80, "mirror_to": "machine_generator_SW"},
    {"id": "machine_generatorLarge_SE", "subject": "A large generator machine with exposed coil housing and thick power cables", "width": 110},
    {"id": "machine_wireless_SE", "subject": "A comms machine cabinet with a short antenna mast and a small cyan screen", "width": 60, "mirror_to": "machine_wireless_SW"},
    {"id": "machine_wirelessCable_SE", "subject": "A comms machine cabinet with a cable spool and a conduit running to a small junction box", "width": 70},
    {"id": "pipe_straight_SE", "subject": "A single straight industrial pipe segment on two low support feet, running diagonally at the isometric angle toward the lower-right", "width": 110},
    {"id": "pipe_ring_SE", "subject": "An industrial pipe segment with a bolted ring joint collar, on low support feet, running diagonally toward the lower-right", "width": 90, "mirror_to": "pipe_ring_NW"},
    {"id": "pipe_ringHigh_SE", "subject": "An elevated industrial pipe with a bolted ring joint, raised on two tall support columns, running diagonally toward the lower-right", "width": 90},
    {"id": "pipe_supportHigh_SE", "subject": "A single tall industrial pipe support column with a saddle bracket on top", "height": 150},
    {"id": "pipe_cross_SE", "subject": "An industrial pipe cross junction: two pipe runs crossing at the isometric angle with a bolted center collar, on low support feet", "width": 110},
    {"id": "pipe_entrance_SE", "subject": "A large pipe entrance structure: a short tunnel mouth with a reinforced ring frame, facing the lower-right", "width": 100},
    {"id": "structure_closed_SE", "subject": "A closed structural storage cabinet locker unit with panel doors and a small status light", "width": 80},
]

# Wall exact-name copies for WALL_SPRITE_FOR_EDGE (pilot files -> Kenney names).
WALL_COPIES = {
    "corridor_wall_NE": "wall_ne",
    "corridor_wall_NW": "wall_nw",
    "corridor_wall_SE": "wall_se",
    "corridor_wall_SW": "wall_sw",
}

PROP_FRAMING = pb.FRAMING["prop"]


def prop_rule(asset: dict[str, Any]) -> dict[str, Any]:
    if "height" in asset:
        return {"mode": "height", "height": asset["height"], "anchor": ("center", 256, 330)}
    return {"mode": "width", "width": asset["width"], "anchor": ("center", 256, 330)}


def compose_env_prompt(asset: dict[str, Any], corrective: str | None = None) -> str:
    if asset["category"] == "floor":
        framing = pb.FRAMING["floor"]
    else:
        framing = PROP_FRAMING
    parts = [pb.STYLE_LOCK, asset["subject"], framing, pb.NEGATIVE]
    if corrective:
        parts.append(corrective)
    return " ".join(parts)


def generate_env_asset(asset: dict[str, Any], api_key: str, calls: list[int],
                       report: dict[str, Any]) -> None:
    record: dict[str, Any] = {"id": asset["id"], "category": asset["category"], "attempts": []}
    rule = pb_rule_for(asset)

    corrective = None
    final_im = None
    final_qa = None
    for attempt in (1, 2):
        if calls[0] >= MAX_CALLS:
            record["notes"] = "env_batch call cap reached before this attempt"
            break
        prompt = compose_env_prompt(asset, corrective)
        calls[0] += 1
        try:
            result = gen.generate_image(prompt, model=MODEL, background="transparent", api_key=api_key)
        except gen.GenerationError as exc:
            record["attempts"].append({"attempt": attempt, "prompt": prompt, "error": str(exc)})
            print(f"    [error] {exc}")
            continue

        im = pb.normalize_to_canvas(result["png_bytes"])
        normalized, info = normalize(im, rule)
        qa = qa_normalized(normalized, rule, info)
        record["attempts"].append({"attempt": attempt, "prompt": prompt,
                                   "usage": result.get("usage"), "qa": qa})
        print(f"    attempt {attempt}: {'PASS' if qa['pass'] else 'FLAGGED'} "
              f"holes={qa.get('interior_hole_pct')}% notes={qa['notes']}")
        final_im, final_qa = normalized, qa
        record["normalize"] = info
        if qa["pass"]:
            break
        corrective = pb.corrective_prompt_for(
            {"has_alpha": qa["has_alpha"], "centroid": None, "centroid_ok": True,
             "solid_ok": qa["solid_ok"]}
        )

    record["final_qa"] = final_qa
    if final_im is not None:
        out_path = OUT_DIR / f"{asset['id']}.png"
        final_im.save(out_path)
        record["staged_path"] = str(out_path.relative_to(REPO_ROOT))
        print(f"  saved {out_path.name}")
    else:
        record["staged_path"] = None
        print("  [no image produced]")
    report["results"][asset["id"]] = record


def pb_rule_for(asset: dict[str, Any]) -> dict[str, Any]:
    if asset["category"] == "floor":
        from normalize_gen2 import NORM_RULES
        return NORM_RULES["floor"]
    return prop_rule(asset)


def derive(report: dict[str, Any]) -> None:
    """Mirrors/copies for direction variants + exact-name wall copies."""
    for asset in PROP_ASSETS:
        src_path = OUT_DIR / f"{asset['id']}.png"
        if not src_path.exists():
            continue
        for key, flip in (("mirror_to", True), ("copy_to", False)):
            dst_id = asset.get(key)
            if not dst_id:
                continue
            im = Image.open(src_path).convert("RGBA")
            if flip:
                im = im.transpose(Image.FLIP_LEFT_RIGHT)
            dst = OUT_DIR / f"{dst_id}.png"
            im.save(dst)
            hole_pct = interior_hole_pct(im)
            report["results"][dst_id] = {
                "id": dst_id,
                "category": "prop",
                "derived_from": asset["id"],
                "attempts": [],
                "staged_path": str(dst.relative_to(REPO_ROOT)),
                "final_qa": {
                    "canvas_ok": True, "has_alpha": True, "anchored_ok": True,
                    "interior_hole_pct": round(hole_pct, 2),
                    "solid_ok": hole_pct <= 10.0,
                    "pass": hole_pct <= 10.0,
                    "notes": [f"derived: {'mirror' if flip else 'copy'} of {asset['id']}"],
                },
            }
            print(f"  {dst_id}: derived ({'mirror' if flip else 'copy'} of {asset['id']})")

    for dst_id, src_id in WALL_COPIES.items():
        src_path = OUT_DIR / f"{src_id}.png"
        if not src_path.exists():
            continue
        dst = OUT_DIR / f"{dst_id}.png"
        Image.open(src_path).save(dst)
        src_qa = (report["results"].get(src_id) or {}).get("final_qa")
        report["results"][dst_id] = {
            "id": dst_id,
            "category": "wall",
            "derived_from": src_id,
            "attempts": [],
            "staged_path": str(dst.relative_to(REPO_ROOT)),
            "final_qa": dict(src_qa or {}, notes=[f"derived: exact-name copy of {src_id} "
                                                  "for WALL_SPRITE_FOR_EDGE"]),
        }
        print(f"  {dst_id}: exact-name copy of {src_id}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", type=str, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--derive-only", action="store_true")
    parser.add_argument("--skip-existing", action="store_true",
                        help="skip assets whose staged PNG already exists")
    args = parser.parse_args(argv)

    assets = [dict(a, category="floor") for a in FLOOR_ASSETS] + [
        dict(a, category="prop") for a in PROP_ASSETS
    ]
    if args.only:
        wanted = set(args.only.split(","))
        assets = [a for a in assets if a["id"] in wanted]

    if args.dry_run:
        for a in assets:
            print(f"--- {a['id']} ({a['category']}) ---")
            print(compose_env_prompt(a)[:400] + " ...")
        print(f"[dry-run] {len(assets)} generations (cap {MAX_CALLS}), "
              f"+{sum(1 for a in PROP_ASSETS if a.get('mirror_to') or a.get('copy_to'))} derivatives, "
              f"+{len(WALL_COPIES)} wall copies")
        return 0

    report_path = OUT_DIR / "report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    report.setdefault("results", {})

    if not args.derive_only:
        api_key = gen.load_api_key()
        calls = [0]
        total_cost = 0.0
        for asset in assets:
            out_path = OUT_DIR / f"{asset['id']}.png"
            if args.skip_existing and out_path.exists():
                print(f"{asset['id']}: exists, skipping")
                continue
            print(f"generating {asset['id']} ({asset['category']}) ...")
            generate_env_asset(asset, api_key, calls, report)
            report_path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
        for rec in report["results"].values():
            for a in rec.get("attempts", []):
                total_cost += (a.get("usage") or {}).get("cost") or 0.0
        print(f"\ncalls this run: {calls[0]}/{MAX_CALLS}; report-wide cost so far: ${total_cost:.4f}")

    derive(report)
    report_path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
    print(f"report updated: {report_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
