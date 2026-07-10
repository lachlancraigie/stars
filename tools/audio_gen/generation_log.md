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
| 2026-07-10 | PA_ML_SCI_CA | 50/50 | 5,520 | — | custom voice |
| 2026-07-10 | GR_ML_ENG_CA | 40/40 | 2,921 | — | custom voice |
| 2026-07-10 | PA_FE_MAR_CA | 48/48 | 3,436 | — | custom voice |
| 2026-07-10 | EV_FE_SCI_CA | 43/43 | 3,127 | 11,243 | custom voice — all 4 captains done. NOTE: post-upgrade billing ratio ≈48% of raw (7,233 billed / 15,004 raw), higher than the pre-upgrade 27–31% |
| 2026-07-10 | CH_FE_SCI_CM | 43/43 | 2,940 | — | custom voice |
| 2026-07-10 | CH_ML_SCI_OF | 39/39 | 3,066 | — | custom voice |
| 2026-07-10 | GR_FE_ENG_OF | 52/52 | 3,683 | — | custom voice |
| 2026-07-10 | EV_ML_MAR_CM | 54/54 | 3,283 | — | custom voice |
| 2026-07-10 | CH_ML_AND_CM | 39/39 | 3,844 | 19,661 | custom voice — 9 of 10 custom archetypes done (408 files) |
| 2026-07-10 13:47 | GR_ML_ENG_CM | 313/313 | 21,753 | 30,552 | custom voice — **all 10 custom archetypes done (721 files)**; billing ratio ≈50% of raw |
| 2026-07-10 | EV_FE_MAR_OF + CH_FE_ENG_CM | 82/82 | 5,638 | 33,501 | stock voices |
| 2026-07-10 | CH_ML_ENG_OF + CH_ML_MAR_CM | 82/82 | 5,952 | 36,388 | stock voices |
| 2026-07-10 | PA_ML_SCI_CM + EV_FE_AND_OF | 80/80 | 6,896 | 39,322 | stock voices |
| 2026-07-10 | GR_FE_MAR_CM + GR_ML_SCI_OF | 100/100 | 8,032 | 43,573 | stock voices |
| 2026-07-10 | EV_ML_ENG_CM + EV_FE_SCI_OF | 105/105 | 8,595 | 48,043 | stock voices |
| 2026-07-10 | GR_FE_AND_CM + PA_ML_MAR_OF | 100/100 | 9,870 | 55,232 | stock voices; billing ratio spiked to ≈73% this batch |
| 2026-07-10 | PA_FE_ENG_CM (partial) | 30/50 | 3,219 | **57,162** | stock voice; three metered chunks (15+10+5) walked quota to **exactly the 85% stop line** — HARD STOP |

## Final state (2026-07-10)

- **1,300 / 1,376 files generated** (94.5%), zero failures, all verified
  (per-archetype counts match CSVs; valid ID3/MPEG headers; the single
  sub-10KB file is the one-word line "hey", which is correct).
- Total spend this run: character_count 2,615 → 57,162 = **54,547 billed
  characters** (incl. 1,395 for 10 voice designs), leaving exactly 15% of
  the monthly quota (10,087 chars) untouched per the stop rule.
- **Remaining, not generated (quota stop):**
  - `PA_FE_AND_OF` — all 56 lines (6,236 raw chars), stock voice Alice
  - `PA_FE_ENG_CM` — 20 of 50 lines (2,020 raw chars), stock voice Laura
- **To finish after the quota resets** (both remainders, resume-safe —
  skips the 1,300 existing files automatically):

  ```powershell
  $env:ELEVENLABS_API_KEY = "<from tools/audio_gen/.env>"
  python tools/audio_gen/elevenlabs_batch.py --archetype PA_FE_ENG_CM --archetype PA_FE_AND_OF
  ```

  (~8,256 raw chars ≈ 4–6K billed at observed ratios; next quota reset per
  the subscription API.)
