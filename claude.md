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
1. Crew walk-cycle feel (kit has single frames per facing; current bob is serviceable)
2. DirectiveMenu: add a "lock/unlock door" directive type (Door.ai_unlock/lock exist; no UI surfaces them yet) — now that locked doors actually block crew pathing and drive the bypass minigame, this is worth exposing to the player
3. Campaign handoff after scenario end (currently ends on the banner)
4. Visual hookup for room power/air state (EventBus.room_power_changed/room_air_changed/ai_core_status_changed already emit; no dimming/particle response in RoomBase yet — see 2026-07-10 session 3 note)
5. Combat resolver — CrewMember.apply_damage()/WoundTable are fully implemented but nothing in the live game calls apply_damage() yet (no weapons fire); dormant, ready to wire up
6. Bubble visuals are only statically/behaviourally verified (no Godot GUI available this session — see 2026-07-10 session 5 note); worth an eyeballing pass in the editor for spacing/legibility
7. Crew portraits/avatars for the archetype voices now exist under `tools/audio_gen/`/`tools/image_gen/` (parallel work, not this session's) — could surface in the HUD/bubbles later

Done this session (Agent 4, camera + collision — see 2026-07-10 session note addendum below): Camera2D pan/zoom
(deck no longer statically fitted — DeckCamera auto-fits DeckPlan.deck_bounds() as the default zoom, then
supports wheel-zoom-to-cursor, drag/WASD/edge-scroll pan, clamped so the deck can't be lost off-screen) and
crew soft-collision/standing-point claiming (CrewMemberNode).

Done this session (Agent 2/"crew simulation", see 2026-07-10 session 5 note): the crew shift-cycle schedule,
crew relationships/romance, the full emergent dialogue runtime, and speech/thought bubbles — the item 6 above
is now DONE, not a next task.

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
- [x] ~~Resource tick loop~~ / ~~HUD resource bars~~ — SCRAPPED 2026-07-10: replaced by the Mothership situational power/life-support model (ShipSystemsTick, PowerModel, LifeSupportModel) + a compact per-room power/air HUD panel. See 2026-07-10 (session 3) note.
- [x] Mothership 1e adoption: CrewMember rewrite, Checks/PanicTable/WoundTable, CrewGen, door bypass, AI core integrity/blackout, repair system — see 2026-07-10 (session 3) note for the adoption map
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
- [x] Camera2D pan/zoom: DeckCamera auto-fits the generated deck as the default zoom, wheel-zoom toward cursor (clamped), drag/WASD/edge-scroll pan (clamped via deck_bounds); Starfield moved into its own CanvasLayer so it stays screen-fixed under the new camera; DirectiveMenu hit-testing/placement made camera-aware
- [x] Crew soft-collision + standing-point claiming: CrewMemberNode applies cheap O(N²) perpendicular-biased separation steering (never stalls route-following/panic-flee/hold_room_until) and claims DeckPlan standing points via a static registry so crew don't stack
- [x] Crew daily schedule: CrewSchedule shift-cycle (work/meal/recreation/sleep) layered on CrewBehavior's IDLE branch; needs/crises/repair duty/accepted directives all still outrank it
- [x] Crew relationships & romance: RelationshipGraph (GameState-owned per-pair affinity + romance stage machine), RelationshipBehavior (panic-snap/crisis-bond/partner-grief hooks)
- [x] Emergent dialogue runtime: DialogueSystem autoload — defensive corpus loading, the spec's scoring formula, declarations, template + emergent conversations, romance-gated intents
- [x] Speech/thought bubbles: reusable per-crew Panel+RichTextLabel reacting to EventBus.line_spoken, thought (declarations) vs speech (conversation lines) styling
- [x] Second scenario: The Narrow Passage (scenario-bible 1.2) — first scenario to dramatize the PowerModel/LifeSupportModel 3-room triage caps; SHIPAI_SCENARIO env selection (quarantine default); scripted autodemo win path verified headless end-to-end

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
│   ├── core/               ← EventBus, GameState, SaveManager, TimeManager, ShipSystemsTick (autoloads)
│   │                         + Checks/PanicTable/WoundTable/Items (Mothership rules utilities)
│   ├── ship/               ← ShipSystem, DamageModel, Door, PowerModel, LifeSupportModel, RepairModel
│   ├── crew/               ← CrewMember, NeedsModel, SuffocationModel, CrewLifecycle, RepairBehavior,
│   │                         PersonalityCore, RelationshipGraph
│   ├── ai/                 ← AIDirective, TrustModel, ObedienceEngine, AccessLevel, AICoreSystem
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
| EventBus | `scripts/core/event_bus.gd` | done | Autoload. All cross-system signals defined; `recent_event` is the dialogue-facing funnel (now also forwards `crisis_resolved` from system-repair/AI-core-recovery/the quarantine's own resolution). `line_spoken`/`conversation_started`/`conversation_ended`/`crew_romance_started`/`crew_relationship_changed` are all now actually emitted (DialogueSystem/RelationshipGraph), not just declared. |
| GameState | `scripts/core/game_state.gd` | done | Autoload. Resource/trust/access mutators wired to EventBus. Also owns `crew_relationships` (per-pair affinity/flags/romance_stage, mutated by RelationshipGraph) and `crew_side_projects` (crew_id → hobby id, lazily assigned by `side_projects.gd`). |
| SaveManager | `scripts/core/save_manager.gd` | stub done | Autoload. Checkpoint structure stubbed; unimplemented. |
| TimeManager | `scripts/core/time_manager.gd` | stub done | Autoload. Real-time with pause, 1x/2x speed, 0.25s tick interval. |
| RoomDefinition | `scripts/ship/room_definition.gd` | done | Resource. Room data schema for ShipConfig. |
| ConnectionDefinition | `scripts/ship/connection_definition.gd` | done | Resource. Connection data schema for ShipConfig. |
| ShipConfig | `scripts/ship/ship_config.gd` | done | Resource. Full ship class definition. Class 1 .tres in resources/. |
| ShipGraph | `scripts/ship/ship_graph.gd` | done | RefCounted. Dijkstra pathfinding over room graph. Respects locked doors + maintenance access. |
| Door | `scripts/ship/door.gd` | done | Node2D. Connects two rooms; AI unlock via access level, gated on AI-core blackout/degraded lag + room power; crew-side manual bypass (Checks-driven Intellect+tech check → fast/slow/instant/jam) with `door_locked_on_crew`/`door_bypass_*` signals and per-door lockout counts feeding TrustModel. |
| ShipLayoutBuilder | `scripts/ship/ship_layout_builder.gd` | done | Static utility. Builds live ship from ShipConfig into scene tree. |
| ShipSystem | `scripts/ship/ship_system.gd` | not started | Base class for all ship systems. |
| DamageModel | `scripts/ship/damage_model.gd` | not started | Localised + cascade damage. |
| ShipSystemsTick | `scripts/core/ship_systems_tick.gd` | done | Autoload (formerly ResourceTick — the old normalised oxygen/power/food/water/fuel/spare-parts/medicine bars are gone). Fans `time_ticked` out to `PowerModel.tick()`/`LifeSupportModel.tick()`/`RepairModel.tick()`. |
| PowerModel | `scripts/ship/power_model.gd` | done | Static utility. Reactor-online-or-battery-budget model: battery drains per powered room while on battery, hard-capped simultaneous rooms (`MAX_BATTERY_ROOMS`). State lives on GameState; mutated via `GameState.set_reactor_online/set_room_powered/set_battery_charge`. |
| LifeSupportModel | `scripts/ship/life_support_model.gd` | done | Static utility. Per-room air quality (0-100) degrades/recovers over minutes depending on `life_support_online` + diverted-room caps; auto-fails if the life_support room loses power. Feeds Checks environmental disadvantage + SuffocationModel. |
| RepairModel | `scripts/ship/repair_model.gd` | done | Static utility. Resolves already-started `GameState.repair_jobs` (reactor/life_support/ai_core) via periodic Intellect+skill Checks; completion re-onlines the target system. |
| CrewMember | `scripts/crew/crew_member.gd` | done | Resource. Full Mothership 1e character: Four Stats, Three Saves, Class, Health/Wounds, Stress/Panic transient state, Skills, Equipment, plus dialogue-facing identity (`archetype_tag`, `rank`, pronouns) — and the pre-existing needs/personality/social simulation layer, unchanged and complementary. |
| CrewMemberNode | `scripts/crew/crew_member_node.gd` | done | Node2D. Kit astronaut w/ 8 facings + role tint + status dot; multi-hop route walking (graph path + walkway waypoints); y-based z-sort; `static nodes` registry. Soft O(N²) pairwise separation steering (`_apply_separation`, ~half-tile personal radius, perpendicular-biased so it doesn't fight forward progress, displacement clamped to the current room's floor rect / walkway-union bounds) keeps crew from stacking without ever stalling route-following, panic-flee, or hold_room_until. A static `_point_claims` registry (`_claim_standing_point`) keeps two crew from picking the same DeckPlan standing point/duty station. Now also owns the speech/thought bubble: one reusable Panel+RichTextLabel built in `_ready()` (`_build_bubble`), restyled/resized per `EventBus.line_spoken` (`_show_bubble`) — declarations render as dimmed/italic thought (no tail), conversation lines as normal speech (with a tail polygon); world-space child (`z_as_relative=false`, large fixed z_index) so it scales with DeckCamera zoom like everything else on the deck. |
| CrewBehavior | `scripts/crew/crew_behavior.gd` | done | Node (added by Main). Autonomous crew movement per state; honours accepted directives via `hold_room_until`; panic overrides; FROZEN (Catatonic) treated like INCAPACITATED. An otherwise-IDLE crew member now defers to CrewSchedule (work/meal/recreation/sleep) — see `_decide_idle_schedule`; priority is incapacitated/frozen > panic > needs (sleep/eat/boredom-work) > an in-progress repair assignment > an accepted directive's hold > the schedule. EATING now correctly paths to "mess" (was "quarters" — a latent bug the schedule work surfaced). |
| CrewSchedule | `scripts/crew/crew_schedule.gd` | done | RefCounted static utility (same shape as CrewStateMachine/NeedsModel). Ship-wide day cycle (`DAY_LENGTH`=360s at 1x) split into work/meal/recreation/sleep phases; `phase_for(crew)` applies a small stable per-crew time jitter so the crew doesn't transition in lockstep. `check_phase_transition()` (called from CrewBehavior's tick) emits the corpus's shift_start/shift_end/meal_time/quiet_shift `recent_event`s on each GLOBAL (unjittered) phase change. `recreation_room_for()` sends idle crew to their side project (`side_projects.gd`), their accepted romance partner's room, or the mess. `repair_duty_room()` is what makes an in-progress repair job outrank recreation. |
| SideProjects | `scripts/crew/side_projects.gd` | done | RefCounted static utility (predecessor's checkpoint stub, unmodified — reviewed and kept as-is). Small data-driven hobby list (tinkering/reading/exercise/plant/cards/journaling); a hobby is assigned once per crew member (`GameState.crew_side_projects`, stable for the run) and resolves to a room TYPE CrewSchedule routes them to during recreation. |
| RepairBehavior | `scripts/crew/repair_behavior.gd` | done | Node (added by Main). Crew-side decision of WHETHER to start a repair job (reactor/life_support/ai_core) — requires an on-scene skilled crew member; ai_core repair is additionally trust-gated. Lives in crew-behaviour space, not `scripts/ai/`, per Rule 1. |
| AICoreSystem | `scripts/ai/ai_core_system.gd` | done | Node (added by Main) + static helpers. AI's own degraded-mode self-limits: door-unlock lag, rotating sensor gaps, directive-issue latency. Blackout gating (`GameState.ai_core_can_act()`) is checked directly by AISystem/Door. |
| CrewLifecycle | `scripts/crew/crew_lifecycle.gd` | done | Static utility. Single funnel for crew death (any cause) → `is_alive=false` + `crew_died` emission, so needs-collapse/Death-Save/suffocation/sabotage deaths are all consistent. |
| Checks | `scripts/core/checks.gd` | done | Static utility. THE roll-resolution utility (docs/rules.md pattern): d100 stat/save checks, advantage/disadvantage netting, doubles/00/90-99 criticals, Panic Checks, Rest Saves. `perform_check()` auto-applies Stress-on-fail + Panic-on-crit-fail + environmental adv/disadv for any CrewMember. |
| PanicTable | `scripts/core/panic_table.gd` | done | Static utility. Full d20 Panic Table; mechanical mappings for adrenaline/freeze(FROZEN)/jumpy/overwhelmed/rage/heart-attack, Condition tags for the rest, "RETIRE" → permanent incapacitation. |
| WoundTable | `scripts/core/wound_table.gd` | done | Static utility. Full 10×5 Wounds Table (bleeding/stress/stat-penalty/death-save effects transcribed from rules.md) + Death Save table; `CrewMember.apply_damage()` drives it. Dormant today (no live combat resolver calls it yet) but exercised live via SuffocationModel. |
| Items | `scripts/core/items.gd` | done | Static registry. Weapons/armor/tools from rules.md tables + mechanical `tags` (door_bypass_bonus/_time_mult, repair_bonus, medical_bonus) that Checks call sites read via `CrewMember.item_bonus()`. Per-class default loadouts. |
| CrewGen | `scripts/procedural/crew_gen.gd` | done | Static generator. Seeded (GameState.ship_seed + slot index) full Mothership character rolls — class adjustments, skills, equipment, names/pronouns. Dimensional archetype support (docs/dialogue_spec.md: personality×gender×career×rank; career maps 1:1 to class) as an OPTIONAL soft dependency: stat/save tendencies as flat roll modifiers, names[] pick, preferred_skills prioritized within class rules. `generate_roster()` guarantees command/engineering/medical role coverage, EXACTLY ONE captain-rank member, and never an Android captain. |
| IsoKit | `scripts/ship/iso_kit.gd` | done | Static utility. Legacy-kit metrics (130×65 diamond @ canvas (256,311)), cell→deck projection, anchored sprite factory, z-order. |
| ShipLayoutGen | `scripts/procedural/ship_layout_gen.gd` | done | Static generator. Seeded procedural ship layout ("freighter" ruleset implemented). Builds a ShipConfig AND calls `DeckPlan.load_plan()` with the matching visual dataset (rects, props, walls, hull polygon, etc). See 2026-07-09 session note for the full ruleset. |
| DeckPlan | `scripts/ship/deck_plan.gd` | done | Static data CONTAINER (refactored from hardcoded consts). Filled at scenario start by `ShipLayoutGen.generate()` via `load_plan()`: room rects, per-type floor tints/tiles, props, walkways, tubes, door cells, hop waypoints, wall segments, hull polygon. Same accessor API as before (`room_rect`, `room_center`, `random_point`, `hop_waypoints`, `deck_bounds`, `has_room`) so downstream consumers (RoomBase, ShipLayoutBuilder, CrewMemberNode) are unchanged. |
| RoomBase (visual) | `scripts/ship/room_base.gd` + `scenes/rooms/RoomBase.tscn` | done | Composes floor tiles (per-type tile via `DeckPlan.floor_tile_for()`) + props from DeckPlan/IsoKit; positioned at DeckPlan.room_center. |
| DeckCamera | `scripts/ship/deck_camera.gd` | done | Camera2D (added by Main as a sibling of ShipDeck). Auto-fits `DeckPlan.deck_bounds()` to the viewport as the default zoom (same formula the old static ShipDeck-scale fit used). Mouse-wheel zoom toward the cursor (clamped 0.5x-2.5x of the fit zoom); left/middle/right-drag pan (left has a ~6px threshold so click-on-crew still works — it never marks the event handled, so DirectiveMenu's own press handling is unaffected either way); WASD/arrow keys + a small edge-scroll. Panning is clamped via Camera2D's own `limit_left/top/right/bottom` (built from `deck_bounds()` + margin) — cooperates with the zoom clamp for free, since Godot centers the view once it's bigger than the limit rect (zoomed fully out = deck centered). |
| Starfield | `scripts/ship/starfield.gd` | done | Node2D, wrapped in its own CanvasLayer (layer -10, added by Main) rather than merely being a ShipDeck sibling — needed once DeckCamera exists, since a Camera2D's transform affects the whole viewport's canvas, not just its own subtree, so CanvasLayer is the only thing that stays screen-fixed. Procedural 3-layer parallax starfield; each layer draws its stars once via `_draw()` and only ever translates (sine drift + an optional tiny DeckCamera-pan-driven parallax nudge) — no per-frame redraw. z_index -1000 within its own layer. |
| Ship hull silhouette | `scripts/ship/ship_layout_builder.gd` (`_build_hull`) | done | Polygon2D + Line2D built from `DeckPlan.HULL_POLYGON` (nose taper + per-row flanks + aft engine block, generated in ShipLayoutGen). z_index -10/-9, behind floors, in front of the starfield. |
| Semi-transparent walls + door gates | `scripts/procedural/ship_layout_gen.gd` (wall segments) + `scripts/ship/door.gd` | done | Generator emits per-room boundary wall tiles (skipping connected edges); front-facing (SE/SW) walls render more transparent than back-facing (NE/NW) since painter's order draws them over the interior. Door gate sprite recolours red/green via `Door.refresh_gate_visual()` on lock/unlock. |
| QuarantineMonitor | `scripts/scenarios/quarantine_monitor.gd` | done | Node (added by Main). Timed medbay-occupancy logic that sets `vasquez_isolated`/`pathogen_contained`; drives `objective_changed`. Resolves "the infected crew member"/"the medic" via `GameState.get_crew_of_role()`, not hardcoded ids — works with any procedurally generated roster. Containment success now also emits `recent_event("crisis_resolved", ...)` — dialogue/relationship-facing (see DialogueSystem/RelationshipGraph). |
| DirectiveActionHandler | `scripts/ai/directive_action_handler.gd` | done | Node. Executes movement for directives the crew *accepted* (`move_to_room`). Respects Rule 1. |
| DirectiveMenu | `scripts/ui/directive_menu.gd` + `scenes/ui/DirectiveMenu.tscn` | done | CanvasLayer. Click-on-crew select + contextual destination menu → `AISystem.issue_directive`. Hit-testing compares in world space (crew `global_position` vs. the CanvasLayer's mouse position converted via `get_canvas_transform().affine_inverse()`); the selection ring/menu popup convert a crew node's world position to screen space via `get_global_transform_with_canvas()` — both needed to stay correct now that DeckCamera can pan/zoom. |
| NeedsModel | `scripts/crew/needs_model.gd` | done | Static utility. Per-tick hunger/fatigue/fear/loneliness/boredom/morale. Fear's O2-scarcity term now reads per-room air (LifeSupportModel) instead of the old ship-wide oxygen bar. |
| SuffocationModel | `scripts/crew/suffocation_model.gd` | done | Static utility. Mothership oxygen survival rules: room air < critical threshold → Body Save every ~round or a Death Save (via WoundTable), through Checks. Androids exempt. |
| CrewStateMachine | `scripts/crew/crew_state_machine.gd` | done | Static utility. Priority-based state eval with hysteresis; adds FROZEN (Catatonic) and INCAPACITATED triggers for retired/unconscious/dying/comatose Mothership states. |
| CrewSystem | `scripts/crew/crew_system.gd` | done | Autoload. Ticks all crew (needs, suffocation, death-clock resolution, state eval); propagates reactor/life-support/power/ai-core crises into fear spikes. |
| PersonalityCore | `scripts/crew/personality_core.gd` | not started | Traits, fears, values, goals — CrewMember already carries `traits`/`fears`/`values`/`goals` arrays (main.gd seeds a couple per role) and the dialogue-spec archetype (personality×gender×career×rank) now stands in for most of what this would formalize; still nothing dedicated. |
| RelationshipGraph | `scripts/crew/relationship_graph.gd` | done | RefCounted static utility (Checks/CrewStateMachine/NeedsModel shape) over `GameState.crew_relationships` (per-pair affinity -1..1 + flags + romance_stage, Rule 3). Moves affinity on a small legible set (praise/apology/insult/banter/etc via `on_line_spoken`, conversations completed, shared crisis survived, snapped-at-while-panicking, romance accept/reject) and drives the romance_hint→romance_advance→romance_accept/reject stage machine (`can_hint`/`can_advance`/`would_accept`, personality-flavoured thresholds from the archetype tag prefix, rejection cooldown, monogamy via `partner_of`). `on_crew_died` gives a surviving partner a heavy grief/stress hit. |
| RelationshipBehavior | `scripts/crew/relationship_behavior.gd` | done | Node (added by Main). Thin EventBus listener over RelationshipGraph for the social events that originate outside the dialogue system: panic bystanders (`crew_state_changed`→PANICKING), a resolved crisis (`recent_event` "crisis_resolved"), and a crew death (`crew_died`). DialogueSystem calls RelationshipGraph directly for per-line/per-conversation hooks since it already has speaker/target/intent in hand. |
| DialogueSystem | `scripts/crew/dialogue_system.gd` | done | Autoload (appended last in project.godot). Implements docs/dialogue_spec.md's "Runtime selection" formula exactly: hard filters (panic/stress bounds/wounded/reply_to_intents/the romance gate) kept separate from scored terms (weight + 2.0 event + 1.0 location + 1.0 target + 1.0 mood + 0.5 stress-band-closeness − 5.0 repetition-in-10min), weighted-random pick among the top-scoring tier. Loads archetypes/lines/conversations defensively (skip+log invalid, keep whatever loaded — 24 archetypes/1376 lines/22 templates load cleanly today). Declarations fire from a per-crew idle timer scaled by stress and are always rendered as thoughts. Conversations: a periodic per-room scan (chance weighted by CrewSchedule phase) prefers a matching template (participants by tag or career/rank code, same-intent/type substitution when the referenced archetype isn't the one actually present) else builds an emergent opener→reply→…→closer chain (3-6 parts); every turn re-checks both participants are still present/alive/not panicking. |
| AIDirective | `scripts/ai/ai_directive.gd` | done | Resource. Type/target/content/confidence/priority/tags + hidden intent fields. |
| AccessLevel | `scripts/ai/access_level.gd` | done | Constants + static checks. 8 domains, 4 levels; type→min-access mapping. |
| TrustModel | `scripts/ai/trust_model.gd` | done | Static utility. Named delta constants; modify() and modify_all() helpers. |
| ObedienceEngine | `scripts/ai/obedience_engine.gd` | done | RefCounted. Suspicion tracking, deviation log (cap 20), cover-up attempt, auto-restrict at 0.85. |
| DirectiveEvaluator | `scripts/ai/directive_evaluator.gd` | done | Static utility. trust × type_modifier ± morale/willpower ± conflict penalty → probabilistic comply. |
| AISystem | `scripts/ai/ai_system.gd` | done | Autoload. Directive lifecycle, ObedienceEngine orchestration, trust propagation on outcomes; blocked outright during AI-core blackout, delayed during degraded mode (AICoreSystem). |
| ScenarioEvent | `scripts/scenarios/scenario_event.gd` | done | Resource. Event with conditions, outcomes, tone range, weight, cooldown. Outcome vocabulary extended with `reactor_failure`/`life_support_failure`/`ai_core_damage`/`ai_core_repair`/`ship_destroyed` stub hooks. |
| EventPool | `scripts/scenarios/event_pool.gd` | done | RefCounted. Weighted draw filtered by tone + conditions + cooldown; `resource_below/above` conditions now read `GameState.get_metric()`. |
| ScenarioDirector | `scripts/scenarios/scenario_director.gd` | done | Autoload. Hidden meta-layer; tension/tone drift; probabilistic event pacing; `resource_delta` outcome now routes through `GameState.adjust_metric()`. |
| ScenarioRunner | `scripts/scenarios/scenario_runner.gd` | done | Autoload. Win/lose detection (all crew dead / ship destroyed / AI decommissioned — via crew-vote OR sustained blackout-with-no-repair-willingness), end-of-leg situational delta via `GameState.adjust_metric()`, scenario handoff stub. |
| QuarantineScenario | `scripts/scenarios/quarantine_scenario.gd` | done | Static builder. 6 events, 3 acts; crew referenced by ROLE not hardcoded id (works with procedurally generated rosters); life-support-contamination escalation now triggers a real `life_support_failure`. |
| NarrowPassageScenario | `scripts/scenarios/narrow_passage_scenario.gd` | done | Static builder (scenario-bible 1.2, Tier 1). Approach warning → mandatory reactor shutdown (early comply = trust credit, hot at the boundary = emergency scram + trust cost) → battery crossing under the 3-powered/3-life-supported room caps → relight/timer exit → reactor restart → `passage_cleared`. ALL monitor timings/thresholds/trust knobs live in the config's `monitor` section (Director-AI-retunable data, not monitor constants). Selected via `SHIPAI_SCENARIO=narrow_passage`; quarantine stays the default. |
| NarrowPassageMonitor | `scripts/scenarios/narrow_passage_monitor.gd` | done | Node (added by Main for the narrow passage only; `setup(config)` shares the builder's dictionary). Clockwork for the timed beats: shutdown-compliance window, scripted `field_turbulence` scares (battery drain + crossing extension — pool-drawn extras converge on the same handler), fragile-patient stability meter (Checks Body Saves, thin-air disadvantage automatic, medic-at-bedside advantage, `WoundTable.death_save` at zero), battery-exhaustion stranded ending (`destroy_ship` after a dark-drift grace), early-relight exit, resolution trust grading (patient/bridge/battery-margin). Never sets crew state (Rule 1); additive EventBus connections only. |
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
2026-07-10 (session 6, scenario content): THE NARROW PASSAGE — second playable scenario
(scenario-bible 1.2, Tier 1), the first to dramatize the power/air triage puzzle the
2026-07-10 session-3 systems shipped (reactor-offline battery budget, MAX_BATTERY_ROOMS=3,
the SEPARATE MAX_LIFE_SUPPORT_ROOMS=3 air pool, the life-support-room-unpowered auto-fail
cascade). New files: scripts/scenarios/narrow_passage_scenario.gd (static builder, the
QuarantineScenario shape) + narrow_passage_monitor.gd (Monitor pattern).

STRUCTURE (all timings/thresholds/trust knobs are DATA in the builder config's "monitor"
section, not monitor constants — deliberate, so the planned Director-AI layer can retune/
stretch a scenario without touching monitor code): quiet_shift recent_event at 6s (the calm
before) -> shear_field_detected at 12s (flags narrow_passage_active + reactor_shutdown_
ordered; the HUD grows a flag-gated "TAKE REACTOR OFFLINE" button) -> shutdown deadline at
50s. Complying early is the AI's own choice (+0.02 trust all, event reactor_shutdown_
complied); still hot at the boundary = emergency scram (-0.06 trust all, fear spike). The
crew can complicate compliance: RepairBehavior's engineer will happily relight a deliberately
cold reactor before entry (bible: the engineer WANTS an early relight) — the counter is
re-pressing the shutdown control before the boundary. Field entry -> crossing on battery
(base 110s), medic_appeal at entry+8s, scripted field_turbulence at entry+25/60/90 (-8
battery, fear 0.05, +8s crossing extension each; the same event is also pool-drawable, and
both firing paths converge on one monitor handler for the extension). Battery<=0 mid-field =
ship_stranded event, 20s dark-drift grace, then GameState.destroy_ship("stranded_in_shear_
field") — the bible's BatteryWatchMonitor folded in. Exit on timer, or at relight+10s if the
engineer completes the reactor RepairModel job mid-field. Win flag passage_cleared requires
field_exited AND reactor back online (brief's "exit -> reactor restart -> resolution"; a
relight-then-exit resolves immediately). Resolution grading: patient alive -> medic +0.05;
bridge powered >=60% of the crossing -> captain +0.03 else -0.04 (the captain's "bridge and
engine room" order is real); lowest-battery-seen >=40 -> all +0.02, <=10 -> all -0.02.

THE PATIENT (bible Act 2): the general-role crew member is CAST at boot (main.gd._place_crew,
setup-time state like the existing needs/fears seeding — the running scenario never sets crew
state, Rule 1): starts unconscious in the medbay (unconscious_until=900s) alongside the medic
(whose start room was already medbay). Monitor-scoped stability meter 0-100: danger whenever
medbay is unpowered OR air < 40 (the Mothership disadvantage threshold); each 12s of danger =
a real Checks Body Save (thin-air disadvantage folds in automatically; medic present in the
room = advantage) — failure -30 stability, even success -8 (the room is cold); safe medbay
recovers +4/s. Stability 0 = WoundTable.death_save (survivors reset to 40; SuffocationModel's
air-recovery stabilize() is the rescue for a "dying" result). Patient death does NOT gate the
win (bible: "you can clear the field with a dead patient, and the game lets you live with
that, on purpose") — it fires patient_lost (-0.05 trust all + medic -0.12) and darkens the
success banner.

SCENARIO SELECTION: SHIPAI_SCENARIO env var (quarantine default, narrow_passage; unknown
values warn + fall back) — main.gd adds only the selected scenario's monitor and passes the
SAME config dictionary to ScenarioRunner.start_scenario() and monitor.setup(), so builder
data and monitor behaviour can't drift. AUTODEMO: SHIPAI_AUTODEMO=1 + SHIPAI_SCENARIO=
narrow_passage plays the win line with real player-analogue calls (comply early, power
engine_room+medbay ONLY — two rooms, the drain margin a thoughtful player finds — air
medbay/engine_room/bridge, re-secure after the engineer's premature relight, INSTRUCTION
directive engineer->engine_room with 8s refusal retries), self-paced off scenario flags (not
wall-clock) and self-quits on scenario_ended. recent_events fired: quiet_shift (monitor,
scripted), reactor_failure/life_support_failure/power_low (automatic via the EventBus funnel
from the real system failures), crisis_resolved (automatic via system_repaired when the
reactor relights / life support is restored at resolution).

hud.gd integration (minimal): flag-gated reactor-shutdown button in the power panel
(reactor_shutdown_ordered + reactor still online; any future scenario can reuse the flag),
narrow-passage EVENT_TEXT entries, scenario-keyed success banner ("scenario_started" feed
line is now dynamic from GameState.scenario_id), panel refresh on scenario_event_triggered
so flag-gated controls appear/disappear on time.

VERIFIED (Godot 4.7 headless, SHIPAI_SEED=42): --headless --import clean; quarantine plain
run (900 frames + a 20s realtime run) — zero errors, unchanged behaviour; quarantine
autodemo still reaches MISSION COMPLETE; narrow-passage plain run (95s, idle player) — full
forced-scram beat chain fires (detected -> scram -> entry -> LS cascade -> appeal ->
turbulence -> patient_crashing), no script errors; narrow-passage autodemo -> ENDED: SUCCESS
end-to-end twice (once through the scram path when the engineer's early relight was left
uncorrected — emergent, kept as a feature — once through the clean re-secure path).

Known limitations / judgment calls: (1) The bible's event table scripts the reactor_failure
at t=0; the approach/compliance window is a deliberate deviation to make the shutdown an AI
choice (the brief's early-comply-vs-forced beat) — the shutdown is still mandatory. (2) On
relight/resolution the monitor scripted-restores life support (the "failure" was a power cut,
not damage — legible reverse of the entry cascade); the gamble-on-the-field-clearing player
therefore pays in crossing-time disadvantage/suffocation risk, not in a post-scenario repair
chore. (3) The patient is modelled as unconscious (a monitor stability meter + real Body/
Death Saves) rather than carrying an actual Wound — WoundTable rolls at cast time risked
random instant deaths; noted as a gap vs the bible's "wound/low health state set at scenario
start". (4) The captain's directive is delivered through event text + resolution grading,
not a live DirectiveEvaluator exchange (the AI never "informs the Captain of the real
tradeoff" — bible dilemma 3's third option has no mechanical surface yet). (5) A pre-existing
art gap (gen2 set missing several platform_* walkway sprites, IsoKit warns + skips) surfaced
once in stderr on the first post-import run — unrelated to this work, cosmetic only.

2026-07-10 (session 3): Mothership 1e rules adoption + situational resource rewrite (Agent 3
of the overhaul/mothership-rewrite branch). THE RESOURCE BARS ARE GONE — the normalised
oxygen/power/food/water/fuel/spare-parts/medicine dictionary on GameState, ResourceTick's
per-tick drains, and the HUD bar column were all removed in favour of a situational model:

POWER — GameState.reactor_online: while true, every room is powered for free. On failure
(GameState.damage_reactor / scenario outcome "reactor_failure") the ship falls to a battery
budget: battery_charge/battery_capacity (0-100), the AI diverts power room-by-room via
GameState.set_room_powered() with a hard cap (PowerModel.MAX_BATTERY_ROOMS=3) and a drain
rate that scales with powered-room count (PowerModel.tick, driven by the ShipSystemsTick
autoload — the renamed ResourceTick, project.godot updated in place at the same load-order
slot). Signals: power_mode_changed, reactor_failure, room_power_changed, battery_changed,
power_low (edge-triggered at 25%). Unpowered rooms: doors AI-inoperable (Door.ai_unlock
checks both rooms' power); room_power_changed is emitted for the visual layer to hook
dimming later (nothing consumes it visually yet — deliberate, per spec).

LIFE SUPPORT — same shape: GameState.life_support_online; on failure per-room air quality
(room_air, 0-100) degrades over ~4 min (LifeSupportModel.tick), the AI keeps up to 3 rooms
supported via set_room_life_supported(). Life support auto-fails if its own room loses
power (legible power->air cascade). Air thresholds implement rules.md "Survival Conditions
> Oxygen": <40 = all checks at Disadvantage (fed automatically into every Checks roll via
CrewMember.has_environmental_disadvantage), <15 = SuffocationModel forces a Body Save per
~10s round, failure -> Death Save (WoundTable). Androids exempt. Signals:
life_support_mode_changed, life_support_failure, room_air_changed.

MOTHERSHIP CHARACTERS — CrewMember rewritten: Strength/Speed/Intellect/Combat (2d10+25),
Sanity/Fear/Body saves (2d10+10), class (Marine/Android/Scientist/Teamster) with exact
rules.md adjustments, max_health (1d10+10), wounds/max_wounds, bleeding_per_round,
conditions[], stress (starts 2, min 2, cap 20 w/ overflow -> sanity penalty), skills
{name->Trained/Expert/Master}, inventory/equipped_weapon/armor_item, archetype_tag + rank +
pronouns for the dialogue layer. The old needs simulation (hunger/fatigue/fear/etc) is KEPT
— it drives CrewBehavior; Mothership Stress/Panic is the discrete-crisis layer on top.
scripts/core/checks.gd is THE roll-resolution utility (rules.md pattern 1:1): d100
roll-under, doubles=crit, 00 auto-crit-success, 90-99 auto-fail, 99 crit-fail, adv/disadv
net-cancel; perform_check(crew, stat, skill, adv, disadv, extra_bonus) auto-applies +1
Stress on failure and a Panic Check (d20 vs stress -> PanicTable) on crit-fail. PanicTable
maps all 20 rows (adrenaline/catatonic-FROZEN-state/jumpy/overwhelmed/rage/heart-attack
mechanically; esoteric rows as condition tags; RETIRE = permanent incapacitation).
WoundTable transcribes the full 10x5 wound grid + Death Save; CrewMember.apply_damage()
implements the rules.md damage flow (wound at <=0, health reset, carryover). Items
(scripts/core/items.gd) holds rules.md weapons/armor/tools with mechanical tags
(door_bypass_bonus/_time_mult, repair_bonus, medical_bonus) + per-class loadouts.

CREW GENERATION — scripts/procedural/crew_gen.gd: CrewGen.generate_roster(ship_seed, count,
required_roles) rolls full Mothership characters seeded from ship_seed+slot (reproducible,
same contract as ShipLayoutGen). Dimensional archetypes per the UPDATED dialogue_spec.md
(personality x gender x career x rank; career->class 1:1; schema: dimensions{}, names[],
stat/save_tendencies as flat roll modifiers, preferred_skills prioritized within class
skill rules) are an optional soft dependency — zero archetype files still generates fine;
legacy pre-dimensional files are skipped. Hard rules enforced: >=1 command/engineering/
medical-skilled member per roster, EXACTLY ONE captain-rank member, Android can never be
captain. main.gd now spawns the quarantine crew this way; QuarantineMonitor + autodemo +
KEY_D resolve crew by ROLE via new GameState.get_crew_of_role() instead of hardcoded ids.

DOORS — locked doors now actually block crew pathing (CrewMemberNode.move_to_room passes
get_locked_doors() as blocked_doors). A blocked crew member attempts a manual bypass
(Door.attempt_crew_bypass): Intellect check + best tech skill (Hacking/Computers/
Engineering/Mechanical Repair) + item bonuses through Checks. Crit success ~1.5s, success
~6s, plain failure still opens it but ~45s + Stress, crit failure JAMS the door (purple
gate tint, AI can't unlock a jammed door, crew retries after 8s). Cutting torch halves
times; crowbar/toolkit add flat bonuses. Signals: door_locked_on_crew (fires per attempt),
door_bypass_started(eta), door_bypass_result(success, critical). Every 3rd lockout on the
same door costs AI trust (TrustModel.DISOBEDIENCE_MINOR).

AI CORE — GameState.ai_core_integrity (0-100) -> ai_core_status online/degraded(<50)/
blackout(0 or manual shutdown). Degraded (AICoreSystem): door-unlock lag 4s, 2 rotating
sensor-gap rooms (GameState.ai_core_sensor_gap_rooms — the HUD/dialogue can treat those
rooms' occupancy as unknown), directive routing latency 2.5s. Blackout: AISystem.
issue_directive returns false, Door.ai_unlock refused, power/air diversion refused
(ai_core_can_act), HUD shows a full-screen input-swallowing "CORE OFFLINE + elapsed"
overlay. Repair is check-based over time (RepairModel ticks GameState.repair_jobs;
progress via Intellect+Engineering-family skills + repair_bonus items) but WHETHER anyone
repairs is decided in crew space (RepairBehavior, scripts/crew/ per Rule 1): needs a
skilled crew member physically in the target room; ai_core repair additionally refuses
below 0.35 average trust (repair_refused signal). Damage sources wired: scenario outcomes
(ai_core_damage/ai_core_repair/reactor_failure/life_support_failure/ship_destroyed added to
ScenarioDirector's outcome vocabulary), GameState.damage_ai_core() as the stub hook for
future fires/breaches/sabotage. The AI core runs on its own isolated cell — ship battery
death does NOT black out the player (deliberate: the blackout lose-path stays trust-driven,
not power-driven). Lose condition wired in ScenarioRunner: blackout + nobody repairing +
avg trust < 0.35 sustained 90s -> "ai_decommissioned" (alongside the existing crew-vote
path); lose set is now all-crew-dead / ship_destroyed / ai_decommissioned (oxygen-bar lose
removed). Scenario end-of-leg deltas migrated from resource_delta_* dicts to leg_delta_*
via GameState.adjust_metric ("battery_charge", "ai_core_integrity"); EventPool
resource_below/above conditions read GameState.get_metric.

DIALOGUE HOOKS (for Agent 2): EventBus.recent_event(event_id, data) is a single funnel
carrying the spec vocabulary — crew_death, injury, reactor_failure, power_low,
life_support_failure, door_locked_on_crew, ai_damaged, repair_success — forwarded from the
specific typed signals in EventBus._ready(). Also new: crew_stress_changed, crew_panicked
(with panic-table effect string), crew_injury, repair_started/progress/refused. Crew
surface for line conditions: crew.stress, crew.current_state ("panicking"/"frozen"),
crew.wounds>0, crew.morale (mood), crew.location + GameState.rooms[loc].room_function,
crew.archetype_tag, crew.rank, crew.role.

MOTHERSHIP ADOPTION MAP (rules.md section -> status): Dice/roll pattern IMPLEMENTED
(Checks, incl. 0-99 percentile convention + doubles/00/99). Stats/Saves/Classes/class
adjustments IMPLEMENTED (CrewGen). Trauma responses STUBBED (class stored; per-class
trauma triggers not wired into panic flow yet). Health/Wounds/Wound Table/Death Saves
IMPLEMENTED (WoundTable; live trigger today is suffocation only — no combat resolver
calls apply_damage yet; bleeding_per_round accumulates but no per-round bleed ticker).
Skills + tiers IMPLEMENTED (flat bonuses via get_skill_bonus; prereq chains simplified to
a documented MASTER_PREREQS table). Stress & Panic IMPLEMENTED (gain-on-fail, min-stress,
overflow; full Panic Table with mapped/stubbed rows as listed); Rest Save IMPLEMENTED
(Checks.rest_save) but nothing calls it yet. Shore Leave/Ports/credits NOT IMPLEMENTED
(no economy). Combat/weapons/armor DATA-ONLY (Items registry; no combat loop). Survival:
Oxygen IMPLEMENTED (per-room air adaptation), Bleeding PARTIAL, radiation/cryo/exhaustion/
food-water/temperature NOT IMPLEMENTED. Contractors NOT IMPLEMENTED. Warden-arbitration
points surfaced as warden_arbitration flags in WoundTable data + comments.

Known limitations / risks: (1) still no Godot binary — statically validated only
(EventBus signal cross-check, GameState member cross-check, bracket balance, class_name
uniqueness, per-file review); first editor open regenerates the script class cache for the
13 new classes. (2) HUD room panel refreshes wholesale on room_air_changed (up to ~48/sec
during a life-support failure with ~12 rooms) — fine at this scale, batch later if it
shows up in profiling. (3) CrewBehavior panic-flee uses get_neighbours() without
blocked_doors, so a panicking crew member can pick a locked-door neighbour and stall into
a bypass attempt — arguably good drama, noted as intentional-ish. (4) crew_relationship_
changed/system_damaged/system_power_changed remain declared-but-unemitted (pre-existing).
(5) Door bypass timers use scene-tree timers, which don't pause with TimeManager pause —
pre-existing pattern (directive latency ditto), acceptable for now.

2026-07-10 (session 4, Agent 4 — camera + collision): Added DeckCamera (scripts/ship/
deck_camera.gd), replacing the static ShipDeck scale/position fit with a real Camera2D:
auto-fits deck_bounds() as the default zoom, wheel-zoom toward the cursor (clamped
0.5x-2.5x of fit), drag/WASD/edge-scroll pan clamped via Camera2D's own limit_* (built
from deck_bounds()+margin, which cooperates with the zoom clamp for free — zoomed fully
out centers the deck). Starfield had to move into its own CanvasLayer (layer -10) since a
Camera2D affects the whole viewport's canvas, not just its subtree — the old "just don't
parent it under ShipDeck" trick only worked because there was no camera at all before.
DirectiveMenu's click-on-crew hit test and ring/menu placement now convert explicitly
between crew world-space and its own CanvasLayer's screen space instead of assuming
they're the same coordinate system. Separately, CrewMemberNode gained soft O(N²)
perpendicular-biased separation steering (personal radius ~half a tile, clamped to the
current room/walkway-union bounds) and a static standing-point claim registry, so crew no
longer walk through or stack on each other; both are pure position nudges layered on top
of the existing route-walking state machine, so they can't stall a route, fight
panic-flee, or fight hold_room_until. No Godot binary available this session either —
validated statically only (bracket/indentation balance, class_name uniqueness, Godot 4
Camera2D/Transform2D API cross-checked against known semantics); first editor open will
need to regenerate the script class cache for the new DeckCamera class.

2026-07-10 (session 5, Agent 2 — crew simulation: schedule, relationships, dialogue,
bubbles): Rebuilt the CREW SIMULATION workstream from the interrupted predecessor's
checkpoint (781348b — a side_projects.gd stub + event_bus/game_state scaffolding for
crew_relationships/crew_side_projects, kept and built on rather than replaced) into four
verified subsystems, each its own commit.

SCHEDULE (scripts/crew/crew_schedule.gd) — a ship-wide day cycle (DAY_LENGTH=360s at 1x:
work 0-45%, meal 45-55%, recreation 55-75%, sleep 75-100%; a small stable per-crew time
jitter, `_crew_jitter`, keeps transitions from snapping in lockstep) layered onto
CrewBehavior's existing IDLE branch — CrewStateMachine/NeedsModel were extended, not
replaced. Priority order (highest first): incapacitated/frozen > panic > needs-driven
states (sleep/eat/boredom-work, unchanged, still computed first in CrewBehavior's outer
match) > an in-progress repair assignment (CrewSchedule.repair_duty_room — makes
RepairBehavior duties outrank recreation, since RepairBehavior itself never moves crew,
only decides whether to start a job on whoever's already on-scene) > an accepted
directive's hold_room_until (unchanged _honouring_directive gate) > the schedule itself.
Fixed a latent bug the work surfaced: EATING was pathing to "quarters" instead of "mess".
CrewSchedule.check_phase_transition() (called once/tick from CrewBehavior) emits the
corpus's shift_start/shift_end/meal_time/quiet_shift `recent_event`s on each GLOBAL
(unjittered) phase change — these had text in ~30+ corpus lines but no emitter before this
session. Side projects (the predecessor's stub, reviewed and left as-is) bias recreation
location; couples (see below) preferentially spend recreation together via
`recreation_room_for`'s partner-join check.

RELATIONSHIPS & ROMANCE (scripts/crew/relationship_graph.gd + relationship_behavior.gd) —
GameState.crew_relationships (per-pair, pair_key sorted so it's order-independent):
affinity -1..1, flags[], romance_stage ("none"|"hinted"|"advancing"|"accepted"),
rejected_until. RelationshipGraph is a pure static utility (Checks/CrewStateMachine/
NeedsModel shape); RelationshipBehavior (Node, added by Main) is the thin EventBus
listener that decides WHEN to call it for social events outside the dialogue system.
WHAT MOVES AFFINITY (the "small legible set"): conversation completed +0.02; per-line
intent when a line has a resolvable specific addressee — praise/reassurance/offer_help
+0.03, apology +0.04, banter/gallows_humor/grief +0.02, insult -0.06, complaint -0.02,
warning -0.01 (DialogueSystem calls RelationshipGraph.on_line_spoken for every such line);
snapped at while panicking -0.04 (bystanders in the panicking crew member's room, on the
first PANICKING transition); a resolved ship-wide crisis +0.05 for every living pair
(recent_event "crisis_resolved" — see below); romance accepted +0.15, rejected -0.05.
ROMANCE ARC: romance_hint -> romance_advance -> romance_accept/reject, all driven by
`on_line_spoken` the moment a romance-intent line is actually spoken (not gated on the
conversation completing) — can_hint()/can_advance() require both crew unpartnered, no
active track between them, affinity above a threshold (0.40, personality-flavoured: ±0.03
to +0.08 by the archetype tag's personality prefix — cheerful hints more readily,
paranoid holds back more), and past any post-rejection cooldown (240s); would_accept()
(threshold 0.55, same personality flavouring) is the hard gate DialogueSystem uses to
decide which of romance_accept/romance_reject is even a valid reply candidate. Accepting
sets a "couple" flag and fires the (previously declared-but-unemitted) crew_romance_started
signal. partner_of()/are_couple() implement monogamy. on_crew_died() gives a surviving
partner a heavy grief/stress hit (+6 stress, pain +0.4, loneliness +0.5, fear +0.3) plus a
"lost_partner" flag. The dialogue corpus's "crisis_resolved" recent_event had ~30 lines
conditioning on it but NO emitter anywhere before this session — wired in EventBus._ready()
(reactor/life-support recovery, AI core returning to online) and QuarantineMonitor
(pathogen_contained).

DIALOGUE RUNTIME (scripts/crew/dialogue_system.gd, autoload, appended LAST in
project.godot) — implements docs/dialogue_spec.md's "Runtime selection" section as close
to verbatim as the prose allows. Loads resources/dialogue/{archetypes,lines,conversations}
at _ready() with defensive parsing (every file/entry individually try-checked; malformed
entries are push_warning'd and skipped, not fatal) into per-archetype-tag line pools, a
key->line lookup (for template resolution), and career-code fallback pools ("crew with no
archetype lines fall back to any same-career pool, else stay quiet" — built once from
every loaded archetype's own pool, keyed by the tag's career dimension). Confirmed loading
cleanly: 24 archetypes, 1376 lines, 22 conversation templates. SELECTION is one shared
function, `_score(crew, line, ctx)`: hard filters (panic flag / stress bounds / wounded /
reply_to_intents-when-answering / the romance gate) return a HARD_FAIL sentinel and are
never scored, matching the spec's explicit separation; everything else adds to
`score = weight + 2.0*recent_event + 1.0*location + 1.0*target + 1.0*mood +
0.5*stress_band_closeness - 5.0*repetition(10min)`. `_pick_line` takes the max score, then
weighted-random-picks among every candidate within TOP_SCORE_MARGIN (1.0) of it, weighted
by each line's own `weight` field. DECLARATIONS (type "declaration", always target:
open_air) fire from a per-crew idle timer (12-45s, shorter under higher stress) and are
ALWAYS the "thought" side of the corpus (docs/dialogue_spec.md's Display section: "Thought
bubbles... reuse declaration lines with target: open_air") — this resolved what would
otherwise be an ambiguity between the two systems' specs. CONVERSATIONS: a periodic
per-room scan (every 4s) groups eligible crew (alive, not mid-route, IDLE/EATING/WORKING —
WORKING is included deliberately: the corpus's own "work_talk" intent implies on-shift
banter, and with one crew per duty station excluding it would make the two crew who
actually share a room while working — e.g. the quarantine's medic+patient in medbay —
unable to ever talk) by room, then rolls a chance weighted by CrewSchedule phase (0.12
if either is mid-shift, 0.65 if both are in recreation, 0.35 otherwise). REPLY-CHAINING:
a matching conversation TEMPLATE is tried first — participants matched by exact archetype
tag OR a career/rank code (_spec_matches), template-level conditions (recent_events/
stress_min/max, checked against whichever of the two crew makes it stricter) filtered,
then each line-slot resolved: if the live speaker's own archetype_tag matches the
template's referenced tag exactly, use that exact line; otherwise substitute a line of the
SAME type+intent from the live speaker's own pool ("the runtime substitutes lines of
matching intent from whichever archetype is actually present" — spec) — every resolved
line, exact or substituted, still passes through the full `_score` hard-filter check (so a
template can't force a line through panic/stress/romance-gate mismatches); a slot that
can't resolve truncates the queue (or aborts the template entirely if it's the opener).
Falling back to EMERGENT chaining: an opener from either party (whichever has one),
then alternating replies whose reply_to_intents contains the prior line's intent, 3-6
parts, preferring a closer-type line on the last planned turn (falling back to a plain
reply if none fits) so the exchange usually lands on a real goodbye rather than just
stopping. Every turn (template or emergent) re-checks both participants are still alive,
in the room, and not panicking immediately before speaking — "a panicking or departing
speaker breaks the chain" — not just at conversation start. ROMANCE GATING: any line whose
intent is romance_hint/advance/accept/reject is hard-filtered through
RelationshipGraph.can_hint/can_advance/would_accept inside `_score` itself, so the gate
applies uniformly whether the line came from a template's fast path, a template
substitution, or emergent selection. Verified via a throwaway probe scene (built, run,
then deleted — not committed) that called the (GDScript-"private"-by-convention-only)
selection functions directly with a real generated roster: template substitution, emergent
chaining, and the full romance stage machine all behaved correctly; caught one real bug
this way (a typed-Array ternary — `Array[String] x = a if cond else b` — that GDScript
accepts at parse time but rejects at runtime as "Trying to assign an array of type Array
to a variable of type Array[String]"; fixed in `_pick_reply`). Also verified live: the
quarantine AUTODEMO win run (SHIPAI_SEED=42) organically produced a real conversation
(medic Marisol <-> patient Julio in medbay: "You should eat..." -> "i'm good!..." ->
"Dismissed. Rest while you can.") without any scripted intervention, and the scenario
still completes to SUCCESS.

BUBBLES (scripts/crew/crew_member_node.gd) — one reusable Panel+RichTextLabel per crew
(built once in `_build_bubble`, called from `_ready()`, same pattern as the existing
`_status_dot`), restyled and resized per line rather than instantiated per-line. Reacts to
EventBus.line_spoken filtered to `crew_id == crew_data.crew_id`; line_type "declaration" ->
thought (italic bbcode, dimmed colour, no tail); anything else (opener/reply/closer) ->
speech (brighter text, bordered panel, a small tail polygon). World-space: a plain Node2D
child of CrewMemberNode (not a CanvasLayer), `z_as_relative=false` with a large fixed
z_index (4000) so it always draws above the sprite/props regardless of the crew's own
dynamic y-sort z — it pans/scales with DeckCamera for free, as intended. Auto-sized from a
character-count heuristic (`_estimate_bubble_size`) rather than an async
fit_content/get_content_height layout pass — deliberately, so two lines arriving close
together (e.g. three consecutive lines from the same speaker mid-conversation) can't race
each other's deferred layout; any in-flight fade tween is `kill()`'d before a new line
starts for the same reason. Held ~4-6s (base + a small per-character reading-time bonus,
capped) then fades over 0.6s. Not visually screenshotted this session (see Known
limitations below) — behaviourally verified only (no script errors across many
show/hide/re-trigger cycles in the AUTODEMO run, including the 3-line medbay exchange
above exercising the tween-kill path).

Signals added/newly-emitted (all pre-declared by the predecessor's checkpoint except the
`recent_event` crisis_resolved forwarding, which is new): line_spoken, conversation_started,
conversation_ended, crew_romance_started, crew_relationship_changed.

Known limitations / risks: (1) No Godot GUI available this session either (same as every
prior session) — verification was `--headless --import` + `--headless --quit-after N
res://scenes/Main.tscn`, both plain and with SHIPAI_SEED/SHIPAI_AUTODEMO/SHIPAI_AUTOSHOT,
checked for SCRIPT ERROR/ERROR lines, plus the throwaway probe scene described above. The
existing SHIPAI_AUTOSHOT screenshot path (main.gd's `_save_screenshot`) errors in headless
mode (`get_viewport().get_texture().get_image()` returns null under the dummy rendering
driver) — this is a pre-existing limitation of headless + screenshot capture, not
something this session introduced or could visually route around; bubble APPEARANCE
(sizing/legibility/colour) is therefore unverified by eye and worth a look in the editor.
(2) Conversations are naturally rarer than they'll eventually feel in a longer session:
NeedsModel's boredom recovers slowly under WORKING (~12+ minutes to fall back below the
IDLE threshold at default rates), so within a short headless run most crew are WORKING
(solo, one per duty station) most of the time; the quarantine scenario's own directive-
driven medbay convergence is what reliably produces a conversation quickly, which is also
why WORKING was deliberately included in dialogue eligibility (see above) rather than
excluded. (3) The recent_event window (RECENT_EVENT_WINDOW_SECONDS=180s, "last N minutes")
and the top-score tier margin (TOP_SCORE_MARGIN=1.0) are both documented judgment calls —
the spec states the repetition window exactly (10 min) but leaves these two open. (4) Template
conditions' stress_min/max are checked against whichever of the two participants makes the
condition stricter (max of the two for stress_min, min of the two for stress_max) — a
reasonable reading of "the pair's" stress with no single obviously-correct interpretation
in the spec. (5) side_projects.gd is the predecessor's stub, reviewed and kept verbatim —
its hobby->location pool is small (6 entries) and could grow later.

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