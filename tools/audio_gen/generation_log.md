# Dialogue TTS generation log

Tracks bulk-generation progress against ElevenLabs quota so an interrupted
run resumes cleanly (`elevenlabs_batch.py` skips existing files; this file
records what's been paid for, with which voices, and why).

## History

- **2026-07-10 (pre-upgrade, superseded):** On the old pay-as-you-go plan the
  account was over its custom-voice slot limit (4/3), so all 24 archetypes
  were mapped to stock library voices and ~546 MP3s were generated that way
  (pilot + phase 1 of a priority-ordered run; ~11K of a 37,472 char quota
  spent). The user rejected the stock-voice compromise, upgraded the plan,
  and deleted all generated audio. Everything below is the post-upgrade run.

## Current plan (2026-07-10, post-upgrade): 10 custom + 14 stock

Post-upgrade account: **starter tier, character_limit=67,249, 10 custom
voice slots**. Quota counter at plan switch: character_count=2,615.

Custom voices are permanent — **never delete them** — so future dialogue can
be generated with the same voice. 10 slots were filled with designed voices
for the 10 highest-priority archetypes (every career represented; all four
captains custom since every ship has exactly one captain). The other 14
archetypes use the stock fallback mapping (`STOCK_FALLBACK` in
`design_voices.py`). Design recipes for the 10 customs are recorded
permanently in `voice_designs.json` (description + preview text + model),
so a close match can be re-designed if a voice is ever lost.

### Voice assignments

| Archetype | Voice | voice_id | Kind |
|---|---|---|---|
| PA_ML_SCI_CA | SHIPAI_PA_ML_SCI_CA | LufiRfu6P5p2GwKgGdX8 | custom |
| GR_ML_ENG_CA | SHIPAI_GR_ML_ENG_CA | zW4jqHUYZ6ji7V3W9ZuJ | custom |
| PA_FE_MAR_CA | SHIPAI_PA_FE_MAR_CA | drGlMOLT70nbnYb78nyy | custom |
| EV_FE_SCI_CA | SHIPAI_EV_FE_SCI_CA | oCLshW2dTMBsJ98dFYlI | custom |
| GR_ML_ENG_CM | SHIPAI_GR_ML_ENG_CM | MCpW9cRCNnb2RnJuHCHf | custom |
| GR_FE_ENG_OF | SHIPAI_GR_FE_ENG_OF | rIayTT22dOZEqEBsAN7Z | custom |
| CH_FE_SCI_CM | SHIPAI_CH_FE_SCI_CM | wT3pKykasfAryrys0D94 | custom |
| CH_ML_SCI_OF | SHIPAI_CH_ML_SCI_OF | XBls2Kq3i9CG9fFuDwkr | custom |
| EV_ML_MAR_CM | SHIPAI_EV_ML_MAR_CM | 0CVW1xcoSLZf1IhzYf5f | custom |
| CH_ML_AND_CM | SHIPAI_CH_ML_AND_CM | JlscJfdJonX6M4plfkam | custom |
| CH_FE_ENG_CM | Jessica (stock) | cgSgspJ2msm6clMCkdW9 | stock |
| CH_ML_ENG_OF | Chris (stock) | iP95p4xoKVk53GoZ742B | stock |
| CH_ML_MAR_CM | Liam (stock) | TX3LPaxmHKxFdv7VOQHJ | stock |
| EV_FE_AND_OF | Eva - Robot Helper (stock) | weA4Q36twV5kwSaTEL0Q | stock |
| EV_FE_MAR_OF | Alice (stock) | Xb7hH8MSUJpSbSDYk0k2 | stock |
| EV_FE_SCI_OF | Bella (stock) | hpp4J3VqNfWAUOO0d1Us | stock |
| EV_ML_ENG_CM | Eric (stock) | cjVigY5qzO86Huf0OWal | stock |
| GR_FE_AND_CM | Herbert - Robotic (stock) | VukfMVtvHInVUWoMNPiQ | stock |
| GR_FE_MAR_CM | Matilda (stock) | XrExE9yKIg1WjnnlVkGX | stock |
| GR_ML_SCI_OF | Brian (stock) | nPczCjzI2devNBz1zQrb | stock |
| PA_FE_AND_OF | Alice (stock, shared) | Xb7hH8MSUJpSbSDYk0k2 | stock |
| PA_FE_ENG_CM | Laura (stock) | FGY2WhTYpPnrIDTdsKH5 | stock |
| PA_ML_MAR_OF | Adam (stock) | pNInz6obpgDQGcFmaJgB | stock |
| PA_ML_SCI_CM | Danny/Devry (stock) | Nagtyt9MktF8AWSgjotJ | stock |

### Cost math

- Corpus: **1,376 lines / 110,031 raw characters** (tag-converted text, the
  "characters sent" metric) across 24 archetype CSVs.
- Observed pre-upgrade billing ratio on `eleven_v3`: actual billed
  characters ≈ 22–31% of raw characters sent (confirmed twice against
  `/v1/user/subscription` deltas). Projected full-corpus cost ≈ 34K billed
  + design costs, vs 64,634 available post-upgrade — fits with headroom.
- Voice design: 10 design+create rounds cost **1,395 billed chars** total
  (character_count 2,615 → 4,010).
- **Stop rule:** generation halts cleanly when character_count ≥ **57,162**
  (85% of the 67,249 monthly limit, leaving 15% for other use). Live check
  after each archetype.

### Generation order

Custom-voiced archetypes first (captains, then the other six), then the 14
stock-voiced archetypes smallest-first. `elevenlabs_batch.py` skips existing
files, so re-running any command below resumes safely.

## Progress (post-upgrade run)

| Timestamp (UTC) | Archetype | Files | Raw chars sent | character_count after | Notes |
|---|---|---|---|---|---|
| 2026-07-09 23:54 | (voice design ×10) | — | — | 4,010 | 10 custom voices created, recipes in voice_designs.json |
