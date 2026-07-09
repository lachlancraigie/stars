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
  `pain` `warning` `request_help` `offer_help` `boast` `memory` `doubt`.
- `conditions` — every field optional; omitted = no constraint:
  - `stress_min`/`stress_max`: Mothership Stress value range (min 2, practical high ~15+)
  - `panic`: true = only while panicked, false = only while calm, omit = either
  - `mood`: any of `high` `ok` `low` `grim` (derived from morale)
  - `wounded`: true = only while carrying a wound
  - `location`: room types (`engine_room` `bridge` `medbay` `mess` `quarters` `cargo` `corridor`
    `life_support` `ai_core` `airlock`) or `any`
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

- Strip `[TAGS]` for the in-game speech/thought bubble. Regex: `\[[A-Z ]+\]\s?`.
- Thought bubbles (internal monologue) reuse `declaration` lines with `target: open_air`,
  rendered in italic/dimmed style without a speaker sound.

## ElevenLabs export (`elevenlabs/*.csv`)

CSV, header `id,text`. `id` = `GR_ML_ENG_CM_00042` (filename-safe key). `text` = the line WITH
emotive tags (the TTS pass maps them to ElevenLabs v3 audio tags / prompt guidance). One row per
line, text double-quoted. `voices.md` holds the voice-design prompt per archetype.
