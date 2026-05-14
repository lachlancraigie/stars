# Sprite Generation Pipeline — SwarmUI / ComfyUI Notes

> Written for the next Claude Code session to set up and monitor sprite generation.
> Context: isometric 2D sci-fi ship sim. Player is the ship AI. Tone ranges from
> competent Trek to claustrophobic Alien. See GDD.md for full visual context.

---

## What We Need (Priority Order)

### Phase 6 (needed to unblock visual ship scene)
1. **Room tiles** — isometric top-down view, each ~128×64px (standard iso tile)
   - Bridge, Engineering/Reactor, Life Support, Medbay, Crew Quarters, Cargo Hold, Corridor
   - Style: worn functional sci-fi, slightly cold lighting, lived-in
2. **Crew sprites** — top-down isometric, 32×48px or similar, 4-directional
   - Base: idle, walk cycle (4 dirs), panic (arms up/running), collapsed
   - Colour-coded by role: captain (blue trim), engineer (orange), medic (white), general (grey)
3. **Door sprites** — open/closed states, fits corridor tile seam

### Phase 7+ (can use Kenney placeholders until then)
4. Ship hull/wall tiles, maintenance tube overlay
5. UI chrome — panel frames, data readout borders (monochrome green-on-dark or amber)
6. Effect sprites — alert flash, smoke, sparks, airlock seal
7. Crew portrait thumbnails for the directive UI (64×64px headshot style)

---

## Recommended SwarmUI Setup

### Models

**Primary — isometric environment tiles:**
- `juggernautXL` or `dreamshaperXL` as base (good structural coherence for tiles)
- Alternative: `RealVisXL` for a more grounded/less painterly look

**Primary — character sprites:**
- `animagine-xl` — strong at stylised character sprites, consistent across poses
- Fallback: `duchaitenAnimagineXL`

**For top-down / isometric specifically:**
- Look for LoRAs tagged `isometric`, `top-down game asset`, `RPG sprite sheet`
- Good sources: CivitAI search `isometric game asset lora`

### Recommended LoRAs to Download

| LoRA | Use | Trigger words |
|---|---|---|
| `isometric_game_assets_xl` | room tiles, structural | `isometric view, game asset, top down` |
| `sci_fi_interior_xl` | room atmosphere | `sci-fi interior, space station` |
| `pixel_sprite_xl` (optional) | if going pixel style | `pixel art, sprite sheet` |
| `worn_metal_texture` | material quality | `worn metal, industrial` |

If you can't find XL versions, use SD1.5 equivalents and upscale.

### Negative Prompt (use for all generations)
```
blurry, soft focus, realistic photo, 3d render, watermark, signature, text,
low quality, bad anatomy, extra limbs, merged tiles, perspective distortion,
gradient background, vignette, bokeh
```

---

## ComfyUI Workflow Notes

### Tile generation workflow
1. **Base pass**: Generate tile on transparent/solid-colour background
2. **rembg pass**: Remove background (the player has rembg — use it via ComfyUI rembg node)
3. **Upscale if needed**: 4x ESRGAN for pixel-crisp edges
4. **Export**: PNG with transparency to `assets/sprites/rooms/`

### Character sprite workflow
1. Generate each direction (N/S/E/W facing) as separate generations with consistent seed+LoRA
2. Use **img2img** for directional variants from the initial N-facing sprite (strength 0.4–0.55)
   - This maintains costume/colour consistency across directions
3. rembg pass
4. Crop to consistent bounding box per pose
5. Optionally: arrange into spritesheet (Godot can use individual frames or spritesheets)

### Consistent character appearance across generations
The biggest challenge. Options:
- **IP-Adapter**: Feed the first approved character image as style reference for subsequent poses
- **ControlNet OpenPose**: Provide pose skeleton for each direction — most reliable
- **Fixed seed + low variation**: Works for same-direction variations, breaks across poses

Recommended: IP-Adapter + ControlNet OpenPose together for character sprites.

### Prompt templates

**Room tile (isometric):**
```
isometric game asset, [ROOM_NAME] interior, sci-fi space station,
worn functional design, cold blue-white lighting, top-down 45-degree angle,
clean edges, game ready, transparent background, 2D flat shading,
[LoRA triggers]
```

**Crew sprite (top-down iso):**
```
isometric game sprite, [ROLE] crew member, sci-fi jumpsuit [COLOUR] trim,
space station worker, top-down view, full body, clean silhouette,
simple flat shading, game asset, transparent background,
[LoRA triggers]
```

---

## File Naming Conventions

Match the room_id and role names already in the codebase:

```
assets/sprites/rooms/
  room_bridge.png
  room_engineering.png
  room_life_support.png
  room_medbay.png
  room_quarters.png
  room_cargo.png
  room_corridor.png
  door_closed.png
  door_open.png

assets/sprites/crew/
  crew_captain_idle_n.png      ← N/S/E/W for each state
  crew_captain_idle_s.png
  crew_captain_walk_n.png
  crew_captain_panic.png
  crew_engineer_idle_n.png
  crew_medic_idle_n.png
  crew_general_idle_n.png
```

---

## Monitoring Generation (for Claude Code)

When running as a local instance to monitor generation:

1. Watch the SwarmUI output folder for new PNGs:
   ```bash
   # Example monitor command
   inotifywait -m --format '%f' assets/sprites/ -e close_write
   ```
2. For each new file:
   - Check dimensions match spec (128×64 tiles, ~32×48 crew)
   - Check transparency is clean (no grey fringe from rembg)
   - Log to a review queue for human approval before integrating into scenes

3. Auto-reject criteria (flag for regeneration, don't delete):
   - Solid background not removed
   - Tile width/height ratio wrong for isometric (should be ~2:1)
   - Obvious anatomy issues in crew sprites

4. Once approved: the sprites drop straight into the paths above — Godot's
   FileSystem dock will auto-import them on next editor focus.

---

## Immediate Next Step

Before generating custom sprites, **download Kenney Space Kit** (CC0, free):
https://kenney.nl/assets/space-kit

Drop the isometric tiles into `assets/sprites/rooms/` as named placeholders.
This unblocks Phase 6 (visual ship scene) immediately while custom sprites generate.

Kenney tile names to use as stand-ins:
- Any isometric floor tile → all room types (differentiate by tint in Godot)
- Wall/barrier tiles → ship hull
- The kit includes a wide range of sci-fi props usable as room dressing

---

## Open Questions for Art Direction

- Pixel art or hand-drawn/painted style? (affects LoRA choice significantly)
- Crew — silhouetted shapes or detailed faces/gear visible from top-down?
- Colour palette — desaturated utilitarian (Alien) or slightly warmer (Trek)?
- Do rooms have visible walls/ceilings in the iso view, or just floor + prop layer?
