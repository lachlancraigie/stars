# Crew Progression — X-COM-Style Veterancy Specification

> Requirement (Lachlan, 2026-07-10): "I would like the crew to be like your soldiers in X-COM.
> if they survive they can get buffs and debuffs that make them feel more real so it should be
> sad when one dies." Replacement crew (FTL-style recruitment) is explicitly PINNED FOR LATER —
> see scenario-bible.md's port/crew-recruitment system; do not build it yet, but nothing here
> may preclude it.
>
> Companions: docs/rules.md (Mothership 1e — this spec finally implements its dormant Rest
> Save / Shore Leave / trauma ideas), director-spec.md (leg boundaries are where most
> progression resolves), dialogue_spec.md (traits can bias line selection later).

---

## 1. Design intent

Crew accumulate HISTORY, not levels. Every scar, buff, and quirk traces to something the
player watched happen. A three-leg veteran with "Iron Lungs", "Survivor's Guilt", and a dead
partner is irreplaceable — and when she dies, the roster panel shows exactly what was lost.
Debuffs are as common as buffs: survivors get *specific*, not just stronger. Permadeath stays
absolute (roguelite frame, director-spec §2).

## 2. Traits

`CrewMember.traits: Array[String]` (persistent, serialized with the character). A static
registry (`scripts/core/traits.gd`, same pattern as Items) defines each trait:
`{id, display_name, blurb, hooks}` where hooks are read at existing mechanical surfaces —
no new subsystems, just reads:

| Hook surface | Existing code point |
|---|---|
| stat/save modifiers | `Checks` (same shape as item bonuses / `extra_bonus`) |
| skill bonus | `CrewMember.get_skill_bonus` |
| stress gain/relief multipliers | `CrewMember.add_stress` / Rest Save resolution |
| needs drift (fear/loneliness/morale floors) | `NeedsModel` |
| dialogue bias (later, optional) | DialogueSystem scoring nudge keyed by trait |

## 3. Earning traits (event → roll at the right moment)

Immediate (the moment it happens) vs leg-boundary (resolved with Rest Saves at the
checkpoint). Every earn rolls a Save per Mothership idiom — success tends toward the buff,
failure toward the scar. Starter table (tune freely; ~a dozen traits is plenty for v1):

| History | Roll | Buff | Debuff |
|---|---|---|---|
| Survived suffocation / near-vacuum | Body | **Iron Lungs** (+5 Body vs air/vacuum) | **Vacuum Nightmares** (fear checks at disadvantage in airlock/low-air rooms) |
| Survived a panic episode | Sanity | **Battle Calm** (+1 panic-table shift) | **Jumpy** (permanent: adjacent panic gives +1 extra stress) |
| Watched a crewmate die | Fear | **Hardened** (stress gain from deaths halved) | **Survivor's Guilt** (min stress +1) |
| Partner died | — (automatic) | — | **Widowed** (loneliness floor raised; grief dialogue bias) |
| Completed a crisis repair (reactor/LS/AI core during a live failure) | Intellect | **Field-Certified** (+5 that skill family) | — |
| Wounded and recovered | Body | **Scar Tissue** (+1 max wound... no: +2 Body) | **Old Wound** (−5 Speed; pain flare dialogue) |
| Bypassed a locked door under stress | — | **Cool Hands** (+5 bypass/tech checks) | — |
| Survived N legs (3 / 6) | — (automatic) | **Old Hand / Lifer** (+2 / +5 all saves) | comes WITH **Set in Their Ways** at 6 (−5 to checks outside their skill set) |
| AI saved their life (door/air/repair traceable to player action) | — (automatic) | **Believer** (personal trust floor raised) | — |
| AI action harmed them (lockout ≥3 / air cut while inside) | — (automatic) | — | **Machine-Wary** (personal trust ceiling lowered) |

Caps: max ~5 traits per crew; a new earn beyond cap replaces the weakest same-polarity trait
(with a log line). No duplicate ids.

## 4. Leg-boundary resolution (ties into director-spec §2/§6)

At each leg checkpoint (Overseer's leg hook, already stubbed to SaveManager):
1. **Rest Saves** (`Checks.rest_save`, implemented but currently uncalled) — Mothership rules:
   success relieves stress toward minimum.
2. Pending trait rolls from the leg's history resolve (the table above).
3. Skill growth, XP-lite: tally each crew member's CRITICAL successes during the leg; at the
   boundary, one skill family with ≥2 crits gains +2 progress; at +10 progress a tier upgrade
   per Mothership prereq chains. Slow by design — veterancy is mostly traits, not stats.
4. Service record increments (`legs_served`).

## 5. Making it visible (the "sad when they die" part)

- **Roster panel** (HUD): click a crew member → service record: name, archetype blurb, legs
  served, traits with blurbs, skills, relationships (partner/friends via affinity), wounds.
  This panel is WHY death hurts — it's a biography, not a stat block.
- **Memorial**: `GameState.fallen: Array[Dictionary]` — snapshot (name, traits, legs, cause,
  partner) recorded by CrewLifecycle.kill. Grief dialogue already fires; a future port leg
  can hold a service. The roster panel gets a "Lost" tab.
- **Trait moments announce themselves diegetically**: earning a trait emits
  `crew_trait_gained(crew_id, trait_id)` → event feed line + a matching thought bubble
  (dialogue corpus `memory`/`doubt`/`boast` intents already fit).

## 6. Explicitly deferred

- Replacement crew / recruitment at ports (FTL-style) — PINNED per Lachlan; bible's
  port system is the intended vehicle. Design consequence honored NOW: traits/memorial must
  serialize cleanly so green replacements contrast with veterans later.
- Shore Leave stress→save conversion (needs the port economy).
- Trait-conditioned dialogue lines in the corpus (a later Haiku pass can add
  trait-flavored lines once trait ids are stable).

## 7. Build order (single agent, after the animation workstream)

1. Traits registry + CrewMember.traits + hook reads in Checks/NeedsModel/add_stress.
2. Earn triggers (EventBus listeners in crew space) + leg-boundary resolution incl. Rest
   Saves + crit-tally skill growth.
3. Memorial + service-record data.
4. Roster/inspection HUD panel (+ Lost tab).
5. Verify: both scenario autodemos + a forced multi-leg run (SHIPAI_FORCE_FLAG) showing a
   trait earned, a Rest Save firing, and a memorial entry.
