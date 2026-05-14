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

**Goal**: Phase 5 — event system + first vertical slice (*The Quarantine*).

**Next tasks**:
1. `ScenarioEvent` Resource class (id, conditions, outcomes, tone_weight)
2. `EventPool` — weighted draw from event pool based on scenario tone
3. `ScenarioDirector` — hidden meta-layer; manages pacing, tone drift, event timing
4. Hand-author *The Quarantine* scenario (Class 1; pathogen; AI knows before crew)
5. Win/lose condition checking in GameState or a dedicated ScenarioRunner

**Blocked on**:
- Save/load structure (checkpoints vs continuous) — do not implement SaveManager beyond stubs until resolved
- Permadeath scope — do not finalise scenario end conditions until resolved

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
- [ ] First scripted event
- [ ] Vertical slice (Class 1, one scenario)

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
| CrewMemberNode | `scripts/crew/crew_member_node.gd` | done | Node2D. Visual + registration; state tint for dev visibility. |
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
2026-05-14: Phase 0–4 complete in same session. Design decisions fully resolved. Ship graph system (Dijkstra, door locks, maintenance tubes), Door scene, ShipConfig resource hierarchy, Class 1 Scout config (.tres), ShipLayoutBuilder utility. Campaign structure confirmed: ship state persists between scenarios; scenarios give resource deltas; checkpoints at scenario completion. GameState extended with ship_graph, doors, get_locked_doors(). Godot 4 project initialised with full folder structure. EventBus, GameState, SaveManager, TimeManager autoloads stubbed. RoomBase scene + script created. Design decisions locked: real-time with pause (1x/2x), FTL/Barotrauma click-on-crew UI (mobile horizontal compatible), all 3 failure states (crew dead / ship destroyed / AI decommissioned). Crew inner state partially visible via mood indicators and readable logs — rich inner lives (Sims-style). Alien Isolation multi-tier AI noted as influence for future Scenario Director layer.
```