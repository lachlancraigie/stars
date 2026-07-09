# Style Bible v2 — "gen2" cel-shaded isometric kit

> Status: **PILOT** (2026-07-10). Produced by `tools/image_gen/generate.py` +
> `tools/image_gen/pilot_batch.py` against OpenRouter's `openai/gpt-image-1-mini`.
> Staging output: `assets/sprites/gen2/` (NOT wired into the game — `scripts/ship/iso_kit.gd`
> still points at `assets/sprites/legacy/`, the Kenney kit). This document is the locked
> style block every gen2 prompt embeds verbatim. Do not hand-edit staged PNGs to "fix"
> style drift — fix the prompt/palette here and regenerate, or the set drifts asset by asset
> exactly the way the retired Reve Flat Vector set did (see `docs/art-direction.md`).

## Why this exists

The first AI-generated set (Reve, "Flat Vector") was retired because separately generated
rooms and crew didn't share a projection or a lighting model — consistency, not per-image
beauty, was the failure. This bible exists to make consistency mechanically checkable:
every value below is a fixed constant (a hex code, a pixel offset, a degree), not a vibe.
If a generated asset can't be checked against a number in this file, the check isn't real.

---

## The grid contract (non-negotiable, from `scripts/ship/iso_kit.gd`)

- **Canvas**: 512×512 px, transparent (RGBA) background.
- **Floor diamond**: 130×65 px, centered at canvas position **(256, 311)**.
- **2:1 dimetric projection**: the diamond is exactly twice as wide as it is tall, i.e. a
  camera elevation of **26.57°** (`atan(0.5)`) above the horizontal — the classic
  "2:1 isometric" used by SimCity/RollerCoaster Tycoon/Age of Empires, NOT true 3D
  isometric (35.264°/`atan(1/√2)`). Every asset must share this exact angle; mixing 2:1
  dimetric with true isometric is the single fastest way to reproduce the old set's
  "rooms don't share a projection" failure.
- Every sprite is a full 512×512 canvas regardless of subject size, anchored identically,
  so `IsoKit.make_sprite()` can place any kit piece with the same offset math.

Because image models don't hit literal pixels, framing instructions below are given as
**fractions of the 512×512 frame** (equivalently the raw 1024×1024 model output, which is
downscaled 2:1 with no recrop — see the pipeline note at the bottom):

- Diamond center: 50% across, **61% down** (311/512) — noticeably below vertical center.
- Diamond width: spans the middle **25%** of frame width (130/512).
- Diamond height band: roughly **55%–67%** down the frame (130/512 → 65px tall, ±32.5px
  around the 61% line).

---

## Locked palette (10 hex values — do not introduce others)

Two- to three-tone cel shading only: a **base** tone and a **shadow** tone per surface, with
a **light** tone reserved for small highlighted edges/panels. No gradients, ever — a shaded
surface is two or three flat fills meeting at a hard edge, not a blend.

| Role | Name | Hex | Use |
|---|---|---|---|
| Outline | Outline | `#14171C` | The ONLY color used for silhouette/detail outlines. Constant weight (see below). Never used as a fill. |
| Structure | Steel Light | `#C7CED6` | Hull/floor/prop highlight facets (top-lit faces) |
| Structure | Steel Mid | `#8B95A1` | Hull/floor/prop base tone (side faces) |
| Structure | Steel Dark | `#4E5661` | Hull/floor/prop shadow facets (unlit faces) |
| Structure | Steel Deepest | `#2A2F36` | Recesses, panel gaps, AO pockets — used sparingly, never as a large fill |
| Neutral | Off-White | `#EDEFF2` | Suit base, light housings, screen bezels, paint markings |
| Accent 1 (warm) | Amber Light | `#FFC857` | Power/engineering/caution: conduits, warning strips, reactor glow |
| Accent 1 (warm) | Amber Dark | `#C9822A` | Shadow tone for the amber accent |
| Accent 2 (cool) | Cyan Light | `#6FE3E0` | Tech/medical/AI-core: screens, status lights, medical crosses |
| Accent 2 (cool) | Cyan Dark | `#2C9A98` | Shadow tone for the cyan accent |

Crew note: matching the existing kit's architecture (`iso_kit.gd` / CLAUDE.md — "role
identity is done with modulate tints"), crew sprites are generated in the **neutral**
Off-White/Steel family, not pre-tinted per role. Role color (captain blue, engineer orange,
medic red, general grey) is applied at runtime via `Sprite2D.modulate`, same as the legacy
kit. Do not generate role-colored suits in gen2 — it would fight the runtime tint and be a
second source of inconsistency.

---

## Outline

Single weight, roughly **3% of subject silhouette width** (thick enough to read at 128px on
a phone, thin enough not to eat detail) — described to the model as "a thin, uniform-weight
dark outline" rather than a pixel count, since the model doesn't render at literal game
pixels. Applied to: silhouette edges, and internal facet boundaries where two flat tones
meet. Never applied as a colored (non-`#14171C`) line, never varies in thickness across a
single sprite, never a soft/blurred stroke.

## Lighting

Flat frontal key light from **upper-left**, fixed for every asset, no exceptions. This is
what a lit face vs. shadowed face means in the palette table above (Steel Light = faces
angled toward upper-left, Steel Dark = faces angled away). No rim light, no bounce light, no
ambient occlusion gradient — AO is represented by the flat Steel Deepest tone in creases
only. No cast shadows on the ground plane beyond a small flat-tone contact shadow directly
under the object (same rule: flat fill, not a soft blob).

## Texture

Zero texture noise — no photographic grain, no painterly brushwork, no scan-line/dither
pattern, no gradient "sheen." Surfaces are flat color fills bounded by outlines. Detail comes
from shape and outline (panel seams, rivets-as-small-shapes, conduit lines), not from surface
texture.

## Readability

Silhouette-first: the subject must be identifiable from its outline alone at 128×128 (the
kit is often viewed shrunk on a phone screen — see `docs/art-direction.md`'s mobile-horizontal
constraint). Chunky simple shapes over fussy detail. If a prop's identity depends on
something smaller than ~8% of the frame, simplify the shape instead of adding detail.

---

## Master prompt template

Every gen2 prompt is assembled from these parts, in order (implemented in
`tools/image_gen/pilot_batch.py::compose_prompt()` — keep that function's literal strings in
sync with this document if either changes):

```
[STYLE LOCK — verbatim, every prompt]
Clean cel-shaded isometric game sprite, 2:1 dimetric camera angle (26.57 degrees above
horizontal, matching SimCity/RollerCoaster Tycoon isometric — the diamond floor footprint
is exactly twice as wide as it is tall), flat frontal key light from the upper-left only.
Two to three flat color tones per surface with hard edges between them, absolutely no
gradients, no soft shading, no ambient occlusion blur, no texture noise, no painterly
brushwork, no photographic detail. Thin uniform-weight dark outline (#14171C) around the
silhouette and between color facets, constant thickness. Restrict all colors strictly to
this palette: outline #14171C; structure grays #C7CED6 / #8B95A1 / #4E5661 / #2A2F36;
off-white #EDEFF2; warm accent #FFC857 / #C9822A; cool accent #6FE3E0 / #2C9A98. Do not
introduce any other hues. Chunky simple readable silhouette, no fine detail smaller than
necessary to read at small size.

[SUBJECT — per asset]
{SUBJECT}

[PIXEL CONTRACT — category framing rule, see table below]
{CATEGORY_FRAMING}

[NEGATIVE / AVOID — verbatim, every prompt]
Avoid: gradients, soft shadows, blur, glow/bloom haze, film grain, painterly texture,
realistic/photographic rendering, top-down 90-degree flat view, any camera angle other than
the specified 2:1 dimetric, fisheye or perspective distortion, multiple copies of the
subject, collage or grid layout, background scenery beyond the subject and its immediate
contact shadow, text, watermark, logo, signature, frame/border.

Transparent background. Single subject only.
```

## Per-category framing rules

| Category | `{CATEGORY_FRAMING}` clause |
|---|---|
| Floor tile | "Isometric floor tile filling the 2:1 diamond footprint exactly: the tile's diamond silhouette is centered horizontally in the frame and centered vertically at 61% down from the top (not the frame's vertical center), spanning the middle 25% of the frame width. Surface detail (panels, markings, equipment) stays within the diamond, flush with the floor, no vertical walls, no ceiling, designed to tile edge-to-edge with identical floor tiles." |
| Wall segment | "A single upright wall segment rising from one edge of the isometric floor diamond, standing vertically like a thin fence panel, uniform height, positioned so its base line sits along the diamond edge at 61% down the frame — do not fill the whole diamond, the wall is a thin vertical slice at the tile boundary, not a floor." |
| Door / gate | "An upright sliding door/hatch fitted into a floor-diamond seam, standing vertically like the wall segments, base aligned to 61% down the frame, centered horizontally, no surrounding wall or room box, isolated door only." |
| Prop | "A single freestanding object standing on the floor diamond's center point: its base/contact shadow sits at 61% down the frame, centered horizontally, the object extending upward from that point within the frame — no floor tile needs to be drawn under it, only the object and its small flat contact shadow." |
| Crew | "A full-body character standing upright with feet planted at the floor diamond's center point: feet at 61% down the frame, centered horizontally, body extending upward, facing {DIRECTION}, chunky simplified proportions (large head-to-body ratio is fine, no fine facial detail), standing idle pose, arms at sides." |

---

## Negative / avoid list (consolidated, matches the template above)

Gradients · soft shadows/blur · glow or bloom haze · film grain · painterly brushwork ·
photographic realism · flat top-down 90° view · any camera angle other than 2:1 dimetric ·
fisheye/perspective distortion · multiple subjects/collage/grid · extra background scenery ·
text/watermark/logo/signature · frame or border art · colors outside the 10-hex palette ·
role-tinted crew suits (tinting happens at runtime, not bake time).

---

## Pipeline notes

1. **Model**: `openai/gpt-image-1-mini` via OpenRouter's dedicated Images API
   (`POST /api/v1/images`), `background=transparent`, `quality=high`. See
   `tools/image_gen/generate.py`'s module docstring for the full model-selection recon
   (why not `gpt-image-2` — no native transparency; cost comparison against `gpt-image-1`).
2. **Fixed output size**: the gpt-image family ignores `resolution`/`aspect_ratio` (not a
   supported parameter) and always returns 1024×1024. The pipeline downscales 2:1
   (LANCZOS, exact half factor, no cropping) straight onto the 512×512 canvas — this is why
   every fractional framing instruction above is phrased as a frame percentage rather than
   an absolute pixel count.
3. **QA heuristic**: after downscale, compute the centroid of all pixels with alpha > 10.
   Flag (don't hard-fail) any asset whose centroid falls outside roughly (256±90, 280±110).
   This is a coarse sanity check for "wildly off-center," not a precise per-category
   assertion — floor tiles legitimately centroid nearer y≈311, tall props/crew nearer
   y≈200–260 depending on height. See `tools/image_gen/pilot_batch.py::run_qa()`.
4. **Transparency**: confirmed native (`background=transparent` produces a real alpha
   channel — verified via `generate.py --selftest`, see its docstring). No chroma-key pass
   needed for this model. `generate.py::chroma_key_to_alpha()` remains available for any
   future model/category that lacks native transparency.
5. **Iteration expectation**: this is a *style pilot*, not a production run. Expect at least
   one iteration of this document (likely the outline weight and "no gradients" instruction,
   which general-purpose image models resist) after reviewing the contact sheet at
   `assets/sprites/gen2/contact_sheet.png`.
