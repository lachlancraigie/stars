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
1. Camera2D pan/zoom (deck currently statically fitted to the 1920×1080 canvas)
2. Door gates tied to Door lock state (visual + crew pathing around locked doors)
3. Crew walk-cycle feel (kit has single frames per facing; current bob is serviceable)
4. More in-scenario choices for the AI (info framing, door locks as containment tools)
5. Campaign handoff after scenario end (currently ends on the banner)

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
| DeckPlan | `scripts/ship/deck_plan.gd` | done | Static data. Class-1 grid layout: room rects, floor tints, props, walkways, tubes, door cells, hop waypoints, random standing points. |
| RoomBase (visual) | `scripts/ship/room_base.gd` + `scenes/rooms/RoomBase.tscn` | done | Composes floor tiles + props from DeckPlan/IsoKit; positioned at DeckPlan.room_center. |
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