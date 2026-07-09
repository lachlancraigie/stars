# CLAUDE.md — Ship AI Game

> Claude Code context file. Keep this updated as the project evolves. This is the first thing to read at the start of every session.

---

## Project Overview

A spaceship AI simulator. The player is the ship's computer. See `GDD.md` for full design documentation.

**Engine**: Godot 4 / GDScript  
**View**: Isometric 2D  
**Repo**: TBD  

---

## Current Sprint

> Update this section at the start/end of every session.

**Goal**: Polish the vertical slice (camera, doors as real obstacles, more scenario content).

**Art direction**: RE-LOCKED 2026-07-09 — **Kenney Space Kit isometric** (`assets/sprites/legacy/`).
The Reve Flat Vector set was retired for style/perspective inconsistency; Reve pipeline
(`tools/asset_gen/`, token via `REVE_API_TOKEN` env) kept for portraits/UI art only.
Deck composition lives in `scripts/ship/iso_kit.gd` + `scripts/ship/deck_plan.gd`.

**Next tasks**:
1. Camera2D pan/zoom (deck currently statically fitted to the 1920×1080 canvas — now generated ships can be considerably larger, so panning matters more)
2. Crew walk-cycle feel (kit has single frames per facing; current bob is serviceable)
3. More in-scenario choices for the AI (info framing, door locks as containment tools)
4. Campaign handoff after scenario end (currently ends on the banner)
5. Mothership mechanics on top of the new `ai_core` room (power grid, door-lock gameplay, AI-core damage/repair — see 2026-07-09 session note for the data contract)

**Blocked on**: nothing hard. SaveManager still stubbed by design (checkpoints resolved, unimplemented).

---

## What's Done

- [x] Godot project created
- [x] Folder structure in place
- [x] EventBus autoload
- [x] GameState autoload
- [x] SaveManager autoload (stub)
- [x] Room scene (base)
- [x] Ship layout (Class 1) — config resource + graph + builder
- [x] Resource tick loop
- [x] HUD stub (resource bars)
- [x] CrewMember base scene + stats
- [x] Needs model
- [x] Crew state machine
- [x] AI directive system
- [x] Trust model
- [x] First scripted event
- [x] Art direction locked (Flat Vector) + Reve asset pipeline (`tools/asset_gen/`) — later retired
- [x] Art direction re-locked: Kenney Space Kit isometric (`assets/sprites/legacy/`), composed deck
- [x] Visual ship scene: iso deck grid, rooms composed from kit tiles + props, walkways, door gates
- [x] Crew: kit astronauts (8 facings, role tints), multi-hop route walking via ship graph + walkway waypoints
- [x] Autonomous crew behaviour (CrewBehavior): sleep/eat→quarters, work→duty station, panic→flee, idle→wander
- [x] Click-on-crew contextual directive menu → issues real AIDirectives; crew comply/refuse
- [x] Vertical slice end-to-end: QuarantineMonitor makes the win achievable in-scene (isolate Vasquez → Chen contains); HUD objective/event feed/win-lose banner; verified via SHIPAI_AUTODEMO run
- [x] Procedural ship generation: ShipLayoutGen ("freighter" ruleset) replaces the hand-authored Class-1 layout; DeckPlan refactored into a generator-filled data container; seed stored on GameState (SHIPAI_SEED env override for reproducible runs)
- [x] Visual upgrades: procedural parallax starfield (3 layers), generated hull silhouette (nose taper + aft engine block), per-room-type floor tiles/tints, semi-transparent boundary walls, door gates that recolour with lock state
- [x] Room-type contract: scenario/behaviour code (QuarantineMonitor, CrewBehavior duty stations, crew start rooms) now looks up rooms by TYPE via `GameState.get_room_of_type()` instead of hardcoded ids, so it works on any generated layout

---

## Architecture Rules

These are hard constraints. Do not deviate without updating this file.

1. **No direct crew control.** The AI (player) issues directives. Crew evaluate and respond autonomously. Nothing in `scripts/ai/` should directly set crew position, state, or action.

2. **EventBus for cross-system communication.** Systems do not call each other directly. Use `EventBus.emit()` and `EventBus.connect()`. Direct calls only within the same system/module.

3. **GameState is the single source of truth.** Don't store authoritative state in individual nodes. Read from GameState, mutate via GameState methods, emit events.

4. **Resource files for data.** Crew, ship configs, events, and scenarios are `.tres` Resource files under `/resources/`. Procedural generation mutates copies of these at runtime, never the base resources.

5. **Scenes own their visuals and input, scripts own logic.** Keep business logic out of `_ready()` and `_process()` where possible — delegate to system scripts.

---

## Conventions

- **GDScript style**: snake_case everywhere. Class names PascalCase. Constants SCREAMING_SNAKE.
- **Signal naming**: past tense verb + subject — `crew_moved`, `system_damaged`, `directive_issued`
- **File naming**: snake_case matching class name — `crew_member.gd`, `event_bus.gd`
- **Scene naming**: PascalCase — `CrewMember.tscn`, `RoomBridge.tscn`
- **No magic numbers**: define constants at the top of the file or in a shared `Constants.gd`
- **Comments**: explain *why*, not *what*. The code says what. Comments say why.
- **TODO format**: `# TODO(system): description` — e.g. `# TODO(crew): add fear cascade when adjacent crew panics`

---

## Project Structure

```
/
├── CLAUDE.md               ← you are here
├── GDD.md                  ← full design doc
├── project.godot
├── assets/
│   ├── sprites/            ← organised by category
│   ├── audio/
│   └── fonts/
├── scenes/
│   ├── ships/
│   ├── rooms/
│   ├── crew/
│   └── ui/
├── scripts/
│   ├── core/               ← EventBus, GameState, SaveManager, TimeManager (autoloads)
│   ├── ship/               ← ShipSystem, DamageModel, LifeSupport, PowerGrid
│   ├── crew/               ← CrewMember, NeedsModel, PersonalityCore, RelationshipGraph
│   ├── ai/                 ← AIDirective, TrustModel, ObedienceEngine, AccessLevel
│   ├── procedural/         ← ScenarioGenerator, EventPool, ShipLayoutGen, CrewGen
│   └── scenarios/          ← scripted scenario definitions
└── resources/
    ├── crew_templates/
    ├── ship_configs/
    └── event_definitions/
```

---

## Key Systems Summary

| System | Location | Status | Notes |
|---|---|---|---|
| EventBus | `scripts/core/event_bus.gd` | stub done | Autoload. All cross-system signals defined. |
| GameState | `scripts/core/game_state.gd` | stub done | Autoload. Resource/trust/access mutators wired to EventBus. |
| SaveManager | `scripts/core/save_manager.gd` | stub done | Autoload. Checkpoint structure stubbed; unimplemented. |
| TimeManager | `scripts/core/time_manager.gd` | stub done | Autoload. Real-time with pause, 1x/2x speed, 0.25s tick interval. |
| RoomDefinition | `scripts/ship/room_definition.gd` | done | Resource. Room data schema for ShipConfig. |
| ConnectionDefinition | `scripts/ship/connection_definition.gd` | done | Resource. Connection data schema for ShipConfig. |
| ShipConfig | `scripts/ship/ship_config.gd` | done | Resource. Full ship class definition. Class 1 .tres in resources/. |
| ShipGraph | `scripts/ship/ship_graph.gd` | done | RefCounted. Dijkstra pathfinding over room graph. Respects locked doors + maintenance access. |
| Door | `scripts/ship/door.gd` | done | Node2D. Connects two rooms; AI unlock via access level. |
| ShipLayoutBuilder | `scripts/ship/ship_layout_builder.gd` | done | Static utility. Builds live ship from ShipConfig into scene tree. |
| ShipSystem | `scripts/ship/ship_system.gd` | not started | Base class for all ship systems. |
| DamageModel | `scripts/ship/damage_model.gd` | not started | Localised + cascade damage. |
| ResourceTick | `scripts/core/resource_tick.gd` | done | Autoload. Tick-based drain; crew-count scaling; system efficiency + power draw hooks stubbed. |
| CrewMember | `scripts/crew/crew_member.gd` | done | Resource. Full stat + needs + personality schema. |
| CrewMemberNode | `scripts/crew/crew_member_node.gd` | done | Node2D. Kit astronaut w/ 8 facings + role tint + status dot; multi-hop route walking (graph path + walkway waypoints); y-based z-sort; `static nodes` registry. |
| CrewBehavior | `scripts/crew/crew_behavior.gd` | done | Node (added by Main). Autonomous crew movement per state; honours accepted directives via `hold_room_until`; panic overrides. |
| IsoKit | `scripts/ship/iso_kit.gd` | done | Static utility. Legacy-kit metrics (130×65 diamond @ canvas (256,311)), cell→deck projection, anchored sprite factory, z-order. |
| ShipLayoutGen | `scripts/procedural/ship_layout_gen.gd` | done | Static generator. Seeded procedural ship layout ("freighter" ruleset implemented). Builds a ShipConfig AND calls `DeckPlan.load_plan()` with the matching visual dataset (rects, props, walls, hull polygon, etc). See 2026-07-09 session note for the full ruleset. |
| DeckPlan | `scripts/ship/deck_plan.gd` | done | Static data CONTAINER (refactored from hardcoded consts). Filled at scenario start by `ShipLayoutGen.generate()` via `load_plan()`: room rects, per-type floor tints/tiles, props, walkways, tubes, door cells, hop waypoints, wall segments, hull polygon. Same accessor API as before (`room_rect`, `room_center`, `random_point`, `hop_waypoints`, `deck_bounds`, `has_room`) so downstream consumers (RoomBase, ShipLayoutBuilder, CrewMemberNode) are unchanged. |
| RoomBase (visual) | `scripts/ship/room_base.gd` + `scenes/rooms/RoomBase.tscn` | done | Composes floor tiles (per-type tile via `DeckPlan.floor_tile_for()`) + props from DeckPlan/IsoKit; positioned at DeckPlan.room_center. |
| Starfield | `scripts/ship/starfield.gd` | done | Node2D (instanced in Main, not a child of ShipDeck). Procedural 3-layer parallax starfield; each layer draws its stars once via `_draw()` and only ever translates (sine drift) — no per-frame redraw. z_index -1000. |
| Ship hull silhouette | `scripts/ship/ship_layout_builder.gd` (`_build_hull`) | done | Polygon2D + Line2D built from `DeckPlan.HULL_POLYGON` (nose taper + per-row flanks + aft engine block, generated in ShipLayoutGen). z_index -10/-9, behind floors, in front of the starfield. |
| Semi-transparent walls + door gates | `scripts/procedural/ship_layout_gen.gd` (wall segments) + `scripts/ship/door.gd` | done | Generator emits per-room boundary wall tiles (skipping connected edges); front-facing (SE/SW) walls render more transparent than back-facing (NE/NW) since painter's order draws them over the interior. Door gate sprite recolours red/green via `Door.refresh_gate_visual()` on lock/unlock. |
| QuarantineMonitor | `scripts/scenarios/quarantine_monitor.gd` | done | Node (added by Main). Timed medbay-occupancy logic that sets `vasquez_isolated`/`pathogen_contained`; drives `objective_changed`. |
| DirectiveActionHandler | `scripts/ai/directive_action_handler.gd` | done | Node. Executes movement for directives the crew *accepted* (`move_to_room`). Respects Rule 1. |
| DirectiveMenu | `scripts/ui/directive_menu.gd` + `scenes/ui/DirectiveMenu.tscn` | done | CanvasLayer. Click-on-crew select + contextual destination menu → `AISystem.issue_directive`. |
| NeedsModel | `scripts/crew/needs_model.gd` | done | Static utility. Per-tick hunger/fatigue/fear/loneliness/boredom/morale. |
| CrewStateMachine | `scripts/crew/crew_state_machine.gd` | done | Static utility. Priority-based state eval with hysteresis. |
| CrewSystem | `scripts/crew/crew_system.gd` | done | Autoload. Ticks all crew; propagates resource crisis into fear spikes. |
| PersonalityCore | `scripts/crew/personality_core.gd` | not started | Traits, fears, values, goals. |
| RelationshipGraph | `scripts/crew/relationship_graph.gd` | not started | Crew social network. |
| AIDirective | `scripts/ai/ai_directive.gd` | done | Resource. Type/target/content/confidence/priority/tags + hidden intent fields. |
| AccessLevel | `scripts/ai/access_level.gd` | done | Constants + static checks. 8 domains, 4 levels; type→min-access mapping. |
| TrustModel | `scripts/ai/trust_model.gd` | done | Static utility. Named delta constants; modify() and modify_all() helpers. |
| ObedienceEngine | `scripts/ai/obedience_engine.gd` | done | RefCounted. Suspicion tracking, deviation log (cap 20), cover-up attempt, auto-restrict at 0.85. |
| DirectiveEvaluator | `scripts/ai/directive_evaluator.gd` | done | Static utility. trust × type_modifier ± morale/willpower ± conflict penalty → probabilistic comply. |
| AISystem | `scripts/ai/ai_system.gd` | done | Autoload. Directive lifecycle, ObedienceEngine orchestration, trust propagation on outcomes. |
| ScenarioEvent | `scripts/scenarios/scenario_event.gd` | done | Resource. Event with conditions, outcomes, tone range, weight, cooldown. |
| EventPool | `scripts/scenarios/event_pool.gd` | done | RefCounted. Weighted draw filtered by tone + conditions + cooldown. |
| ScenarioDirector | `scripts/scenarios/scenario_director.gd` | done | Autoload. Hidden meta-layer; tension/tone drift; probabilistic event pacing. |
| ScenarioRunner | `scripts/scenarios/scenario_runner.gd` | done | Autoload. Win/lose detection, resource delta on end, scenario handoff stub. |
| QuarantineScenario | `scripts/scenarios/quarantine_scenario.gd` | done | Static builder. 6 events, 3 acts, all three lose conditions, resource deltas. |
| ScenarioGenerator | `scripts/procedural/scenario_generator.gd` | not started | Procedural scenario seeding. |

---

## Open Design Questions

**Do not implement the listed systems until these are resolved.**

| Question | Blocks | Status |
|---|---|---|
| What does the player UI look like? (text console / visual / hybrid) | AI directive input, UI scenes | **resolved**: FTL/Barotrauma visual style, click-on-crew contextual menus, mobile horizontal browser compatible (1920×1080 canvas, GL Compatibility) |
| How are directives issued? (text input, contextual menus, click-on-crew) | AIDirective, all UI | **resolved**: click-on-crew contextual interface |
| Real-time with pause (FTL) or turn/phase based? | TimeManager, all tick systems | **resolved**: real-time with pause, 1x/2x speed |
| Save/load structure? (checkpoints or continuous) | SaveManager | **resolved**: checkpoints — at scenario completion and major in-scenario events |
| Does AI personality persist across scenarios? | AIDirective, ObedienceEngine | **resolved**: yes — ship carries all state (crew, resources, AI trust/access) into the next scenario; scenarios are consecutive legs of the same voyage |
| Permadeath for crew? For the AI? | ScenarioGenerator, win/lose conditions | **resolved**: yes on both; any of crew all dead / ship destroyed / AI decommissioned ends the run |

---

## Session Notes

> Append dated notes here as the project progresses.

```
2026-07-09 (session 2): Procedural ship generation + visual overhaul (Agent 1 of the
overhaul/mothership-rewrite branch). New scripts/procedural/ship_layout_gen.gd generates a
freighter-class ship from a seed: fore-to-aft spine of corridor-type room segments, bridge
capping fore, engine_room capping aft (both door-sealed, no gap), flank rows offering a
west/east slot each for ai_core/mess/quarters/cargo/medbay/airlock in a fixed thematic order
(ai_core first row off the bridge; mess+quarters clustered next; medbay at the structural
middle of the flank sequence; cargo distributed around it; airlock(s) outermost), life_support
inline directly ahead of engine_room. Room-type vocabulary is exactly the 10 strings shared
with docs/dialogue_spec.md: bridge, engine_room, medbay, mess, quarters, cargo, corridor,
life_support, ai_core, airlock — every generated ship has exactly one bridge/engine_room/
medbay/mess/life_support/ai_core and at least one quarters/cargo/airlock. Doors (lockable,
AI-overridable) sit on bridge/engine_room/every cargo hold/ai_core/every airlock; medbay/mess/
quarters/life_support/corridor seams stay open (matches the existing Quarantine scenario's
behavioural-not-physical containment). Maintenance tubes are secondary, maintenance-only graph
edges (life_support<->engine_room, ai_core<->life_support, a cargo-to-cargo crawlway) — dormant
under normal crew pathing (ShipGraph.find_path default allow_maintenance=false) but available
for a future directive type to bypass a locked door. Room counts/sizes randomise per seed within
tables in ShipLayoutGen (quarters 1-2, cargo 1-3, airlock 1-2). The seed lives on
GameState.ship_seed/ship_class_id (SHIPAI_SEED env var pins a specific layout for tooling); the
same seed regenerates the identical ship, so saves can reproduce it.

DeckPlan (scripts/ship/deck_plan.gd) was refactored from hardcoded consts into a data
CONTAINER — same static accessor API (room_rect, room_center, random_point, hop_waypoints,
deck_bounds, has_room, floor_tile_for) but now filled by ShipLayoutGen.generate() calling
DeckPlan.load_plan() once per scenario start, so RoomBase/ShipLayoutBuilder/CrewMemberNode
needed zero call-site changes. Per-room-type prop pools (medbay/mess/quarters/cargo/
engine_room/life_support/ai_core/airlock/bridge) place sensible dressing hugging room walls
only (perimeter cells, excluding whichever edge connects to the corridor/another room) so
door cells, walkways, and hop waypoints are never blocked; ai_core and bridge get a
"centerpiece" prop (machine_wireless_SE / desk_computerScreen_SE) placed prominently on a
back wall. The Kenney kit has no literal table/bunk sprite, so mess/quarters substitute
chairs + barrels/desks (documented in ship_layout_gen.gd).

Visual layer additions: Starfield (scripts/ship/starfield.gd) — 3-layer procedural parallax
backdrop, each layer drawn once via _draw() and only ever translated (sine drift) for near-zero
per-frame cost on GL Compatibility; sits behind everything (z_index -1000), fixed to the
viewport (not the scaled/panned ShipDeck). Ship hull silhouette — a Polygon2D + Line2D built
in ShipLayoutBuilder._build_hull() from a polygon ShipLayoutGen computes as the union of each
row's extent, inflated, with a nose taper ahead of the bridge and a flared aft block behind the
engine room (z_index -10/-9: behind floors, in front of the starfield). Floors now use a
per-room-type tile + tint (FLOOR_TILE_BY_TYPE/FLOOR_TINTS_BY_TYPE in ShipLayoutGen). Walls: the
generator emits semi-transparent wall sprites (corridor_wall_NE/NW/SE/SW) along every room
boundary edge that ISN'T an open connection; front/camera-facing edges (SE/SW, drawn over the
interior by painter's-order z-sort) are more transparent (alpha .32) than back edges (NE/NW,
alpha .62). Door gates now recolour on lock state — Door.refresh_gate_visual() tints the gate
sprite red/green — via a gate_sprite reference ShipLayoutBuilder wires up.

Downstream code that assumed the old fixed ids ("medbay", "bridge", "engineering", "cargo",
"corridor_main") now looks rooms up by TYPE via new GameState.get_room_of_type()/
get_rooms_of_type() helpers: main.gd crew start rooms + KEY_D/autodemo directives,
CrewBehavior's DUTY_STATION resolution, QuarantineMonitor's medbay reference (resolved once at
_ready(), cached). DirectiveMenu now skips corridor-type rooms from the "go to" list (a
generated ship can have several corridor segments; they're pass-through, not meaningful
destinations). Removed main.gd's dead `_build_class1_config()` fallback and the
resources/ship_configs/class_1_scout.tres load path — it relied on DeckPlan's old hardcoded
consts and would have produced an invisible ship now that DeckPlan is generator-filled; the
.tres file itself is left on disk, unreferenced, in case it's wanted as a reference later.

Known limitations / handoff notes for later agents: (1) no Godot binary available this session
— everything was validated statically (every sprite path cross-checked against
assets/sprites/legacy/, brackets/indentation/class_name-uniqueness checked programmatically,
GDScript reviewed line-by-line) but never actually run; first editor open will regenerate
.godot/global_script_class_cache.cfg to pick up the two new classes (ShipLayoutGen, Starfield).
(2) Maintenance-tube hop-waypoints aren't generated (they're unreachable under default crew
pathing anyway); if a future directive enables allow_maintenance routing, crew will walk that
edge without intermediate waypoints (cosmetic only). (3) CrewBehavior's "cargo" duty station and
similar always resolve to the FIRST room of that type (e.g. cargo_1) when multiple exist —
fine for now, but a future pass could distribute crew across multiple cargo bays/quarters.
(4) DirectiveMenu still lists every non-corridor room as a flat button list; with freighter-size
ships (~10-12 rooms) that's a long menu — worth grouping/paging later.

2026-07-09: Art pivot + working vertical slice. The Reve Flat Vector set was retired (inconsistent
styles/perspectives between assets); the whole visual layer now composes from the Kenney Space Kit
in assets/sprites/legacy/ (512×512 canvases, 130×65 floor diamond registered at (256,311) — every
sprite anchors identically, so rooms are built per-cell on one iso grid). New: IsoKit (projection/
anchoring), DeckPlan (Class-1 grid layout: rects, props, walkways, tubes, door gates, hop waypoints),
RoomBase composes tiles, ShipDeck container in Main fits deck to view, crew are kit astronauts with
8 facings/role tints/status dots and walk multi-hop graph routes across walkways. Gameplay: crew are
now autonomous (CrewBehavior: eat/sleep→quarters, work→duty station by role, panic→flee, idle→wander;
boredom-driven WORKING added to state machine); QuarantineMonitor turns the win flags into achievable
play (Vasquez alone-or-with-Chen in medbay 10s → isolated; Chen present 25s → contained → success);
HUD gained objective line, event feed, win/lose banner. Fixed class_1_scout.tres (script-class
sub_resources need type="Resource" + script=ExtResource), added icon.svg. Directive-vs-autonomy rule:
accepted directives hold crew in place (hold_room_until) except panic. Verified end-to-end in Godot
4.7 via SHIPAI_AUTOSHOT/SHIPAI_AUTODEMO env hooks in main.gd (timed screenshots + scripted win run:
detection → directives incl. a refusal → isolation → containment → MISSION COMPLETE banner).

2026-07-07: Phase 6 visual layer. Art direction locked to Flat Vector; full 61-asset sprite set generated via the Reve pipeline (tools/asset_gen/). Built the missing visual/input layer on top of the (already logic-complete) systems: rooms render their floor-plate sprites on a hand-authored 1920×1080 deck plan (RoomDefinition.layout_position); crew render role/state/facing sprites and walk between rooms; click-on-crew opens a contextual directive menu that issues real AIDirectives (move_to_room), executed only when the crew accepts (DirectiveActionHandler). NOTE: no Godot binary in the web environment, so none of this is runtime-verified — validated statically (sprite paths, .tscn format, EventBus/GameState/AISystem contracts, class-name uniqueness). First-time editor open will import the PNGs and generate .import files. Next: open in Godot, fix any runtime issues, tune deck-plan spacing visually, then wire the scenario to a visible win/lose beat.

2026-05-14: Phase 0–5 complete in same session. Design decisions fully resolved. Ship graph system (Dijkstra, door locks, maintenance tubes), Door scene, ShipConfig resource hierarchy, Class 1 Scout config (.tres), ShipLayoutBuilder utility. Campaign structure confirmed: ship state persists between scenarios; scenarios give resource deltas; checkpoints at scenario completion. GameState extended with ship_graph, doors, get_locked_doors(). Godot 4 project initialised with full folder structure. EventBus, GameState, SaveManager, TimeManager autoloads stubbed. RoomBase scene + script created. Design decisions locked: real-time with pause (1x/2x), FTL/Barotrauma click-on-crew UI (mobile horizontal compatible), all 3 failure states (crew dead / ship destroyed / AI decommissioned). Crew inner state partially visible via mood indicators and readable logs — rich inner lives (Sims-style). Alien Isolation multi-tier AI noted as influence for future Scenario Director layer.
```