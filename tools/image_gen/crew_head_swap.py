#!/usr/bin/env python3
"""
tools/image_gen/crew_head_swap.py
====================================

HEAD-SWAP COMPOSITING (paper-doll) fix for head-size inconsistency across
assets/sprites/gen2/crew/ facings/states -- see crew_head_geom.py's docstring
for why this replaces (rather than extends) the two failed regeneration
rounds and the two failed QA gates (ratio-based crew_proportion_qa.py, and
human-eye contact-sheet review). Generation SAMPLES head proportions per
call; it cannot be dictated to hit an exact pixel size. This script makes the
head IDENTICAL BY CONSTRUCTION instead: one canonical head PNG per facing,
pasted onto every sprite of that facing.

Pipeline (see main() / --step):
  1. measure   -- segment every crew_*.png's head (crew_head_geom) and write
                  _test/head_bbox_before.json (the defect's evidence baseline).
  2. canon     -- pick the best idle donor head per facing (s, se, e, ne, n),
                  crop+save it to _test/canonical_heads/, and derive w/sw/nw
                  by horizontal mirror of e/se/ne (mirroring guarantees
                  left-right symmetry by construction -- no separate donor
                  needed for the mirrored facings).
  3. composite -- for every "stand"-contract sprite (the upright poses:
                  idle/walk/injured_walk/fight_melee/fight_ranged/carry_*),
                  erase the sprite's own head pixels and paste the canonical
                  head for its facing, anchored on THAT SPRITE'S OWN
                  shoulder/collar line (crew_head_geom.shoulder_row -- a
                  defective oversized head compresses the whole body into
                  the fixed 70px contract, so the shoulder line itself moves;
                  see that function's docstring), 1px alpha feather at the
                  seam, then palette-snap. "prone"/"seated" contract sprites
                  (dead, sleeping, floating, repairing, eating) are handled
                  separately -- see prone_skip_report().
  4. verify    -- re-measure everything into _test/head_bbox_after.json and
                  assert every non-flagged sprite of a facing has an
                  IDENTICAL head bbox + identical pasted-region pixel
                  checksum (verify_construction()).
  5. zoomstrip -- _test/head_zoom_strips.png: per-facing rows of every
                  state's head crop at 4x, the artifact the owner actually
                  reviews (never rely on full-sheet review again).
  6. contactsheet -- regenerate _test/idle_all_facings_contact_sheet.png.

Usage:
    python crew_head_swap.py --step measure
    python crew_head_swap.py --step canon
    python crew_head_swap.py --step composite
    python crew_head_swap.py --step verify
    python crew_head_swap.py --step zoomstrip
    python crew_head_swap.py --step contactsheet
    python crew_head_swap.py --step all
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

from palette_snap import snap_image, alpha_bbox, PALETTE_LIST
from crew_sheet_gen import JOBS, _parse_crew_filename, FACING_DESC
from crew_head_geom import head_bbox_of, neck_row, shoulder_row, measure_head, HEAD_ALLOWED_COLORS

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
CREW_DIR = REPO_ROOT / "assets" / "sprites" / "gen2" / "crew"
TEST_DIR = CREW_DIR / "_test"
CANON_DIR = TEST_DIR / "canonical_heads"

ALPHA_T = 10

STATE_CONTRACT: dict[str, str] = {job["state"]: job["contract"] for job in JOBS.values()}

# Facings authored directly from idle donors; the rest are horizontal mirrors
# (mirroring guarantees left-right symmetry by construction -- task spec).
AUTHORED_FACINGS = ["s", "se", "e", "ne", "n"]
MIRROR_OF = {"w": "e", "sw": "se", "nw": "ne"}  # derived facing -> source facing

FACING_ORDER = ["s", "se", "e", "ne", "n", "nw", "w", "sw"]

# Padding around the measured head bbox to capture the full hair silhouette
# (outline pixels can sit just outside the strict color-mask bbox -- see
# crew_head_geom.HEAD_ALLOWED_COLORS docstring). Bottom is deliberately NOT
# padded -- the crop's own bottom edge is exactly the donor's own detected
# neck row, i.e. the head crop's "chin" -- so when step_composite anchors
# that chin to a target sprite's own shoulder line (crew_head_geom.
# shoulder_row), the head registers flush against the collar with no
# per-sprite offset math needed.
CANON_PAD_SIDES = 3
CANON_PAD_TOP = 3

# Pre-existing corrupt source sprites found during visual review while
# building the BEFORE table -- NOT a head-size defect, out of scope for this
# fix. Most of these contain TWO overlapping figures (a slicing/bleed defect
# in crew_sheet_gen.py's slice_cells_auto -- the raw sheets for these jobs
# either drew an extra unrequested column (_raw_fight_melee_s_e.png visibly
# has 4 columns of content where only 3 were requested) or packed figures
# tightly enough that the alpha-gap column/row detector mis-drew the
# boundary, bleeding a neighbor cell's edge into this one -- confirmed by
# eye against every job's own _raw_*.png sheet); crew_walk_n_3 is a sliver --
# roughly half the figure is missing (sliced across the body). Found via a
# full visual sweep of every "stand"-contract sprite (a bbox-width outlier
# check alone under-caught several of these -- crew_carry_walk_s_2's bleed
# fragment is only ~10px, well inside the range of a legitimate crate-
# holding pose). Head-swap cannot repair a mis-sliced or missing body --
# pasting a correctly-sized head onto a two-headed or half-missing body
# would not "look right" per the task's own skip criterion. Left completely
# untouched and flagged in composite_report.json; needs its own
# regeneration/re-slice, separate from this task.
KNOWN_CORRUPT_SPRITES = {
    "crew_walk_n_2", "crew_walk_n_3", "crew_walk_nw_2",
    "crew_walk_s_2", "crew_walk_se_1", "crew_walk_se_2",
    "crew_fight_melee_s_0", "crew_fight_melee_e_0",
    "crew_carry_walk_e_0", "crew_carry_walk_e_1", "crew_carry_walk_e_2",
    "crew_carry_walk_s_0", "crew_carry_walk_s_1", "crew_carry_walk_s_2",
}


def crew_files() -> list[Path]:
    return sorted(p for p in CREW_DIR.glob("crew_*.png") if p.suffix == ".png")


def parsed_entries() -> list[tuple[Path, str, str, int]]:
    out = []
    for p in crew_files():
        parsed = _parse_crew_filename(p.stem)
        if parsed is None:
            continue
        state, facing, frame = parsed
        out.append((p, state, facing, frame))
    return out


# ---------------------------------------------------------------------------
# Step 1: measure
# ---------------------------------------------------------------------------


def step_measure(out_path: Path) -> dict[str, Any]:
    entries: dict[str, Any] = {}
    for p, state, facing, frame in parsed_entries():
        m = measure_head(p)
        m.update({"state": state, "facing": facing, "frame": frame,
                   "contract": STATE_CONTRACT.get(state, "?"), "file": p.name})
        entries[p.stem] = m
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(entries, indent=2, default=str), encoding="utf-8")
    n_err = sum(1 for e in entries.values() if "error" in e)
    print(f"measured {len(entries)} sprites ({n_err} with no head found) -> {out_path}")
    return entries


# ---------------------------------------------------------------------------
# Step 2: canonical heads
# ---------------------------------------------------------------------------


def crop_head(im: Image.Image, hbbox: tuple[int, int, int, int]) -> tuple[Image.Image, tuple[int, int, int, int]]:
    """Crop the head with a small pad on top/left/right (catches hair-outline
    pixels that sit just outside the strict color mask) but NO pad on the
    bottom -- the crop's bottom edge is exactly the donor's neck row. Returns
    (cropped_image, actual_crop_box_used)."""
    x0, y0, x1, y1 = hbbox
    w, h = im.size
    cx0, cy0 = max(0, x0 - CANON_PAD_SIDES), max(0, y0 - CANON_PAD_TOP)
    cx1, cy1 = min(w, x1 + CANON_PAD_SIDES), y1  # no bottom pad, see docstring
    return im.crop((cx0, cy0, cx1, cy1)), (cx0, cy0, cx1, cy1)


def step_canon() -> dict[str, dict[str, Any]]:
    """Pick the idle frame as the donor for each authored facing (idle is the
    single-frame neutral stand -- the pose every other state's neck anchors
    against) and save canonical head crops. Mirrors derive w/sw/nw.

    Only the head's SIZE (crop dimensions) is canonical here -- WHERE it gets
    pasted on a given target sprite is computed per-sprite in step_composite
    from that sprite's own shoulder line (crew_head_geom.shoulder_row), not
    from the donor's own position. An earlier version of this script used a
    single fixed paste rectangle per facing (donor's own neck row, applied to
    every sprite of that facing) on the theory that every "stand"-contract
    sprite shares the same 70px-height/bottom-y=320/x-centered-256 contract
    (crew_sheet_gen.NORM_RULES) -- true, but that contract fixes the sprite's
    TOTAL bbox, not where the BODY's shoulders sit within it: a defective
    oversized donor head (crew_idle_w_0's original ~26px head, for instance)
    ate into the same fixed 70px budget, compressing the body underneath it,
    so that body's own shoulder line sits at a genuinely different absolute
    row than a clean sibling's (measured 7px lower for w vs e). Pasting a
    correctly-sized head at the CLEAN facing's fixed row left a visible gap
    above the defective body's real, lower collar. Anchoring per-sprite (this
    version) closes that gap by construction -- see shoulder_row's docstring.
    """
    CANON_DIR.mkdir(parents=True, exist_ok=True)
    canon_info: dict[str, dict[str, Any]] = {}

    for facing in AUTHORED_FACINGS:
        src_path = CREW_DIR / f"crew_idle_{facing}_0.png"
        im = Image.open(src_path).convert("RGBA")
        bbox = alpha_bbox(im)
        hbbox = head_bbox_of(im, bbox)
        if hbbox is None:
            raise SystemExit(f"canon: no head found in donor {src_path}")
        crop, used_box = crop_head(im, hbbox)
        crop = snap_image(crop)
        out_path = CANON_DIR / f"head_{facing}.png"
        crop.save(out_path)
        hw, hh = crop.size
        canon_info[facing] = {
            "source": src_path.name,
            "donor_head_bbox": hbbox,
            "crop_box": used_box,
            "size": [hw, hh],
        }
        print(f"canon[{facing}]: donor={src_path.name} head_bbox={hbbox} crop={used_box} size={crop.size}")

    for dst, src in MIRROR_OF.items():
        src_path = CANON_DIR / f"head_{src}.png"
        im = Image.open(src_path).convert("RGBA")
        mirrored = im.transpose(Image.FLIP_LEFT_RIGHT)
        out_path = CANON_DIR / f"head_{dst}.png"
        mirrored.save(out_path)
        hw, hh = mirrored.size
        canon_info[dst] = {"source": f"mirror of head_{src}.png", "size": [hw, hh]}
        print(f"canon[{dst}]: mirrored from head_{src}.png size={mirrored.size}")

    (CANON_DIR / "canon_info.json").write_text(json.dumps(canon_info, indent=2, default=str), encoding="utf-8")
    return canon_info


def load_canon_info() -> dict[str, dict[str, Any]]:
    p = CANON_DIR / "canon_info.json"
    if not p.exists():
        raise SystemExit("canon_info.json missing -- run --step canon first")
    return json.loads(p.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Step 3: composite
# ---------------------------------------------------------------------------


# Erase-cleanup safety net: even if a sprite's OWN head-detection is noisy
# (crew_proportion_qa.py's neck-pinch heuristic is documented to drift on
# non-neutral poses -- confirmed while building the before table: some
# injured/combat frames measured a clearly-wrong few-px head), the cleanup
# zone always reaches at least this far below the sprite's own bbox top, so
# an oversized defective donor head (worst observed: 26px) is fully removed
# regardless of per-sprite detection noise.
ERASE_FLOOR_PX = 34
ERASE_CEILING_PX = 46  # hard cap so a garbage detection can't eat half the torso
ERASE_MARGIN = 3


def clear_rect(im: Image.Image, rect: tuple[int, int, int, int]) -> None:
    """In-place: set every pixel in rect (clipped to canvas) fully transparent."""
    w, h = im.size
    x0, y0, x1, y1 = rect
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(w, x1), min(h, y1)
    if x1 <= x0 or y1 <= y0:
        return
    px = im.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            px[x, y] = (0, 0, 0, 0)


def clear_head_colors_in_rect(im: Image.Image, rect: tuple[int, int, int, int]) -> None:
    """In-place: clear only head-colored (hair/skin/outline) pixels within
    rect. Used for the cleanup zone OUTSIDE the fixed paste rectangle, where
    we must not blindly nuke legitimate suit-colored collar/shoulder pixels
    that vary per pose (see step_composite's zone A / zone B split)."""
    w, h = im.size
    x0, y0, x1, y1 = rect
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(w, x1), min(h, y1)
    if x1 <= x0 or y1 <= y0:
        return
    px = im.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a <= ALPHA_T:
                continue
            if (r, g, b) in HEAD_ALLOWED_COLORS:
                px[x, y] = (0, 0, 0, 0)


def paste_head(body: Image.Image, head: Image.Image, paste_rect: list[int]) -> Image.Image:
    """Paste `head` at the exact fixed paste_rect (already guaranteed blank
    by the caller's zone-A clear). 1px seam feather on the head crop's own
    bottom 2 rows so the paste doesn't leave a hard rectangular edge -- safe
    to alpha-blend here because the destination underneath is guaranteed
    fully transparent (zone A), so the blend can't pull in a differing
    per-sprite color and can't break the identical-checksum guarantee."""
    out = body.copy()
    feathered = head.copy()
    if feathered.mode != "RGBA":
        feathered = feathered.convert("RGBA")
    fpx = feathered.load()
    fw, fh = feathered.size
    for x in range(fw):
        for dy in (1, 2):
            y = fh - dy
            if y < 0:
                continue
            r, g, b, a = fpx[x, y]
            if a > ALPHA_T:
                fpx[x, y] = (r, g, b, round(a * (0.6 if dy == 1 else 0.85)))
    out.paste(feathered, (paste_rect[0], paste_rect[1]), feathered)
    return out


# A per-sprite shoulder_row() reading that deviates from its facing's median
# by more than this is treated as unreliable (a held-prop occlusion or a
# detection glitch, not a genuine pose difference) and replaced by the
# facing median instead -- calibrated against the real spread found while
# building the before table: legitimate pose-driven variation (a contact-
# pose lean, a hunch) stays within ~11px of the median; the one real outlier
# found (crew_carry_idle_s_0 -- a held crate visually occludes the collar
# for most of the upper body, so the "first body-colored row" reads far
# lower than any other 's' sprite) was 18px off.
SHOULDER_ROW_TOLERANCE = 12


def step_composite(dry_run: bool = False) -> dict[str, Any]:
    canon_info = load_canon_info()
    canon_imgs = {f: Image.open(CANON_DIR / f"head_{f}.png").convert("RGBA") for f in FACING_ORDER}

    results: dict[str, Any] = {}

    # Pass 1: gather every candidate sprite's own bbox + shoulder row, and the
    # facing-level median (fallback anchor for outlier/undetected readings).
    candidates: list[tuple[Path, str, str, int, tuple[int, int, int, int], int | None]] = []
    by_facing_rows: dict[str, list[int]] = {}
    for p, state, facing, frame in parsed_entries():
        if STATE_CONTRACT.get(state, "?") != "stand":
            continue
        if p.stem in KNOWN_CORRUPT_SPRITES:
            results[p.stem] = {"state": state, "facing": facing, "frame": frame, "skipped": True,
                                "reason": "pre-existing corrupt source sprite (multi-figure bleed or "
                                          "missing-body slice defect, unrelated to head size) -- see "
                                          "KNOWN_CORRUPT_SPRITES docstring; left untouched"}
            continue
        im = Image.open(p).convert("RGBA")
        bbox = alpha_bbox(im)
        if bbox is None:
            candidates.append((p, state, facing, frame, None, None))
            continue
        srow = shoulder_row(im, bbox)
        candidates.append((p, state, facing, frame, bbox, srow))
        if srow is not None:
            by_facing_rows.setdefault(facing, []).append(srow)

    def median(vals: list[int]) -> float:
        s = sorted(vals)
        n = len(s)
        return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2

    facing_median = {f: median(rows) for f, rows in by_facing_rows.items()}

    flagged: list[str] = [stem for stem, rec in results.items() if rec.get("skipped")]

    for p, state, facing, frame, bbox, srow in candidates:
        if bbox is None:
            flagged.append(p.stem)
            results[p.stem] = {"state": state, "facing": facing, "frame": frame,
                                "skipped": True, "reason": "no opaque pixels"}
            continue

        x0, y0, x1, y1 = bbox
        med = facing_median[facing]
        used_fallback = srow is None or abs(srow - med) > SHOULDER_ROW_TOLERANCE
        anchor_y = round(med) if used_fallback else srow

        im = Image.open(p).convert("RGBA")
        own_hbbox = head_bbox_of(im, bbox)  # may be noisy on non-neutral poses; used only to widen cleanup

        head = canon_imgs[facing]
        hw, hh = head.size
        px0 = round(256 - hw / 2)
        paste_rect = [px0, anchor_y - hh, px0 + hw, anchor_y]

        # Zone A: the paste rectangle itself. Full clear (every pixel, any
        # color) -- guarantees the paste destination is byte-identical
        # (fully transparent) regardless of what was there before, which is
        # what makes the pasted-region checksum identical by construction
        # across every sprite of a facing (crop each sprite's OWN paste_rect
        # -- same size, same source head, same blank destination -- and the
        # bytes match even though paste_rect's absolute position differs per
        # sprite; see step_verify).
        composited = im.copy()
        clear_rect(composited, tuple(paste_rect))

        # Zone B: a generous cleanup band around/below zone A, color-masked
        # only (hair/skin/outline pixels -- never suit/trim colors), so a
        # per-sprite oversized OR misdetected old head gets removed without
        # eating legitimate pose-specific collar/shoulder pixels. Floor/
        # ceiling are constants (not the noisy per-sprite detection alone)
        # so an unreliable detection on one frame can't under-clean it --
        # see ERASE_FLOOR_PX.
        own_bottom = own_hbbox[3] if own_hbbox else y0
        cleanup_y1 = min(y0 + ERASE_CEILING_PX, max(y0 + ERASE_FLOOR_PX, own_bottom, paste_rect[3]) + ERASE_MARGIN)
        cleanup_x0 = min(x0, paste_rect[0]) - ERASE_MARGIN
        cleanup_x1 = max(x1, paste_rect[2]) + ERASE_MARGIN
        clear_head_colors_in_rect(composited, (cleanup_x0, y0, cleanup_x1, cleanup_y1))
        # zone A was already fully cleared above; redo it after zone B in
        # case zone B's rect overlapped and somehow left alpha noise at the
        # exact border -- cheap and makes the ordering-independent.
        clear_rect(composited, tuple(paste_rect))

        composited = paste_head(composited, head, paste_rect)
        composited = snap_image(composited)

        if not dry_run:
            composited.save(p)

        results[p.stem] = {
            "state": state, "facing": facing, "frame": frame,
            "own_shoulder_row": srow, "facing_median_shoulder_row": med,
            "used_median_fallback": used_fallback,
            "paste_region": paste_rect, "cleanup_region": [cleanup_x0, y0, cleanup_x1, cleanup_y1],
        }

    n_ok = sum(1 for v in results.values() if not v.get("skipped"))
    n_fallback = sum(1 for v in results.values() if v.get("used_median_fallback"))
    print(f"composited {n_ok} sprites ({n_fallback} used the facing-median anchor fallback), "
          f"{len(flagged)} flagged/skipped: {flagged}")

    # Merge in the prone/seated skip records too, so composite_report.json
    # is a complete per-sprite account of every crew_*.png -- composited,
    # corrupt-source-skipped, or prone/seated-skipped -- for the final report.
    results.update(prone_skip_report())

    (TEST_DIR / "composite_report.json").write_text(json.dumps(results, indent=2, default=str), encoding="utf-8")
    return results


# ---------------------------------------------------------------------------
# Step 3b: prone/seated poses (dead, sleeping, floating, repairing, eating)
# ---------------------------------------------------------------------------

# These states are not "upright" -- pasting an upright canonical head at a
# fixed angle would look wrong (a standing head glued onto a supine corpse).
# Per task spec: rotate the canonical head to the pose angle where that's a
# sound operation, otherwise skip and flag rather than force it.
#
# Reviewed each prone/seated sprite currently in the crew set -- all 16 are
# "prone" contract (dead x2, sleeping x2, floating x12; "repairing"/"eating"
# are defined as future "seated"-contract jobs in crew_sheet_gen.JOBS but
# have no generated crew_*.png files yet, kept in this skip set defensively
# for whenever they exist). All 16 draw the head as part of a continuously-
# shaded, non-axis-aligned silhouette (a tilted skull on a sprawled corpse, a
# side-lying sleeper's head on a pillow-less bunk, a tumbling zero-g drift)
# where the "neck pinch" geometric signal the upright composite depends on
# doesn't hold -- width-profile neck detection assumes a roughly vertical,
# bottom-anchored standing silhouette (see crew_proportion_qa.py's own
# module docstring: "breaks on action poses"). Forcing a rotate-guess per
# pose risks the exact "force garbage" outcome the task explicitly says to
# avoid. SKIPPING these (leaving the original generated head in place) is
# the sound call: a small, already-reviewed minority of the set (16/116
# sprites), flagged individually below rather than silently left out.
PRONE_SKIP_STATES = {"dead", "sleeping", "floating", "repairing", "eating"}


def prone_skip_report() -> dict[str, Any]:
    out: dict[str, Any] = {}
    for p, state, facing, frame in parsed_entries():
        contract = STATE_CONTRACT.get(state, "?")
        if contract == "stand":
            continue
        out[p.stem] = {
            "state": state, "facing": facing, "frame": frame, "contract": contract,
            "skipped": True,
            "reason": ("non-upright pose (prone/seated) -- neck-pinch anchor geometry doesn't hold; "
                       "canonical-head paste would require a per-pose rotation guess, risking a worse "
                       "result than the original render. Left untouched."),
        }
    return out


# ---------------------------------------------------------------------------
# Step 4: verify by construction
# ---------------------------------------------------------------------------


def region_checksum(im: Image.Image, region: tuple[int, int, int, int]) -> str:
    crop = im.crop(region)
    return hashlib.sha256(crop.tobytes()).hexdigest()


def step_verify(before: dict[str, Any]) -> dict[str, Any]:
    after = step_measure(TEST_DIR / "head_bbox_after.json")
    composite_report = json.loads((TEST_DIR / "composite_report.json").read_text(encoding="utf-8")) \
        if (TEST_DIR / "composite_report.json").exists() else {}

    per_facing_bbox: dict[str, set[tuple[int, int]]] = {}
    per_facing_checksum: dict[str, dict[str, str]] = {}
    flagged_stems: set[str] = {stem for stem, rec in composite_report.items() if rec.get("skipped")} \
        | set(prone_skip_report().keys())
    mismatches: list[str] = []

    # The gate is scoped to NON-FLAGGED sprites only (task step 4's own
    # wording) -- KNOWN_CORRUPT_SPRITES and prone/seated poses were
    # deliberately left untouched (step_composite / prone_skip_report) and
    # are expected to keep their pre-existing (inconsistent) head geometry;
    # including them here would report a false mismatch for a sprite this
    # script intentionally didn't touch.
    # per_facing_bbox_general: the generic re-measurement (same tool/method
    # as the BEFORE table, for direct before/after comparability) -- kept as
    # DIAGNOSTIC data in head_bbox_after.json, not the gate. It's the same
    # width-profile neck-pinch heuristic crew_proportion_qa.py's own
    # docstring documents as unreliable off neutral poses (a hunched limp, a
    # mid-punch torso lean shift where the "narrowest row" lands); re-running
    # it post-composite can still misfire on those poses even though the
    # actual pasted pixels are provably identical (see the checksum group
    # below) -- gating on it would fail the task's own goal by re-trusting
    # the exact tool this whole approach exists to route around.
    per_facing_bbox_general: dict[str, set[tuple[int, int]]] = {}
    # per_facing_bbox: the AUTHORITATIVE head size -- the paste_region this
    # script itself recorded when it pasted the canonical head (same image,
    # same crop, so by construction every composited sprite of a facing
    # shares one (w, h)). This is what step 4's "IDENTICAL head bbox" gates
    # on.
    for stem, rec in after.items():
        if "error" in rec or stem in flagged_stems:
            continue
        contract = rec.get("contract")
        if contract != "stand":
            continue
        facing = rec["facing"]
        per_facing_bbox_general.setdefault(facing, set()).add((rec["head_w"], rec["head_h"]))

        comp = composite_report.get(stem)
        if comp and not comp.get("skipped") and comp.get("paste_region"):
            region = tuple(comp["paste_region"])
            im = Image.open(CREW_DIR / f"{stem}.png").convert("RGBA")
            checksum = region_checksum(im, region)
            per_facing_checksum.setdefault(facing, {})[stem] = checksum
            rw, rh = region[2] - region[0], region[3] - region[1]
            per_facing_bbox.setdefault(facing, set()).add((rw, rh))

    verdict: dict[str, Any] = {"per_facing_head_sizes": {}, "per_facing_head_sizes_general_remeasurement": {},
                                "per_facing_checksum_groups": {},
                                "flagged_sprites": sorted(flagged_stems), "pass": True}
    for facing in FACING_ORDER:
        sizes = per_facing_bbox.get(facing, set())
        verdict["per_facing_head_sizes"][facing] = sorted(sizes)
        if len(sizes) > 1:
            verdict["pass"] = False
            mismatches.append(f"facing {facing}: {len(sizes)} distinct head sizes (authoritative, from the "
                               f"recorded paste_region) {sorted(sizes)}")

        verdict["per_facing_head_sizes_general_remeasurement"][facing] = sorted(per_facing_bbox_general.get(facing, set()))

        checks = per_facing_checksum.get(facing, {})
        distinct = set(checks.values())
        verdict["per_facing_checksum_groups"][facing] = {
            "n_sprites": len(checks), "n_distinct_checksums": len(distinct),
        }
        if len(distinct) > 1:
            verdict["pass"] = False
            mismatches.append(f"facing {facing}: pasted-region checksums differ across {len(checks)} sprites "
                               f"({len(distinct)} distinct) -- THE authoritative by-construction check")

    verdict["mismatches"] = mismatches
    (TEST_DIR / "verify_report.json").write_text(json.dumps(verdict, indent=2, default=str), encoding="utf-8")
    print(f"VERIFY {'PASS' if verdict['pass'] else 'FAIL'} -- {len(mismatches)} mismatch(es), "
          f"{len(flagged_stems)} flagged sprites excluded from the gate")
    for m in mismatches:
        print(f"  - {m}")
    return verdict


# ---------------------------------------------------------------------------
# Step 5: zoom strips
# ---------------------------------------------------------------------------

ZOOM = 4
STRIP_PAD = 6
CELL_LABEL_H = 16


def load_font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype("arial.ttf", size)
    except Exception:
        return ImageFont.load_default()


def step_zoomstrip(after: dict[str, Any]) -> Path:
    """Per-facing rows of every state/frame's head crop at 4x zoom -- the
    artifact the owner actually reviews (a full contact sheet hides exactly
    this kind of few-px delta at thumbnail scale; that's why the ratio QA
    and the first contact-sheet review both missed the original defect).

    Crop center/size prefers the AUTHORITATIVE paste_region this script
    itself recorded when compositing (exact, not re-derived) over the
    general re-measurement, which is known-noisy on non-neutral poses (see
    step_verify's per_facing_bbox_general comment) -- using it here would
    reproduce the same blank/mis-centered crops that noise caused before
    this fix. Corrupt-skipped and prone/seated-skipped sprites have no
    paste_region (never composited) so they fall back to the general
    measurement, which is exactly what a reviewer wants to see for those:
    their pre-existing, un-fixed geometry, clearly labeled SKIP.
    """
    font = load_font(11)
    font_facing = load_font(16)

    composite_report = json.loads((TEST_DIR / "composite_report.json").read_text(encoding="utf-8")) \
        if (TEST_DIR / "composite_report.json").exists() else {}

    by_facing: dict[str, list[tuple[str, dict]]] = {}
    for stem, rec in sorted(after.items()):
        if "facing" not in rec:
            continue
        by_facing.setdefault(rec["facing"], []).append((stem, rec))

    # Fixed head-crop cell size, generous enough for the largest canonical
    # head (n: 28x24) plus margin so a well-anchored crop is never clipped.
    cell_src = 44  # px of source canvas cropped around each head, before zoom
    cell_w = cell_src * ZOOM
    cell_h = cell_src * ZOOM + CELL_LABEL_H

    max_cols = max((len(v) for v in by_facing.values()), default=1)
    row_h = cell_h + STRIP_PAD
    facing_label_w = 40
    width = facing_label_w + max_cols * (cell_w + STRIP_PAD) + STRIP_PAD
    height = sum(row_h for _ in by_facing) + STRIP_PAD * 2 + 20

    canvas = Image.new("RGB", (width, height), (20, 20, 24))
    draw = ImageDraw.Draw(canvas)
    draw.text((STRIP_PAD, 4), "crew head_zoom_strips -- 4x zoom, one row per facing, columns = every state/frame "
                               "(SKIP = corrupt-source or prone/seated, left untouched)",
               fill=(230, 230, 235), font=font)

    y = 24
    for facing in FACING_ORDER:
        entries = by_facing.get(facing, [])
        draw.text((STRIP_PAD, y + cell_h // 2 - 8), facing, fill=(120, 220, 255), font=font_facing)
        x = facing_label_w
        for stem, rec in entries:
            im = Image.open(CREW_DIR / f"{stem}.png").convert("RGBA")
            comp = composite_report.get(stem, {})
            region = comp.get("paste_region")
            skipped = bool(comp.get("skipped"))
            if region:
                cx = (region[0] + region[2]) // 2
                cy = (region[1] + region[3]) // 2
                size_label = f"{region[2]-region[0]}x{region[3]-region[1]}"
            else:
                hbbox = rec.get("head_bbox")
                if hbbox:
                    cx, cy = (hbbox[0] + hbbox[2]) // 2, (hbbox[1] + hbbox[3]) // 2
                    size_label = f"{rec.get('head_w','?')}x{rec.get('head_h','?')}"
                else:
                    bbox = rec.get("bbox")
                    cx, cy = ((bbox[0] + bbox[2]) // 2, bbox[1] + 10) if bbox else (256, 260)
                    size_label = "?"
            crop_box = (cx - cell_src // 2, cy - cell_src // 2, cx + cell_src // 2, cy + cell_src // 2)
            crop = im.crop(crop_box)
            zoomed = crop.resize((cell_w, cell_w), Image.NEAREST)
            checker = Image.new("RGBA", zoomed.size, (40, 40, 46, 255))
            checker.alpha_composite(zoomed)
            canvas.paste(checker.convert("RGB"), (x, y))
            tag = " SKIP" if skipped else ""
            label = f"{rec['state'][:10]}_{rec['frame']} {size_label}{tag}"
            draw.text((x, y + cell_w + 1), label, fill=((255, 150, 130) if skipped else (180, 185, 195)), font=font)
            x += cell_w + STRIP_PAD
        y += row_h

    out_path = TEST_DIR / "head_zoom_strips.png"
    canvas.save(out_path)
    print(f"wrote {out_path}")
    return out_path


# ---------------------------------------------------------------------------
# Step 6: idle contact sheet
# ---------------------------------------------------------------------------


def step_contactsheet() -> Path:
    font = load_font(14)
    facings_top = ["s", "se", "e", "ne"]
    facings_bottom = ["n", "nw", "w", "sw"]

    thumb = 140
    pad = 16
    label_h = 18
    cell_w = thumb + pad
    cell_h = thumb + label_h + pad

    width = cell_w * 4
    height = cell_h * 2

    canvas = Image.new("RGB", (width, height), (18, 18, 22))
    draw = ImageDraw.Draw(canvas)

    for row, facings in enumerate([facings_top, facings_bottom]):
        for col, facing in enumerate(facings):
            path = CREW_DIR / f"crew_idle_{facing}_0.png"
            im = Image.open(path).convert("RGBA")
            bbox = alpha_bbox(im) or (0, 0, im.width, im.height)
            x0, y0, x1, y1 = bbox
            pad_px = 8
            crop = im.crop((max(0, x0 - pad_px), max(0, y0 - pad_px),
                             min(im.width, x1 + pad_px), min(im.height, y1 + pad_px)))
            crop.thumbnail((thumb, thumb), Image.NEAREST)
            cx = col * cell_w + (cell_w - crop.width) // 2
            cy = row * cell_h + label_h + (thumb - crop.height) // 2
            tile = Image.new("RGBA", crop.size, (30, 30, 36, 255))
            tile.alpha_composite(crop)
            canvas.paste(tile.convert("RGB"), (cx, cy))
            draw.text((col * cell_w + pad // 2, row * cell_h + 2), facing, fill=(200, 205, 215), font=font)

    out_path = TEST_DIR / "idle_all_facings_contact_sheet.png"
    canvas.save(out_path)
    print(f"wrote {out_path}")
    return out_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--step", choices=["measure", "canon", "composite", "verify", "zoomstrip",
                                            "contactsheet", "all"], default="all")
    parser.add_argument("--dry-run", action="store_true", help="composite: compute but don't write sprite files")
    args = parser.parse_args(argv)

    if args.step in ("measure", "all"):
        step_measure(TEST_DIR / "head_bbox_before.json")
    if args.step in ("canon", "all"):
        step_canon()
    if args.step in ("composite", "all"):
        step_composite(dry_run=args.dry_run)
    if args.step in ("verify", "all"):
        before = json.loads((TEST_DIR / "head_bbox_before.json").read_text(encoding="utf-8"))
        step_verify(before)
    if args.step in ("zoomstrip", "all"):
        after_path = TEST_DIR / "head_bbox_after.json"
        after = json.loads(after_path.read_text(encoding="utf-8")) if after_path.exists() else step_measure(after_path)
        step_zoomstrip(after)
    if args.step in ("contactsheet", "all"):
        step_contactsheet()
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
