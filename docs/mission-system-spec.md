# Mission System Spec — Ship AI

> THE contract for the mission/scenario overhaul. Every implementing agent reads this
> first. Companion docs: `scenario-bible.md` (design language, 16 seed concepts),
> `director-spec.md` (the Overseer), `rules.md` (Mothership 1e mechanics).
> Status: DESIGN APPROVED — implementation in flight on `feature/mission-system`.

---

## 0. The pitch

**Missions** are the overt layer: clearly displayed objectives the ship is ordered to
carry out — meet a ship, survey a planet, deliver cargo, limp to a repair yard.
**Scenarios** are the covert layer: the complication that interweaves — the thing that
comes back on the shuttle, the thing in the cargo, the crew member who returns *wrong*.

The player (the ship's AI) sees the mission. The Overseer decides which scenario — if
any — infects it, and when. Missions chain into a voyage: each ends with an outcome
that weights what's offered next (a mauled ship gets a repair-yard mission; a crew
carrying a hidden infection gets an aftermath scenario two legs later).

**One mission = one leg.** The existing leg machinery (escalation floor, Rest Saves,
checkpoint stub) keys off mission completion, not scenario drain, when mission mode
is active.

---

## 1. Core loop

```
MissionManager picks mission (weighted deck: follow-ons + ship state + campaign flags)
  → briefing shown, objectives displayed (HUD mission panel)
  → phases: transit_out → arrival → on_station → transit_back → resolution
       │         │            │           │
       └─────────┴── scenario hooks ──────┘   (Overseer picks 0-1 scenario per hook,
                                               cap 2 concurrent, axis-compatible)
  → objectives tick off (engine-resolved kinds; scenarios can complete/fail them too)
  → resolution: outcome grade + outcome flags → rewards/penalties applied
  → leg boundary (advance_leg, checkpoint, crew progression hooks)
  → next mission drawn
```

**Away ops** (the signature mechanic): crew leave the ship — by shuttle to a surface,
or through the airlock into a docked/derelict ship. The player NEVER sees what happens.
The AwayResolver plays it out off-screen with real `Checks.perform_check` rolls against
the away team's stats/skills/equipment, narrated only by radio barks. What comes back:
the report, the survivors, the cargo… and possibly hidden `status_flags` (infected,
changed) that detonate as scenarios legs later.

---

## 2. File layout (new)

```
resources/missions/<id>.json          ← one file per mission (40+)
resources/scenarios/<id>.json         ← one file per data-driven scenario (40+)
docs/mission-catalog.md               ← human-readable index (id, title, type, hooks, follow-ons)
docs/scenario-catalog.md              ← human-readable index (id, axis, contexts, solves)
docs/asset-backlog.md                 ← art/audio needs list (doc only this sprint)
scripts/missions/mission_def.gd       ← class_name MissionDef (parsed JSON wrapper + validation)
scripts/missions/mission_manager.gd   ← autoload MissionManager
scripts/missions/mission_deck.gd      ← class_name MissionDeck (eligibility + weighted draw)
scripts/missions/away_resolver.gd     ← class_name AwayResolver (off-screen op resolution)
scripts/missions/shuttle_system.gd    ← class_name ShuttleSystem (Node, owned by MissionManager)
scripts/missions/approach_visual.gd   ← class_name ApproachVisual (planet/ship background sprite)
scripts/scenarios/scenario_catalog.gd ← class_name ScenarioCatalog (loads resources/scenarios/, replaces hardcoded registry)
scripts/scenarios/generic_monitor.gd  ← class_name GenericScenarioMonitor (data-driven monitor)
scripts/scenarios/outcome_applier.gd  ← class_name OutcomeApplier (shared outcome vocabulary — ScenarioDirector delegates here)
scripts/ship/intruder_system.gd       ← autoload IntruderSystem (room-graph hostile presence)
tools/missions/validate_content.py    ← schema/reference validator for ALL content JSON
```

Autoload additions to `project.godot`: `MissionManager`, `IntruderSystem` (after
existing autoloads; both depend on EventBus/GameState/TimeManager).

---

## 3. Mission JSON schema

```jsonc
{
  "id": "survey_kepler_verde",            // snake_case, unique, == filename
  "title": "Greenhouse",                  // short evocative title
  "mission_type": "planet_survey",        // see §3.1 type list
  "giver": "Meridian Combine",            // faction/corp handing out the job
  "briefing": "2-4 sentences, player-facing, second person addressed to the AI.",
  "flavor": "Optional 1-2 sentence log-book color.",
  "destination": {
    "kind": "planet",                     // planet | ship | station | point | home
    "name": "Kepler-Verde",
    "descriptor": "jungle world",         // drives placeholder art tint + barks
    "art": "planet_jungle"                // asset hook (placeholder generated until art lands)
  },
  "phases": {                             // seconds; any omitted = engine default
    "transit_out": 180, "arrival": 300, "on_station": 300, "transit_back": 180
  },                                      // arrival default 300 = the 5-min planet grow-in
  "objectives": [
    {"id": "reach",  "text": "Make orbit over Kepler-Verde", "kind": "reach_destination"},
    {"id": "survey", "text": "Put a survey team on the surface", "kind": "away_team",
     "params": {"site": "surface", "min_crew": 2, "suggested_skills": ["Botany", "Field Medicine"]}},
    {"id": "home",   "text": "Return to the lane with all hands", "kind": "return_home", "optional": false}
  ],
  "away_risk": {                          // only for missions with away_team objectives
    "tier": "moderate",                   // low | moderate | high | extreme
    "skill_mitigators": ["Botany", "Field Medicine"],   // canonical rules.md names
    "item_mitigators": ["hazard_suit", "medscanner"],   // Items.REGISTRY ids
    "outcome_bias": {"crew_infected": 1.5, "find_item": 1.2}   // multiplies AwayResolver beat weights
  },
  "eligibility": {
    "min_leg": 1,
    "requires_flags_all": [], "requires_flags_any": [], "excludes_flags": [],
    "min_hull": 0, "max_hull": 100        // e.g. repair missions: "max_hull": 50
  },
  "weight": 1.0,                          // deck draw weight when eligible
  "priority": 0,                          // >0 preempts the weighted draw (highest wins); use for forced repair/emergency missions
  "repeatable": false,
  "scenario_hooks": {                     // per-phase: chance a scenario attaches + context offered
    "transit_out":  {"chance": 0.35, "context": "transit"},
    "on_station":   {"chance": 0.85, "context": "planet_orbit", "tag_bias": {"bio": 1.5}},
    "transit_back": {"chance": 0.5,  "context": "aftermath"}
  },
  "rewards": {"credits": 400, "items": ["med_kit"], "metrics": {"battery_charge": 10.0}},
  "extra_outcome_flags": {                // engine always sets mission_success/partial/failed;
    "survey_data_recovered": "survey"     // extras: campaign_flag -> objective id that must be complete
  },
  "follow_ons": [                         // weights next-mission draw; "tag:x" or explicit id
    {"when": ["mission_success"], "next": ["tag:trade", "return_to_hub"], "weight": 2.0},
    {"when": ["crew_infected_aboard"], "next": ["tag:bio_aftermath"], "weight": 3.0}
  ],
  "tags": ["planet", "science", "low_stakes"]   // free vocabulary; follow_ons + hooks reference these
}
```

### 3.1 Mission types (mission_type)

`rendezvous` (meet a ship, dock, exchange) · `planet_survey` · `delivery` · `salvage`
(derelict boarding) · `repair_yard` (fix the ship — has its own scenario hooks!) ·
`distress` (answer a call) · `escort` · `passenger` (carry someone) · `mining` ·
`patrol` · `science` (anomaly study) · `evacuation` · `quarantine_run` (carry sealed
cargo) · `crew_transfer` (gain/lose crew) · `homecoming` (return to hub/station).

### 3.2 Objective kinds (engine-resolved)

| kind | completes when | params |
|---|---|---|
| `reach_destination` | arrival phase ends | — |
| `dock_with_ship` | docking_completed fires | — |
| `away_team` | shuttle/boarding party returns with op attempted | `site` (surface\|derelict\|station\|other_ship), `min_crew`, `suggested_skills` |
| `deliver_cargo` | on_station phase ends with cargo flag intact | `cargo_flag` |
| `survive_until` | phase reached with ship alive | `phase` |
| `return_home` | resolution phase entered, ship alive | — |
| `repair_to` | hull_integrity >= value | `value` |
| `keep_alive` | resolution reached, target crew alive | `role` or `"all"` |
| `scenario_flag` | named scenario flag set true | `flag` (lets a scenario BE the objective) |

Objectives with `"optional": true` don't gate success; each completed optional
upgrades the outcome grade one notch (partial→success).
Grade: all required complete = `mission_success`; ship survives but required
incomplete = `mission_partial`; mission aborted or objective hard-failed = `mission_failed`.

---

## 4. Scenario JSON schema

Generalizes the config dict `QuarantineScenario.build()` / `NarrowPassageScenario.build()`
already return — those two stay as bespoke GDScript builders registered in
ScenarioCatalog as overrides; everything new is JSON + GenericScenarioMonitor.

```jsonc
{
  "id": "the_hitchhiker",
  "title": "The Hitchhiker",
  "pressure_axis": "bio",                 // bio | systems | social | combat | mystery
  "intensity": 2,                         // 1 = unsettling, 2 = dangerous, 3 = run-ending threat
  "contexts": ["away_return", "docked"],  // see §4.1
  "trigger_status": "",                   // if set (e.g. "infected"): scenario is the DELAYED
                                          // payoff for a crew status_flag — force-queued 1-2
                                          // legs after any crew gains that flag
  "tone_start": 0.4,
  "expected_length": 240,
  "weight": 1.0,
  "min_leg": 2,
  "once_per_run": true,
  "win_flags": ["hitchhiker_resolved"],
  "leg_delta_success": {"ai_core_integrity": 5.0},
  "leg_delta_crew_dead": {"ai_core_integrity": -10.0},
  "solves": [                             // the skill/equipment paths that crack it — informational
    {"desc": "Identify the organism before it molts",   // header + drives monitor checks below
     "skill": "Xenobiology", "stat": "intellect", "items_help": ["medscanner"]}
  ],
  "events": [ /* ScenarioEvent dicts — §4.2 */ ],
  "monitor": { /* GenericScenarioMonitor program — §4.3 */ },
  "morph_edges": [
    {"to": "something_in_the_walls", "condition_flags": ["organism_escaped"], "overlap_ok": false, "weight": 1.0}
  ]
}
```

### 4.1 Contexts (the mission↔scenario interlink vocabulary — CLOSED SET)

`transit` (deep-space leg) · `arrival` (destination approach) · `planet_orbit` ·
`away_return` (fires when an away op comes back) · `docked` (another ship/station
connected at the airlock) · `derelict` (boarding a dead ship) · `station` ·
`aftermath` (return leg after something happened) · `any`.

A scenario may list several. Mission hooks offer exactly one context; the catalog
filters on it. `away_return` scenarios additionally get first refusal to INJECT
outcomes into the away report itself (see §6).

### 4.2 Events

Same fields as `ScenarioEvent` (`scripts/scenarios/scenario_event.gd`): `event_id`,
`title`, `description`, `tone_min/max`, `weight`, `min_elapsed`, `cooldown`,
`one_shot`, `conditions[]`, `outcomes[]`. Conditions/outcomes use the vocabulary in
§5 — **only** the vocabulary in §5; the validator rejects unknown types.

### 4.3 Monitor program (GenericScenarioMonitor)

```jsonc
"monitor": {
  "cast": {"host": "role:medic"},         // optional: bind names to crew for target refs
  "timers":  [{"at": 20.0, "outcomes": [...], "requires_flags": []}],
  "watches": [{"conditions": [...], "outcomes": [...], "once": true}],   // checked per tick
  "checks":  [{                            // periodic dice — the solve-path engine
    "id": "identify_organism",
    "interval": 30.0,
    "crew": "best_skill:Xenobiology",      // role:<r> | best_skill:<s> | cast:<name> | random | away_team
    "stat": "intellect", "skill": "Xenobiology", "item_tag": "medical_bonus",
    "requires_flags": ["specimen_contained"],
    "successes_needed": 2,                 // cumulative successes then fires on_solved
    "on_success": [...], "on_fail": [...],
    "on_crit_fail": [...],                 // optional; Checks handles stress/panic automatically
    "on_solved": [{"type": "set_flag", "flag": "organism_identified"}]
  }],
  "objective_text": {"start": "Something came aboard with the shuttle.",
                     "flags": {"organism_identified": "Contain the specimen in the medbay."}}
}
```

Checks route through `Checks.perform_check` — stress on failure, panic on crit-fail,
skill-crit tallies, Overseer `check_bonus` mercy all apply for free.

---

## 5. Outcome & condition vocabulary

`OutcomeApplier` centralizes this; `ScenarioDirector._apply_outcomes` delegates to it.
EventPool `_check_condition` extends likewise. **Closed set — validator-enforced.**

**Existing outcomes (keep):** `resource_delta`, `crew_fear_spike`, `set_flag`,
`spawn_event`, `ai_trust_delta`, `scenario_end`, `reactor_failure`,
`life_support_failure`, `ai_core_damage`, `ai_core_repair`, `ship_destroyed`.

**New outcomes:**

| type | params | effect |
|---|---|---|
| `crew_injury` | `target`, `severity` (light\|serious\|grave) | wound via WoundTable on selected crew |
| `crew_stress` | `target`, `amount` | add_stress |
| `crew_status_flag` | `target`, `flag`, `value` | sets CrewMember.status_flags[flag] — HIDDEN from player |
| `crew_join` | `archetype` (optional) | CrewGen generates + boards a new crew member |
| `crew_leave` | `target`, `reason` | crew departs (not death — leaves roster) |
| `crew_kill` | `target`, `cause` | outright death (use sparingly; prefer checks) |
| `grant_item` | `target`, `item_id` | add to crew inventory |
| `remove_item` | `target`, `item_id` | remove |
| `hull_damage` | `amount` | GameState.adjust_metric("hull_integrity", -amount) |
| `hull_repair` | `amount` | positive delta |
| `spawn_intruder` | `intruder_type`, `room` (room type or "random") | IntruderSystem.spawn |
| `intruder_remove` | `intruder_id` or "all" | despawn (fled/died narratively) |
| `radio_line` | `speaker` (crew target or "contact"), `text` | event-log + speech bubble if aboard |
| `objective_complete` | `objective_id` | force-complete a mission objective |
| `objective_fail` | `objective_id` | hard-fail it |
| `mission_abort` | `reason` | current mission → failed, skip to transit_back |
| `door_lock_room` | `room` (type) | lock all doors of that room (AI can unlock per existing rules) |
| `air_vent_room` | `room`, `amount` | drop room air quality |

**Target selector grammar** (`target`): `random` (living) · `role:<role>` ·
`cast:<name>` · `away_team` (most recent op's members) · `status:<flag>` · `all`.

**Existing conditions (keep):** `resource_below/above`, `flag_set/unset`,
`crew_state_count`, `ai_trust_below`, `ai_suspicion_above`.

**New conditions:** `crew_has_skill` {skill, tier?} · `item_aboard` {item_id} ·
`mission_phase` {phase} · `away_team_out` {} · `crew_status_any` {flag} ·
`intruder_present` {} · `docked` {} · `leg_at_least` {leg} · `crew_count_below` {value}
· `hull_below` {value}.

**GameState additions:** `hull_integrity` (0-100, new metric; `ship_destroyed` fires
at 0 via existing destroy path) · `credits` (metric; economy hook, rewards accumulate
it) · `CrewMember.status_flags: Dictionary` (hidden narrative state).

---

## 6. Away ops (AwayResolver)

One resolver for BOTH shuttle-to-surface and airlock-boarding. Flow:

1. AI issues an **away directive** (site, from mission objective params). Crew
   evaluate via existing ObedienceEngine — refusals possible (Architecture Rule 1:
   the AI never force-assigns). Willing crew walk to shuttlebay (surface ops) or
   airlock (boarding ops), then despawn from the deck; `shuttle_departed` /
   `boarding_started` emits.
2. Op runs `duration` (default 90-180s) of TimeManager time. During it, the resolver
   plays 2-4 **beats** at intervals. Each beat: weighted draw from the op's outcome
   table = base table for `away_risk.tier`, × mission `outcome_bias`, × attached
   `away_return` scenario injections (a scenario may REPLACE the table for one beat).
   Beat kinds: `nothing` · `find` (item/cargo/data) · `hazard` (Body/Fear save or
   relevant skill check → injury/death on fail — real dice vs the actual crew) ·
   `exposure` (hidden `crew_status_flag`) · `shuttle_strain` (return damage) ·
   `contact` (radio_line color + fear) · `survivor` (crew_join candidate).
   Each beat emits 0-1 `radio_line` barks — the ONLY live window the player gets.
3. Return: shuttle reappears with `shuttle_returned(report)`. Report lists ONLY
   observable facts (who returned, visible wounds, shuttle damage, cargo). Hidden
   flags stay hidden. Crew respawn at bay/airlock and resume the sim.
   Skills/items matter mechanically: hazard beats check the BEST relevant skill on
   the team (mitigators from mission def grant advantage; missing them = straight
   roll; `extreme` tier without mitigators = disadvantage).
4. A `lost` outcome (rare, extreme tier) strands crew — sets campaign flag
   `crew_stranded_<site>` which follow_ons turn into a rescue mission.

---

## 7. Ship additions

- **Shuttlebay**: new room type in `ShipLayoutGen` (both ship classes) — sized ~5×4,
  doored, unique. Holds the shuttle (visual: parked sprite placeholder). New tile
  hook `tile_shuttlebay` (falls back to cargo tiles until art lands).
- **Airlock**: room type exists; guarantee ≥1 per generated ship (verify in gen,
  add if a layout lacks one). Docking = other ship abstractly connects here.
- **Shuttle**: not a walkable interior — an entity with states
  `bayed | outbound | on_site | inbound | lost`, hull 0-100 (damage from strain
  beats; at 0 during an op → op aborts with casualties roll). Repairable via the
  existing RepairModel as target `shuttle`.
- **Docking sequence**: `docking_started` → 20s → `docking_completed` (other-ship
  approach visual plays); undock likewise. Boarding ops only while docked.

## 8. Destination visuals (ApproachVisual)

Node layered with `Starfield`. Driven by mission phase:
- `arrival` phase start → destination sprite fades/scales in from nothing to full
  presence across the phase duration (default 300s — the user-specified ~5 minutes).
- `on_station`: holds (planet slowly rotates if shader allows; ship holds off-beam).
- `transit_back` start → recedes over ~60s.
Placeholder art: procedurally tinted circles + atmosphere ring for planets
(descriptor → palette), silhouette sprite for ships/stations. `art` field names the
real asset for the future image-gen pass (`docs/asset-backlog.md`).

## 9. Intruders (IntruderSystem — minimal, sensor-level)

Room-granular hostile presence; NO pathfinding sprite this sprint (the player is a
ship AI — it sees *sensor contacts*, which is both cheaper and scarier):
- `spawn(type, room_id)` → contact appears on HUD room overlay (unless `hidden`).
- Tick: every 20-40s, chance to move to a ShipGraph-adjacent room. Sharing a room
  with crew → fear spikes + a combat round: marines/armed crew fight back via
  `Checks` + `WoundTable.apply_damage` (FINALLY its first caller); unarmed crew
  take a hazard roll and flee to an adjacent room (existing panic/flee states).
- AI counterplay: lock doors to contain it (existing door system!), vent room air
  (`air_vent_room` outcome exists for scenarios; AI-initiated venting comes later),
  direct a hunt (`hunt_intruder` directive type via DirectiveActionHandler).
- Death → `intruder_killed(intruder_id, room)` → scenarios listen via watches.
- Types this sprint: `stalker` (moves, hunts isolated crew), `nest` (static,
  spreads air-quality damage), `mimic` (dormant until triggered). Data table in
  intruder_system.gd, extensible.

## 10. Overseer binding

- **Hook firing**: at each phase hook, effective chance =
  `hook.chance * lerp(0.6, 1.4, ScenarioDirector.effective_heat())` and the roll is
  skipped entirely if a cooldown is active (`modifiers.cooldown_mult` stretches a
  120s base inter-scenario gap). Cap 2 concurrent (existing OVERLAP_CAP).
- **Selection** (ScenarioCatalog.pick): filter by context, `min_leg`, once_per_run,
  recent-history (existing soft de-prioritization), axis-compatibility with active
  scenarios (existing rules). Weight × hook `tag_bias` × generalized weakness-fit:
  `bio`→no medic alive or medbay unpowered; `systems`→battery <50%; `social`→avg
  trust <0.45; `combat`→no marine alive; `mystery`→flat 1.0.
- **Intensity gate**: intensity 3 requires `effective_heat() ≥ 0.6` OR leg ≥ 4;
  at heat <0.35 prefer intensity 1 (mercy = the Overseer sends ghosts, not gore).
- **Delayed payoffs**: when any crew gains a status flag with a matching
  `trigger_status` scenario, MissionManager schedules it: force-attach at a hook
  1-2 legs later (overrides the chance roll). THE interweave mechanic.
- **Leg boundary**: mission resolution calls `ScenarioDirector.advance_leg()` +
  checkpoint + `leg_boundary_reached` (moves from ScenarioRunner scenario-drain,
  which stays as fallback when `MissionManager.mission_mode == false`).

## 11. New EventBus signals

```gdscript
signal mission_started(mission_id: String)
signal mission_phase_changed(mission_id: String, phase: String)
signal mission_objective_updated(mission_id: String, objective_id: String, state: String)  # active|complete|failed
signal mission_completed(mission_id: String, outcome: String)   # mission_success|mission_partial|mission_failed
signal shuttle_departed(crew_ids: Array, site: String)
signal shuttle_returned(report: Dictionary)
signal boarding_started(crew_ids: Array, target_name: String)
signal docking_started(contact_name: String)
signal docking_completed(contact_name: String)
signal undocked(contact_name: String)
signal destination_sighted(kind: String, name: String)
signal intruder_spawned(intruder_id: String, room_id: String, visible: bool)
signal intruder_moved(intruder_id: String, from_room: String, to_room: String)
signal intruder_killed(intruder_id: String, room_id: String)
signal crew_status_flag_changed(crew_id: String, flag: String, value: bool)  # internal — HUD must NOT surface hidden flags
```

## 12. Boot & testing

- Mission mode default ON in normal play: `main.gd` boots
  `MissionManager.begin_campaign(seed)` which draws the opener (a tagged
  `opener` mission, low stakes).
- `SHIPAI_MISSION=<id>` forces the first mission. `SHIPAI_SCENARIO=` (existing)
  still boots scenario-only legacy mode — every existing AUTODEMO/acceptance run
  stays green. `SHIPAI_AWAY_FAST=1` compresses away-op durations 10× for testing.
- Verification per engine task: `--headless --import` then scene run, grep
  `SCRIPT ERROR`; plus one `SHIPAI_MISSION=<simple>` AUTODEMO-style soak.
- `tools/missions/validate_content.py`: validates every mission/scenario JSON —
  parse, required fields, id==filename, unique ids, follow_on refs resolve (id or
  tag reachable), contexts/axes/outcome-types/condition-types/objective-kinds in
  closed sets, skill names canonical (rules.md list), item ids in Items.REGISTRY,
  every win_flag settable by some event/monitor outcome, morph targets exist (or
  known-stub list). Run in CI-style at end of every content/engine task.

## 13. Content quotas & discipline (content agents read this)

- **Missions: 45 target (40 floor).** Spread: ~8 rendezvous/docking, ~10 planet
  (survey/mining/science), ~6 delivery/escort/passenger, ~5 salvage/derelict,
  ~4 repair/homecoming/hub, ~5 distress/evacuation, ~4 patrol/quarantine/smuggle,
  ~3 openers (tag `opener`, gentle). Every mission: full schema, 2-5 objectives,
  scenario_hooks on ≥2 phases, ≥1 follow_on rule. At least 12 missions must
  reference outcome flags OTHER missions set (real chains: stranded-crew rescue,
  infection aftermath, repair after mauling, faction grudges).
- **Scenarios: 42 target (40 floor).** Axis spread ≈ bio 10 / systems 9 / social 8 /
  combat 7 / mystery 8. Intensity spread ≈ 1: 12, 2: 20, 3: 10. Context coverage:
  every context ≥4 scenarios; ≥6 with `trigger_status` payoffs (infected, changed,
  shaken, marked); ≥8 morph edges pointing at REAL catalog ids. Each scenario:
  6-14 events, ≥2 solve paths using DIFFERENT skills/equipment (spread across the
  full skill list — not everything is Xenobiology), monitor program with ≥1 check.
  Seed from `scenario-bible.md` tier concepts (implement The Long Crack and Close
  Quarters properly — morph stubs exist pointing at them!) plus sci-fi canon:
  Alien, The Thing, Event Horizon, Solaris, Roadside Picnic, BSG, Dead Space,
  Mothership modules — file the serial numbers off.
- Tone: Mothership house voice (see bible pillar section) — blue-collar space
  horror, wry, concrete. Briefings in corporate-dispatch register.

## 14. Dialogue & audio expansion (AFTER catalogs land)

Once both catalogs are final, a dedicated workstream extends the dialogue corpus
(`docs/dialogue_spec.md` pipeline: archetype JSON → lines → Fish Audio v2 batch):
away-op radio chatter per site/risk-tier, mission briefing acknowledgments per
archetype, scenario-specific bark sets (per axis at minimum, per scenario for the
ten intensity-3s), docking/shuttle operational chatter. Content agents should write
`radio_line` text inline in JSON (spoken via bubbles unvoiced at first); the corpus
pass then lifts recurring lines into the voiced-archetype system. Voice map:
`tools/audio_gen/fish_voices.json`.
```
