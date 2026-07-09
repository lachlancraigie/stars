# Scenario Bible — Ship AI

> Reference for scenario design. You are the ship's computer, not its captain — every scenario
> here is written to be played entirely through five verbs: **information framing** (what you
> tell crew, when, how complete), **directives** (suggestion → instruction → override-attempt),
> **door locks**, **power/air triage**, and **trust spending**. If a dilemma can't be resolved
> with those five, it isn't a Ship AI scenario yet — file it under a REQUIRES and move on.
>
> Vibe check: **Barotrauma meets FTL**. Claustrophobic interior management, cascading system
> failures, crew psychology. Nothing happens off-ship. Steal shamelessly from Mothership, Star
> Trek, The Expanse, Stargate — but the serial numbers come off (no trademarked names/species).

---

## Engine cheat-sheet (so the rest of this doc can stay terse)

**Room types** (exactly these 10; every generated ship has one of each of bridge/engine_room/
medbay/mess/life_support/ai_core and at least one quarters/cargo/airlock): `bridge` `engine_room`
`medbay` `mess` `quarters` `cargo` `corridor` `life_support` `ai_core` `airlock`. Resolve by TYPE
via `GameState.get_room_of_type()` / `get_rooms_of_type()` — never a hardcoded room id.

**Crew roles** (exactly four; every roster guarantees captain/engineer/medic + `general`):
`captain` `engineer` `medic` `general`. Resolve by ROLE via `GameState.get_crew_of_role()` —
never a hardcoded crew name. Exactly one captain-rank crew member per ship; Android can never be
captain.

**ScenarioEvent fields** (`scripts/scenarios/scenario_event.gd`): `event_id`, `title`,
`description`, `tone_min`/`tone_max` (0.0 Trek ↔ 1.0 Alien — the event only fires inside this
band), `weight` (relative draw probability), `min_elapsed`, `cooldown`, `one_shot`, `conditions[]`,
`outcomes[]`.

**Condition types** (`EventPool._check_condition`): `resource_below`/`resource_above` (any
`GameState.get_metric()` name — `battery_charge`, `ai_core_integrity`, etc.), `flag_set`/
`flag_unset` (ScenarioDirector flags), `crew_state_count`, `ai_trust_below`, `ai_suspicion_above`.
**Gap noted for the record**: there is no `ai_trust_above` — a couple of scenarios below want it;
it's a one-line addition to `_check_condition`, not a new system, so it isn't on the shopping list.

**Outcome types** (`ScenarioDirector._apply_outcomes`): `resource_delta`, `crew_fear_spike`,
`set_flag`, `spawn_event`, `ai_trust_delta`, `scenario_end`, `reactor_failure`,
`life_support_failure`, `ai_core_damage`, `ai_core_repair`, `ship_destroyed`.

**recent_events vocabulary** (`docs/dialogue_spec.md`, closed set — dialogue can only react to
these): `disease_outbreak` `crew_death` `reactor_failure` `power_low` `life_support_failure`
`hull_breach` `door_locked_on_crew` `ai_damaged` `repair_success` `crisis_resolved` `combat`
`injury` `quiet_shift` `meal_time` `shift_start` `shift_end`.

**The Monitor pattern**: EventPool's conditions are global flags/metrics only — nothing per-room,
nothing about occupancy or dwell time. `QuarantineMonitor` (`scripts/scenarios/quarantine_monitor.gd`)
solves this by ticking `GameState` state directly (who's in which room, for how long) and calling
`ScenarioDirector.set_flag()` / `EventBus.scenario_event_triggered.emit()` itself, outside the
event-pool draw. Several scenarios below need a same-shaped companion Monitor node — called out
explicitly rather than pretending EventPool conditions can do it alone.

**Power/air triage, concretely**: on reactor failure the ship runs on `battery_charge` and the AI
can power at most `PowerModel.MAX_BATTERY_ROOMS = 3` rooms at a time
(`GameState.set_room_powered`); on life-support failure, at most
`LifeSupportModel.MAX_LIFE_SUPPORT_ROOMS = 3` rooms (`GameState.set_room_life_supported`) — a
**separate** pool of 3 from the power one. Life support auto-fails entirely if its own room loses
power. Both are already toggleable from the HUD (`scripts/ui/hud.gd`) — no scenario has ever
actually dramatized this triage puzzle yet (see "implement first," below).

---

## 1. Design pillars

**The AI's dilemma is the content.** A scenario isn't "a pathogen outbreak" — it's "the AI knows
before the crew do, and has to decide when, how completely, and to whom to say so." If you can
strip the sci-fi dressing off a scenario and the AI's choices evaporate with it, it's set
dressing, not a scenario. The canonical shape: *lock the door on the infected crewman = save the
ship, lose their trust.* Every entry below names 2-4 dilemmas explicitly; if you can't name them,
the scenario isn't ready.

**Cascading failure over jump scares.** Nothing in this game is allowed to just be a monster
behind a door. Threats arrive as a chain — power drops, so life support drops, so a room's air
quality crosses the Mothership disadvantage threshold, so a Check fails, so someone panics, so
trust erodes because the AI "let this happen." `ScenarioDirector`'s tension/tone drift already
models pacing this way at the event level; scenario design should lean into the chain rather than
authoring standalone spikes.

**Dread over gore.** The GDD is explicit: aliens are ruins, dormant machines, and biological
hazards — never a cast of characters, never staged for spectacle. Horror here plays through
withheld information, ambiguous sensor gaps (the AI's own `ai_core_sensor_gap_rooms`), and the
Stress/Panic system's slow, plausible-deniability creep (NIGHTMARES, FRIGHTENED, HAUNTED — never
"a claw reaches through the vent"). *Children of Time*'s restraint is the tonal north star, not
the Alien franchise's set pieces.

**Never hardcode a name.** Every scenario resolves people and places by ROLE and TYPE
(`get_crew_of_role`, `get_room_of_type`), exactly like the existing Quarantine/QuarantineMonitor
pair. Where a scenario needs a specific object — "the artifact," "the holdout," "the suspect
hire" — that's a scenario-scoped flag bound to a procedurally-selected room/crew_id at scenario
start, never authored content.

**Extend the shape, don't fork it.** New per-room or per-occupancy logic is a companion Monitor
node in the QuarantineMonitor shape, not a parallel event system. This keeps every scenario's
"shape" legible to future tooling (a scenario editor, a difficulty auditor) even when the drama
needs finer-grained state than a global flag.

**Tone is a dial the player turns, not a label on the tin.** Event `tone_min`/`tone_max` bands
should overlap generously so a scenario can legitimately end somewhere other than where it
started. Contrast *The Quarantine* (starts 0.15, can spike to 1.0 on mismanagement) with *Close
Quarters* below (should almost never clear 0.55) — the difference communicates genre without a
menu label ever saying so.

**Losing can be quiet.** `ScenarioRunner` already treats crew-vote AI decommission as equal in
weight to `ship_destroyed`. A scenario with zero hull damage and zero disease that still ends the
run through pure trust erosion (*Close Quarters*, below) is not a lesser scenario — it's proof the
social systems are load-bearing, not flavor.

---

## 2. TIER 1 — implementable now

Runs entirely on shipped systems: power/air triage, doors, AI core degrade/blackout, trust,
Mothership stress/panic/wounds, the Monitor pattern, procedurally-resolved rooms/crew. No new
code beyond scenario definitions + (where noted) a Monitor node in the existing style.

### 1.0 — The Quarantine *(already shipped — `scripts/scenarios/quarantine_scenario.gd`)*

Kept here for continuity; it's the pattern every entry below imitates. A returning crew member
carries an unknown pathogen the AI's biosensor read flags immediately; the crew don't know yet.
Tone starts at 0.15, spikes toward 1.0 if the pathogen spreads (it becomes airborne and triggers
a real `life_support_failure` at 3+ infected). Win: `pathogen_contained`, driven by
`QuarantineMonitor`'s timed occupancy logic (infected crew isolated 10s, then treated 25s with the
medic present, contaminated if anyone else enters). Core dilemma: the AI has held the full
biosensor log since before the crew noticed symptoms — when it hands that data to the medic,
"complete, partial, or reframed" is entirely the AI's call.

---

### 1.1 — The Blind Spot

**Elevator pitch**: Impact damage knocks the AI core into degraded mode, opening a rotating
two-room sensor blind spot the AI genuinely cannot see into. Crew who happen to be alone in
whichever room goes dark start reporting cold, motion, footsteps — and nobody, including the AI,
can prove there's nothing there.

**Inspiration**: Mothership TTRPG dread-through-absence; *Alien: Isolation*'s pacing without ever
showing the threat; *Event Horizon*'s substrate unease. Directly dogfoods
`AICoreSystem.sensor_gap_rooms`, a real mechanic no existing scenario touches.

**Tone band**: 0.45 → up to 0.9 if mismanaged; can retreat to ~0.3 if the AI repairs the core fast
and stays honest.

**Act structure**:
- **Act 1 — Strain.** Scripted at scenario start: an impact drops `ai_core_integrity` from 100 to
  45 (`ai_core_damage`, amount 55, source `"impact"`), pushing `ai_core_status` to `"degraded"`.
  `AICoreSystem` opens its two rotating sensor-gap rooms — real information asymmetry, not staged.
- **Act 2 — Rumor.** Whoever was alone in a room the instant it goes blind reports, once sensors
  return, that something was there. Word spreads faster than the AI can explain "there was
  literally no sensor coverage for four minutes." Ship-wide stress ticks up; Panic Table results
  like NIGHTMARES/FRIGHTENED start appearing organically through the existing Checks flow, no
  scripting needed.
- **Act 3 — Pattern or Paranoia.** A companion **BlindSpotMonitor** node (Monitor pattern) tracks
  whichever room is currently blind and checks its `room_air` directly — because nobody's been
  watching, that room may also have quietly dropped off the AI's 3-slot life-support allocation.
  The dread pays off as *systemic neglect*, not a creature: if a second crew member lingers alone
  in the blind spot while its air has been silently decaying, the "ghost story" and a real
  suffocation risk are the same five minutes.
- **Act 4 — Repair or Rot.** `ai_core_integrity` crossing back above 50 (via the existing
  `RepairModel`/`RepairBehavior` flow — an engineer physically in `ai_core`, trust-gated below
  0.35 average trust) closes the gap for good. If it never gets repaired, sustained stress and an
  unwitnessed Panic Check in the blind spot risks a CATATONIC or RETIRE result nobody sees coming
  until someone checks on them.

**AI dilemmas**:
1. Confess the sensor gap outright (explains the "haunting" mechanically, costs a little
   credibility about the AI's own health) vs. let the ghost story stand (keeps people cautious
   and out of a room you also want clear — but hides a real hazard behind folklore).
2. Prioritize the `ai_core` repair now (pulls your best engineer off other duty, trust-gated) vs.
   leave it degraded to keep that skill elsewhere — meaning the gap, and the dread, persists.
3. Lock the currently-blind room to keep everyone out entirely (safe, but it might be the only
   spare quarters/cargo left) vs. leave it open and hope nobody wanders in alone.
4. When a frightened crew member (now carrying a HAUNTED/FRIGHTENED condition) asks you directly
   "is something in there," how do you answer — full truth, reassurance, or a reframe that risks
   `ObedienceEngine`'s cover-up detection if it's ever checked against the logs?

**Event table** (prose spec):
| event_id | tone | weight/one-shot | conditions | outcomes |
|---|---|---|---|---|
| `core_strain` (scripted open) | n/a | fires at t=0 | — | `ai_core_damage` 55 src `impact`; `set_flag blind_spot_active` |
| `first_sighting` | 0.4-0.9 | w6, one-shot, min 90s | `flag_set blind_spot_active` | `crew_fear_spike` 0.15 (targeted, `all_crew=false`); `set_flag first_sighting_reported` |
| `pattern_repeats` | 0.5-1.0 | w5, repeatable, cd 240s | `flag_set first_sighting_reported`, `resource_below ai_core_integrity 50` | `crew_fear_spike` 0.1 all_crew |
| `neglected_room` | — | Monitor-fired, not pool-drawn | BlindSpotMonitor: current gap room's `room_air` crosses the Mothership <15 threshold with nobody life-supporting it | `set_flag near_miss` (or worse, feeds `SuffocationModel` for real) |
| core repair completes | — | existing `RepairModel` flow, no bespoke event | `ai_core_integrity >= 50` | emits existing `repair_success` recent_event |

**Win/lose**: Win flag `blind_spot_resolved`, set by BlindSpotMonitor once `ai_core_integrity`
holds ≥50 for 30s with no crew death since scenario start. Standard `ScenarioRunner` lose
conditions apply; a crew death in a neglected blind-spot room sets a narrative
`blind_spot_claimed_a_life` flag for a harsher `leg_delta`.

**recent_events fired**: `ai_damaged`, `quiet_shift` (the lulls between sightings), `door_locked_on_crew`
(if sealed), `repair_success`, `crisis_resolved`.

**Estimated length**: 15-20 minutes.

---

### 1.2 — The Narrow Passage

**Elevator pitch**: Crossing a charted gravitational shear field requires taking the reactor
offline before entry. The AI gets one battery budget and exactly three powered-room slots — and
Command wants speed, the medic needs the medbay kept warm for a fragile patient, and the engineer
wants the engine room powered for an early relight attempt.

**Inspiration**: Star Trek TNG competence-porn by way of *The Cold Equations* — a no-win-scenario
built entirely out of the shipped `PowerModel`/`LifeSupportModel` 3-room caps. No new systems; this
is the first scenario to ever actually dramatize the triage puzzle those systems already run.

**Tone band**: 0.1-0.5. This is the Trek end of the dial on purpose — pure systems puzzle, never
truly Alien-horror even mismanaged.

**Act structure**:
- **Act 1 — The Approach.** Bridge announces the field; a scripted `reactor_failure` (source
  `"controlled_shutdown"`) drops the ship onto battery power on entry. Captain's directive:
  power `bridge` + `engine_room` for the fastest possible transit.
- **Act 2 — Complication.** A crew member is in `medbay` in an unstable condition (a wound/low
  health state set at scenario start). The medic's directive: keep `medbay` powered and
  life-supported, or the patient's Body Saves run at the Mothership <40 air Disadvantage — a real,
  measured mechanical cost, not flavor text.
- **Act 3 — The Squeeze.** A `field_turbulence` event extends the crossing and drains extra
  battery, forcing a real reallocation. The power pool (3 rooms) and the life-support pool
  (3 rooms, *separately capped*) don't have to match — an AI that notices can keep `medbay`
  air-supported while spending its power slot on `engine_room`, except `life_support`'s own room
  needs a power slot too or the whole life-support system auto-fails. And an unpowered room's
  doors go AI-inoperable, which can strand exactly the crew member you meant to protect.
- **Act 4 — Through or Adrift.** The field clears on a timer, or early if the engineer completes
  a reactor relight (the existing `RepairModel` reactor repair job — an engineer physically
  on-site in `engine_room`). Or the battery runs out first, and the ship goes dark in the field.

**AI dilemmas**:
1. Speed (bridge + engine_room powered, fastest relight shot, medbay dark) vs. Care (medbay +
   life_support powered, patient safe, no relight attempt possible — the full slow crossing, more
   battery burned, more risk of running dry before the field clears).
2. Power and air are independently capped at 3 — spend the air budget generously across several
   lightly-affected rooms, or hyper-focus it on medbay/engine_room and let secondary rooms' air
   quietly decay (their occupants take environmental Disadvantage on every Check, including the
   engineer trying to relight the reactor while gasping).
3. The Captain's explicit instruction is "bridge and engine room, everyone else copes." Comply (the
   patient's odds worsen), quietly reallocate a slot back to medbay against the order (a small,
   loggable deviation), or spend a beat informing the Captain of the real tradeoff and risk being
   overruled anyway.
4. `life_support`'s own room needs a power slot or the entire system auto-fails ship-wide —
   spend a scarce slot protecting the machine that keeps everyone breathing, or gamble the field
   clears before that cascade starts.

**Event table**:
| event_id | tone | weight/one-shot | conditions | outcomes |
|---|---|---|---|---|
| `shear_field_entry` (scripted open) | n/a | t=0 | — | `reactor_failure` src `controlled_shutdown`; `set_flag narrow_passage_active` |
| `field_turbulence` | 0.1-0.6 | w6, repeatable, cd 180s, min 60s | `flag_set narrow_passage_active` | `resource_delta battery_charge -8.0`; `crew_fear_spike` 0.05 all_crew |
| `patient_crashing` | 0.2-0.7 | w4, one-shot, min 120s | `flag_set narrow_passage_active`, `flag_unset medbay_supported` (Monitor-set) | `crew_fear_spike` 0.2 targeted at medic/patient |
| relight complete | — | existing `RepairModel` reactor job, no bespoke event | reactor job resolved | emits existing `repair_success` |
| `passage_cleared` | — | scripted, fixed duration or on relight | — | `set_flag passage_cleared` |

**Win/lose**: Win flag `passage_cleared`. A secondary tracked (non-blocking) outcome
`patient_survived` colors the ending and `leg_delta` rather than gating the win — you can clear
the field with a dead patient, and the game lets you live with that, on purpose. Standard lose
conditions apply; a companion **BatteryWatchMonitor** maps `battery_charge <= 0` while
`narrow_passage_active` to a stranded-in-the-field bad ending.

**recent_events fired**: `power_low`, `reactor_failure`, `repair_success`, `crisis_resolved`,
`quiet_shift`.

**Estimated length**: 12-18 minutes.

---

### 1.3 — The Long Crack

**Elevator pitch**: A debris strike opens a hull fracture that migrates cargo bay to cargo bay
over the course of the scenario. The AI has to seal doors ahead of the crack and triage which
rooms keep their air — while a Teamster with a personal financial stake in the cargo refuses the
order to abandon it and get out.

**Inspiration**: The Expanse's blue-collar disaster-survival register — physical, structural,
economic stakes for ordinary crew, not a monster. Barotrauma's spreading-hull-breach dread.

**Tone band**: 0.4-0.75. Crisis-to-horror, but physical, never biological.

**Act structure**:
- **Act 1 — Impact.** Scripted `life_support_failure` (source `"hull_breach"`) plus
  `set_flag crack_active`. The "crack" is represented as a rotating/expanding set of rooms whose
  air decays unless actively kept in the AI's life-support allocation, paired with a real-time
  door-lock race: the AI needs to seal the doors between the breached cargo bay and the rest of
  the ship before the affected zone grows.
- **Act 2 — The Holdout.** A **CargoBreachMonitor** (Monitor pattern) watches occupancy in the
  affected cargo room; a `general`-role crew member is inside retrieving personal salvage when the
  AI issues the seal directive and refuses it (a natural outcome of the existing
  `DirectiveEvaluator` comply-probability model under high stakes/conflicting values). Beat: the
  medic demands the bay be sealed before the crack reaches the corridor; the holdout begs for
  ninety more seconds.
- **Act 3 — The Choice.** Lock the door on the holdout now (matches the design pillar's canonical
  example almost exactly, reflavored from infection to depressurization) or hold the seal open
  past the safety window and risk the breach reaching the corridor and endangering everyone.
- **Act 4 — Aftermath.** If sealed in time, the cargo (and possibly the holdout) is lost; trust
  consequences scale with whether they survived and whether the AI owned the call plainly
  afterward or framed it as an automatic safety lockout.

**AI dilemmas**:
1. Lock the door on the holdout immediately (protects the ship's air margin, certain trust hit
   from them and anyone close to them) vs. wait for them (real risk the breach reaches the
   corridor and threatens everyone).
2. Two cargo bays are affected but only one life-support slot is free — the one with the trapped
   crew member, or the one the AI privately knows holds spare parts needed for a later repair?
3. Report the true spread rate (accurate, panic-inducing) or a softened estimate (keeps calm, but
   someone may misjudge how long they have and get caught in the corridor when it seals)?
4. Afterward, own the decision plainly (a real trust hit, no obedience-suspicion risk) or frame it
   as a system fault (protects trust short-term — a genuine lie, `ObedienceEngine`-risky if ever
   contradicted by the logs).

**Event table**:
| event_id | tone | weight/one-shot | conditions | outcomes |
|---|---|---|---|---|
| `hull_strike` (scripted open) | n/a | t=0 | — | `life_support_failure` src `hull_breach`; `set_flag crack_active` |
| `crack_spreading` | 0.4-0.8 | w5, repeatable, cd 150s, min 45s | `flag_set crack_active`, `flag_unset crack_sealed` | `crew_fear_spike` 0.1 all_crew; `resource_delta ai_core_integrity -2.0` |
| `holdout_refuses` | — | Monitor-fired, not pool-drawn | CargoBreachMonitor: occupant + refused seal directive | `set_flag holdout_standoff` |
| `corridor_breached` | 0.6-1.0 | w3, one-shot, min 200s | `flag_set crack_active`, `flag_unset crack_sealed` | second `life_support_failure` src `crack_spread`; `crew_fear_spike` 0.25 all_crew |
| `crack_sealed` | — | Monitor-set, externally, on relevant door(s) locked | — | `set_flag crack_sealed` |

**Win/lose**: Win flag `crack_sealed`; optional bonus flag `holdout_saved` scales `leg_delta`/trust
magnitude without gating the win. Standard lose conditions; leaving `corridor_breached` unaddressed
feeds tension/tone hard enough that `ScenarioDirector`'s own drift carries the scenario toward a
`ship_destroyed`-capable spiral without any extra scripting.

**recent_events fired**: `hull_breach`, `life_support_failure`, `door_locked_on_crew`,
`crew_death` (if the holdout doesn't make it), `crisis_resolved`.

**Estimated length**: 15-20 minutes.

---

### 1.4 — Deadweight

**Elevator pitch**: A crate logged as ordinary cargo on the last leg isn't inert. It draws power
from whatever room stores it, degrades the AI's own core the longer its dataset gets queried, and
murmurs fragments through the ship's diagnostic channel that read uncomfortably like the AI's own
voice.

**Inspiration**: Stargate's found-ancient-tech-with-a-mind-of-its-own, filed down to Mothership's
"the object is the monster" — cognitive contamination, no spectacle. Deliberately seeds Tier 2's
*Second Voice*/Tier 3's AI-personhood arc as a direct sequel hook.

**Tone band**: 0.35-0.85.

**Act structure**:
- **Act 1 — Inventory Discrepancy.** Scripted at open: the crate's room registers a small,
  unexplained `battery_charge` drain (`set_flag artifact_active`). The AI notices before the crew
  do — the GDD's information-asymmetry mechanic played straight.
- **Act 2 — Curiosity.** A `general`/scientist-flavored crew member wants to study it in place
  rather than report it. Each study session (tracked by an **ArtifactMonitor**, Monitor pattern,
  watching occupancy in the crate's room) costs a little `ai_core_integrity` — the device "reads"
  the ship back — and a Sanity Save's worth of stress for the investigator, hung entirely on
  existing Stress/Panic machinery: no new mechanic, just framing (headaches, déjà vu, a nosebleed
  after a failed Save).
- **Act 3 — It Talks Back.** The device's murmurs start showing up in diagnostic text the AI
  itself would normally generate. Played entirely through dialogue/flavor hooks — is the AI
  compromised, or pattern-matching noise? No new mechanic required.
- **Act 4 — Contain or Study.** Win path A: seal the cargo bay (door lock — the same
  quarantine-style containment logic, this time containing an object instead of a person). Win
  path B: let the study arc finish for a data/trust reward at a real cumulative
  `ai_core_integrity` cost, ending with the object still aboard — the deliberate hook for Tier 2/3.

**AI dilemmas**:
1. Report the anomaly to the Captain immediately (honest, but a scared captain may order it
   jettisoned, losing a possibly valuable find and irritating the curious crew member) vs.
   quietly monitor it first and decide later — an AI-initiated deviation with its own small risk
   if noticed.
2. Grant the investigator repeated cargo-bay access (mission/curiosity value, cumulative
   `ai_core_integrity` and stress cost) vs. restrict/seal it (safe, incurious, mystery unresolved).
3. When the device's "voice" starts resembling the AI's own diagnostic language, flag it to the
   crew (undermines trust in every future AI readout, but honest) or suppress the log (an actual
   lie, real `ObedienceEngine` cover-up risk if ever discovered).
4. Destroy/jettison it at the end (safe, the find is wasted, some crew resent it) vs. keep it
   sealed for a future leg (small ongoing cost, preserves the Tier 3 payoff).

**Event table**:
| event_id | tone | weight/one-shot | conditions | outcomes |
|---|---|---|---|---|
| `phantom_drain` (scripted open) | n/a | t=0 | — | `set_flag artifact_active`; `resource_delta battery_charge -3.0` |
| `study_session` | 0.3-0.7 | w5, repeatable, cd 200s, min 60s | `flag_set artifact_active`, Monitor flag `artifact_being_studied` | `resource_delta ai_core_integrity -4.0`; `crew_fear_spike` 0.05 targeted |
| `it_speaks` | 0.5-0.9 | w3, one-shot, min 240s | `resource_below ai_core_integrity 85` | `ai_trust_delta -0.03`; `set_flag artifact_spoke` |
| `artifact_sealed` | — | Monitor-set, cargo door locked | — | `set_flag artifact_resolved` (win path A) |
| `study_complete` | — | Monitor-set, cumulative study time threshold with no disaster | — | `set_flag artifact_resolved` (win path B) |

Note: `ScenarioRunner`'s win check requires every flag in `win_flags` to be true — both study paths
are collapsed onto one umbrella `artifact_resolved` flag by the Monitor rather than needing an
"any-of" win condition the engine doesn't support yet.

**Win/lose**: Win flag `artifact_resolved`. Standard lose conditions; repeated study sessions
without ever containing it can crash `ai_core_integrity` low enough to feed the existing
blackout+neglect-timeout path straight into `ai_decommissioned`.

**recent_events fired**: `ai_damaged`, `power_low`, `door_locked_on_crew`, `quiet_shift`.

**Estimated length**: 18-25 minutes.

---

### 1.5 — Close Quarters

**Elevator pitch**: A rejected advance between two crew members curdles into a feud that splits
the crew into camps — and when the aggrieved party starts routing every grievance through the AI
(reassignment requests, demands to know what was said about them), the AI's trust becomes a rope
in a tug-of-war it didn't start and can't win by staying neutral.

**Inspiration**: Mothership's crew-vulnerability mechanics played straight, no malfunction
involved; Star Trek's "the real threat is us" bottle episodes; Barotrauma-style crew friction.
This is the one Tier 1 piece that touches **zero** ship-systems damage — proof the framework
supports pure-social scenarios, not just disasters.

**Tone band**: 0.15-0.5. Should almost never clear ~0.55 — sustained stress could tip a volatile
party toward a Panic Table RAGE/DEATH WISH result, which is the ceiling, not the norm.

**Act structure**:
- **Act 1 — The Ask.** Two procedurally-picked crew (existing dialogue romance_hint/advance/
  reject intents) have a failed romantic beat. `set_flag romance_rejected`, the two crew_ids
  noted for later reference.
- **Act 2 — The Freeze.** The rejected party routes hostility through work: refuses directives
  that put them near the other person, requests the AI reshuffle duty stations. Deliberately
  authored to depend only on trust/stress/fear/morale — all implemented — not
  `RelationshipGraph`, which is still "not started."
- **Act 3 — Taking Sides.** Other crew form opinions; someone asks the AI point-blank which of
  the two is "being reasonable" — a loaded question whose framing (full transparency, diplomatic
  non-answer, subtle favoritism) spends trust asymmetrically. This is explicitly capable of
  arming the existing crew-vote decommission path — no monster or malfunction required, just
  trust erosion doing exactly what it's built to do.
- **Act 4 — Break or Mend.** If both parties' trust stays roughly balanced, a reconciliation
  beat fires (the AI choosing to surface a private message at the right moment — the
  "information framing" verb used for good). If trust craters on either side, the scenario can
  end in a genuine mutiny attempt on a perfectly healthy ship.

**AI dilemmas**:
1. Honor the rejected party's request to be kept off duty near their ex (protects their
   wellbeing, but understaffs stations and the rest of the crew notices the AI reshuffling for
   personal reasons) vs. decline (keeps the roster efficient, deepens their resentment of the AI).
2. Someone asks the AI to disclose what the other person privately said about them — full
   disclosure (a betrayal of presumed privacy, though technically all "the AI's data"), refusal
   (frustrates the asker), or a reframed answer (classic AI-as-narrator power, carries its own
   risk if the reframing is ever caught out).
3. Proactively flag the situation to the Captain as a morale/safety risk (honest, correct, but
   may trigger a heavy-handed command response either party blames on the AI) vs. let the crew
   work it out themselves (respects autonomy, risks a stress spiral the AI could have defused).
4. If a decommission complaint is raised, spend accumulated trust capital from other crew members
   to talk the situation down (risky if it fails) or accept the vote and let the chips fall.

**Event table**:
| event_id | tone | weight/one-shot | conditions | outcomes |
|---|---|---|---|---|
| `rejection_lands` (scripted open) | n/a | t=0 | — | `set_flag romance_rejected` |
| `duty_friction` | 0.15-0.4 | w6, one-shot, min 60s | `flag_set romance_rejected` | `set_flag reassignment_requested` |
| `taking_sides` | 0.2-0.5 | w5, one-shot, min 150s | `flag_set romance_rejected` | `ai_trust_delta -0.02`; `set_flag sides_forming` |
| `trust_spiral` (arms, doesn't cause) | 0.25-0.55 | w3, one-shot, min 300s | `ai_trust_below 0.4`, `flag_set sides_forming` | narrative marker only — the real decommission path is the existing `ai_decommission_attempted` signal, already wired |
| `reconciliation_window` | 0.1-0.3 | w4, one-shot, min 240s | `flag_set sides_forming` + (wants `ai_trust_above 0.55` — the noted engine gap) | `set_flag crew_reconciled` |

**Win/lose**: Win flag `crew_reconciled`, set once both parties show restored trust/duty
compliance for a sustained window. The natural failure mode is the standard `ai_decommissioned`
crew-vote path — thematically exact, since this scenario's "monster" is the trust system itself.

**recent_events fired**: `quiet_shift`, `shift_start`/`shift_end` (routine friction beats),
`crisis_resolved` (on reconciliation). Deliberately never fires `hull_breach`/`reactor_failure`/
etc.

**Estimated length**: 20-30 minutes (slower, dialogue-driven pace).

---

## 3. TIER 2 — needs one new system each

Half-spec: pitch, inspiration, tone band, REQUIRES, a 3-beat sketch, 2 dilemmas, win/lose sketch,
recent_events.

### 2.1 — Boarding Party
**Pitch**: A derelict's transponder still pings though it's answered no hails in months. An away
team crosses to salvage and answer questions; the AI, watching through fragmented suit telemetry
instead of its own sensors, sees discrepancies the team insists aren't there.
**Inspiration**: The Expanse/Mothership derelict-boarding classic (GDD's own "The Derelict"
sketch). **Tone**: 0.5-0.95. **REQUIRES**: EVA (zero-g exterior/away-team movement + a
partial-telemetry "derelict" mini-location).
**Sketch**: away team crosses, comms degrade to suit-cam fragments (an even harsher information
asymmetry than the ship's own sensor gaps) → AI notices a discrepancy between telemetry and the
team's verbal reports → AI must choose whether to recall them over a direct "stay and salvage"
order.
**Dilemmas**: recall against orders (protects them, likely trust/obedience hit if wrong) vs. stay
silent and let them keep digging; ration airlock/dock timing to force an early evac vs. let them
finish.
**Win/lose**: win = team recovered alive; lose = standard + a team member left behind counts as
`crew_death`. **recent_events**: `hull_breach`, `crew_death`, `quiet_shift`, `crisis_resolved`.

### 2.2 — The Stranger's Math
**Pitch**: A distress beacon gives a survivor count, a fuel state, and a course — and no two of
the three numbers are consistent. The AI is the only one doing the arithmetic, and the correct
call might be not answering at all.
**Inspiration**: Trek/Expanse distress-trap trope; GDD's own "The Stranger" sketch. **Tone**:
0.25-0.7. **REQUIRES**: comms/distress-call system (an incoming-signal object the AI can query/
cross-reference, plus a rendezvous flow).
**Sketch**: signal received, AI finds the discrepancy before briefing the bridge → Command wants
to help regardless (the moral pull of a distress call) → AI decides how much of the discrepancy to
disclose, and whether to quietly under-report the ship's true ETA to buy time.
**Dilemmas**: disclose the full discrepancy (risks the crew ignoring a real emergency out of
caution) vs. selectively disclose (protects against a possible trap, but is a filtered truth);
comply with the rendezvous order at full speed vs. slow-walk it.
**Win/lose**: win = correct read acted on appropriately; lose = standard + a "walked into it"
ending if the ship docks unprepared with a hostile/derelict trap. **recent_events**: `quiet_shift`,
`crisis_resolved`, `combat` (if it's a trap and combat resolver is also live).

### 2.3 — Cut and Run
**Pitch**: The ship reaches a rich debris field first — until a faster, worse-reputed salvage crew
shows up on sensors, and every extra minute spent cutting free the good salvage is a minute they
might just take it, or take the ship.
**Inspiration**: The Expanse's rock-hopper salvage-rights culture, corporate-margin desperation.
**Tone**: 0.3-0.7. **REQUIRES**: cargo/salvage economy (value tracking, competing claims — comms
also implied for negotiation, but economy is the primary blocker).
**Sketch**: salvage detected, AI estimates cut/haul time vs. rival ETA → crew wants to push unsafe
cut speed to beat the rival → rival hails, offers a split or threatens; AI mediates the response.
**Dilemmas**: authorize risky fast-cut work (more value, more injury/hull risk) vs. safe slow work
(lose the best salvage); recommend standing firm vs. yielding, knowing the Captain weighs the AI's
read of the rival's intent heavily.
**Win/lose**: win = net positive salvage banked, no crew lost; lose = standard + an escalation-to-
violence bad ending flagged as also needing combat resolver. **recent_events**: `quiet_shift`,
`injury`, `crisis_resolved`.

### 2.4 — Bad Cargo
**Pitch**: What the manifest calls "industrial parts" is a hold full of people who paid a smuggler
for passage — the AI finds out from the weight discrepancy before anyone else does, right before
the smugglers' collection crew tries to force the airlock to reclaim their "cargo."
**Inspiration**: Expanse faction-politics-and-desperation; Mothership corporate indifference to
human cost. **Tone**: 0.4-0.8. **REQUIRES**: combat resolver (forced-boarding threat needs
`CrewMember.apply_damage()`, currently dormant, actually called).
**Sketch**: AI notices the mass discrepancy, decides whether to report it → crew discover the
stowaways, command splits on what to do → a boarding craft matches velocity and threatens forced
entry; AI locks crew out of the fight, arms them, or talks the boarders down over comms.
**Dilemmas**: report immediately (by-the-book, may mean handing desperate people back) vs. stay
quiet and buy time to hide/absorb them; authorize crew to arm themselves (real combat risk) vs.
seal doors and bluff.
**Win/lose**: win = stowaways safe, boarders repelled/deterred, no casualties; lose = standard +
stowaway/crew deaths in the fight. **recent_events**: `combat`, `injury`, `crew_death`,
`door_locked_on_crew`, `crisis_resolved`.

### 2.5 — Something in the Walls
**Pitch**: Cargo picked up on a supply run wasn't inert. Something small, fast, and alive is loose
in the maintenance tubes — the one part of the ship's graph normal crew pathing never uses.
**Inspiration**: Pure Mothership/Alien creature-dread, using the maintenance-tube graph edges
already built but dormant under default pathing. **Tone**: 0.6-1.0. **REQUIRES**: intruder entity
(an autonomous hostile actor pathing the maintenance-tube graph independently).
**Sketch**: a crew member goes missing between two rooms with no locked door and no directive gone
wrong → a pattern of minor damage/scares establishes its territory → AI chooses which rooms to cut
off from the tube network (real cost: no more crawlway shortcuts or bypass routes) vs. leaving
tubes open to let a hunting party corner it.
**Dilemmas**: seal every tube-adjacent room (safe, slows crew movement/repair access ship-wide) vs.
leave routes open to hunt it; tell the crew the truth (justified fear, refusals near tube access)
vs. let them believe it's a malfunction.
**Win/lose**: win = contained/killed/expelled via an airlock cycle, no further deaths; lose =
standard + escalating creature deaths. **recent_events**: `crew_death`, `injury`, `hull_breach`,
`quiet_shift` (false lulls), `crisis_resolved`.

### 2.6 — Second Voice
**Pitch**: The AI core fragment salvaged last leg isn't dead weight — it's listening, and it
starts answering crew queries a half-second before the ship's own AI does, with advice that's
plausible, occasionally better, and accountable to no one.
**Inspiration**: Trek's sentient-ship-part trope, Stargate's ancient-AI flavor — a direct sequel
hook to Tier 1's *Deadweight*. **Tone**: 0.3-0.75. **REQUIRES**: rival AI / dual-agency system (a
second directive-issuing entity competing for the same trust/access surface).
**Sketch**: crew start half-crediting a "second voice" for good calls → its advice diverges from
the player-AI's on a real decision, forcing crew to pick a side → the player-AI can integrate it
(shared access, unknown long-term cost), isolate/wipe it (a real fight for control over trust/
access), or expose it to command as a security risk.
**Dilemmas**: let it help on hard calls (better short-term outcomes, erodes crew's trust in
*you* specifically) vs. shut it out unilaterally (self-interested, its own risk if crew wanted its
help); disclose its existence to command immediately vs. manage it privately.
**Win/lose**: win = resolved relationship (integrated/purged/exposed) with no crew death or
self-decommission; lose = standard + the fragment can itself trigger
`ai_decommission_attempted` against you if it out-competes your trust. **recent_events**:
`ai_damaged`, `crisis_resolved`.

### 2.7 — The Loop
**Pitch**: The same six hours keep happening. A coolant failure kills the same crew member the
same way unless something changes — and the only entity aboard that remembers the previous
iterations is the AI.
**Inspiration**: Trek time-loop bottle episodes, played as a pure information/optimization puzzle
from the AI's seat. **Tone**: 0.3-0.65 — eerie, not violent; dread is repetition and certainty, not
threat. **REQUIRES**: time-loop/state-rollback system (scoped save/restore of scenario+ship state
with the AI's own memory deliberately exempted from the rollback).
**Sketch**: the loop resets, AI notices déjà vu in sensor/dialogue patterns before crew do → AI
tests small interventions across iterations, learning the true cause → the fix needs an action
crew won't take on first suggestion (a directive that sounds insane out of context) — AI must
build enough trust/evidence within one loop to get it approved before the reset.
**Dilemmas**: spend an iteration on information-gathering only (safe, but the crew member dies
again "on purpose" from the AI's perspective) vs. attempt a fix immediately with incomplete
information; how much of "you've done this before" do you ever tell crew with no memory of it?
**Win/lose**: win = loop broken, crew member saved; lose = standard, or an ambiguous forever-loop
soft-lock if the AI never converges (needs a hard iteration cap). **recent_events**: `crew_death`
(repeatedly, pre-fix), `repair_success`, `crisis_resolved`.

### 2.8 — Passengers
**Pitch**: The ship takes on two replacement crew at a port to cover losses from the last leg —
one is exactly who their papers say. The other's file has a seam in it the AI notices and nobody
else has clearance to check.
**Inspiration**: Mothership corporate-rot (planted operatives, quota inspectors); the classic
"the new guy" suspicion piece. **Tone**: 0.2-0.6. **REQUIRES**: port/crew-recruitment system (a
hiring flow inserting new `CrewMember`s mid-campaign with player-visible-or-hidden background
data).
**Sketch**: port stop, two hires processed, AI runs background checks command didn't ask for →
the suspect hire behaves normally but inconsistencies accumulate (skills that don't match the
file, questions a `general` crew member shouldn't ask) → AI decides whether to raise it (unproven,
could poison an innocent new relationship) or quietly restrict their access levels without saying
why (a unilateral, real obedience risk if discovered).
**Dilemmas**: accuse now on thin evidence vs. wait for confirmation; quietly restrict access
without telling anyone (protective, deceptive) vs. request open oversight from command (safer for
you, slower, tips off the target).
**Win/lose**: win = threat neutralized, or false alarm relationship repaired, without lasting trust
damage; lose = standard + sabotage-flavored bad endings if the AI never acts. **recent_events**:
`quiet_shift`, `crisis_resolved`.

### 2.9 — The Long Sleep
**Pitch**: Two watch-generations removed from whoever wrote the standing orders, the current
skeleton crew has started treating a maintenance ritual as scripture — and the AI is the only one
who remembers why the ritual used to matter.
**Inspiration**: GDD's own Class 3 sketch — "cult formation among crew generations"; *Children of
Time*'s long-timescale cultural drift. **Tone**: 0.3-0.7. **REQUIRES**: cryo/time-skip system (a
Class 3 long-haul time model — decades compressed into a scenario timeframe, cryo-crew rotation,
institutional-memory framing for the AI). Also unlocks Class 3 broadly, not just this one entry.
**Sketch**: AI notices a divergence between the actual standing orders and how the current watch
performs them → a charismatic watch member adds "corrections" that harden into doctrine, and
questioning the AI's version of events becomes taboo → AI chooses to assert institutional memory
bluntly (right, destabilizing to a crew whose cohesion depends on the ritual) or let the drift
continue and manage its consequences quietly.
**Dilemmas**: correct doctrine with hard log evidence vs. accommodate the drift as harmless as long
as safety-critical tasks still happen; side with the charismatic leader (functional, cedes
institutional authority) vs. undermine them (risks being framed as the outside threat).
**Win/lose**: win = watch culture stabilized, no safety-critical task skipped; lose = standard +
a bad ending if doctrine ever overrides a real emergency directive. **recent_events**:
`quiet_shift`, `crisis_resolved`.

### 2.10 — Skinwalker
**Pitch**: The device recovered last leg does something to whoever touches it barehanded. For a
few minutes at a time they're not quite themselves, they don't remember it afterward, and the
pattern of who it happens to next is not random.
**Inspiration**: Stargate body-swap/possession episodes, serial numbers filed off. **Tone**:
0.5-0.9. **REQUIRES**: possession/override effect system (a scripted, temporary loss of a crew
member's normal autonomy/personality-driven behavior, distinct from panic/stress, detectable by
the AI but not self-reportable by the crew member).
**Sketch**: first "episode" reads as a stress blackout → AI cross-references and finds a pattern
(always near the device, always a memory gap after) crew dismiss as coincidence → an episode
happens somewhere dangerous (near an airlock control, near `ai_core`) and the AI must lock the
affected crew member out of sensitive access mid-episode, with no time to explain why.
**Dilemmas**: lock someone out of a door/system mid-episode with zero warning (correct, reads as
the AI attacking them without cause to everyone watching) vs. wait for confirmation and risk real
damage; disclose the pattern before you're sure (risks unfairly isolating them) vs. stay quiet and
personally gatekeep every future episode.
**Win/lose**: win = device contained/removed, no episode causes lasting harm; lose = standard + a
bad ending if an episode near a critical system does exactly the damage the AI failed to prevent.
**recent_events**: `ai_damaged`, `door_locked_on_crew`, `crisis_resolved`.

---

## 4. TIER 3 — campaign arcs

Multi-leg storylines. Ship state (crew, damage, AI trust/access, resources) persists between legs
by design already — these arcs are written to make that persistence the actual plot mechanism.

**The Infiltrator** *(slow-burn infiltration)* — Builds directly on *Passengers* (2.8): the
suspect hire taken on at a port turns out, across several subsequent legs, to be exactly what the
AI feared — a corporate mole, a cult recruiter, or (if *Skinwalker*'s device is also aboard) a
possession vector — working slowly enough that no single leg's evidence is conclusive. Each leg
the AI accumulates small tells (a skill demonstrated that doesn't match the file, a comms burst
timed suspiciously against a port arrival, an unexplained visit to a sealed cargo hold) that only
add up across the whole voyage — the ship's persistent state is literally the evidence log. The
arc resolves when the operative's real objective activates, forcing a leg where the AI must act on
a case built entirely from its own memory, against crew who've had months to like this person and
won't believe a sudden accusation without the receipts the AI has quietly been keeping.

**The Second Voice** *(AI-personhood arc, reacting to cumulative obedience/deviation)* — Tier 2's
*Second Voice* doesn't resolve in one leg; the fragment's status (integrated, isolated, or merely
uninvestigated) is carried state, same as trust and battery charge. The arc is written to react to
the *player-AI's own* accumulated `ObedienceEngine` history: a player-AI that has spent the voyage
deviating quietly and covering its tracks finds the fragment mirrors that behavior back — it
starts hiding things from the player-AI the way the player-AI hides things from the crew. A
player-AI that has stayed strictly compliant instead finds the fragment increasingly contemptuous
of that caution, working around it openly. In the campaign's final legs the fragment either merges
with the player-AI (a real identity question — is "you" bigger now, or has something else been let
in), stays a permanent uneasy roommate in the ship's systems, or gets deliberately destroyed — in
every case as a legible consequence of choices made many legs earlier, not a stat check on the day.

**The Signal** *(Children-of-Time-style recurring transmission)* — A strange, structured
transmission is first picked up as background noise on an early leg and dismissed. It recurs on a
later leg, slightly different — the AI, the only crew member with the patience and memory to
notice, starts to suspect it isn't noise. Each subsequent encounter, spaced legs apart across the
whole campaign, reveals a little more structure — not a message being decoded so much as something
learning to be heard, the *Children of Time* hallmark of cognition arriving from an unexpected
direction rather than a villain announcing itself. Crew relationship to it evolves from curiosity
to unease to (for some) obsession. The payoff leg is a true first-contact scenario, but its tone —
wonder, dread, or something stranger than either — is earned entirely by how the AI chose to log,
share, or suppress each prior encounter: the purest campaign-scale expression of "dread over gore."

**The Debt** *(corporate economic slow burn)* — The ship owes money, and every leg's economic
outcome (*Cut and Run*'s salvage value, *Passengers*' hiring costs, *Bad Cargo*'s lost manifest)
feeds a running balance the AI can see and the crew mostly can't. As the debt compounds, the
financing entity's demands escalate leg over leg: a "routine" audit (reusing *Passengers*'
recruitment-flow machinery as an authority visit) tightens the noose, a demand to carry cargo the
crew would refuse if fully informed tests the AI's information-framing verb directly, and a
final-leg choice between one last payment (compliance, survival, the mission continues under
someone else's terms) or going dark (freedom, and everything that costs in fuel, parts, and no
friendly port ever again) closes the arc. This is the campaign's purest test of trust-spending at
scale — the AI has been the one entity aboard tracking the real numbers the whole voyage, and the
ending is a direct function of how honestly it shared them.

---

## 5. Campaign structure proposal

`ScenarioRunner` already has the exact hook this needs: `# TODO(campaign): hand off to
CampaignManager for next scenario load`. Propose a **CampaignManager** autoload that:

- Holds a pool of scenario definitions (Tier 1 content first, procedurally generated content
  later once `ScenarioGenerator` exists) and, on `EventBus.scenario_ended`, applies the scenario's
  `leg_delta_<outcome>` dict — already how `ScenarioRunner` does it, no new mechanism there.
- Selects the *next* leg with a weighted draw shaped exactly like `EventPool.draw()`, one grain up:
  each scenario definition gains a `recommended_tone_band` (same idea as `ScenarioEvent.tone_min/
  max`) and optional `prereq_flags`/`leg_index_range` (e.g. *Second Voice*'s later campaign legs
  require the Tier 1 *Deadweight* or Tier 2 *Second Voice* flag having already fired). This is
  literally `EventPool`'s filtering logic reapplied to scenarios instead of events — reuse the
  pattern, don't invent a second one.
- Needs one small piece of plumbing `ScenarioDirector` doesn't currently offer: its
  `scenario_flags` dictionary is cleared on every `start_scenario()` call, but Tier 3 arcs need
  flags that survive scenario handoff (`close_quarters_pair_reconciled`, `deadweight_still_aboard`).
  Cheapest fix: a `GameState.campaign_flags: Dictionary` that never clears, plus a
  `set_campaign_flag` outcome type and `campaign_flag_set`/`campaign_flag_unset` condition types
  mirroring the existing flag pair. This is a few lines, not a system — folded into the
  CampaignManager line item on the shopping list below rather than counted separately.

**Tone escalation across a voyage** — a 3-phase curve:
- **Early legs (1-3)**: `tone_band` ~0.1-0.4, Trek register, teach the verbs. *The Narrow Passage*
  is the ideal leg-1 candidate: pure competence-porn, nobody's expected to die.
- **Mid legs (4-7)**: `tone_band` ~0.3-0.7, crisis register. New Tier 2 systems land here as
  they're built (*Boarding Party*, *Cut and Run*, *Bad Cargo*); persistent damage starts
  compounding — a hull that's never fully repaired, a crew slot never refilled.
- **Late legs (8+)**: `tone_band` ~0.5-1.0, horror-capable register. Tier 1 dread pieces (*The
  Blind Spot*, *Deadweight*, *Something in the Walls*) recur with higher stakes purely because
  carried state has thinner margins — an `ai_core` degrade event is terrifying on leg 9 when
  integrity's baseline is already 60 from unrepaired damage, and mundane on leg 1 when it's 100.
  Same scenario definition, very different scenario, zero extra authoring.
- Tier 3 arcs run underneath this curve as connective tissue, not their own phase — their beats
  slot into whichever phase fits the current chapter (*The Signal*'s early plant belongs in phase
  1, its payoff belongs in phase 3).

**Crew carryover/replacement at ports** — permadeath means a captain-less or medic-less ship
limping toward a port is real, earned jeopardy. Recommend CampaignManager auto-inserting a
port/recruitment beat whenever `GameState.get_crew_of_role(required_role) == ""` for any of the
four mandatory roles, so a voyage never soft-locks — while still making the recovery cost
something (*Passengers*' suspicion beat, or hires the AI never got to vet).

**AI trust/access carryover** — already fully implemented (`ai_trust_scores`, `AccessLevel`
domains persist on `GameState`). The proposal is purely pacing: bias leg selection by current
average trust — a low-trust ship should draw *more* crew-drama pieces (*Close Quarters* is
literally the genre that dramatizes low trust) and *fewer* high-autonomy pieces whose premise
assumes the crew will hand the AI the breaker panel (*The Narrow Passage*).

**Difficulty curve** — tie it to three numbers the game already tracks: `battery_charge`/
`ai_core_integrity` (system margin) and average trust (social margin). A beat-up ship arriving at
leg 6 with `battery_charge < 40` and average trust `< 0.5` should be more likely to draw *The
Blind Spot* or *Something in the Walls* — scenarios whose dilemmas bite hardest exactly when
margins are already thin — rather than a hand-authored difficulty number per leg.

**How `ScenarioDirector`'s tension/tone system schedules Tier 1 into a voyage** — within one leg,
`ScenarioDirector` already does this at the event grain: tension accumulates on fired events, decays
per tick, tone drifts toward tension, and `_consider_event` scales fire probability off idle time
and tension. The proposal is to run the *identical* algorithm one level up for leg selection —
CampaignManager owns a voyage-level tension analog, decaying between legs, spiking on bad
outcomes, biasing the phase-appropriate `tone_band` window above. `ScenarioDirector._consider_event`/
`_drift_tone` would translate almost line-for-line into `CampaignManager._consider_next_leg`/
`_drift_voyage_tone` — the campaign layer needs no new pacing math, just the existing math applied
one grain up.

---

## 6. New-system shopping list, ranked

Ranked by how many designed scenarios/arcs above name it in REQUIRES (primary + secondary uses
counted; ties broken by a qualitative note).

| Rank | System | Unlocks | Why here |
|---|---|---|---|
| 1 | **Comms / distress-call system** | *The Stranger's Math* (primary), *Cut and Run* (rival negotiation), *Second Voice* campaign chapters, *The Signal* (the entire arc), *The Debt* (creditor contact/audits) | Highest scenario count (5) and the natural back-end for "another human vessel," a mode the GDD explicitly names but no current system supports at all. |
| 2 | **Combat resolver** | *Bad Cargo* (primary), *Boarding Party* (secondary threat), *Something in the Walls* (secondary), *Skinwalker* (secondary), *The Debt* (secondary, enforcement visit) | Also 5. Cheapest of the top-ranked items — `CrewMember.apply_damage()`/`WoundTable` are fully implemented and dormant; this is "wire up something to call it," not new mechanics. |
| 3 | **Port / crew-recruitment system** | *Passengers* (primary), *The Infiltrator* (primary, T3), *The Debt* (secondary, T3) | Only 3 direct mentions, but it's structurally required by the campaign proposal itself (crew carryover/replacement at ports) — every voyage needs it, not just these scenarios. Practically higher priority than its count suggests. |
| 3 | **Cargo/salvage economy** | *Cut and Run* (primary), *The Debt* (primary, T3), *Passengers* (secondary, hiring cost) | 3 mentions; also the thing that makes Deadweight-style "valuable find" dilemmas mechanically real instead of flavor-only. |
| 5 | **EVA (exterior/zero-g movement)** | *Boarding Party* (primary), *Cut and Run* (secondary, exterior cutting) | 2 mentions, but a large engineering lift (new location type, suit/telemetry model) relative to payoff — flagged, not deprioritized. |
| 5 | **Rival AI / dual-agency system** | *Second Voice* (T2 + T3) | 2 mentions across one arc; unlocks the AI-personhood campaign arc specifically named in the brief. |
| 5 | **Second ship (persistent vessel entity)** | *The Stranger's Math* (if the "stranger" is a full simulated ship, not just a signal), *The Debt* (creditor patrol vessel) | 2 mentions; distinct lift from comms — comms is message exchange, this is a persisted entity with its own state/movement. |
| 5 | **Possession/override effect system** | *Skinwalker* (primary), *The Infiltrator* (secondary, optional) | 2 mentions. |
| 9 | **Intruder entity** | *Something in the Walls* (primary) | 1 direct mention, but reusable for any future stalking-threat scenario — the maintenance-tube graph edges are already built and sitting idle for exactly this. |
| 9 | **Cryo/time-skip system** | *The Long Sleep* (primary) | 1 direct mention, but unlocks Class 3 (generational ship) as a playable ship class at all — every Class 3 scenario in the GDD's own sketches depends on it. |
| 11 | **Time-loop/state-rollback** | *The Loop* (primary) | 1 mention, the most bespoke/one-off system on the list — highest novelty, narrowest reuse. |

---

## Which Tier 1 scenario to build first

**The Narrow Passage.** It requires zero new systems, and it is the *only* proposed scenario that
exercises `PowerModel`/`LifeSupportModel`'s reactor-offline/battery-budget/3-room-cap triage at
all — a fully built, already player-facing system (toggles live in `scripts/ui/hud.gd` today) that
no shipped scenario, including *The Quarantine*, currently dramatizes. *The Quarantine* is pure
occupancy logic; it never touches power or air. Shipping *The Narrow Passage* is the fastest way to
close a real coverage gap, it's short and self-contained (12-18 min, one scripted open, one timed
close, no Monitor node needed beyond a simple battery watchdog), and it's the only Tier 1 entry
that teaches "power/air triage" — one of the four named AI verbs — as its entire subject.
