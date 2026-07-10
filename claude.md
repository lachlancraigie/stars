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

## RESUME QUEUE (work in order, one agent at a time)

1. **Finish dialogue to ~2,500 lines** — state: 2,188 lines, validator clean (2026-07-10 recovery check: lost agent's GR work was valid, committed); CH + EV groups COMPLETE; GR group: done EXCEPT `gr_ml_sci_of` (50 lines, needs ~+50); PA group: all six PA files need expansion (296 lines total, target ~90 each). **Rules**: ONE Haiku agent per group sequentially; append-only; IDs continue from file's current max; hand-written in character (no nested agents, no generation scripts); closed vocabularies from `docs/dialogue_spec.md` only; `reply_to_intents` holds INTENTS only (never event names). Validate: `python tools/dialogue/validate_dialogue.py resources/dialogue/lines/*.json`

2. **Corpus finalization** (orchestrator): run validator → fix stragglers → `python tools/dialogue/normalize_and_export.py` (normalizes tags AND regenerates all ElevenLabs CSVs; JSON is canonical) → commit.

3. **Voice the expansion** — ElevenLabs quota re-added. Run `python tools/audio_gen/elevenlabs_batch.py` (resume-safe, skips existing 1,376 MPs; `voices.json` complete: 10 permanent SHIPAI custom voices + 14 stock; `voice_designs.json` has recipes; key in gitignored `tools/audio_gen/.env`). Use eleven_v3 for TTS.

4. **Character animations** (Lachlan's priority; prior agent died before committing — restart fresh): states wanted: walk, sleeping, fighting, holding/carrying, dead, injured, floating zero-g + extras. Consistency strategy (test first, hard-stop ~$2.50 if it fails): (a) sheet-based generation — frames in one image can't drift, use strict grid prompts + PIL slicing; (b) palette-snap post-pass; (c) reference-anchor sheets on approved base. Naming: `assets/sprites/gen2/crew/crew_{state}_{facing}_{frame}.png` + `manifest.json`. Integrate into `crew_member_node.gd` (recently edited: bubbles + voice) with per-frame texture swap and LEGACY FALLBACK. Budget ~$10, report spend, verify both autodemos.

5. **Crew progression** — per `docs/crew-progression-spec.md` §7: traits registry, earn triggers, leg-boundary Rest Saves, memorial, roster biography panel. PINNED — do NOT build FTL-style replacement crew recruitment yet.

6. **Sprint close-out**: consider fast-forwarding `main` (last synced `0619ecb` — ask Lachlan), CLAUDE.md consolidation, rotate the two API keys (they passed through chat).

---

## Operational Facts

- **Godot 4.7**: `& "$env:LOCALAPPDATA\Programs\Godot\Godot.exe"` (NOT on PATH). After any new `class_name`: `--path "D:\code\stars" --headless --import` first, then verify with `--headless --quit-after 600 res://scenes/Main.tscn` and grep for `SCRIPT ERROR`.
- **Env hooks**: `SHIPAI_SCENARIO=narrow_passage|quarantine` · `SHIPAI_AUTODEMO=1` · `SHIPAI_SEED` · `SHIPAI_FORCE_HEAT` / `SHIPAI_FORCE_FLAG` / `SHIPAI_DIRECTOR_DEBUG=1`
- **Secrets**: `tools/audio_gen/.env` (ElevenLabs), `tools/image_gen/.env` (OpenRouter) — gitignored, never commit/print. `assets/audio/dialogue/` gitignored (1,376 MP3s on disk).
- **Commit style**: explicit paths only (never `git add -A`), end messages with Claude Co-Authored-By line, retry once on index.lock.

---

## Gameplay Backlog (next up after resume queue)

1. DirectiveMenu "lock/unlock door" directive type (mechanics exist, no UI)
2. Visual hookup for room power/air state (signals emit; no RoomBase dimming yet)
3. Combat resolver (WoundTable/apply_damage implemented; nothing calls it — Bad Cargo scenario is the vehicle)
4. Bubble editor pass (fixed 260px width looks oversized on short lines)
5. CampaignManager for between-run structure
6. Crew portraits in HUD/bubbles

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