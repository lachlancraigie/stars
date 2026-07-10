#!/usr/bin/env python3
"""
tools/image_gen/crew_facings.py
=================================

Crew facing-consistency test (the gate before batch-generating the crew set):
generate ONE astronaut S-facing idle (prompt-only, current style block), then
derive E, N, W facings via reference anchoring (input_references = the
approved S sprite), and QA whether all four read as the same character.

The Kenney kit has 8 facings per astronaut; the game currently uses S/E/N/W
plus mirrors. If this 4-facing test holds, the pattern extends to the full
crew set (idle/walk/panic/collapsed per the old Reve manifest); if it
doesn't, crew stays on the Kenney astronauts (they already work) and gen2
covers environment only.

Usage:
    python crew_facings.py            # run all 4 facings (S prompt-only, ENW anchored)
    python crew_facings.py --only e,n
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

import generate as gen
import pilot_batch as pb
from normalize_gen2 import NORM_RULES, normalize, qa_normalized

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
OUT_DIR = REPO_ROOT / "assets" / "sprites" / "gen2"

MODEL = pb.MODEL
CREW_RULE = NORM_RULES["crew"]

BASE_SUBJECT = (
    "A ship crew member in a simple utilitarian jumpsuit, off-white body with "
    "steel-gray trim, standing idle, no helmet, simplified featureless face."
)

FACINGS: dict[str, str] = {
    "s": "toward the camera (south/front view)",
    "e": "to the right (east view), full side profile",
    "n": "away from the camera (north/back view), seen from behind",
    "w": "to the left (west view), full side profile",
}

REF_CLAUSE = (
    " This must be EXACTLY the same character as in the reference image: same "
    "jumpsuit colors, same body proportions, same head size, same hair, same "
    "outline weight, same cel shading, same camera angle -- only the facing "
    "direction changes."
)


def run_one(facing: str, api_key: str, report: dict[str, Any]) -> None:
    asset_id = f"crew_astronaut_idle_{facing}"
    asset = {
        "id": asset_id,
        "category": "crew",
        "subject": BASE_SUBJECT,
        "direction": FACINGS[facing],
    }
    prompt = pb.compose_prompt(asset)
    refs: list[Path] = []
    if facing != "s":
        s_path = OUT_DIR / "crew_astronaut_idle_s.png"
        if not s_path.exists():
            raise SystemExit("generate the s facing first (it is the anchor)")
        refs = [s_path]
        prompt += REF_CLAUSE

    record: dict[str, Any] = {"id": asset_id, "category": "crew",
                              "anchored_on": "crew_astronaut_idle_s" if refs else None,
                              "attempts": []}
    print(f"generating {asset_id} ({'anchored' if refs else 'prompt-only'}) ...")
    try:
        result = gen.generate_image(prompt, model=MODEL, background="transparent",
                                    input_references=refs or None, api_key=api_key)
    except gen.GenerationError as exc:
        record["attempts"].append({"attempt": 1, "prompt": prompt, "error": str(exc)})
        report["results"][asset_id] = record
        print(f"  [error] {exc}")
        return

    im = pb.normalize_to_canvas(result["png_bytes"])
    normalized, info = normalize(im, CREW_RULE)
    qa = qa_normalized(normalized, CREW_RULE, info)
    record["attempts"].append({"attempt": 1, "prompt": prompt,
                               "usage": result.get("usage"), "qa": qa})
    record["normalize"] = info
    record["final_qa"] = qa

    out_path = OUT_DIR / f"{asset_id}.png"
    normalized.save(out_path)
    record["staged_path"] = str(out_path.relative_to(REPO_ROOT))
    report["results"][asset_id] = record
    print(f"  [{'PASS' if qa['pass'] else 'FLAGGED'}] saved {out_path.name} "
          f"holes={qa.get('interior_hole_pct')}%")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--only", type=str, default=None, help="comma-separated facings (s,e,n,w)")
    args = parser.parse_args(argv)

    facings = list(FACINGS) if not args.only else [f.strip().lower() for f in args.only.split(",")]

    report_path = OUT_DIR / "report.json"
    report = json.loads(report_path.read_text(encoding="utf-8"))
    report.setdefault("results", {})

    api_key = gen.load_api_key()
    for f in facings:
        run_one(f, api_key, report)
        report_path.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")

    print("done -- judge cross-facing consistency on the contact sheet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
