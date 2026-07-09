# Dialogue voice generation (ElevenLabs)

Turns the dialogue corpus into per-line MP3s the game can play when a speech
bubble appears. Line id ↔ audio filename is the contract:
`GR_ML_ENG_CM#00042` (line key) → `assets/audio/dialogue/GR_ML_ENG_CM_00042.mp3`.

## Workflow

1. **Design voices** — one per archetype. Descriptions live in
   `resources/dialogue/voices.md`. Use ElevenLabs voice design (or pick
   library voices) and note each `voice_id`.
2. **Configure** —
   ```powershell
   $env:ELEVENLABS_API_KEY = "sk_..."
   python elevenlabs_batch.py --init-voices     # writes/refreshes voices.json slots
   python elevenlabs_batch.py --list-voices     # helps find voice_ids
   ```
   Paste each archetype's `voice_id` into `voices.json`. Re-run
   `--init-voices` whenever new archetype CSVs are added (it only adds slots,
   never overwrites).
3. **Preview** — `python elevenlabs_batch.py --archetype GR_ML_ENG_CM --limit 3 --dry-run`
   prints the converted text (tags lowercased for eleven_v3, `[EMPHASIS]` →
   UPPERCASED word) without spending credits.
4. **Generate** — `python elevenlabs_batch.py` runs everything missing.
   Resume-safe: re-run after rate limits/quota; existing files are skipped.
   `--archetype TAG` (repeatable) and `--limit N` scope a run; `--force`
   regenerates.

## Cost control

The summary line reports total characters sent — ElevenLabs bills per
character. Generate one archetype fully as a quality check before running the
whole corpus. `eleven_v3` is the model that honors inline audio tags; if cost
matters more than delivery nuance, `--model eleven_turbo_v2_5` is much
cheaper (tags are then best stripped — pass `--model` and expect tags to be
read literally on non-v3 models, so prefer v3 for tagged lines).
