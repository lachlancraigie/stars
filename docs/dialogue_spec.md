# Dialogue Corpus Specification

> Contract between the dialogue corpus (data, `resources/dialogue/`) and the runtime dialogue
> selector (`scripts/crew/`). Both sides MUST follow this exactly. Grounded in the Mothership 1e
> ruleset (`docs/rules.md`) — archetypes reference its classes, stats, saves, skills, and the
> Stress/Panic system.

---

## Archetype dimensions & tags

Archetypes are combinations of four dimensions (not free-form concepts):

| Dimension | Codes |
|---|---|
| Personality | GR gruff/experienced · CH cheerful/friendly · EV even/steady · PA paranoid/excitable |
| Gender | ML male · FE female |
| Career (maps 1:1 to Mothership class) | SCI scientist/medic → Scientist · AND android → Android · ENG teamster/engineer → Teamster · MAR marine → Marine |
| Rank | CA captain · OF officer · CM crew mate |

Tag format: `{PERSONALITY}_{GENDER}_{CAREER}_{RANK}` — e.g. `GR_ML_ENG_CM` (gruff male engineer,
crew mate), `CH_FE_SCI_OF` (cheerful female medic, officer).

Coverage rules — we do NOT generate all 96 combinations. Target ~24 (about a quarter):
- Every career × rank cell has at least one archetype, EXCEPT android captains, which are
  forbidden (androids can never be captains). That's 11 mandatory cells.
- Both genders and all four personalities each appear several times across the set.
- Remaining slots are chosen for variety and interest, not systematic coverage.

Each archetype file defines: tag, the four dimension values, a 2–3 sentence **blurb** describing
who this person tends to be, a list of 8–12 possible **names** (crew gen picks one at random),
**stat/save tendencies** (modifiers applied on top of the standard 2d10+25 / 2d10+10 rolls),
preferred skills drawn from rules.md, speech quirks, and an **ElevenLabs voice description**.

Legacy note: the pilot set `GR_OL_ML_ENG` / `GR_OL_FE_ENG` / `EN_BR_FE_CA` predates this scheme
and is deprecated. Its content is migrated into the nearest dimensional archetypes (the migration
re-tags and renumbers lines; the old files are deleted).

## Line IDs

- Numeric, unique **within an archetype**, zero-padded to 5 digits in filenames/keys.
- Canonical key: `GR_ML_ENG_CM#00042`. Display form in docs: `GR_ML_ENG_CM #42`.
- Audio file mapping (ElevenLabs output, saved later): `assets/audio/dialogue/GR_ML_ENG_CM_00042.mp3`.
- IDs are stable forever once assigned. Never renumber. New lines append with the next free ID.

## Delivery tags (Fish Audio S2.1 syntax)

> Revision note (Fish Audio v2 revoice, Phase A): ElevenLabs is retired; Fish Audio S2.1 Pro's
> inline `[]` syntax (see `skills/fishaudio.md`) is now canonical for delivery direction, replacing
> the old closed-vocabulary UPPERCASE tags below. This section is the only vocabulary this revision
> changes — intents, contexts/conditions, and `reply_to_intents` rules are all UNCHANGED, see the
> rest of this document.

Inline in the text, square brackets. Stripped before on-screen display (see Display, below); kept
verbatim for the Fish Audio TTS pass — no export-time tag mapping step, the corpus text is sent to
the API as written.

Rules for writers (Phase B and beyond):
- **Square brackets only. Never `(parentheses)`.** Parenthetical tags are S1 syntax; the S2.1 API
  does not read them and they will be spoken aloud literally as English text.
- **A tag applies forward** — to the words after it — **until the next tag or the end of the
  line/sentence.** Placement is meaning, not decoration: a tag mid-sentence only kicks in at that
  point.
- **Descriptive tags must always be followed by text on the same line.** Never leave a tag dangling
  at line end — `He looked away. [sad]` is invalid; `[sad] He looked away.` is correct.
- **Prefer the well-tested tags** below when one fits; **free-form descriptions are encouraged**
  when it doesn't — write what you'd tell a voice actor (e.g.
  `[voice rough from crying, trying to sound normal]`). This is an open set, not a whitelist.
- **0–2 tags per line is typical.** Don't stack more than 3 — it muddies delivery instead of
  sharpening it.
- **Pair a physical tag with an emotion tag** for grounded delivery
  (`[panting] [scared] Don't — don't come any closer.`) rather than stacking multiple emotion tags
  alone.

### Well-tested tags (subset — full reference in `skills/fishaudio.md`)

`[emphasis] [sigh] [inhale] [exhale] [gasp] [panting] [clears throat] [laughing] [chuckling]
[giggle] [sobbing] [crying] [groan] [pause] [short pause] [long pause] [whispering] [soft voice]
[loud voice] [shouting] [low voice] [excited] [angry] [sad]`

Each archetype also has a `delivery_baseline` (`tools/audio_gen/fish_voices.json`) — a default
Fish-style direction tag for that character (e.g. `[nervous, speaking quickly, glancing around]`).
Phase C prepends it to any line with no leading tag; Phase B can use it as tone guidance when a
line needs its own more specific tag instead.

### Migration table — old closed-vocab tag → recommended Fish equivalent(s)

| Old tag | Fish equivalent(s) |
|---|---|
| `[EMPHASIS]` | `[emphasis]` |
| `[CONFIDENT]` | `[confident, assured tone]` |
| `[REASSURING]` | `[soft voice, reassuring]` |
| `[TERRIFIED]` | `[terrified, voice shaking]` |
| `[NERVOUS]` | `[nervous, speaking quickly]` |
| `[ANGRY]` | `[angry]` |
| `[GRUFF]` | `[low voice, gruff]` |
| `[WARM]` | `[warm, gentle tone]` |
| `[TIRED]` | `[tired, dead tired]` |
| `[EXHAUSTED]` | `[exhausted, breathing laboured]` |
| `[PANICKED]` | `[panicked, panting]` |
| `[CALM]` | `[calm, measured]` |
| `[URGENT]` | `[urgent, fast pace]` |
| `[SARCASTIC]` | `[dry, sarcastic tone]` |
| `[DRY]` | `[dry tone]` |
| `[GRIM]` | `[grim, heavy]` |
| `[HOPEFUL]` | `[hopeful tone]` |
| `[WHISPERS]` | `[whispering]` |
| `[SHOUTS]` | `[shouting]` |
| `[MUTTERS]` | `[low voice, muttering]` |
| `[LAUGHS]` | `[laughing]` or `[chuckling]` |
| `[SIGHS]` | `[sigh]` |
| `[PAINED]` | `[pained, voice tight]` |
| `[FLIRTY]` | `[flirty, playful tone]` |
| `[EMBARRASSED]` | `[embarrassed, voice quiet]` |
| `[SUSPICIOUS]` | `[suspicious tone]` |
| `[CURIOUS]` | `[curious tone]` |
| `[PROUD]` | `[proud tone]` |
| `[DISMISSIVE]` | `[dismissive tone]` |
| `[PLEADING]` | `[pleading]` |
| `[RESIGNED]` | `[resigned, flat tone]` |
| `[DEADPAN]` | `[deadpan]` |

Old `[UPPERCASE]` tags remain valid syntactically during the Phase B transition — the validator
checks tag *structure* (well-formed, non-empty, bracketed, not dangling, ≤3 per line), not
vocabulary, so a corpus with a mix of old and new tags passes cleanly. Phase B rewrites the corpus
to the new vocabulary; an un-migrated old tag is not an error, just deprecated style.

## Files

```
resources/dialogue/
├── archetypes/
│   └── gr_ml_eng_cm.json          # archetype definition (see schema)
├── lines/
│   └── gr_ml_eng_cm.json          # all lines for that archetype, array of Line objects
├── conversations/
│   └── convos_core.json           # multi-part conversation templates (may reference any archetype)
├── elevenlabs/
│   └── gr_ml_eng_cm.csv           # export: id,text-with-tags (one line per row, quoted)
└── voices.md                      # per-archetype ElevenLabs voice design descriptions
```

## Archetype schema (`archetypes/*.json`)

```json
{
  "tag": "GR_ML_ENG_CM",
  "dimensions": { "personality": "gruff", "gender": "male", "career": "teamster_engineer", "rank": "crew_mate" },
  "mothership_class": "Teamster",
  "blurb": "Thirty years of freighter engine rooms have left him with bad knees, worse manners, and an uncanny ear for a failing reactor. He trusts machines more than people and the ship's AI least of all.",
  "names": ["Harlan Voss", "Dmitri Okafor", "Ray Calloway", "Stig Andersen", "Mo Delacroix", "Walt Kaminski", "Jonah Pryce", "Earl Nakagawa"],
  "stat_tendencies": { "intellect": 5, "strength": 5, "speed": -5 },
  "save_tendencies": { "fear": 5, "sanity": 0, "body": 0 },
  "preferred_skills": ["mechanical_repair", "engineering", "jury_rigging"],
  "speech_quirks": "mutters at machinery, sentence fragments, calls everyone 'kid' or by their job",
  "elevenlabs_voice": "Male, 60s, gravelly low timbre, slow deliberate pacing, faint industrial-belt accent, dry delivery with smoker's texture"
}
```

Crew generation rolls standard Mothership characters, applies `stat_tendencies`/`save_tendencies`
as flat modifiers, picks a random entry from `names`, and takes skills honoring class rules with
`preferred_skills` prioritized. Every ship must have exactly one captain-rank crew member (never
an android).

## Line schema (`lines/*.json` — array of these)

```json
{
  "id": 42,
  "key": "GR_ML_ENG_CM#00042",
  "text": "i'm [EMPHASIS] freaking out about this disease",
  "type": "declaration",
  "intent": "fear_vent",
  "conditions": {
    "stress_min": 8, "stress_max": 20,
    "panic": false,
    "mood": ["low", "grim"],
    "wounded": null,
    "location": ["any"],
    "target": ["any"],
    "recent_events": ["disease_outbreak"]
  },
  "reply_to_intents": [],
  "weight": 1.0
}
```

Field rules:
- `type`: `declaration` (spoken to open air) · `opener` (starts a conversation) · `reply`
  (mid-conversation) · `closer` (ends one).
- `intent` (closed set): `greeting` `farewell` `smalltalk` `status_report` `complaint` `fear_vent`
  `reassurance` `banter` `insult` `apology` `romance_hint` `romance_advance` `romance_accept`
  `romance_reject` `work_talk` `acknowledgment` `grief` `gallows_humor` `suspicion_ai` `praise_ai`
  `pain` `warning` `request_help` `offer_help` `boast` `memory` `doubt`. **Mission-system
  additions** (2026-07-11, additive — see "Mission-system line categories" below for firing
  triggers and writing guidance): `away_depart_surface` `away_depart_derelict`
  `away_depart_station` `away_depart_other_ship` `away_radio_calm` `away_radio_tense`
  `away_radio_bad` `away_return_fine` `away_return_shaken` `away_return_injured`
  `briefing_ack_routine` `briefing_ack_risky` `briefing_ack_grim` `docking_approach`
  `docking_clamped` `docking_undock` `shuttle_ops_prep` `shuttle_ops_launch` `shuttle_ops_land`
  `scenario_axis_bio` `scenario_axis_systems` `scenario_axis_social` `scenario_axis_combat`
  `scenario_axis_mystery`.
- `conditions` — every field optional; omitted = no constraint:
  - `stress_min`/`stress_max`: Mothership Stress value range (min 2, practical high ~15+)
  - `panic`: true = only while panicked, false = only while calm, omit = either
  - `mood`: any of `high` `ok` `low` `grim` (derived from morale)
  - `wounded`: true = only while carrying a wound
  - `location`: room types (`engine_room` `bridge` `medbay` `mess` `quarters` `cargo` `corridor`
    `life_support` `ai_core` `airlock` `shuttlebay`) or `any` — `shuttlebay` added 2026-07-11
    for the mission system (`mission-system-spec.md` §7)
  - `target`: who they're addressing — archetype tags, career codes (`SCI` `AND` `ENG` `MAR`),
    rank codes (`CA` `OF` `CM`), `any`, or `open_air` for declarations
  - `recent_events` (closed set): `disease_outbreak` `crew_death` `reactor_failure` `power_low`
    `life_support_failure` `hull_breach` `door_locked_on_crew` `ai_damaged` `repair_success`
    `crisis_resolved` `combat` `injury` `quiet_shift` `meal_time` `shift_start` `shift_end`
- `reply_to_intents`: for `reply` lines — which prior-line intents this can answer (must be
  non-empty). `closer` lines MAY leave it empty, meaning they can close an exchange regardless of
  the prior intent.
- `weight`: base selection weight, default 1.0.

## Conversation schema (`conversations/*.json` — array of these)

```json
{
  "convo_id": "CV_DISEASE_PANIC_01",
  "shape": "4-6",
  "participants": ["PA_FE_MAR_CA", "GR_ML_ENG_CM"],
  "conditions": { "recent_events": ["disease_outbreak"], "stress_min": 6 },
  "lines": ["PA_FE_MAR_CA#00187", "GR_ML_ENG_CM#00554", "PA_FE_MAR_CA#00188", "GR_ML_ENG_CM#00556"]
}
```

- `shape`: `3` (greeting/response/close) or `4-6` (topic exchanges).
- `participants` may use career codes (`ENG`) or rank codes (`CA`) meaning "any archetype with
  that career/rank" — the runtime substitutes lines of matching intent from whichever archetype
  is actually present.
- Speaker alternates in `lines` order; the runtime may bail out early if a participant walks away
  or panics.

## Runtime selection (implemented in `scripts/crew/` — the "weighting net")

Score every candidate line whose hard conditions pass, then softmax-ish weighted-random pick:

```
score = weight
      + 2.0 * recent_event_match      # event named in conditions occurred in last N minutes
      + 1.0 * location_match
      + 1.0 * target_match            # specific archetype/career/rank beats "any"
      + 1.0 * mood_match
      + 0.5 * stress_band_center      # closer to band midpoint = better fit
      - 5.0 if line said in last 10 min by anyone (repetition penalty)
```

Hard filters (must pass, never scored): panic flag, stress bounds, wounded, `reply_to_intents`
when answering. Declarations fire from a per-crew idle timer scaled by stress; conversations
start when two crew share a room and both are free.

## Display

- Strip `[tags]` for the in-game speech/thought bubble. Regex updated for Fish Audio v2 (Phase A):
  `\[[^\]]+\]\s?` — the old `\[[A-Z ]+\]\s?` only matched all-caps single-word tags and no longer
  covers lowercase/punctuated/free-form Fish tags like `[voice rough from crying, trying to sound
  normal]`. Works on both old and new tag styles during the Phase B transition.
- Thought bubbles (internal monologue) reuse `declaration` lines with `target: open_air`,
  rendered in italic/dimmed style without a speaker sound.

## ElevenLabs export (`elevenlabs/*.csv`)

CSV, header `id,text`. `id` = `GR_ML_ENG_CM_00042` (filename-safe key). `text` = the line WITH
emotive tags (the TTS pass maps them to ElevenLabs v3 audio tags / prompt guidance). One row per
line, text double-quoted. `voices.md` holds the voice-design prompt per archetype.

---

## Mission-system line categories (2026-07-11)

> Extension for the mission/scenario overhaul (`docs/mission-system-spec.md`, STAGE 1 of the
> dialogue-corpus expansion). These are ADDITIVE `intent` values, fired by the engine at specific
> narrative beats rather than picked by the ambient idle-declaration timer. Coverage across the 24
> archetypes is OPTIONAL and incremental — the corpus stays valid with zero, partial, or full
> coverage of these keys; only 3 exemplar archetypes are complete as of this date (see
> `docs/dialogue-expansion-handoff.md` for the bulk-fill brief). Every other field on these lines
> follows the normal Line schema above (`type`, `conditions`, `weight`, etc.) — only `intent` is
> new vocabulary.

### Engine-triggered selection (new runtime mode)

Unlike ambient declarations (selected purely by the weighted scoring net against whatever
conditions happen to hold at the time), these categories are requested by NAME at a specific
moment: the engine already knows *what kind* of line it needs (a crew member is stepping through
the airlock, a mission briefing just landed, a scenario just went active) and asks the dialogue
selector for a line matching `archetype_tag` + a **hard filter on `intent`**. Once that hard
filter narrows the pool, the existing scoring net (stress band, mood, location, repetition
penalty) picks among the surviving candidates exactly as before.

**Format rule enforced by the validator**: every line whose `intent` is one of the mission-system
values below MUST have `type: "declaration"`, `target` (under `conditions`) containing
`"open_air"`, and empty `reply_to_intents` — they are barks, not conversation turns.

### New location: `shuttlebay`

Added to the `location` closed set (see Line schema above). The Shuttlebay is the new room type
from `mission-system-spec.md` §7 — surface-bound away teams stage there; boarding ops
(derelict/station/other-ship) still stage at `airlock`.

### Categories

#### `away_depart_{surface|derelict|station|other_ship}`

Fires once, the moment an away team departs — `shuttle_departed` (surface) or
`boarding_started` (derelict/station/other_ship), per `mission-system-spec.md` §6 step 1. One
line per site kind minimum; spoken by an archetype who is actually on the departing team.
Suggested band: `stress_min 3, stress_max 8`, `mood: ["ok","low"]`. Location: `shuttlebay` for
surface, `airlock` for the other three.

Writing guidance: this is a THRESHOLD line — the last thing said with both feet still on home
ground. Understatement, checklist-mutters, gallows humor, or (for jumpy archetypes) visible
reluctance all read well. Avoid describing what's on the other side — nobody knows yet.

#### `away_radio_{calm|tense|bad}`

Fires per AwayResolver beat (§6 step 2) while the team is out — `nothing`/`find` beats draw from
`calm`, `hazard`/`contact` from `tense`, `injury`/`exposure` from `bad`. An op runs 2-4 beats, so
write AT LEAST 2 lines per sub-key or the repetition penalty forces reuse within a single op.
Suggested bands: calm `2-6`, tense `6-11`, bad `9-15`. These are the corpus's generic fallback
pool for a beat with no scenario-specific `radio_line` text attached (`mission-system-spec.md`
§14) — keep them site-agnostic (no planet/ship names) so they work for any op.

Writing guidance: `calm` is procedural, almost bored. `tense` is a held breath — first sign
something's off, not yet a crisis. `bad` is the crisis itself: injury, panic, or a request for
help, in the archetype's own register (a marine barks orders, a scientist spirals into diagnosis,
an android reports damage like a status log).

#### `away_return_{fine|shaken|injured}`

Fires once per team member on `shuttle_returned` (§6 step 3), keyed off THAT crew member's own
observable outcome (their wound state / stress delta from the op — not the mission's overall
outcome). Suggested bands: fine `2-7` (`mood: ["ok"]`), shaken `6-12` (`mood: ["low","grim"]`),
injured `6-13` (`wounded: true`). Write at least 2 per sub-key — this fires on every single away
op, high traffic.

Writing guidance: `fine` is relief, checklist-closure, dry humor. `shaken` is someone who won't
say what they saw yet — trail off, deflect, ask for space. `injured` downplays the injury in the
same breath as reporting it (Mothership house tone: nobody's a hero about a wound, they're
annoyed by it).

#### `briefing_ack_{routine|risky|grim}`

Fires once when `mission_started` lands, before the ship gets underway. Tier comes from the new
mission's `away_risk.tier` when the mission has one (`low`/`moderate` → `routine`, `high` →
`risky`, `extreme` → `grim`); missions with no away component infer tier from type/tags
(`distress`/`evacuation`/`quarantine_run` or a `high_stakes` tag → `risky`;
`opener`/`homecoming`/a `low_stakes` tag → `routine`; `grim` is reserved for explicit
extreme-risk missions). Suggested bands: routine `2-6`, risky `4-9` (`mood: ["ok","low"]`), grim
`7-13` (`mood: ["low","grim"]`).

Writing guidance: this is the crew's FIRST reaction to new orders, before anything has happened —
professional resignation for routine, a flicker of real concern for risky, open dread (still
followed by getting on with it — Mothership crews don't get to refuse work) for grim.

#### `docking_{approach|clamped|undock}`

Fires on the matching EventBus signal (`docking_started` → `approach`, `docking_completed` →
`clamped`, `undocked` → `undock`). Ship-wide chatter, no location constraint (comms-audible
anywhere). Suggested band: `approach` runs slightly hotter (`3-8`); `clamped`/`undock` are
procedural (`2-6`).

Writing guidance: operational, matter-of-fact register — this is a crew narrating a mechanical
process, not an emotional beat. Personality still shows in HOW they narrate routine mechanics
(a distrustful engineer double-checks the readout; a chipper android enjoys the numbers matching).

#### `shuttle_ops_{prep|launch|land}`

Shuttlebay-floor chatter around the shuttle itself (as opposed to `away_depart_*`, which is the
departing crew's own threshold line) — pre-flight checks, the launch itself, touchdown back in
the bay. Location: `shuttlebay`. Suggested band: `3-7` (`prep`/`launch`), `3-8` (`land`).

Writing guidance: distinct from `away_depart` in FOCUS — this is about the shuttle as equipment
(fuel, seals, burn, touchdown), not the crew's state of mind. Reads well from an engineer/teamster
archetype even when they're not the one going out on the op.

#### `scenario_axis_{bio|systems|social|combat|mystery}`

Ambient dread declarations while a scenario of that `pressure_axis` is active
(`mission-system-spec.md` §4/§10) — fired like a normal idle declaration but filtered to the
active scenario's axis. The corpus has no direct hook into scenario `tone`/`intensity` floats, so
use the EXISTING mechanism (`stress_min`/`stress_max`, `mood`) as the tone-band proxy — write
these in the upper-middle stress band where dread is legible but the scenario hasn't necessarily
resolved. Suggested band: `5-11`, `mood: ["low","grim"]`. One line per axis is the floor;
archetypes central to a given axis's solve path (a scientist for `bio`, an engineer for
`systems`) can carry more without breaking the ~30-line/archetype budget.

Writing guidance: never name the specific scenario or monster — these are pooled across EVERY
scenario on that axis, so keep it to the axis's *flavor of wrongness*: `bio` = the body/organism
is lying to you, `systems` = the ship is lying to you, `social` = the crew is lying to you (or to
itself), `combat` = something wants you dead and is patient about it, `mystery` = the universe
doesn't add up and nobody can say why.

### Per-archetype budget

~25-35 new lines total per archetype (an ADDITION to the existing ~100-line average, not a
rewrite). Reference split used by the 3 exemplar archetypes (30 lines): 4 `away_depart` + 6
`away_radio` (2/sub-key) + 6 `away_return` (2/sub-key) + 3 `briefing_ack` + 3 `docking` + 3
`shuttle_ops` + 5 `scenario_axis` (1/axis) = 30.
