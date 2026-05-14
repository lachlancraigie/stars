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

**Goal**: Project scaffold — nothing implemented yet.

**Next tasks**:
1. Godot project initialisation and folder structure
2. EventBus autoload stub
3. GameState autoload stub
4. Placeholder room scene

**Blocked on**:
- Open design questions in GDD.md (UI model, time model) — do not implement AI directive input or time systems until these are resolved

---

## What's Done

- [ ] Godot project created
- [ ] Folder structure in place
- [ ] EventBus autoload
- [ ] GameState autoload
- [ ] SaveManager autoload
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
| EventBus | `scripts/core/event_bus.gd` | not started | Autoload. Central signal hub. |
| GameState | `scripts/core/game_state.gd` | not started | Autoload. Source of truth. |
| SaveManager | `scripts/core/save_manager.gd` | not started | Autoload. Scenario checkpoints. |
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
| What does the player UI look like? (text console / visual / hybrid) | AI directive input, UI scenes | unresolved |
| How are directives issued? (text input, contextual menus, click-on-crew) | AIDirective, all UI | unresolved |
| Real-time with pause (FTL) or turn/phase based? | TimeManager, all tick systems | unresolved |
| Save/load structure? (checkpoints or continuous) | SaveManager | unresolved |
| Does AI personality persist across scenarios? | AIDirective, ObedienceEngine | unresolved |
| Permadeath for crew? For the AI? | ScenarioGenerator, win/lose conditions | unresolved |

---

## Session Notes

> Append dated notes here as the project progresses.

```
YYYY-MM-DD: [what was done, what decisions were made, what changed]
```