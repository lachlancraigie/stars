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

**Goal**: Phase 1 — ship layout (room graph, door system, pathfinding, Class 1 layout).

**Next tasks**:
1. Room connection graph + door system
2. Graph-based pathfinding (BFS/Dijkstra over `connected_room_ids`)
3. Class 1 ship layout scene (3–6 crew, tight)
4. ResourceTick loop wired to `TimeManager.time_ticked`

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
- [ ] Room scene (base)
- [ ] Ship layout (Class 1)
- [ ] Resource tick loop
- [ ] CrewMember base scene + stats
- [ ] Needs model
- [ ] Crew state machine
- [ ] AI directive system
- [ ] Trust model
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
| ShipSystem | `scripts/ship/ship_system.gd` | not started | Base class for all ship systems. |
| DamageModel | `scripts/ship/damage_model.gd` | not started | Localised + cascade damage. |
| ResourceTick | `scripts/ship/resource_tick.gd` | not started | Oxygen, power, food, fuel loop. |
| CrewMember | `scripts/crew/crew_member.gd` | not started | Stats, needs, state machine. |
| NeedsModel | `scripts/crew/needs_model.gd` | not started | Hunger, fatigue, fear, morale. |
| PersonalityCore | `scripts/crew/personality_core.gd` | not started | Traits, fears, values, goals. |
| RelationshipGraph | `scripts/crew/relationship_graph.gd` | not started | Crew social network. |
| AIDirective | `scripts/ai/ai_directive.gd` | not started | Directive data structure. |
| TrustModel | `scripts/ai/trust_model.gd` | not started | Per-crew-member AI trust scores. |
| ObedienceEngine | `scripts/ai/obedience_engine.gd` | not started | AI deviation detection + risk. |
| ScenarioGenerator | `scripts/procedural/scenario_generator.gd` | not started | Procedural scenario seeding. |

---

## Open Design Questions

**Do not implement the listed systems until these are resolved.**

| Question | Blocks | Status |
|---|---|---|
| What does the player UI look like? (text console / visual / hybrid) | AI directive input, UI scenes | **resolved**: FTL/Barotrauma visual style, click-on-crew contextual menus, mobile horizontal browser compatible (1920×1080 canvas, GL Compatibility) |
| How are directives issued? (text input, contextual menus, click-on-crew) | AIDirective, all UI | **resolved**: click-on-crew contextual interface |
| Real-time with pause (FTL) or turn/phase based? | TimeManager, all tick systems | **resolved**: real-time with pause, 1x/2x speed |
| Save/load structure? (checkpoints or continuous) | SaveManager | unresolved |
| Does AI personality persist across scenarios? | AIDirective, ObedienceEngine | unresolved |
| Permadeath for crew? For the AI? | ScenarioGenerator, win/lose conditions | **resolved**: yes on both; any of crew all dead / ship destroyed / AI decommissioned ends the run |

---

## Session Notes

> Append dated notes here as the project progresses.

```
2026-05-14: Phase 0 scaffold complete. Godot 4 project initialised with full folder structure. EventBus, GameState, SaveManager, TimeManager autoloads stubbed. RoomBase scene + script created. Design decisions locked: real-time with pause (1x/2x), FTL/Barotrauma click-on-crew UI (mobile horizontal compatible), all 3 failure states (crew dead / ship destroyed / AI decommissioned). Crew inner state partially visible via mood indicators and readable logs — rich inner lives (Sims-style). Alien Isolation multi-tier AI noted as influence for future Scenario Director layer.
```