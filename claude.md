# CLAUDE.md — Ship AI Game

> Claude Code context file. Read this first every session. Full session notes → `notes.md`.

---

## Project Overview

A spaceship AI simulator. The player is the ship's computer. See `GDD.md` for full design.

**Engine**: Godot 4 / GDScript | **View**: Isometric 2D | **Repo**: TBD

---

## Current Sprint

**Branch**: `overhaul/mothership-rewrite`  
**Orchestration**: Main session directs, Sonnet subagents implement (Haiku for bulk dialogue). ONE agent at a time. Incremental commits with explicit paths always. Memory dir: `~/.claude/projects/d--code/memory/`

**Art**: gen2 cel-shaded (`assets/sprites/gen2/`, 65 assets via `IsoKit.KIT_DIR`). CREW still use legacy Kenney kit (`CrewMemberNode.KIT_DIR`) — cross-facing color consistency failed, animation workstream below is the fix. Image pipeline: `tools/image_gen/` (OpenRouter, key in gitignored `.env`, ~$10+ credits).

---

## SESSION HANDOFF (2026-07-10, mid-sprint)

**Shipped this sprint** (all committed, runtime-verified): procgen freighter + starfield/hull/walls · Mothership 1e rules + situational power/air + AI core · camera/collision · crew sim: schedules, relationships/romance, emergent dialogue, bubbles · voice playback on bubbles · The Narrow Passage scenario · THE OVERSEER director AI · gen2 environment art live · dialogue corpus 1,376 lines fully voiced (1,376 MP3s). Specs: `docs/director-spec.md`, `docs/crew-progression-spec.md`, `docs/scenario-bible.md`, `docs/audio-direction.md`, `docs/dialogue_spec.md`.

---

## RESUME QUEUE (work in order, one agent at a time — session detail in `notes.md`)

1. ~~Dialogue expansion~~ ✅ 2,482 lines / 24 files, validator clean
2. ~~Corpus finalization~~ ✅ ElevenLabs CSVs regenerated (`ab32eac`)
3. ElevenLabs voicing — ON HOLD (1,550/2,482 done, quota dead); superseded by the Fish v2 trial below. Rerun cmd in `notes.md` if ElevenLabs returns.
4. ~~Character animations~~ ✅ integrated w/ Kenney fallback; head consistency SOLVED by head-swap compositing (`d248a27`: canonical head per facing, checksum-identical; tools `crew_head_{geom,swap,qa}.py`) — zoom strips with Lachlan. OPEN: 16 prone/floating poses un-swapped (by design) · 14 pre-existing corrupt slices in walk/melee/carry need a re-slice pass (list in `_test/composite_report.json`)
5. ~~Crew progression~~ ✅ (`e092bcf`/`30a9d9c`); FTL recruitment still PINNED
6. ~~Fish Audio v2 revoice~~ ✅ COMPLETE (2026-07-11): 2,482/2,482 MP3s in `assets/audio/dialogue_v2/` (195MB, gitignored). Voice map `tools/audio_gen/fish_voices.json`; CH_ML_ENG_OF re-voiced with Lachlan's dedicated pick (double-duty resolved; 3 other flagged compromises unreviewed). STILL TODO on approval: point bubble voice playback at dialogue_v2, retire ElevenLabs path.
7. ~~Sprint close-out~~: `main` fast-forwarded to sprint tip (2026-07-11). OUTSTANDING: rotate API keys (ElevenLabs/OpenRouter/Fish — all passed through chat) · head-swap strips verdict · 14 corrupt slices re-slice pass (Lachlan's go).

---

## Operational Facts

- **Godot 4.7**: `& "$env:LOCALAPPDATA\Programs\Godot\Godot.exe"` (NOT on PATH). After any new `class_name`: `--path "D:\code\stars" --headless --import` first, then verify with `--headless --quit-after 600 res://scenes/Main.tscn` and grep for `SCRIPT ERROR`.
- **Env hooks**: `SHIPAI_SCENARIO=narrow_passage|quarantine` · `SHIPAI_AUTODEMO=1` · `SHIPAI_SEED` · `SHIPAI_FORCE_HEAT` / `SHIPAI_FORCE_FLAG` / `SHIPAI_FORCE_KILL=<archetype>` / `SHIPAI_DIRECTOR_DEBUG=1`
- **Secrets**: `tools/audio_gen/.env` (ElevenLabs), `tools/image_gen/.env` (OpenRouter) — gitignored, never commit/print. `assets/audio/dialogue/` gitignored (1,376 MP3s on disk).
- **Commit style**: explicit paths only (never `git add -A`), end messages with Claude Co-Authored-By line, retry once on index.lock.

---

## Gameplay Backlog (next up after resume queue)

1. ~~Door lock/unlock UI~~ ✅ + full click-interaction overhaul (2026-07-10, `9dd37f6`/`bc18d59`/`7706f53`): crew menu w/ Move-to submenu + Inspect page (equipment/monologue/jobs), top-right info card w/ portrait, door Open/Close+Lock/Unlock (decoupled axes), Repair→designate-crew directive flow
2. Visual hookup for room power/air state (signals emit; no RoomBase dimming yet)
3. Combat resolver (WoundTable/apply_damage implemented; nothing calls it — Bad Cargo scenario is the vehicle)
4. Bubble editor pass (fixed 260px width looks oversized on short lines)
5. CampaignManager for between-run structure
6. Crew portraits in bubbles (info-card portrait shipped; bubbles still plain)

**Blocked on**: nothing hard. SaveManager stub by design — `ScenarioRunner`'s leg-boundary hook calls `SaveManager.save_checkpoint()`, still a no-op.

---

## Architecture Rules

1. **No direct crew control.** AI issues directives. Crew evaluate and respond autonomously. Nothing in `scripts/ai/` directly sets crew position, state, or action.
2. **EventBus for cross-system comms.** No direct calls between systems. Use `EventBus.emit()` / `EventBus.connect()`.
3. **GameState is single source of truth.** Read from GameState, mutate via GameState methods, emit events.
4. **Resource files for data.** `.tres` files under `/resources/`. Procedural generation mutates copies at runtime, never base resources.
5. **Scenes own visuals/input, scripts own logic.** Keep business logic out of `_ready()` / `_process()` where possible.

---

## Conventions

- **GDScript**: snake_case everywhere; PascalCase class names; SCREAMING_SNAKE constants
- **Signals**: past tense — `crew_moved`, `system_damaged`, `directive_issued`
- **Files**: snake_case matching class name; scenes PascalCase
- **No magic numbers**: constants at file top or in `Constants.gd`
- **Comments**: explain *why*, not *what*
- **TODOs**: `# TODO(system): description`

---

## Project Structure

```
/
├── CLAUDE.md / GDD.md / notes.md
├── project.godot
├── assets/sprites/ audio/ fonts/
├── scenes/ships/ rooms/ crew/ ui/
├── scripts/
│   ├── core/        ← autoloads + rules utilities
│   ├── ship/        ← ship systems, power, life support
│   ├── crew/        ← crew sim, needs, relationships, dialogue
│   ├── ai/          ← directives, trust, obedience
│   ├── procedural/  ← generators
│   └── scenarios/   ← scenario definitions + monitors
├── resources/crew_templates/ ship_configs/ event_definitions/
├── docs/            ← specs
└── tools/audio_gen/ image_gen/ dialogue/
```

---

## Key Systems (status only — implementation detail in notes.md)

| System | Location | Status |
|---|---|---|
| EventBus | `scripts/core/event_bus.gd` | done |
| GameState | `scripts/core/game_state.gd` | done |
| SaveManager | `scripts/core/save_manager.gd` | stub |
| TimeManager | `scripts/core/time_manager.gd` | stub |
| ShipGraph | `scripts/ship/ship_graph.gd` | done |
| Door | `scripts/ship/door.gd` | done |
| ShipLayoutBuilder | `scripts/ship/ship_layout_builder.gd` | done |
| ShipLayoutGen | `scripts/procedural/ship_layout_gen.gd` | done |
| DeckPlan | `scripts/ship/deck_plan.gd` | done |
| DeckCamera | `scripts/ship/deck_camera.gd` | done |
| PowerModel | `scripts/ship/power_model.gd` | done |
| LifeSupportModel | `scripts/ship/life_support_model.gd` | done |
| RepairModel | `scripts/ship/repair_model.gd` | done |
| ShipSystemsTick | `scripts/core/ship_systems_tick.gd` | done |
| CrewMember | `scripts/crew/crew_member.gd` | done |
| CrewMemberNode | `scripts/crew/crew_member_node.gd` | done |
| CrewBehavior | `scripts/crew/crew_behavior.gd` | done |
| CrewSchedule | `scripts/crew/crew_schedule.gd` | done |
| CrewGen | `scripts/procedural/crew_gen.gd` | done |
| CrewLifecycle | `scripts/crew/crew_lifecycle.gd` | done |
| RelationshipGraph | `scripts/crew/relationship_graph.gd` | done |
| RelationshipBehavior | `scripts/crew/relationship_behavior.gd` | done |
| DialogueSystem | `scripts/crew/dialogue_system.gd` | done (autoload) |
| NeedsModel | `scripts/crew/needs_model.gd` | done |
| SuffocationModel | `scripts/crew/suffocation_model.gd` | done |
| CrewStateMachine | `scripts/crew/crew_state_machine.gd` | done |
| CrewSystem | `scripts/crew/crew_system.gd` | done (autoload) |
| Checks | `scripts/core/checks.gd` | done |
| PanicTable | `scripts/core/panic_table.gd` | done |
| WoundTable | `scripts/core/wound_table.gd` | done |
| Items | `scripts/core/items.gd` | done |
| AICoreSystem | `scripts/ai/ai_core_system.gd` | done |
| AIDirective | `scripts/ai/ai_directive.gd` | done |
| AISystem | `scripts/ai/ai_system.gd` | done (autoload) |
| TrustModel | `scripts/ai/trust_model.gd` | done |
| ObedienceEngine | `scripts/ai/obedience_engine.gd` | done |
| DirectiveEvaluator | `scripts/ai/directive_evaluator.gd` | done |
| DirectiveMenu | `scripts/ui/directive_menu.gd` | done |
| DirectiveActionHandler | `scripts/ai/directive_action_handler.gd` | done |
| ScenarioDirector | `scripts/scenarios/scenario_director.gd` | done (+ Overseer) |
| ScenarioRunner | `scripts/scenarios/scenario_runner.gd` | done (multi-instance) |
| QuarantineScenario/Monitor | `scripts/scenarios/quarantine_*.gd` | done |
| NarrowPassageScenario/Monitor | `scripts/scenarios/narrow_passage_*.gd` | done |
| IsoKit | `scripts/ship/iso_kit.gd` | done |
| Starfield | `scripts/ship/starfield.gd` | done |
| RoomBase | `scripts/ship/room_base.gd` | done |
| AccessLevel | `scripts/ai/access_level.gd` | done |
| SideProjects | `scripts/crew/side_projects.gd` | done |
| PersonalityCore | `scripts/crew/personality_core.gd` | not started |
| ShipSystem | `scripts/ship/ship_system.gd` | not started |
| DamageModel | `scripts/ship/damage_model.gd` | not started |
| ScenarioGenerator | `scripts/procedural/scenario_generator.gd` | not started |