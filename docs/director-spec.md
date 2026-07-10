# The Overseer — Director AI Specification

> The pacing brain of the game. Requirement (Lachlan, 2026-07-10): "a tough roguelite with
> permadeath, but reactive and flexible. like the dual AI system in alien isolation. the
> scenarios should flex and morph into each other. if players are taking too long with a
> session, then it can start another simultaneous one. but if they are struggling and getting
> smashed with resource[s] and character deaths it can slow down or reduce the difficulty
> slightly."
>
> Companion docs: `scenario-bible.md` (the content the Overseer schedules), `gdd.md` (vision).
> Builds on the EXISTING `ScenarioDirector` (tension/tone drift) — this spec grows it into a
> two-layer director; it does not start over.

---

## 1. The dual-AI split (Alien Isolation pattern)

**Layer 1 — the Overseer** (this spec): omniscient, out-of-fiction. Reads everything (player
performance, crew state, ship state, wall-clock pacing), decides *what pressure exists*:
which scenarios run, when they morph, how hard their knobs are turned. Ticks slowly (~every
10s). Never acts inside the fiction directly.

**Layer 2 — scenario agents** (monitors like `QuarantineMonitor`, future threat entities):
in-fiction, deliberately blind to global state. They execute beats mechanically and honestly
— a pathogen doesn't know the player is losing; only the Overseer does, and it modulates by
choosing what the pathogen is ALLOWED to do next, not by faking outcomes.

Hard rule inherited from both Alien Isolation and this game's trust theme: **the Overseer
never cheats visibly and never lies through mechanics.** No teleporting threats, no retconned
rolls. It only turns knobs that exist in the simulation anyway.

## 2. Roguelite frame

- **Permadeath**: crew death is final (already true); run ends on all-crew-dead /
  ship-destroyed / AI-decommissioned (already wired in ScenarioRunner). SaveManager
  checkpoints exist ONLY at leg boundaries — no mid-scenario saves; quitting mid-scenario
  resumes from the leg start with the leg's starting state. Death is never rolled back.
- **A run = one voyage** of consecutive legs (scenario clusters). Ship, crew, trust, AI
  integrity, battery — everything persists between legs (already the design).
- **Escalation floor**: a per-leg minimum heat that only rises (leg 1 ≈ 0.2 → leg 6+ ≈ 0.7).
  The Overseer's mercy (see §4) can never drop effective heat below the floor — runs get
  harder no matter how badly it's going. Tough first, fair second.

## 3. The heat model (one number, carefully fed)

`heat` ∈ [0,1] is the Overseer's difficulty dial. It moves toward a target computed from a
rolling **performance score** — high performance pulls heat up, being smashed pulls it down —
with hysteresis (target must differ by >0.1 for 20s+ before heat starts moving; slew-rate
limited) so it never oscillates visibly.

Performance score inputs (rolling 3-5 min window; all signals already exist on EventBus):
| Signal | Push |
|---|---|
| crew_death | strongly down |
| injury / crew_panicked / high avg stress (>9) | down |
| ai_damaged / repair_refused / avg trust < 0.4 | down |
| battery < 30% / any room air < 40 / reactor+life-support both offline | down |
| repair_success / crisis_resolved / objective progress | up |
| all crew calm (stress ≤ 5) + all systems green + no active scenario beat | strongly up |
| wall-clock time since last meaningful player decision | up (boredom pressure) |

`effective_heat = max(heat, leg_escalation_floor)`.

## 4. What the Overseer does with heat

**Cruising (performance high, heat rising):**
- Compress event cooldowns / raise crisis-event weights in the ACTIVE scenario first.
- Past `OVERLAP_THRESHOLD` (heat ≥ ~0.75) AND active scenario older than its expected
  length: start a SECOND simultaneous scenario (cap: 2 concurrent; a second one must come
  from a different pressure axis — see compatibility matrix §5 — never two of the same kind).
- Prefer morphs/overlaps that exploit current weaknesses (low battery → power-hungry
  scenario; low trust → crew-drama scenario). The Overseer is allowed to be mean; it is not
  allowed to be arbitrary.

**Getting smashed (performance low, heat falling):**
- Stretch event cooldowns, halve new-crisis weights, delay the next scheduled beat.
- Hidden small mercies, strictly bounded: +5 on repair/bypass check targets, slightly slower
  battery drain (≤10%), one extra beat of quiet before the next act. Never announced, never
  visible in UI, never below the escalation floor, and NEVER cancels an in-flight
  consequence (a death spiral already rolling is allowed to land — mercy shapes what comes
  NEXT, not what already happened).
- If two crew died within the window: force a `quiet_shift` recovery beat before any new
  scenario starts (grief dialogue, repairs, Rest Saves get room to breathe).

**Always:** dialogue pressure follows automatically — stress/panic/recent-events already
drive the corpus; the Overseer needs no dialogue integration.

## 5. Scenario flex & morph

Scenarios stop being one-shot islands. Each scenario definition gains:
- `pressure_axis`: one of `systems` (power/air/hull), `bio` (disease/infestation),
  `social` (trust/mutiny/romance-fallout), `external` (artifact/comms/combat).
- `morph_edges`: outgoing transitions — `{to, condition_flags, overlap_ok, weight}`.
  Conditions are the scenario-flag vocabulary that already exists (e.g. quarantine ends with
  `pathogen_contained=false` → morphs toward a crew-drama "blame" scenario; NarrowPassage
  ends with `battery < 20%` → eligible morph into a systems-failure scenario).
- Morphs may OVERLAP: scenario B's act 1 may start while scenario A's act 3 winds down
  (the handoff feels continuous — "the ship never stops being a ship").
- Compatibility matrix: two concurrent scenarios must differ in `pressure_axis`, and
  `social` scenarios can run alongside anything (crew drama layers over any crisis).

The Tier-1 bible scenarios get axes/edges as data in their builders; the Overseer picks by
weight × heat-fit × axis-compatibility × recent-history (no repeats within 2 legs).

## 6. Implementation map (existing code → new)

| Piece | Where | Change |
|---|---|---|
| Overseer core | `scripts/scenarios/scenario_director.gd` | grow: heat model, performance window, mercy/pressure knob application, overlap scheduling. Keep its existing tension/tone drift as the WITHIN-scenario pacing layer. |
| Multi-scenario runtime | `scripts/scenarios/scenario_runner.gd` | refactor single active scenario → `active_scenarios: Dictionary` (id → instance); win/lose per scenario; RUN-lose conditions stay global. Monitors already avoid exclusive signal ownership (NarrowPassage brief enforced this). |
| Scenario metadata | each `*_scenario.gd` builder | add `pressure_axis`, `expected_length`, `morph_edges` static data. |
| Escalation floor / legs | `scenario_runner.gd` handoff stub | leg counter → floor table; checkpoint hook (SaveManager) at leg boundary only. |
| Mercy knobs | `checks.gd` (`extra_bonus` already exists), `power_model.gd` (drain multiplier), `event_pool.gd` (weight/cooldown multipliers) | thread a single `Overseer.modifiers` read — no scattered special cases. |
| Heat inputs | EventBus (all signals exist) | Overseer connects; no new emitters needed except objective-progress pings from monitors. |

## 7. Legibility & tells

The player must FEEL the pacing, never see the dial: no heat UI, no difficulty text, no log
lines. The only legitimate tells are diegetic — event frequency, crew mood, how much quiet
they get. Debug: `SHIPAI_DIRECTOR_DEBUG=1` env prints heat/performance/decisions to console
(dev only). The AUTODEMO hooks must keep working with the Overseer active (it should detect
scripted runs via the existing env hooks and hold heat neutral so verification stays
deterministic).

## 8. Build order (for the implementing agent)

1. Heat + performance window inside ScenarioDirector (read-only, debug-printed) — verify
   numbers move sanely across an AUTODEMO run and a sandbox run.
2. Knob application (cooldown/weight/mercy modifiers) — single `modifiers` surface.
3. ScenarioRunner multi-instance refactor (the risky bit — both existing scenarios must
   still pass their autodemo wins after it).
4. Morph edges + axis metadata on Quarantine + NarrowPassage; first live morph.
5. Overlap scheduling behind heat threshold; escalation floor + leg checkpoint hook.
