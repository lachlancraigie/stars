# Dialogue Corpus Specification

> Contract between the dialogue corpus (data, `resources/dialogue/`) and the runtime dialogue
> selector (`scripts/crew/`). Both sides MUST follow this exactly. Grounded in the Mothership 1e
> ruleset (`docs/rules.md`) — archetypes reference its classes, stats, saves, skills, and the
> Stress/Panic system.

---

## Archetype tags

Format: `{PERSONALITY}_{AGE}_{GENDER}_{ROLE}`, each part 2–3 uppercase letters.

| Part | Codes |
|---|---|
| Personality | GR gruff · EN energetic-brash · NV nervous · WA warm · CO cold-professional |
| Age | YO young · MI mid · OL old |
| Gender | ML male · FE female |
| Role | ENG engineer · CA captain · MED medic/doctor · SCI scientist · MAR marine · TEA teamster/hand · PIL pilot |

Initial three archetypes (more later):
- `GR_OL_ML_ENG` — gruff old male engineer (Mothership class: Teamster, high Intellect/Engineering skills)
- `GR_OL_FE_ENG` — gruff old female engineer (Teamster)
- `EN_BR_FE_CA` — energetic brash female captain (note: personality part here is `EN_BR` collapsed to `EN`; canonical tag is `EN_BR_FE_CA` for continuity with existing naming)

Each archetype file defines: Mothership class, stat/save/skill tendencies (used at char-gen),
personality traits, background sketch, speech quirks, and an **ElevenLabs voice description**.

## Line IDs

- Numeric, unique **within an archetype**, zero-padded to 5 digits in filenames/keys.
- Canonical key: `GR_OL_ML_ENG#00042`. Display form in docs: `GR_OL_ML_ENG #42`.
- Audio file mapping (ElevenLabs output, saved later): `assets/audio/dialogue/GR_OL_ML_ENG_00042.mp3`.
- IDs are stable forever once assigned. Never renumber. New lines append with the next free ID.

## Emotive tags

Inline in the text, square brackets, UPPERCASE. Stripped before on-screen display; kept for the
ElevenLabs export. Vocabulary (closed set — do not invent new ones without adding them here):

`[EMPHASIS] [CONFIDENT] [REASSURING] [TERRIFIED] [NERVOUS] [ANGRY] [GRUFF] [WARM] [TIRED]
[EXHAUSTED] [PANICKED] [CALM] [URGENT] [SARCASTIC] [DRY] [GRIM] [HOPEFUL] [WHISPERS] [SHOUTS]
[MUTTERS] [LAUGHS] [SIGHS] [PAINED] [FLIRTY] [EMBARRASSED] [SUSPICIOUS] [CURIOUS] [PROUD]
[DISMISSIVE] [PLEADING] [RESIGNED] [DEADPAN]`

A tag applies to the words after it until the next tag or end of line.

## Files

```
resources/dialogue/
├── archetypes/
│   └── gr_ol_ml_eng.json          # archetype definition (see schema)
├── lines/
│   └── gr_ol_ml_eng.json          # all lines for that archetype, array of Line objects
├── conversations/
│   └── convos_core.json           # multi-part conversation templates (may reference any archetype)
├── elevenlabs/
│   └── gr_ol_ml_eng.csv           # export: id,text-with-tags (one line per row, quoted)
└── voices.md                      # per-archetype ElevenLabs voice design descriptions
```

## Line schema (`lines/*.json` — array of these)

```json
{
  "id": 42,
  "key": "GR_OL_ML_ENG#00042",
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
  `pain` `warning` `request_help` `offer_help` `boast` `memory` `doubt`.
- `conditions` — every field optional; omitted = no constraint:
  - `stress_min`/`stress_max`: Mothership Stress value range (min 2, practical high ~15+)
  - `panic`: true = only while panicked, false = only while calm, omit = either
  - `mood`: any of `high` `ok` `low` `grim` (derived from morale)
  - `wounded`: true = only while carrying a wound
  - `location`: room types (`engine_room` `bridge` `medbay` `mess` `quarters` `cargo` `corridor`
    `life_support` `ai_core` `airlock`) or `any`
  - `target`: who they're addressing — archetype tags, role codes (`ENG`, `CA`, …), `any`, or
    `open_air` for declarations
  - `recent_events` (closed set): `disease_outbreak` `crew_death` `reactor_failure` `power_low`
    `life_support_failure` `hull_breach` `door_locked_on_crew` `ai_damaged` `repair_success`
    `crisis_resolved` `combat` `injury` `quiet_shift` `meal_time` `shift_start` `shift_end`
- `reply_to_intents`: for `reply`/`closer` lines — which prior-line intents this can answer.
- `weight`: base selection weight, default 1.0.

## Conversation schema (`conversations/*.json` — array of these)

```json
{
  "convo_id": "CV_DISEASE_PANIC_01",
  "shape": "4-6",
  "participants": ["EN_BR_FE_CA", "GR_OL_ML_ENG"],
  "conditions": { "recent_events": ["disease_outbreak"], "stress_min": 6 },
  "lines": ["EN_BR_FE_CA#19287", "GR_OL_ML_ENG#00554", "EN_BR_FE_CA#19288", "GR_OL_ML_ENG#00556"]
}
```

- `shape`: `3` (greeting/response/close) or `4-6` (topic exchanges).
- `participants` may use role codes (`ENG`) meaning "any archetype with that role" — the runtime
  substitutes lines of matching intent from whichever archetype is actually present.
- Speaker alternates in `lines` order; the runtime may bail out early if a participant walks away
  or panics.

## Runtime selection (implemented in `scripts/crew/` — the "weighting net")

Score every candidate line whose hard conditions pass, then softmax-ish weighted-random pick:

```
score = weight
      + 2.0 * recent_event_match      # event named in conditions occurred in last N minutes
      + 1.0 * location_match
      + 1.0 * target_match            # specific archetype/role beats "any"
      + 1.0 * mood_match
      + 0.5 * stress_band_center      # closer to band midpoint = better fit
      - 5.0 if line said in last 10 min by anyone (repetition penalty)
```

Hard filters (must pass, never scored): panic flag, stress bounds, wounded, `reply_to_intents`
when answering. Declarations fire from a per-crew idle timer scaled by stress; conversations
start when two crew share a room and both are free.

## Display

- Strip `[TAGS]` for the in-game speech/thought bubble. Regex: `\[[A-Z ]+\]\s?`.
- Thought bubbles (internal monologue) reuse `declaration` lines with `target: open_air`,
  rendered in italic/dimmed style without a speaker sound.

## ElevenLabs export (`elevenlabs/*.csv`)

CSV, header `id,text`. `id` = `GR_OL_ML_ENG_00042` (filename-safe key). `text` = the line WITH
emotive tags (the TTS pass maps them to ElevenLabs v3 audio tags / prompt guidance). One row per
line, text double-quoted. `voices.md` holds the voice-design prompt per archetype.
