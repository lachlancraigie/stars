# Art Direction — Style Candidates

> Status: **LOCKED — Candidate 3, Flat Vector** (decision 2026-07-07).
> All game assets are generated in the Flat Vector style below; the other four
> candidates are kept for reference. Five candidates were each rendered from
> the identical subject (Class 1 scout medbay, one crew member) via the
> Reve API (`reve.v1` — note v2 is not enabled on our key). Test renders live in
> `docs/art-style-candidates/`. The executable form of the locked style is
> `tools/asset_gen/style.json`; rooms are generated as wall-less isometric
> floor-plates so they compose into a ship deck plan, unlike the walled
> diorama in the candidate render.

Generation cost reference: ~18 credits/image at 3:2. Budget at time of writing: ~7,390.

---

## Shared constraints (apply to every candidate)

- **Isometric 2D**, room-scale assets; FTL/Barotrauma-style readable ship cross-section
- Must survive shrinking to game scale: rooms rendered large then downscaled, crew ~32–48 px on screen
- Role colour-coding must read at distance: captain (blue), engineer (orange), medic (white/red), general (grey)
- Tone must be able to slide Trek → Alien within one visual language (lighting/fx do the sliding, not the base art)
- Mobile-horizontal browser target: high contrast, chunky silhouettes, no fine detail dependence

---

## Candidate 1 — Pixel Sim (`01_pixel_sim.jpg`)

The FTL heir. Chunky readable pixel art, desaturated steel greys, teal/orange accent
lighting, dark outlines, flat shading.

- **Pros**: Genre-native; most forgiving of AI-generation inconsistency (pixel quantising
  hides seams between separately generated assets); trivially readable at small scale;
  cheap to patch by hand.
- **Cons**: Very crowded genre look; "AI pixel art" sometimes produces inconsistent pixel
  density between assets — needs a post-pass (downscale + nearest-neighbour requantise).
- **Tone range**: mid. Does Trek fine, does horror via lighting palettes.

## Candidate 2 — Cassette Futurism (`02_cassette_futurism.jpg`)

Hand-painted 1970s retro-future: CRT green phosphor, worn beige plastic, chunky bezels,
film grain. Nostromo / Mothership RPG energy.

- **Pros**: Strongest thematic fit with the GDD's Alien-end and "worn functional, lived-in"
  brief; the test render is striking; instantly distinctive on a store page.
- **Cons**: Warm beige palette fights the role-colour-coding requirement a little; the
  painterly detail is the hardest to keep consistent across 60+ assets; horror-first look
  makes pure-Trek scenarios feel off-tone.
- **Tone range**: sits at survival/horror, can't reach bright Trek easily.

## Candidate 3 — Flat Vector (`03_flat_vector.jpg`)

Into the Breach / Rymdkapsel: crisp geometry, bold outlines, minimal texture, slate base
with saturated accent coding.

- **Pros**: Highest readability of the five — best fit for mobile-browser target and for
  UI integration (the game IS mostly UI); most consistent across AI generations (flat fills
  hide model noise); smallest file sizes.
- **Cons**: Emotionally coolest — horror beats depend entirely on lighting/palette swaps;
  can read "corporate infographic" if props aren't characterful.
- **Tone range**: Trek-native; horror achievable via palette (blackouts, red alert) but weakest here.

## Candidate 4 — Painterly Grim (`04_painterly_grim.jpg`)

Barotrauma-adjacent: semi-realistic painted, cold blue-white key light, grime, deep shadow.

- **Pros**: Most atmospheric; matches "every failure has a human cost" mood; crew read as
  people, not tokens; test render quality is excellent.
- **Cons**: Least forgiving of asset-to-asset inconsistency (realistic shading exposes
  lighting mismatches between separately generated rooms); crew at 32–48 px will lose most
  facial/gear detail; heaviest need for curation passes.
- **Tone range**: crisis/survival-native, both directions reachable.

## Candidate 5 — AI Schematic (`05_ai_schematic.jpg`)

The world as the ship computer sees it: luminous cyan/amber vector linework on near-black
navy, glowing crew figures with status rings, FUI restraint.

- **Pros**: Strongest *concept* — the player is the AI, so the diegetic frame justifies the
  whole art style AND the UI in one language; UI chrome and world art are the same system;
  events can literally glitch/degrade the render as sensors fail (mechanics as art);
  linework is very consistent across generations.
- **Cons**: Risky — an entire game of dark linework can fatigue; crew expressiveness is
  limited (mood must be carried by colour/animation of the glow, not faces); demands strict
  discipline on the accent palette or it turns to noise.
- **Tone range**: wide but abstract — horror = sensors dying and the map going dark, which
  is thematically perfect but visually austere.

---

## Recommendation

**5 (AI Schematic)** for concept strength or **2 (Cassette Futurism)** for tonal fit are the
distinctive picks; **3 (Flat Vector)** is the pragmatic pick that de-risks the mobile target
and asset-consistency problem. A hybrid worth considering: **world in style 2 or 4, with
style 5 as the AI-overlay layer** (directive targeting, hazard flags, sensor views) — the
overlay is UI anyway.

## Pipeline notes (post lock-in)

1. Write `tools/asset_gen/style.json` from the winning candidate's prompt language
   (see `style.json.example`).
2. Generate 2–3 **style anchor** images first (one room, one crew figure, one prop),
   approve them, then pass them as `anchor_images` — all subsequent assets are generated
   with `reve.v1.image.remix()` against the anchors for consistency.
3. Generate Phase 6 set → staging → QA report → human review → `promote.py` into
   `assets/sprites/`.
4. Crew directional/pose variants: generate the N-facing idle first, then use
   `edit()`/`remix()` from that sprite for the other directions and states.
