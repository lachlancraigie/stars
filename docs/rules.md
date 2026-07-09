---
name: mothership-1e-mechanics
description: Reference for implementing Mothership RPG (1st Edition) mechanics in code. Covers all core systems from the Player's Survival Guide v1.2.
---

# Mothership 1e — Mechanics Reference

This file is authoritative for all Mothership 1e rules. When implementing any game mechanic, resolve ambiguity by checking this file first. Where the rules say "use common sense", that means the Warden (GM) arbitrates — model this as a configurable/overridable flag rather than hardcoding an outcome.

---

## Currency & Notation

Credits (cr) are the only currency. Notation is shorthand:
- `cr` = face value (e.g. `100cr` = 100 credits)
- `kcr` = thousands (e.g. `2.5kcr` = 2,500cr)
- `mcr` = millions (e.g. `35.2mcr` = 35,200,000cr)
- `bcr` = billions (e.g. `4bcr` = 4,000,000,000cr)

Store all credit values internally as integers in base credits (cr). Convert for display only.

---

## Dice Notation

- **1d100 / d100 / percentile**: roll two d10s, one = tens digit, one = ones digit. `00` + `0` = 0 (not 100). Range is 0–99.
- **xd10**: roll x ten-sided dice and sum them. e.g. `2d10` = sum of two d10s.
- **1d20 (Panic Die)**: standard d20, only used for Panic Checks.
- **[+] Advantage**: roll the dice pool twice, take the **better** result.
- **[-] Disadvantage**: roll the dice pool twice, take the **worse** result.
- Advantage and Disadvantage cancel each other out (net zero regardless of multiples).
- `1d10+10`, `2d10+25` etc. are standard summed rolls with a flat modifier.

---

## Character Stats

### Four Stats (roll `2d10+25` each at character creation)

| Stat | Used for |
|------|----------|
| `strength` | Physical tasks under pressure — holding airlocks, carrying, climbing |
| `speed` | Reaction and movement — acting before others, running away |
| `intellect` | Mental tasks — recalling training, solving problems, inventing |
| `combat` | Fighting |

A value of 36 is considered average. Range at creation: 27–45 before class adjustments.

### Three Saves (roll `2d10+10` each at character creation)

| Save | Used for |
|------|----------|
| `sanity` | Rationalising the impossible, detecting illusions, coping with Stress |
| `fear` | Maintaining composure under emotional/psychological pressure |
| `body` | Quick reflexes, resisting disease/poison/alien organisms |

Range at creation: 12–30 before class adjustments.

---

## Classes

Four classes. Each modifies starting stats/saves and grants a Trauma Response.

```
MARINE:    +10 COMBAT, +10 BODY SAVE, +20 FEAR SAVE, +1 MAX WOUNDS
ANDROID:   +20 INTELLECT, -10 TO 1 STAT (player's choice), +60 FEAR SAVE, +1 MAX WOUNDS
SCIENTIST: +10 INTELLECT, +5 TO 1 STAT (player's choice), +30 SANITY SAVE
TEAMSTER:  +5 TO ALL STATS, +10 TO ALL SAVES
```

### Trauma Responses (triggered on Panic)

- **Marine**: Every Close friendly player must make a Fear Save.
- **Android**: Fear Saves made by Close friendly players are at Disadvantage.
- **Scientist**: Whenever the Scientist fails a Sanity Save, all Close friendly players gain 1 Stress.
- **Teamster**: Once per session, may take Advantage on a Panic Check.

---

## Health & Wounds

- **Max Health**: roll `1d10+10` at character creation.
- Marines and Androids start with **2 Max Wounds**; Scientists and Teamsters start with **1 Max Wound**.
- Characters start at Max Health with 0 Wounds.

### Damage flow

1. Subtract incoming DMG from current Health.
2. If Health reaches 0 or below: gain 1 Wound, roll on the **Wounds Table** (see below), reset Health to Max, then subtract carryover damage from the new Health total.
3. If Wounds = Max Wounds: make a **Death Save**.

Bleeding damage ignores Armor and Damage Reduction.

### Armor Points (AP)

- Characters **ignore** all damage strictly less than their AP.
- If a single hit deals damage **≥ AP**: armor is **destroyed** and the character takes the full damage amount (not just the overflow — the armor absorbed nothing on that hit once exceeded).
- **Anti-Armor (AA)** weapons always ignore and destroy armor.
- **Damage Reduction (DR)** reduces all incoming damage by its value, applied **before** Armor, even if armor is destroyed or weapon is AA.

### Cover

| Type | AP |
|------|----|
| Insignificant (wood furniture, body shields) | AP 5 |
| Light (trees, bulkhead walls, metal furniture) | AP 10 |
| Heavy (airlock doors, cement beams, ships) | DR 5 / AP 20 |

Cover only protects against ranged attacks (sometimes melee at Warden discretion). Shooting while in Cover puts you **out of Cover until your next turn**.

---

## Wounds Table

Roll `1d10` on the appropriate column when a Wound is gained. Use the weapon's wound type.

| d10 | Severity | Blunt Force | Bleeding | Gunshot | Fire & Explosives | Gore & Massive |
|-----|----------|-------------|----------|---------|-------------------|----------------|
| 00 | Flesh Wound | Knocked down | Drop held item | Grazed, knocked down | Hair burnt, gain 1d5 Stress | Vomit, [-] on next action |
| 01 | Minor Injury | Winded, [-] until catch breath | Lots of blood, Close crew gain 1 Stress | Bleeding +1 | Awesome scar, +1 Min Stress | Awesome scar, +1 Min Stress |
| 02 | Minor Injury | Sprained ankle, [-] Speed Checks | Blood in eyes, [-] until wiped | Broken rib | Singed, [-] next action | Digit mangled |
| 03 | Minor Injury | Concussion, [-] mental tasks | Laceration, Bleeding +1 | Fractured extremity | Shrapnel/large burn | Eyes gouged out |
| 04 | Minor Injury | Leg/foot broken, [-] Speed Checks | Major cut, Bleeding +2 | Internal bleeding, Bleeding +2 | Extensive burns, -1d10 Strength | Ripped off flesh, -1d10 Strength |
| 05 | Major Injury | Arm/hand broken, [-] manual tasks | Fingers/toes severed, Bleeding +3 | Lodged bullet, Surgery required | Major burn, -2d10 Body Save | Paralysed waist down |
| 06 | Major Injury | Snapped collarbone, [-] Strength Checks | Hand/foot severed, Bleeding +4 | Gunshot wound to neck | Skin grafts required, -2d10 Body Save | Limb severed, Bleeding +5 |
| 07 | Lethal Injury (Death Save in 1d10 rounds) | Back broken, [-] all rolls | Limb severed, Bleeding +5 | Major blood loss, Bleeding +4 | Limb on fire, 2d10 DMG/round | Impaled, Bleeding +6 |
| 08 | Lethal Injury (Death Save in 1d10 rounds) | Skull fracture, [-] all rolls | Major artery cut, Bleeding +6 | Sucking chest wound, Bleeding +5 | Body on fire, 3d10 DMG/round | Guts spooled on floor, Bleeding +7 |
| 09 | Fatal Injury (Death Save) | Spine/neck broken, Death Save | Throat slit or heart pierced, Death Save | Headshot, Death Save | Engulfed in fiery explosion, Death Save | Head explodes. No Death Save. You have died. |

### Bleeding

Bleeding wounds deal **1 Damage per round** (ignoring armor/DR). This is cumulative: Bleeding +1 on top of existing Bleeding 1 = 2 DMG/round. Treat or stop the bleeding to halt it.

### Death Save

When a character hits Max Wounds, the Warden rolls `1d10` secretly (hidden in a cup), revealed when someone checks the character's vitals.

| d10 | Result |
|-----|--------|
| 00 | Unconscious. Wake in 2d10 minutes. Reduce Max Health by 1d5. |
| 01–02 | Unconscious and dying. Die in 1d5 rounds without intervention. |
| 03–04 | Comatose. Only extraordinary measures can return them. |
| 05–09 | Dead. Roll a new character. |

---

## Stat Checks

Used when the character attempts something with high failure cost.

1. Roll `1d100`.
2. If result < relevant Stat: **success**.
3. If result ≥ relevant Stat: **failure**, gain 1 Stress.
4. **90–99 always fails**, regardless of Stat value.
5. **Doubles are Criticals** — if success: Critical Success (something very good); if failure: Critical Failure (something bad + make a Panic Check).
6. `00` is always a Critical Success. `99` is always a Critical Failure.

---

## Saves

Same mechanic as Stat Checks but using a Save value (Sanity, Fear, or Body). Triggered reactively to avoid danger/trauma. Failures also gain 1 Stress. Same critical/90-99 rules apply.

---

## Skills

Skills add a flat bonus to the relevant Stat or Save *before* rolling.

| Tier | Bonus |
|------|-------|
| Trained | +10 |
| Expert | +15 |
| Master | +20 |

Expert requires at least one Trained prerequisite. Master requires at least one Expert prerequisite. Skills are specific to domains — grant the bonus only when the skill is directly relevant to the task.

### Starting Skills by Class

```
MARINE:    Military Training (T), Athletics (T)
           Bonus: 1 Expert Skill OR 2 Trained Skills

ANDROID:   Linguistics (T), Computers (T), Mathematics (T)
           Bonus: 1 Expert Skill OR 2 Trained Skills

SCIENTIST: 1 Master Skill + its Expert + Trained prerequisites
           Bonus: 1 Trained Skill

TEAMSTER:  Industrial Equipment (T), Zero-G (T)
           Bonus: 1 Trained Skill + 1 Expert Skill
```

### Trained Skills (full list)
Archaeology, Art, Athletics, Botany, Chemistry, Computers, Geology, Industrial Equipment, Jury-Rigging, Linguistics, Mathematics, Military Training, Rimwise, Theology, Zero-G, Zoology

### Expert Skills (require 1 Trained prerequisite)
Asteroid Mining, Ecology, Explosives, Field Medicine, Firearms, Hacking, Hand-to-Hand Combat, Mechanical Repair, Mysticism, Pathology, Pharmacology, Physics, Piloting, Psychology, Wilderness Survival

### Master Skills (require 1 Expert prerequisite)
Artificial Intelligence, Command, Cybernetics, Engineering, Exobiology, Hyperspace, Planetology, Robotics, Sophontology, Surgery, Xenoesotericism

---

## Stress & Panic

### Stress

- Starts at 2 (both current and Minimum).
- Maximum is 20.
- Gained on failed Stat Checks, failed Saves, and certain events.
- Damage over 20 reduces the most relevant Stat or Save by the overflow amount.
- Stress by itself does nothing — it increases Panic risk.

### Gaining Stress

- Fail a Stat Check or Save: +1 Stress.
- Certain Panic Table results modify Minimum Stress.
- Some wounds or events add Stress directly.

### Relieving Stress (Rest)

In a relatively safe location:
1. Make a Rest Save using the **worst** Save value.
2. Success: reduce Stress by the **ones digit** of the roll (e.g. roll 24 → reduce by 4).
3. Failure: gain 1 Stress.
4. Advantage on Rest Saves from: consensual sex, recreational drug use, heavy drinking, prayer, other leisure activities.
5. Unsafe locations may impose Disadvantage at Warden discretion.
6. Stress is not relieved during cryosleep.

### Shore Leave (converting Stress to Saves)

Requires credits and a relatively safe Port. Roll a Sanity Save:
- **Success**: convert Stress (amount varies by Port class, see below) into +1 to any Save per point converted. Remaining Stress relieved, reset to Minimum.
- **Critical Success**: convert the maximum allowed, relieve rest.
- **Failure**: no conversion, all Stress relieved to Minimum, +1 Stress for failing.
- **Critical Failure**: nothing converted or relieved, make a Panic Check.

| Port Class | Cost | Stress Converted |
|------------|------|-----------------|
| X-Class | 1d100 × 10kcr | 2d10 [+] |
| C-Class | 2d10 × 100cr | 1d5 |
| B-Class | 2d10 × 1kcr | 1d10 |
| A-Class | 2d10 × 10kcr | 2d10 |
| S-Class | 2d10 × 100kcr | All |

Shore Leave duration: 2d10 days minimum.

### Panic Checks

Roll the Panic Die (1d20) and attempt to roll **greater than** current Stress. If you fail (roll ≤ Stress), look up the result on the Panic Table.

**When to make a Panic Check:**
- On a Critical Failure on any Stat Check or Save.
- Watching a crewmember die.
- Witnessing 2+ crewmembers Panic simultaneously.
- Ship Critical Failure (everyone on board).
- First encounter with a horrifying entity.
- When all hope is lost.
- Any time a player voluntarily wants to.

### Panic Table (d20, rolled on failure)

| d20 | Effect |
|-----|--------|
| 01 | ADRENALINE RUSH: [+] all rolls for 2d10 min. Reduce Stress by 1d5. |
| 02 | NERVOUS: Gain 1 Stress. |
| 03 | JUMPY: Gain 1 Stress. All Close crewmembers gain 2 Stress. |
| 04 | OVERWHELMED: [-] all rolls for 1d10 min. Increase Minimum Stress by 1. |
| 05 | COWARD: New Condition — must make Fear Save to engage in violence or flee. |
| 06 | FRIGHTENED: New Condition — when re-encountering what frightened you, Fear Save [-] or gain 1d5 Stress. |
| 07 | NIGHTMARES: New Condition — sleep is difficult, [-] on Rest Saves. |
| 08 | LOSS OF CONFIDENCE: New Condition — lose the bonus from one chosen Skill. |
| 09 | DEFLATED: New Condition — whenever a Close crewmember fails a Save, gain 1 Stress. |
| 10 | DOOMED: New Condition — all Critical Successes become Critical Failures. |
| 11 | SUSPICIOUS: For the next week, when anyone joins the crew (even briefly), Fear Save or gain 1 Stress. |
| 12 | HAUNTED: New Condition — something visits the character at night and will start making demands. |
| 13 | DEATH WISH: For 24 hours, on encountering a stranger or known enemy, Sanity Save or immediately attack. |
| 14 | PROPHETIC VISION: Intense hallucination of impending terror. Increase Minimum Stress by 2. |
| 15 | CATATONIC: Unresponsive for 2d10 min. Reduce Stress by 1d10. |
| 16 | RAGE: [+] all Damage rolls for 1d10 hours. All crewmembers gain 1 Stress. |
| 17 | SPIRALING: New Condition — all Panic Checks at [-]. |
| 18 | COMPOUNDING PROBLEMS: Roll twice on this table. Increase Minimum Stress by 1. |
| 19 | HEART ATTACK / SHORT CIRCUIT (Androids): Reduce Max Wounds by 1. [-] all rolls for 1d10 hours. Increase Minimum Stress by 1. |
| 20 | RETIRE: Roll a new character. |

Conditions persist until treated (see Medical Care).

---

## Combat

### Turn Order

Mothership does **not** use individual initiative by default. Each round (~10 seconds):
1. Warden describes the situation and what happens if no one acts.
2. Players declare actions simultaneously.
3. Warden resolves all actions at once, assigns rolls.
4. Damage and Wounds are rolled.
5. Warden describes new situation. Repeat.

**Optional strict initiative**: at encounter start, all players make Speed Checks. Success = act before hostiles; failure = act after.

### Actions per Round

A character can **move to Close Range** and **do one thing**. If only running (no other action), they can move to **Long Range**.

### Attacking

1. Make a Combat Check (roll 1d100 under Combat stat, add relevant Skill bonus if applicable e.g. Firearms for guns, Hand-to-Hand for melee).
2. Success: roll weapon damage, subtract from enemy Health.
3. Failure: situation worsens, gain 1 Stress.

### Surprise

If characters are ambushed, Warden calls a Fear Save. Success = can react; failure = cannot act until next round.

---

## Range Bands

| Band | Approximate Distance | Notes |
|------|---------------------|-------|
| Adjacent | <1m / 3ft | Touch range. Fist fights, first aid, terminals. |
| Close | ~5–10m / 15–30ft | Can reach in a few seconds. Shotguns most effective here. |
| Long | ~20–100m / 50–300ft | Rifles effective; handguns/shotguns less so. Full round+ to cross. |
| Extreme | >100m / 300ft | Only Smart Rifles and similar. Multiple turns to reach. |

---

## Weapons

All weapons have: Cost, Range, Damage dice, Shots (magazine size, N/A = no ammo tracking), Wound type, and Special rules.

### Wound Types
`blunt_force`, `bleeding`, `gunshot`, `fire_explosives`, `gore_massive`

### Key Weapon Rules
- **Anti-Armor (AA)**: bypasses and destroys armor on any hit.
- **Heavy**: typically requires two hands.
- **Bleeding +N**: adds N to the character's ongoing Bleeding value on a Wound.
- Flamethrower: target makes Body Save [-] or is set on fire for 2d10 DMG/round.
- Rigging Gun: 1d10 initial + 2d10 when removed. Body Save or become entangled.
- Laser Cutter: 1 round recharge between shots.
- Smart Rifle: [-] on Combat Check when used at Close Range.
- Vibechete: on a Wound, roll on **both** Bleeding and Gore columns.
- Stun Baton: Body Save or stunned 1 round.
- Tranq Pistol: if damage dealt, target Body Save or unconscious 1d10 rounds.
- Foam Gun: Body Save or become stuck; Strength Check [-] to escape.
- Unarmed: Strength ÷ 10 damage (rounded down), min 1.

### Weapon Table

| Weapon | Cost | Range | Damage | Shots | Wound |
|--------|------|-------|--------|-------|-------|
| Boarding Axe | 150cr | Adjacent | 2d10 | N/A | Gore [+] |
| Combat Shotgun | 1,400cr | Close | 4d10 | 4 | Gunshot |
| Crowbar | 25cr | Adjacent | 1d5 | N/A | Blunt Force [+] |
| Flamethrower | 4kcr | Close | 2d10 | 4 | Fire/Explosives [+] |
| Flare Gun | 25cr | Long | 1d5 | 2 | Fire/Explosives [-] |
| Foam Gun | 500cr | Close | 1 | 3 | Blunt Force |
| Frag Grenade | 400cr | Close | 3d10 | 1 | Fire/Explosives |
| GPMG | 4.5kcr | Long | 4d10 | 5 | Gunshot [+] |
| Hand Welder | 250cr | Adjacent | 1d10 | ∞ | Bleeding |
| Laser Cutter | 1,200cr | Long | 1d100 | 6 | Bleeding [+] / Gore [+] |
| Nail Gun | 150cr | Close | 1d5 | 32 | Bleeding |
| Pulse Rifle | 2.4kcr | Long | 3d10 | 5 | Gunshot |
| Revolver | 750cr | Close | 1d10+1 | 6 | Gunshot |
| Rigging Gun | 350cr | Close | 1d10 (+2d10 on removal) | 1 | Bleeding [+] |
| Scalpel | 50cr | Adjacent | 1d5 | N/A | Bleeding [+] |
| Smart Rifle | 5kcr | Extreme | 4d10 AA | 3 | Gunshot [+] |
| SMG | 1kcr | Long | 2d10 | 5 | Gunshot |
| Stun Baton | 150cr | Adjacent | 1d5 | N/A | Blunt Force |
| Tranq Pistol | 250cr | Close | 1d5 | 6 | Blunt Force |
| Unarmed | Free | Adjacent | STR÷10 | N/A | Blunt Force |
| Vibechete | 1kcr | Adjacent | 3d10 AA | N/A | Bleeding + Gore |

---

## Armor

| Armor | Cost | AP | O2 | Speed | Notes |
|-------|------|----|----|-------|-------|
| Standard Crew Attire | 100cr | 1 | — | Normal | Basic clothing |
| Vaccsuit | 10kcr | 3 | 12hr | [-] | Comms, headlamp, radiation shielding. Decompresses in 1d5 rounds if punctured. |
| Hazard Suit | 4kcr | 5 | 1hr | Normal | Air filter, heat/cold protection, hydration reclamation (1L water lasts 4 days), comms, headlamp, radiation shielding. |
| Standard Battle Dress | 2kcr | 7 | — | Normal | Short-range comms. |
| Advanced Battle Dress | 12kcr | 10 | 1hr | [-] | Comms, body cam, headlamp, HUD, exoskeletal weave (Strength [+]), radiation shielding. DR 3. |

Speed [-] means Speed Checks are at Disadvantage while wearing.

---

## Equipment (Selected Rules)

- **Stimpak**: cures cryosickness, -1 Stress, +1d10 Health, [+] all rolls for 1d10 min. Roll 1d10; if under doses taken in last 24hr, make a Death Save. Cost: 1kcr each.
- **Salvage Drone**: can carry 20–30kg, fly 450m high, 3km range, 2hr runtime. Can be equipped with up to 2 attachments.
- **Patch Kit (x3)**: repairs punctured vaccsuits. Patched vaccsuits have AP 1.
- **Exoloader**: can only be worn with Standard Crew Attire or Standard Battle Dress. Loader claws deal 1 Wound directly.
- **Radio Jammer**: blocks Emergency Beacon and Detonator signals within 100km.
- **Smart-link Add-On**: +5 DMG to a ranged weapon, enables remote operation and recording.

---

## Survival Conditions

### Bleeding
1 DMG/round cumulative. Bypasses armor and DR. Must be actively treated.

### Oxygen
- 15 seconds without O2 before unconscious.
- After unconscious: 1d5 minutes before death.
- Ship O2 supply: multiply 1d10 × max crew capacity = remaining O2 units.
- Subtract breathing crew count every 24hr. Strenuous activity (combat, running, repairs) costs 2 extra per person.
- O2 supply < 2× breathing passengers: all rolls at Disadvantage.
- O2 supply < breathing passengers: every passenger Body Save each round or Death Save.
- Androids consume no O2. Cryosleeping crew don't reduce supply.

### Radiation

| Level | Source | Effect |
|-------|--------|--------|
| Level 1 – Trace | Normal cosmic radiation | No immediate effect; long-term risk |
| Level 2 – Acute | Unshielded reactors, Warp Cores | -1 to all Stats and Saves per round |
| Level 3 – Lethal | Atomic weapons, direct Warp Core contact | Body Save each round or lethal dose (death in 1d5 days) |

Armor with Radiation Shielding (Vaccsuit, Hazard Suit, Advanced Battle Dress) blocks all three levels.

### Cryosickness
After emerging from cryosleep: [-] on all rolls for 1 week. Cured instantly by a Stimpak.

### Atmospheres
- **Toxic**: not breathable but otherwise safe. Without a rebreather or O2 armor: 1d10 DMG/round, Body Save for half.
- **Corrosive**: 1–10 DMG/round depending on severity. Anything above 10 requires specialised equipment — treat as impassable.

### Exhaustion
After 12+ hours of activity, make a Body Save every hour. Failure: +1 Stress, 1 DMG. After 24hr continuous exhaustion: [-] all rolls until 8hr rest.

### Food & Water
- No food for 24hr: [-] all rolls.
- Water minimum: 1L/day. Strenuous activity at minimum water: Body Save or pass out.
- Tracking scarce water closely: [-] all rolls.

### Temperature
- **Extreme Cold**: hypothermia/frostbite in 10–30 min without appropriate gear. Fatal in 30 min – 6 hours.
- **Extreme Heat**: >100°F/40°C. Body Saves each hour or succumb. Fatal within hours.

---

## Medical Care

### Short-Term Recovery
Once per day, after 6+ hours rest: Body Save. Success = reset Health to Max. Wounds do **not** heal this way.

### Long-Term Treatments

| Treatment | Cost | Effect |
|-----------|------|--------|
| Artificial Wellness Counselor | 150cr | 1hr session (max 1/wk). +1 Sanity Save. 1% chance random Condition. |
| Cognitive Defragmentation | 100kcr | 24hr surgery. Remove 1 Condition. 1% total amnesia. [-] Intellect/Sanity/Fear for 4 wks. |
| Deep Tissue Nanogel Massage | 24kcr | 1hr (max 1/wk). -1 Minimum Stress. [-] all actions 24hr. |
| Immersive Slicksim Therapy | 1kcr | 4hr. Restore 1d10 Combat OR 1d10 Fear Save. 1% stuck 1d10 days + lose 1d5 Sanity. |
| Medpod | 6kcr | 1 week. Restore 1 Wound. Does not restore lost limbs/digits. |
| Pseudoflesh Injection | 18kcr | 8hr surgery. Restore 2d10 Speed/Strength/Body Save OR all Wounds. [-] all rolls 2wks + 4wks convalescence. |
| Psychosurgery | 28kcr | 8hr surgery. Restore Intellect, Sanity, or Fear to maximum OR reduce Minimum Stress to 2. [-] all rolls 4wks. |

---

## Contractors (NPCs for Hire)

Simplified characters with four stats only:

- **Combat**: same as player Combat stat.
- **Instinct**: catchall for Fear, Sanity, Body, Speed, Intellect.
- **Max Wounds**: any damage = 1 Wound. Hit Max Wounds = dead.
- **Loyalty**: a Save rolled when contractor must choose between their interests and the crew's. Start: `2d10+10` (rolled after hiring). Success = helps crew; failure = helps themselves.
- **Motivation**: when present, always overrides Loyalty.

Contractors earn a monthly salary plus hazard pay (1d5 months extra) for life-threatening situations. Nonpayment: Loyalty Save [-].

Loyalty improves by 1 when contractor survives a job and is paid in full.

---

## Ports

Five port classes, relevant primarily for Shore Leave costs and available services:

| Class | Description |
|-------|-------------|
| X-Class | Criminal settlements, beyond Company law |
| C-Class | Remote outposts, minimal supplies |
| B-Class | Industrial stations, military installations |
| A-Class | Major metropolises, full services |
| S-Class | Luxury, invite-only, heavily guarded |

---

## Implementation Notes for Code

### Roll resolution pattern

```
function statCheck(statValue, skillBonus = 0, advantage = false, disadvantage = false) {
  const effectiveTarget = statValue + skillBonus;
  let roll;
  if (advantage && !disadvantage) {
    roll = Math.min(rollD100(), rollD100());
  } else if (disadvantage && !advantage) {
    roll = Math.max(rollD100(), rollD100());
  } else {
    roll = rollD100();
  }
  // 90-99 always fails
  if (roll >= 90) return { roll, success: false, critical: roll === 99 };
  // 00 always crits
  if (roll === 0) return { roll, success: true, critical: true };
  // Doubles = critical
  const isCritical = (Math.floor(roll / 10) === roll % 10);
  return { roll, success: roll < effectiveTarget, critical: isCritical };
}
```

### Key data constraints

- Stress is bounded `[minimumStress, 20]`. Track minimum separately — it can change.
- Health resets to Max on each new Wound, minus carryover. Never goes below 0 before triggering a new Wound.
- Advantage/Disadvantage cancel: track counts, net the difference, apply once.
- Bleeding is cumulative: store as a single integer `bleedingPerRound`, increment on Bleeding +N wounds.
- Wound type determines which column of the Wounds Table to use — store as an enum.
- Class stat adjustments are applied once at creation, they don't stack.
- Androids cannot be affected by organic Wound results that make no anatomical sense (e.g. "hair burnt") — substitute or Warden-arbitrate. Flag these as `warden_arbitration: true` in your wound data.

### Warden-arbitrated outcomes

Where the rules say "use common sense" or "at the Warden's discretion", expose a hook/callback rather than hardcoding. Examples:
- Whether a skill is relevant to a task.
- Whether cover blocks a specific melee attack.
- Whether an unsafe location imposes Disadvantage on Rest Saves.
- How many Stress points a horrifying event inflicts.