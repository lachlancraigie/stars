# Dialogue Expansion Handoff — Mission-System Categories (Stage 2 bulk-fill brief)

> Written for a cheap bulk-fill model extending the remaining 21 archetypes. Stage 1
> (this handoff, the spec section, the validator, and 3 exemplar archetypes) is done.
> Read this file top to bottom before writing anything — it is meant to be followed
> mechanically, not interpreted. Full rules live in `docs/dialogue_spec.md` under
> "Mission-system line categories (2026-07-11)" — read that section too, it has the
> per-category firing triggers and writing guidance this file only summarizes.

## What you are doing

Each of the 21 remaining archetype files in `resources/dialogue/lines/*.json` needs
~30 new lines appended, covering the same 24 mission-system `intent` values the 3
exemplar archetypes already have. You are matching an established pattern, not
inventing one. Do ONE archetype file at a time. Do not touch `resources/dialogue/lines/gr_ml_eng_cm.json`, `pa_ml_sci_cm.json`, or `ch_ml_and_cm.json` — those are done (exemplars).

## The 3 exemplar files — READ THESE FIRST, every time

Before writing lines for a new archetype, open all 3 and read the mission-system
lines at the end of each (they're the last 30 entries — ids 364-393, 91-120, 85-114
respectively). They are your gold standard for format AND for how differently three
voices can hit the same 24 keys:

- `resources/dialogue/lines/gr_ml_eng_cm.json` — gruff engineer (Gus Hollis): terse,
  lowercase, dry understatement, industrial metaphors.
- `resources/dialogue/lines/pa_ml_sci_cm.json` — paranoid scientist (Dwight
  Kowalczyk): lowercase, hedges and repeats himself, spirals into worst-case detail.
- `resources/dialogue/lines/ch_ml_and_cm.json` — cheerful android (Milo): full
  capitalized sentences, grammatically correct, eager, over-literal, unsettling
  under the cheer.

Also re-read the target archetype's OWN existing lines (the first N entries in its
file) and its `resources/dialogue/archetypes/<tag>.json` — blurb, speech_quirks,
elevenlabs_voice. New lines must sound like they were written by the same person who
wrote that archetype's existing ~90-100 lines. Match: capitalization style (most
archetypes are lowercase like Gus/Dwight; check before assuming), sentence rhythm,
which delivery tags they lean on, their specific quirks (e.g. an archetype who
"apologizes before finishing a theory" should keep doing that here).

## The 24 keys and per-archetype line count (target = 30 total)

Write in this exact order, this exact count, per archetype:

| # | intent | count | conditions to set |
|---|---|---|---|
| 1 | `away_depart_surface` | 1 | stress 3-8, mood `["ok","low"]`, location `["shuttlebay"]` |
| 2 | `away_depart_derelict` | 1 | stress 3-8, mood `["ok","low"]`, location `["airlock"]` |
| 3 | `away_depart_station` | 1 | stress 3-8, mood `["ok","low"]`, location `["airlock"]` |
| 4 | `away_depart_other_ship` | 1 | stress 3-8, mood `["ok","low"]`, location `["airlock"]` |
| 5 | `away_radio_calm` | 2 | stress 2-6 |
| 6 | `away_radio_tense` | 2 | stress 6-11 |
| 7 | `away_radio_bad` | 2 | stress 9-15 |
| 8 | `away_return_fine` | 2 | stress 2-7, mood `["ok"]` |
| 9 | `away_return_shaken` | 2 | stress 6-12, mood `["low","grim"]` |
| 10 | `away_return_injured` | 2 | stress 6-13, `wounded: true` (1 of the 2 may also add `recent_events: ["injury"]`) |
| 11 | `briefing_ack_routine` | 1 | stress 2-6 |
| 12 | `briefing_ack_risky` | 1 | stress 4-9, mood `["ok","low"]` |
| 13 | `briefing_ack_grim` | 1 | stress 7-13, mood `["low","grim"]` |
| 14 | `docking_approach` | 1 | stress 3-8 |
| 15 | `docking_clamped` | 1 | stress 2-6 |
| 16 | `docking_undock` | 1 | stress 2-6 |
| 17 | `shuttle_ops_prep` | 1 | stress 3-7, location `["shuttlebay"]` |
| 18 | `shuttle_ops_launch` | 1 | stress 3-7, location `["shuttlebay"]` |
| 19 | `shuttle_ops_land` | 1 | stress 3-8, location `["shuttlebay"]` |
| 20 | `scenario_axis_bio` | 1 | stress 5-11, mood `["low","grim"]` |
| 21 | `scenario_axis_systems` | 1 | stress 5-11, mood `["low","grim"]` |
| 22 | `scenario_axis_social` | 1 | stress 5-11, mood `["low","grim"]` |
| 23 | `scenario_axis_combat` | 1 | stress 5-11, mood `["low","grim"]` |
| 24 | `scenario_axis_mystery` | 1 | stress 5-11, mood `["low","grim"]` |

Total: 30 lines (rows with count 2 are the `away_radio_*`/`away_return_*` triples —
write genuinely different lines for the pair, not near-duplicates, since both can be
heard in the same away op / same return and the runtime penalizes repeats).

## Fixed fields on every new line (do not deviate)

- `"type": "declaration"` — always. These are barks, not conversation turns.
- `"conditions".target": ["open_air"]` — always.
- `"reply_to_intents": []` — always empty.
- `"weight": 1.0` — unless you have a specific reason to vary it (rare; the
  exemplars don't).
- `id`: next free integer for that archetype file (check the last entry's `id` and
  continue from there — do NOT reuse or renumber existing ids).
- `key`: `"<TAG>#<00000-padded id>"`, e.g. `"PA_FE_ENG_CM#00091"`.

The validator hard-enforces the `declaration`/`open_air`/empty-`reply_to_intents`
rules for any line using one of these 24 intents — get them right or the run fails.

## Writing guidance (condensed — full version in dialogue_spec.md)

- `away_depart_*`: last line before stepping off the ship. Threshold energy, not
  description of the unknown. Vary by site (surface via shuttlebay feels different
  from boarding a dead ship via airlock).
- `away_radio_*`: `calm` = bored/procedural. `tense` = first bad sign, not yet a
  crisis. `bad` = the crisis (injury, panic, request for help) in the archetype's
  own register.
- `away_return_*`: `fine` = relief/dry humor. `shaken` = won't say what they saw,
  deflects, wants space. `injured` = downplays the wound while reporting it —
  Mothership house tone, nobody's a hero about getting hurt.
- `briefing_ack_*`: first reaction to new orders, before anything has happened yet.
  `routine` = professional resignation. `risky` = a flicker of real concern.
  `grim` = open dread, still followed by doing the job anyway.
- `docking_*` / `shuttle_ops_*`: operational, matter-of-fact — narrating a mechanical
  process. Personality shows in HOW they narrate it, not in raw emotion.
- `scenario_axis_*`: ambient dread, NEVER name a specific scenario or monster (these
  lines are shared across every scenario on that axis). `bio` = the body is lying to
  you. `systems` = the ship is lying to you. `social` = the crew is lying to you (or
  itself). `combat` = something wants you dead and is patient. `mystery` = nothing
  adds up and no one can say why.

## Delivery tags

Use the archetype's own established tag habits (check its existing lines and its
`delivery_baseline` in `tools/audio_gen/fish_voices.json` if present). Square
brackets only, 0-2 tags per line typically, never dangling at line end. See
`docs/dialogue_spec.md` "Delivery tags" section for the full rules if unsure.

## Validation command — run after EVERY archetype file you touch

```
python tools/dialogue/validate_dialogue.py resources/dialogue/lines/<tag>.json
```

Or validate the whole corpus at once (do this before considering the batch done):

```
python tools/dialogue/validate_dialogue.py resources/dialogue/lines/*.json
```

Expect `TOTAL ISSUES: 0`. Each file with mission-system lines prints a coverage line
like:

```
mission-system coverage: 24/24 intents used, categories touched: away_depart, away_radio, away_return, briefing_ack, docking, scenario_axis, shuttle_ops
```

If your file doesn't show `24/24`, you missed a key — go back and check the table
above against what you wrote.

## Commit

Explicit paths only (never `git add -A`). One commit per batch of archetypes is
fine; don't mix in unrelated files. End the message with:

```
Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
```
