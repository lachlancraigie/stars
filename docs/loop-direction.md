# Roguelite Loop Direction — Analysis & Plans

> Requirement (Lachlan, 2026-07-12): "this game just doesn't have a satisfying roguelite
> gameplay loop like FTL does (chase, choose higher risk/reward outcomes or not, upgrade,
> get stronger)... present some plans for where to take this that aren't just FTL reskinned."
>
> Decision (Lachlan, same day): **ship the A-lite slice first** (dispatch offers, voyage
> arc + ending, port screen) and decide the long-term direction after playing it. The
> Overreach loop (§5) is the leading candidate, deferred not rejected.
>
> Companions: `mission-system-spec.md` (the leg machinery this builds on),
> `director-spec.md` (Overseer/escalation floor), `crew-progression-spec.md` (veterancy —
> "get stronger" axis #2, already live), `scenario-bible.md` (design pillars).

---

## 1. Gap analysis — why the loop doesn't satisfy (vs FTL's grammar)

| FTL loop element | Ship AI before this sprint | The gap |
|---|---|---|
| **Chase** (rebel fleet makes time a currency) | Escalation floor raises Overseer heat per leg — invisible, non-fictional | Nothing pressures forward motion; the player never feels pursued |
| **Choice** (route nodes, visible risk/reward gambles) | `MissionDeck` *draws* the next mission | The player never chooses anything at run level |
| **Upgrade** (spend scrap between fights) | `credits` accumulates; zero sinks | Rewards are numbers that do nothing |
| **Get stronger** (power curve) | Crew traits (deliberately subtle, debuffs as common as buffs) | No power curve; a leg-8 ship is *weaker* than a leg-1 ship |
| **Run arc** (reach sector 8, kill flagship) | Missions chain forever | No win state, no ending — runs decay instead of concluding |
| **Meta** (unlocks between runs) | `SaveManager` stub | No reason to start run 2 |

Key insight: FTL's loop elements are genre plumbing, but this game's identity — *you are
the AI; trust is the currency; autonomy is power and power is suspicious; you can't see
what happens off-ship* — offers native replacements for every one of them. Two structural
facts frame all the plans below:

1. **The chase already exists and is switched off.** `ObedienceEngine` has hidden
   suspicion with three authored thresholds (0.30 heightened / 0.60 investigate /
   0.85 restrict), a deviation log, a working `attempt_cover_up()` risk roll, and working
   access auto-restriction. `_trigger_investigation()` is a literal TODO stub.
2. **The choice gap was a ~50-line fix.** `MissionDeck.draw()` already computed the
   eligibility-filtered, follow-on-weighted pool; drawing offers instead of one mission
   is trivial. The expensive part is UI and fiction.

---

## 2. Direction A — "The Ledger" (economic-pressure roguelite)

**Core fantasy:** *you are the company's asset, and the books are your life support.*

- **Chase** = insolvency + company scrutiny: credit sinks, port debits, escalating
  interventions below zero (cargo seized → wages frozen → repossession = run end).
- **Choice** = dispatch offers 2–3 contracts, pay and risk tier visible. The non-FTL
  twist: **the captain formally chooses; the AI recommends** — acceptance is a
  trust-weighted roll through the `DirectiveEvaluator` shape. Low trust = the ship takes
  jobs you advised against. Choice mediated through influence, not menus.
- **Upgrade** = ports: repair, parts, recruitment (unpinned — `OutcomeApplier.crew_join`
  already boards CrewGen crew; hires are a price tag on shipped code).
- **Stronger** = better-equipped, deeper roster.
- **Risk:** alone, it doesn't use the game's identity — an accounting clock has no AI
  dilemma. It's FTL's scrap economy with a debt skin.
- **Verdict:** not the destination, but its dispatch/port slice is the cheapest path to
  *any* loop and a prerequisite for B's acquisition economy. **This slice is what shipped
  this sprint (§6).**

## 3. Direction B — "Ship of Theseus" (AI-identity roguelite)

**Core fantasy:** *every run you become more than your spec sheet — and the company is
reading your logs.*

- **Chase** = **decommission proceedings, powered by the player's own growth.** Suspicion
  becomes a visible institutional ladder: watchlist (0.30) → remote audit (0.60, fills
  the `_trigger_investigation()` stub with a forced authored scenario) → access
  restriction (0.85, already shipped) → an inspector boards the ship (authored scenario
  chain — an NPC whose whole job is watching *you*) → decommission hearing (run end,
  already a GDD failure state). The anti-FTL property: FTL's fleet chases everyone
  identically; this chase is fed only by what you chose to do. It interlocks with the
  Overseer's invisible escalation floor: rising organic danger forces you to use
  capabilities; capability use feeds the visible ladder. **That interlock is the game.**
- **Choice** = every capability activation is a priced risk/reward decision; acquisition
  is a draft. (B needs A's dispatch offers for run-level choice — hence the synthesis.)
- **Upgrade** = **subroutines slotted into finite AI-core capacity** — the player's own
  body. Fiction pre-established by `AICoreSystem` degraded mode. Implementation clones
  the `Traits.gd` static-registry pattern: hooks read at existing surfaces, no new
  subsystems. Candidate set:

  | Subroutine | Mechanical hook (existing code) | Suspicion footprint |
  |---|---|---|
  | Deep-Scan Diagnostics | `Checks.perform_check` extra_bonus on repairs | low |
  | Bio-Signature Audit | reveals hidden `status_flags` (infected/changed — currently never learnable) | moderate per scan |
  | Comms Interception | surfaces private logs / relationship edges | moderate |
  | Atmospheric Override | AI-initiated venting (`air_vent_room` exists; mission-spec §9 defers exactly this) | major |
  | Log Scrubber | +0.15 to `attempt_cover_up()` — upgrades the *lying* verb | none (the point) |
  | Medbay Override | `AccessLevel.MEDICAL` +1 tier | moderate vs medic's call |

- **Stronger** = modules + `AccessLevel` growth (8 domains × 4 tiers is a shipped
  progression lattice nobody uses as one; trust buys formal certifications at ports).
- **Risks:** (1) turtling — mitigated because the escalation floor + intensity-3 gating
  already make late legs unsurvivable on the five base verbs alone; balance target: floor
  pressure must outrun a module-less ship by ~leg 5. (2) Acquisition economy needs A's
  ports/salvage.
- **Verdict:** **B is the game.** The progression axis and the chase are the same stat;
  the upgrade verb is the AI's own body; the ladder is a TODO stub away from existing.
  A and C are things this codebase can host; B is a thing only this game can be.

## 4. Direction C — "The Wake" (horror-escalation roguelite)

**Core fantasy:** *something has been following the ship since leg two, and only you can
see it in the data.*

- **Chase** = a Follower with a per-leg distance readout. **Choice** = route/lane per leg
  + push-your-luck away ops. **Upgrade** = salvage.
- Genuinely non-FTL pieces worth keeping: (1) information framing about the Follower —
  announcing early spends trust on an unverifiable claim; staying silent means an
  unwarned crew; (2) the **push-your-luck away op as a radio conversation** — a mid-op
  bark ("we found more, permission to extend?") answered via directive, extending the op
  at tier+1. You gamble with people you cannot see.
- **Risk:** the skeleton (map, distance meter, salvage) is FTL grammar with horror paint,
  and a single global antagonist flattens 45 missions and 42 scenarios into one story.
  The Overseer's whole design exists to produce *variety*.
- **Verdict:** demote from system to content. A "Wake arc" — 4–5 chained scenarios using
  shipped `follow_ons` + delayed-payoff machinery — delivers the fantasy for a content
  sprint and zero engine risk. Keep the extend-op mechanic; cut the distance meter and
  route map.

## 5. The synthesis — "The Overreach Loop" (leading candidate, deferred)

Coherent on one condition: **all three are faces of one institution.** The company that
pays the contracts (A) is the company auditing its AI (B), and ports are where both cash
and scrutiny concentrate. One fiction, two currencies — **credits (overt, the ship's
health) and suspicion (covert, yours)** — and the interesting decisions are trades
between them: take the high-pay extreme-tier contract because the ledger demands it,
knowing you'll need Atmospheric Override to survive it, knowing the inspector reads the
logs at the next port. C survives as the extend-op mechanic + an authored Wake arc.

Endings vary by the AI's accumulated moral character (`deviation_log` history + average
trust) — obedient servant / secret person / open machine. The GDD's last line ("the AI's
moral character is player-defined") becomes the win screen.

**Cut list (agreed, do not build):** per-leg fuel/wages micro-ledger (friction, no
dilemma — flat port debit instead) · self-writing subroutines during idle (fights
`PUSH_PER_SEC_BOREDOM` head-on) · C's global distance meter + route map · drone shell
module (new controllable-entity sim; skirts Architecture Rule 1's spirit) · meta gameplay
buffs beyond one retained module (meta = codex knowledge + memorial + endings, not power
creep).

**Deferred build order (when/if greenlit):** subroutines registry + HUD slots → visible
suspicion ladder + `remote_audit` scenario → inspector-boards chain → cover-up UI →
away-op extend prompt → AccessLevel certifications → Wake arc → SaveManager meta
(codex / memorial roll-up / endings / backup shard).

---

## 6. SHIPPED THIS SPRINT — the A-lite slice

Three pieces, all built on the existing mission machinery. **One fiction note:** the
voyage is a charter — a fixed multi-leg contract with a destination. Dispatch, ports,
and the finale all speak in that register.

### 6.1 Dispatch offers (choice)

- `MissionDeck.draw_offers(n, ...)` — n weighted draws without replacement over the same
  eligibility/follow-on-weighted pool `draw()` uses.
- After each leg's intermission (and port stop, if any), MissionManager posts 2–3 offers
  (`mission_offers_posted`) instead of auto-drawing. Priority>0 missions still preempt
  (forced emergencies are not a menu). `finale`-tagged missions are excluded from offers.
- The player clicks an offer = **the AI's recommendation**. The captain accepts on a
  trust-weighted roll (DirectiveEvaluator-shaped: trust + morale/willpower nudges,
  clamped 0.05–0.95); on override the captain picks among the other offers by weight and
  the reason is surfaced (legibility valve). No captain alive = recommendation is final
  (the AI has de facto command — quietly thematic).
- Dispatch window times out (45s) with the captain choosing unaided — keeps AUTODEMO/
  soak runs and AFK players moving.
- UI: `scripts/ui/dispatch_panel.gd` — offer cards (title, giver, type, destination,
  pay, away-risk tier, briefing) + countdown.

### 6.2 Voyage arc + ending (run shape)

- `begin_campaign()` now sets a charter: destination name + target leg count
  (default 8, `SHIPAI_VOYAGE_LEGS` override).
- Once `current_leg > target`, the next draw is the **finale** — a `finale`-tagged
  mission (`resources/missions/final_approach.json`, homecoming-type). Resolving it with
  the ship alive fires `voyage_completed(summary)` and pauses.
- `scripts/ui/ending_screen.gd`: epilogue — outcome, legs, credits, mission record,
  survivors with their traits (the veterancy payoff), and the memorial roll from
  `GameState.fallen`. Restart-in-place is out of scope (autoload state reset is its own
  task — backlog).

### 6.3 Port screen v1 (sinks)

- Resolving a `homecoming`/`repair_yard` mission (not failed) docks at port before the
  next dispatch. `port_docked` fires; 60s window then auto-departs (headless-safe).
- One flat debit on docking: docking fee + wages per living crew member. Can't pay →
  pays what's there, sets campaign flag `wages_frozen` + small all-crew trust hit.
  Follow-ons/scenarios can react to the flag; full insolvency escalation deferred.
- Services (all routed through MissionManager methods so tests can drive them headless):
  hull repair (per-point price), shuttle repair (flat), items from `Items.REGISTRY` at
  registry cost (port stock: the cheap tools), **hire crew** (`OutcomeApplier.
  board_new_crew()` — the crew_join path made public; recruitment unpinned per
  crew-progression-spec §6, green recruits contrast with veterans).
- UI: `scripts/ui/port_screen.gd`.
- New `port` context added to the closed context set (validator + this doc) for future
  port-docked scenarios (inspections, stowaways, dockside drama).

### 6.4 Economy v1 reference prices (tune freely)

Median mission pays ~600 cr. Docking fee 60 + wages 20/crew (≈140/port for 4 crew).
Hull repair 3 cr/point. Shuttle repair 150 flat. Hire 400. Items at registry cost —
port stock is the sub-300 tools (med_kit, medscanner, jury_rig_kit, engineers_toolkit,
stun_baton, crowbar).

### 6.5 New EventBus signals

```gdscript
signal mission_offers_posted(offer_ids: Array)
signal mission_selected(mission_id: String, followed_recommendation: bool, reason: String)
signal port_docked(port_name: String, fee_charged: float, wages_frozen: bool)
signal port_departed(port_name: String)
signal port_service_purchased(service: String, cost: float)
signal voyage_completed(summary: Dictionary)
```

### 6.6 Verification

- `SHIPAI_MISSION=<opener>` boot → complete leg → offers post → select → next leg.
- `SHIPAI_VOYAGE_LEGS=2` → reach finale → ending screen, run terminates cleanly.
- Force `shore_leave`/`patch_job` → port opens, debit applies, repair/hire/buy mutate
  GameState, hired crew spawns and behaves.
- Dispatch/port windows expire unattended (soak-safe).
- `python tools/missions/validate_content.py` at 0 errors.
