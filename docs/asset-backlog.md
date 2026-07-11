# Asset Backlog — Mission System Sprint

> What the mission/scenario overhaul needs visually and aurally. Nothing here blocks
> the engine work — everything ships first with procedural placeholders (tinted
> circles, silhouettes, existing tiles). Pipeline: `tools/asset_gen/` +
> `tools/image_gen/` (gen2 cel-shaded style, `docs/style-bible-v2.md`).
> Ordered by gameplay impact within each section.

## Planets (ApproachVisual backgrounds)

Large (≥1024px) cel-shaded orbs with atmosphere rim, viewed from high orbit; each
needs a subtle 2-frame or shader-driven cloud/rotation variant. Descriptor palette
drives placeholder tint until these land.

| id | descriptor | used by |
|---|---|---|
| `planet_jungle` | dense green canopy, river glint | survey/science missions |
| `planet_ice` | white-blue, cracked sheets | mining/distress |
| `planet_desert` | rust dunes, dry seas | salvage/mining |
| `planet_ocean` | deep blue, storm swirls | survey/passenger |
| `planet_barren` | grey regolith, craters | mining/patrol |
| `planet_volcanic` | black crust, ember veins | high-risk survey |
| `planet_gas` | banded giant (no landing — moons) | rendezvous backdrop |
| `planet_ruined` | ash shroud, dead city glints | mystery/evac arcs |

## Ships & stations (docking/rendezvous contacts)

Exterior silhouettes at 2-3 approach scales (distant sprite → alongside sprite).

- `ship_hauler` — rust-bucket freighter (most common contact)
- `ship_corporate` — clean company vessel
- `ship_derelict` — torn, unlit hulk (salvage/boarding)
- `ship_military` — patrol corvette
- `ship_alien` — clearly non-human geometry (late-campaign mystery)
- `station_hub` — waystation ring (homecoming/repair yard)
- `station_yard` — repair gantry frame the ship noses into

## Shuttle

- `shuttle_bayed` — parked-in-bay sprite (isometric, gen2 kit style)
- `shuttle_launch` / `shuttle_return` — 3-4 frame lift/settle animation
- exterior mini-sprite for departure flight line across starfield

## New rooms / tiles (IsoKit gen2 additions)

- `tile_shuttlebay` + bay props: fuel hose, tool rack, warning stripes, bay door
- airlock detail pass: inner/outer door prop, pressure light strip
- `tile_brig` (social scenarios want a lockable holding room — stretch)
- docking-collar wall piece (visible where a docked ship connects)

## Effects

- slime/growth overlay set (3 stages) — invasive-organism scenarios paint rooms
- fire/smoke room overlay (2-3 frames each)
- sparks/electrical arc burst (door/console damage)
- hull-breach shimmer + venting particles
- sensor-contact marker set (unknown/hostile/lost — HUD-side, ties to IntruderSystem)
- infection tell: subtle per-crew shader tint ramp (revealed state only)

## Monsters / intruders (sensor-first, sprites later)

IntruderSystem ships with HUD sensor blips only. When creature sprites land they
replace blips in AI-visible rooms:

- `intruder_stalker` — lean quadruped shadow (idle/move/lunge, 4-facing)
- `intruder_nest` — pulsing organic mass (static, 3-frame throb)
- `intruder_mimic` — cargo-crate double (dormant/revealed)

## UI

- Mission panel iconography: objective states (active/done/failed), mission-type
  glyphs (15 types), faction chips for givers
- Away-op status widget: shuttle icon + radio-static bark frame
- Docking clamp indicator for the info card

## Audio (see spec §14 — dialogue corpus is its own workstream)

- SFX: shuttle launch/land, docking clamp thunk, airlock cycle, sensor ping,
  intruder kill confirm, mission complete sting, radio static in/out
- Ambience: hangar-bay loop, docked-umbilical groan, planet-orbit low wash
