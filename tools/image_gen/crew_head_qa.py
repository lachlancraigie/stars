#!/usr/bin/env python3
"""
tools/image_gen/crew_head_qa.py
==================================

ABSOLUTE-PIXEL head-size QA gate for assets/sprites/gen2/crew/ -- the
replacement for crew_proportion_qa.py's head-height RATIO check (kept in
place, not deleted: its amber-leak and skin-fragmentation signals are still
useful and unrelated to head size). Two regeneration rounds and the ratio
gate all failed to fix/catch head-size inconsistency because a ratio can
pass while the absolute pixel size is still wrong (a bigger head on a
proportionally bigger body reads as "fine" on a ratio check -- see
crew_head_geom.py's module docstring). crew_head_swap.py fixed the existing
116 sprites by construction (one canonical head PNG pasted per facing, see
that script + _test/verify_report.json); THIS script is the standing gate so
a future regenerated/added sprite is checked against the SAME canonical
sizes in exact pixels, not a ratio.

CANONICAL SIZES: measured live, per facing, from that facing's own
crew_idle_{facing}_0.png -- using measure_head(), the EXACT SAME function
this script uses to measure every scanned sprite. This is deliberate, not
just convenient: _test/canonical_heads/canon_info.json records the PADDED
crop PNG's own pixel dimensions (a few px of hair-outline margin added on
top/left/right when crew_head_swap.py authored the canonical head -- see
that script's CANON_PAD_SIDES/CANON_PAD_TOP), which is a different quantity
than what measure_head's strict color+geometric segmentation reports for a
head already sitting on a body. Comparing measure_head's output against the
padded crop size flagged every single sprite in this kit at 0px tolerance,
including the literal canonical donor sprites -- an apples-to-oranges bug
caught while validating this gate against the just-fixed 116-sprite set (see
crew_head_swap.py's own before/after tables for that fix). Measuring the
donor with the SAME function fixes the comparison; idle is used because it's
the single-frame neutral stand every facing's canonical head was authored
from.

GATE: for every "stand"-contract sprite (the upright poses head-swap
applies to -- idle/walk/injured_walk/fight_melee/fight_ranged/carry_*),
measure its head bbox (crew_head_geom.measure_head -- the identical
geometric+palette method used for the before/after tables) and compare
(head_w, head_h) to its facing's canonical size. Flags if either dimension
differs by more than --tolerance px (default +-2, see DEFAULT_TOLERANCE for
the calibration -- absorbs measurement noise while still catching the
original defect's scale, several px to over 10px off).

Known measurement caveat, inherited from crew_proportion_qa.py's own
documented limitation (crew_head_geom.neck_row) and confirmed while building
this pipeline: the geometric neck-pinch detector can misfire on non-neutral
poses (a hunched limp, a mid-swing torso lean), occasionally under/over-
shooting by a few px even on a sprite whose head is genuinely correct. Sprites
flagged here are a lead for a human/pixel diff, not an automatic reject --
same posture crew_proportion_qa.py already takes with its own tolerance.
Prone/seated-contract sprites (dead, sleeping, floating, ...) are reported
but never gated -- the geometric detector needs a roughly vertical standing
silhouette (see crew_head_geom.shoulder_row's docstring), which those poses
don't have.

KNOWN RESIDUAL FALSE POSITIVES (found running this gate over the just-fixed
116-sprite set, kept here so a future run doesn't re-chase them): on a
handful of frames -- crew_fight_melee_s_1, crew_fight_ranged_n_0/n_1,
crew_injured_walk_s_2/s_3, crew_walk_s_1, crew_walk_w_2/w_3, and (as a
"no head-colored region found" error rather than a size delta)
crew_walk_s_3/crew_walk_se_0/crew_walk_se_3 -- the neck-pinch detector
collapses to a near-zero head height (4px, vs. an 18-21px canonical) or
finds nothing at all. Each was individually visually verified (pixel-zoomed
crop, see the task's _test/head_zoom_strips.png) to have a correctly-sized,
correctly-seated head; the detector is simply confused by that specific
pose's silhouette (a lean, a raised arm passing through the neck's width-
profile window). Not promoted to KNOWN_CORRUPT_SPRITES-style permanent
exclusion because unlike crew_head_swap.py's corrupt-sprite list (verified
bleed/missing-body defects visible in the pixels themselves), this is a
measurement-tool limitation on sprites that are actually fine -- excluding
them here would hide a REAL future regression on those same frames.

Usage:
    python crew_head_qa.py                       # scan everything, print + save report
    python crew_head_qa.py --facing sw w          # scan only these facings
    python crew_head_qa.py --tolerance 2          # allow +-2px per dimension
    python crew_head_qa.py --json out.json        # also write a JSON report
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from crew_sheet_gen import JOBS, _parse_crew_filename, _KNOWN_FACINGS
from crew_head_geom import measure_head

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
CREW_DIR = REPO_ROOT / "assets" / "sprites" / "gen2" / "crew"

# +-2px per dimension: tight enough to still catch the original defect (the
# owner-measured example was 15x22 vs 26x24 -- an 11px/6px delta, far outside
# this window) while absorbing the neck-pinch geometric detector's documented
# few-px noise on non-neutral poses (crew_head_geom.shoulder_row's docstring;
# also see this module's own docstring) so a genuinely-fixed sprite doesn't
# spuriously flag. Calibrated against the just-fixed 116-sprite set with
# --tolerance 0 (every sprite flagged, including several with a provably
# identical, checksum-verified pasted head -- pure measurement noise) vs
# --tolerance 2 (see main()'s module-level test invocation in the commit
# this file shipped with).
DEFAULT_TOLERANCE = 2

STATE_CONTRACT: dict[str, str] = {job["state"]: job["contract"] for job in JOBS.values()}
GATED_CONTRACT = "stand"


def load_canonical_sizes() -> dict[str, tuple[int, int]]:
    """(w, h) per facing, in px -- measure_head() run on that facing's own
    crew_idle_{facing}_0.png. See module docstring for why this measures the
    donor with the SAME function used to scan every other sprite, instead of
    reading _test/canonical_heads/canon_info.json's padded crop size."""
    sizes: dict[str, tuple[int, int]] = {}
    for facing in sorted(_KNOWN_FACINGS):
        path = CREW_DIR / f"crew_idle_{facing}_0.png"
        if not path.exists():
            continue
        m = measure_head(path)
        if "head_w" in m:
            sizes[facing] = (m["head_w"], m["head_h"])
    return sizes


def scan(facings_filter: set[str] | None = None, tolerance: int = DEFAULT_TOLERANCE) -> dict[str, Any]:
    canonical = load_canonical_sizes()
    files = sorted(CREW_DIR.glob("crew_*.png"))
    entries: dict[str, Any] = {}

    for path in files:
        parsed = _parse_crew_filename(path.stem)
        if parsed is None:
            continue
        state, facing, frame = parsed
        if facings_filter and facing not in facings_filter:
            continue
        contract = STATE_CONTRACT.get(state, "?")

        m = measure_head(path)
        m.update({"state": state, "facing": facing, "frame": frame, "contract": contract, "file": path.name})

        canon_wh = canonical.get(facing)
        m["canonical_wh"] = list(canon_wh) if canon_wh else None

        gated = contract == GATED_CONTRACT
        m["gated"] = gated
        flagged = False
        reasons: list[str] = []
        if gated:
            if "error" in m:
                flagged = True
                reasons.append(m["error"])
            elif canon_wh is None:
                flagged = True
                reasons.append(f"no canonical size on record for facing {facing!r}")
            else:
                dw = m["head_w"] - canon_wh[0]
                dh = m["head_h"] - canon_wh[1]
                m["delta_w"], m["delta_h"] = dw, dh
                if abs(dw) > tolerance or abs(dh) > tolerance:
                    flagged = True
                    reasons.append(f"head {m['head_w']}x{m['head_h']}px vs canonical {canon_wh[0]}x{canon_wh[1]}px "
                                   f"(delta {dw:+d}x{dh:+d}, tolerance +-{tolerance}px)")
        m["flagged"] = flagged
        m["flag_reasons"] = reasons
        entries[path.stem] = m

    gated_entries = {k: v for k, v in entries.items() if v["gated"]}
    flagged = sorted(k for k, v in gated_entries.items() if v["flagged"])

    return {
        "tolerance_px": tolerance,
        "canonical_sizes": {f: list(wh) for f, wh in canonical.items()},
        "n_sprites": len(entries),
        "n_gated": len(gated_entries),
        "n_flagged": len(flagged),
        "flagged": flagged,
        "entries": entries,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--facing", nargs="*", default=None, help="restrict to these facing codes")
    parser.add_argument("--tolerance", type=int, default=DEFAULT_TOLERANCE,
                         help=f"allowed per-dimension px delta from canonical (default {DEFAULT_TOLERANCE})")
    parser.add_argument("--json", type=Path, default=None, help="also write full report to this path")
    parser.add_argument("--quiet", action="store_true", help="only print the summary, not every sprite")
    args = parser.parse_args(argv)

    facings_filter = set(args.facing) if args.facing else None
    if facings_filter and not facings_filter.issubset(_KNOWN_FACINGS):
        parser.error(f"unknown facing(s): {facings_filter - _KNOWN_FACINGS}")

    report = scan(facings_filter, args.tolerance)

    print(f"canonical head sizes (px): {report['canonical_sizes']}")
    print(f"tolerance: +-{report['tolerance_px']}px per dimension")
    print(f"scanned {report['n_sprites']} sprites ({report['n_gated']} gated -- 'stand' contract), "
          f"{report['n_flagged']} flagged\n")

    if not args.quiet:
        for key in sorted(report["entries"]):
            e = report["entries"][key]
            if not e["gated"]:
                continue
            mark = "FLAG" if e["flagged"] else "pass"
            wh = f"{e.get('head_w','?')}x{e.get('head_h','?')}" if "head_w" in e else "?"
            print(f"  [{mark}] {key:32s} facing={e['facing']:2s} head={wh:7s} canonical={e.get('canonical_wh')}"
                  + (f"  -- {'; '.join(e['flag_reasons'])}" if e["flagged"] else ""))

    if report["n_flagged"]:
        print(f"\nFLAGGED ({report['n_flagged']}): {', '.join(report['flagged'])}")

    if args.json:
        args.json.write_text(json.dumps(report, indent=2, default=str), encoding="utf-8")
        print(f"\nfull report written to {args.json}")

    return 1 if report["n_flagged"] else 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
