# CLAUDE.md — Ship AI Game

> Claude Code context file. Read this first every session. Full session notes → `notes.md`.

---

## Project Overview

A spaceship AI simulator. The player is the ship's computer. See `GDD.md` for full design.

**Engine**: Godot 4 / GDScript | **View**: Isometric 2D | **Repo**: TBD

---

## Current Sprint

**Branch**: `feature/mission-system` (off main tip `ee47299`)  
**Orchestration**: Main session directs; Opus for story content, Sonnet for code, Haiku for bulk. Max 2 agents concurrent. Incremental commits with explicit paths always. Memory dir: `~/.claude/projects/d--code/memory/`. **Agents must verify in FOREGROUND** — background-wait parking killed four agents this sprint (see memory `subagent-background-wait-stall`).

**Art**: gen2 cel-shaded environments (`assets/sprites/gen2/`) · **gen3 character models** (`assets/sprites/gen3_chars/`, 24/24 crew archetypes, mannequin-reskin pipeline `tools/image_gen/reskin_batch.py` — gemini via OpenRouter; NOT yet wired into CrewMemberNode). Image pipeline: `tools/image_gen/` (OpenRouter, gitignored `.env`).

---

## SESSION HANDOFF (2026-07-11, mission-system sprint COMPLETE)

**Shipped** (all committed + Godot-verified on `feature/mission-system`): **the mission system** — spec `docs/mission-system-spec.md` · 45 missions (`resources/missions/`) + 42 scenarios (`resources/scenarios/`), validator `tools/missions/validate_content.py` 0 errors · Engine A–E: data loaders/ScenarioCatalog (`f982386`), MissionManager spine + mission HUD + ApproachVisual planet grow-in (`1e21949`), away ops: shuttlebay/shuttle/AwayResolver/hidden status flags/radio barks (`b1a8ff5`), OutcomeApplier + GenericScenarioMonitor + IntruderSystem (`25c941a4`), Overseer refinement: heat-scaled hooks, trigger_status delayed payoffs, away-beat injection (`5516c776`) · dialogue +750 mission-system lines all voiced (Fish v2, 3,232 MP3s total) · Lyria 3 soundtrack pipeline (`tools/audio_gen/lyria_batch.py`, 19/78 tracks generated) · gen3 crew sprite roster 24/24.

---

## RESUME QUEUE (session detail in `notes.md`)

1. **Credit-blocked** (~$10 top-up covers all): 6 NPC + 3 robot sprite models (~$4, `reskin_batch.py` descriptions in notes) · 59 remaining soundtrack tracks (~$5, `lyria_batch.py` is resume-safe, $2 floor guard)
2. Wire gen3 crew models into `CrewMemberNode` (replace Kenney kit) — needs Lachlan's style verdict on `assets/sprites/gen3_chars/*/preview_walk.gif` first
3. Merge `feature/mission-system` → `main` after Lachlan plays a campaign
4. Dialogue_v2 playback swap + retire ElevenLabs path (carried; on audio approval)
5. Rotate API keys — ElevenLabs/OpenRouter/Fish (carried from last sprint, still outstanding)
6. Delete spent `ClaudeSprintRevive` scheduled task (self-delete was access-denied)

---

## Operational Facts

- **Godot 4.7**: `& "$env:LOCALAPPDATA\Programs\Godot\Godot.exe"` (NOT on PATH). After any new `class_name`: `--path "D:\code\stars" --headless --import` first, then verify with `--headless --quit-after 600 res://scenes/Main.tscn` and grep for `SCRIPT ERROR`.
- **Env hooks**: mission mode is the DEFAULT boot; `SHIPAI_SCENARIO=<id>` forces legacy scenario-only boot (any catalog id or narrow_passage/quarantine) · `SHIPAI_MISSION=<id>` forces first mission · `SHIPAI_AWAY_FAST=1` (10× away ops) · `SHIPAI_AWAY_AUTOTEST=1` (auto-launch away teams, soak hook) · `SHIPAI_AUTODEMO=1` · `SHIPAI_SEED` · `SHIPAI_FORCE_HEAT` / `SHIPAI_FORCE_FLAG` / `SHIPAI_FORCE_KILL=<archetype>` / `SHIPAI_DIRECTOR_DEBUG=1`
- **Godot gotchas**: `--quit-after` counts FRAMES not seconds (~110–125 fps headless) · `-s` scripts can't see autoloads — verify with real-scene runs + output capture.
- **Secrets**: `tools/audio_gen/.env` (ElevenLabs + Fish), `tools/image_gen/.env` (OpenRouter) — gitignored, never commit/print. Gitignored asset trees: `assets/audio/dialogue/` (1,376 v1 MP3s), `assets/audio/dialogue_v2/` (3,232 Fish MP3s), `assets/music/` (Lyria soundtrack).
- **Content validation**: `python tools/missions/validate_content.py --root D:\code\stars` after ANY mission/scenario JSON change — closed vocabularies, must be 0 errors.
- **Commit style**: explicit paths only (never `git add -A`), end messages with Claude Co-Authored-By line, retry once on index.lock.

---

## Gameplay Backlog (next up after resume queue)

1. ~~Door lock/unlock UI~~ ✅ + full click-interaction overhaul (2026-07-10, `9dd37f6`/`bc18d59`/`7706f53`): crew menu w/ Move-to submenu + Inspect page (equipment/monologue/jobs), top-right info card w/ portrait, door Open/Close+Lock/Unlock (decoupled axes), Repair→designate-crew directive flow
2. Visual hookup for room power/air state (signals emit; no RoomBase dimming yet)
3. ~~Combat resolver~~ ✅ IntruderSystem is now WoundTable's caller (intruder combat rounds, 2026-07-11)
4. Bubble editor pass (fixed 260px width looks oversized on short lines)
5. ~~CampaignManager~~ ✅ superseded — MissionManager owns campaign flow (deck, follow-ons, legs); between-RUN meta-structure still open
6. Crew portraits in bubbles (info-card portrait shipped; bubbles still plain)
7. Intruder sprites (sensor blips ship today; stalker/nest/mimic art in `docs/asset-backlog.md`)
8. Real planet/ship art for ApproachVisual (procedural placeholders live; hooks named per mission `destination.art`)

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
| MissionManager | `scripts/missions/mission_manager.gd` | done (autoload) |
| MissionDef / MissionDeck | `scripts/missions/mission_def.gd` / `mission_deck.gd` | done |
| ShuttleSystem | `scripts/missions/shuttle_system.gd` | done |
| AwayResolver | `scripts/missions/away_resolver.gd` | done |
| ApproachVisual | `scripts/missions/approach_visual.gd` | done (placeholder art) |
| ScenarioCatalog | `scripts/scenarios/scenario_catalog.gd` | done |
| OutcomeApplier | `scripts/scenarios/outcome_applier.gd` | done |
| GenericScenarioMonitor | `scripts/scenarios/generic_monitor.gd` | done |
| IntruderSystem | `scripts/ship/intruder_system.gd` | done (autoload, sensor-level) |
| PersonalityCore | `scripts/crew/personality_core.gd` | not started |
| ShipSystem | `scripts/ship/ship_system.gd` | not started |
| DamageModel | `scripts/ship/damage_model.gd` | not started |
| ScenarioGenerator | `scripts/procedural/scenario_generator.gd` | not started |