#!/usr/bin/env python3
"""
tools/image_gen/crew_head_geom.py
====================================

Shared head-segmentation geometry for the head-swap compositing fix
(crew_head_swap.py) and its QA gate (crew_head_qa.py).

WHY: two regeneration rounds and two QA gates (crew_proportion_qa.py's
ratio-based check, and human eye review of idle_all_facings_contact_sheet.png
at contact-sheet scale) both failed to fix or catch head-size inconsistency
across facings/states -- generation SAMPLES proportions per call, it doesn't
obey a dictated head/body ratio, and a ratio can pass while the absolute
pixel size is still wildly different (a bigger head on a bigger body reads as
"fine" on a ratio check). The fix in this file is deterministic PIL
compositing (head-swap/paper-doll): every upright sprite gets its head
region erased and replaced with ONE canonical head PNG per facing, so the
head is pixel-identical by construction instead of independently generated
and merely ratio-checked.

HEAD SEGMENTATION: combines two signals (module reused from
crew_proportion_qa.py's proven neck-detection, not reimplemented):

  1. GEOMETRIC neck-pinch: crew_proportion_qa.width_profile() +
     head_bottom_row() -- the row (from the top of the sprite's own alpha
     bbox) where the silhouette is narrowest in the upper half, i.e. the
     neck. Proven against crew_idle_s_0 vs crew_idle_sw_0 (see that module's
     docstring) to land within 1px of the visible chin/collar line.

  2. PALETTE color mask: within those rows, only pixels whose (already
     palette-snapped) RGB is a hair/skin/outline tone count toward the head's
     horizontal extent -- HEAD_ALLOWED_COLORS below. This excludes suit_light
     /suit_mid/trim_offwhite (the jumpsuit's own main colors), so a raised
     suit-sleeve/arm that pokes above the neck row in an action pose (melee
     wind-up, ranged aim) doesn't widen the measured head bbox. It does NOT
     fully solve a raised SKIN-colored fist above the head (same tone family
     as the face) -- that residual ambiguity is exactly why crew_head_swap.py
     is told to skip and flag any sprite whose measured head geometry is an
     outlier for its facing rather than force a paste.

Both the geometric neck-row and the color mask are necessary: color alone
double-counts (suit_dark/suit_deepest are reused for boots and collar/
harness trim per crew_proportion_qa.py's documented finding), and geometry
alone would include a raised suit-colored limb. Combined, they reproduce
"hair+skin region at the top of the figure, down to the neck pinch" as
literally as this kit's color reuse allows.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from palette_snap import CHARACTER_PALETTE, alpha_bbox  # noqa: E402
from crew_proportion_qa import width_profile, head_bottom_row  # noqa: E402

ALPHA_T = 10

# Hair (suit_dark base + suit_deepest shadow tone) + skin (face/hands) +
# outline. Deliberately excludes suit_light/suit_mid/trim_offwhite (the
# jumpsuit's own colors) and the reserved accent colors -- see module
# docstring.
HEAD_ALLOWED_COLORS: set[tuple[int, int, int]] = {
    CHARACTER_PALETTE["outline"],
    CHARACTER_PALETTE["suit_dark"],
    CHARACTER_PALETTE["suit_deepest"],
    CHARACTER_PALETTE["skin"],
    CHARACTER_PALETTE["skin_shadow"],
}

# Hair-only (no skin) -- used to find the crown/hairline color region when
# authoring canonical heads and when deciding what counts as "hair pixel" for
# recoloring/rotation edge cases.
HAIR_COLORS: set[tuple[int, int, int]] = {
    CHARACTER_PALETTE["suit_dark"],
    CHARACTER_PALETTE["suit_deepest"],
}
SKIN_COLORS: set[tuple[int, int, int]] = {
    CHARACTER_PALETTE["skin"],
    CHARACTER_PALETTE["skin_shadow"],
}


def neck_row(im: Image.Image, bbox: tuple[int, int, int, int]) -> int:
    """Row index, RELATIVE to bbox top (y0), of the neck pinch."""
    widths = width_profile(im, bbox)
    return head_bottom_row(widths)


BODY_COLORS: set[tuple[int, int, int]] = {
    CHARACTER_PALETTE["suit_light"],
    CHARACTER_PALETTE["suit_mid"],
    CHARACTER_PALETTE["trim_offwhite"],
}


def shoulder_row(im: Image.Image, bbox: tuple[int, int, int, int], min_px: int = 4,
                  min_run: int = 3) -> int | None:
    """Absolute canvas row of the shoulder/collar line: the first row (from
    the sprite's own bbox top) that STARTS a run of at least min_run
    consecutive rows each containing at least min_px pixels of the
    jumpsuit's own main colors (suit_light/suit_mid/trim_offwhite -- never
    used for hair or skin, so unlike the neck-pinch width-profile signal this
    doesn't get confused by suit_dark's collar-trim reuse or by combat poses
    raising a suit-colored sleeve above head height).

    THE min_run REQUIREMENT MATTERS: found while validating this against
    crew_fight_melee_n_1.png -- a single stray body-colored highlight line
    directly under the chin (part of the original head/collar shading, one
    row, ~7px wide) tripped a single-row "cnt >= min_px" check 3 rows above
    the real shoulder line, anchoring the new head 3px too high and leaving
    a visible gap above the actual collar even though the reading LOOKED
    plausible (close to the facing's median, so the outlier-fallback check
    in crew_head_swap.py didn't catch it either -- it was precise, not
    accurate). Requiring the body color to persist for min_run rows before
    it counts filters that one-row artifact out; verified against the same
    file plus a full re-scan of every "stand"-contract sprite's shoulder
    row before and after adding the run requirement (see crew_head_swap.py's
    SHOULDER_ROW_TOLERANCE comment for the calibration data).

    THIS is the anchor crew_head_swap.py's compositor uses to place the
    canonical head, per crew_head_swap.py's own head-swap-vs-body-rescale
    reasoning: a defective (oversized) donor head didn't just draw a bigger
    head, it compressed the WHOLE BODY into the same fixed 70px total-height
    contract, so the body's own shoulder line sits at a genuinely different
    absolute row on a defective sprite than on a clean one (measured:
    crew_idle_w_0's shoulder line was 7px lower than crew_idle_e_0's, before
    the fix). Anchoring the new head to a single fixed row (e.g. the donor's
    own row) left a visible gap above that sprite's real collar. Anchoring
    to THIS body's own shoulder row closes that gap by construction, at the
    cost of the head's absolute canvas position (not size) varying slightly
    per sprite -- exactly the "compute per-sprite anchor from its own mask"
    the task asked for.

    Returns the LAST row of the first qualifying run (not the first) --
    the shoulder silhouette tapers in gradually from the sides, so the row
    that first crosses min_px is still thin/sparse; anchoring the head's
    chin there left a visible 1px-ish gap above a not-yet-solid shoulder
    line (found via connected-components scan: the pasted head registered
    as a separate blob from the body on most sprites, not just a cosmetic
    nit). Using the run's last row lands on a row that's already been
    solidly body-colored for min_run rows running, closing that gap.

    Returns None if no qualifying run is found (e.g. a pose where a held
    prop occludes the collar for most of the sprite's bbox -- observed on
    carry_idle/carry_walk; caller falls back to the facing's median)."""
    x0, y0, x1, y1 = bbox

    def count_at(px, y: int) -> int:
        return sum(1 for x in range(x0, x1)
                   if px[x, y][3] > ALPHA_T and (px[x, y][0], px[x, y][1], px[x, y][2]) in BODY_COLORS)

    px = im.load()
    counts = [count_at(px, y) for y in range(y0, y1)]
    for i in range(len(counts) - min_run + 1):
        if all(c >= min_px for c in counts[i:i + min_run]):
            return y0 + i + min_run - 1
    return None


def head_bbox_of(im: Image.Image, bbox: tuple[int, int, int, int] | None = None,
                  ) -> tuple[int, int, int, int] | None:
    """Absolute-canvas-coordinate head bbox (x0, y0, x1, y1), or None if the
    sprite has no opaque pixels / no head-colored pixels found above the neck
    row. x1/y1 are exclusive (PIL bbox convention)."""
    rgba = im.convert("RGBA")
    if bbox is None:
        bbox = alpha_bbox(rgba)
    if bbox is None:
        return None
    x0, y0, x1, y1 = bbox
    nrow = neck_row(rgba, bbox)  # relative to y0
    head_y1 = min(y1, y0 + nrow + 1)  # exclusive
    px = rgba.load()
    min_x, max_x = None, None
    min_y, max_y = None, None
    for y in range(y0, head_y1):
        for x in range(x0, x1):
            r, g, b, a = px[x, y]
            if a <= ALPHA_T:
                continue
            if (r, g, b) not in HEAD_ALLOWED_COLORS:
                continue
            if min_x is None or x < min_x:
                min_x = x
            if max_x is None or x > max_x:
                max_x = x
            if min_y is None or y < min_y:
                min_y = y
            if max_y is None or y > max_y:
                max_y = y
    if min_x is None:
        return None
    return (min_x, min_y, max_x + 1, max_y + 1)


def measure_head(path: Path) -> dict:
    """Full measurement record for one sprite file -- used by both the
    before/after tables and the QA gate."""
    im = Image.open(path).convert("RGBA")
    bbox = alpha_bbox(im)
    if bbox is None:
        return {"error": "no opaque pixels"}
    hbbox = head_bbox_of(im, bbox)
    if hbbox is None:
        return {"error": "no head-colored pixels found above neck row", "bbox": bbox}
    hx0, hy0, hx1, hy1 = hbbox
    return {
        "bbox": bbox,
        "head_bbox": hbbox,
        "head_w": hx1 - hx0,
        "head_h": hy1 - hy0,
        "neck_row": neck_row(im, bbox),
    }
