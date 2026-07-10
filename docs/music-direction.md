# Music Direction — Suno Prompt Pack

> Companion to `docs/audio-direction.md` (which covers SFX + an earlier, broader music list under
> `assets/audio/music/`). This document is the **canonical mood-based synth score**: one cohesive
> sonic identity, mapped directly onto `docs/director-spec.md`'s heat model and the tone bands used
> throughout `docs/scenario-bible.md`. Finished MP3s land under `assets/music/<mood>/` (a new,
> separate tree from `assets/audio/music/` — keep the two apart so the mood-driven playlist stays
> unambiguous for wiring later).
>
> Tone reference (GDD): competent procedural Star Trek voyages through claustrophobic Alien (1979)
> horror. The player is the ship's AI watching an isometric crew sim — this is **background music
> under a systems-management game**, not a foreground score.

---

## 1. Sonic identity

**Working name: "Cold Circuit."** One instrument family, one recurring gesture, used at different
intensities across every mood so the whole soundtrack reads as a single machine breathing at
different rates — not a mood-board of unrelated sci-fi cues.

- **Instrument family**: detuned vintage analog polysynth (Juno/Prophet-adjacent) only — pads,
  drones, and a slow filtered arpeggio. No orchestral instruments, no acoustic instruments, no
  guitars, no full drum kits, no vocals, ever.
- **The recurring gesture**: a slow, repeating filtered arpeggio motif (think a heartbeat rendered
  as a synth sequence) that is present, at some intensity, in nearly every track. Near heat 0 it is
  barely moving and consonant; as heat/tension rises it speeds up slightly, narrows its filter, and
  detunes further. This one thread is what makes the whole pack feel authored, not generated.
- **The floor texture**: soft tape hiss / wow-and-flutter under everything, plus a low sub-bass
  drone standing in for the ship's engine hum. Never lets a track go digitally "clean."
- **Dynamics**: deliberately low dynamic range and low information density — sustained pads over
  sharp transients, nothing that jumps out of a mix. No build-drop structures. No lead melodies
  competing for attention. Percussion, where it exists at all (crisis/combat moods only), is sparse
  and mechanical (a single pulse, a metallic tick) — never a full kit, never busy.
- **Loopability**: every track should breathe as a static-ish bed, not tell a story arc. Suno will
  want to build/resolve on its own; every prompt below explicitly fights that.

### STYLE ANCHOR PHRASE

Paste this fragment into the **Style** field of every prompt in this pack (append/blend with the
per-mood style additions below — don't replace it):

```
minimal analog synth, detuned vintage polysynth pads, slow tape-saturated drone, soft tape hiss,
restrained filtered arpeggio motif, low dynamic range, sparse, loop-friendly, instrumental,
no vocals, ambient sci-fi score
```

---

## 2. Mood taxonomy → folders

Derived from `director-spec.md`'s `heat` dial (§3–4) and the tone bands (`tone_min`/`tone_max`,
0.0 Trek ↔ 1.0 Alien) used throughout `scenario-bible.md`.

| Folder | Heat / tone band | Drives from |
|---|---|---|
| `calm_routine` | heat ~0.0–0.2 | "all crew calm + all systems green" cruising state; `quiet_shift` |
| `low_tension_unease` | heat ~0.2–0.4 | tension rising, first anomaly, early scenario acts (tone 0.1–0.4) |
| `tense_crisis` | heat ~0.4–0.75 | one active scenario mid-crisis (reactor/life-support/hull events) |
| `combat_danger` | heat ~0.6–0.9, overlap scenarios | boarding, forced entry, second concurrent scenario, `combat` |
| `aftermath_somber` | post-event, any heat | `crew_death`, forced `quiet_shift` recovery beat after 2 deaths |
| `eerie_derelict` | tone 0.45–0.9, dread not danger | `The Blind Spot`, `Deadweight`, sensor gaps, derelicts, mystery |
| `overseer_ai_motif` | any heat | AI core focus, degraded-mode moments, the Overseer's own "presence" |
| `main_menu_title` | n/a | title screen / campaign start |
| `victory_arrival` | falling heat, resolution | `crisis_resolved`, scenario win, leg complete / port arrival |

9 folders — within the requested 6–10 range.

---

## 3. Per-mood prompts

Every prompt is `[Instrumental]`. **Style field** = anchor phrase + mood-specific additions.
**Prompt field** = short descriptive scene direction, always ending with a loop-friendly-ending
instruction.

### calm_routine
**When it plays**: default underway state, nightwatch, no active scenario, all systems green.
**Feel**: weightless, patient, unhurried. **Tempo**: no fixed beat, felt pulse ~55 BPM. **Energy**: 1/10.

1. **Style**: `minimal analog synth, detuned vintage polysynth pads, slow tape-saturated drone, soft tape hiss, restrained filtered arpeggio motif, low dynamic range, sparse, loop-friendly, instrumental, no vocals, ambient sci-fi score, extremely slow arpeggio, gentle sine sub-bass, spacious reverb`
   **Prompt**: `[Instrumental] Quiet nightwatch on a starship bridge, a barely-moving synth pad under a distant engine hum, nothing urgent, weightless calm, end on a long sustained pad with no cold stop for seamless looping.`
2. **Style**: `... , warmer Rhodes-adjacent polysynth tone, slower arpeggio (half speed), minimal reverb tail`
   **Prompt**: `[Instrumental] A slow patrol through empty corridors, machinery humming steadily somewhere below, safe and monotonous, static ambient bed with almost no movement, fade to a held drone for looping.`
3. **Style**: `... , twin detuned pads a fifth apart, single soft arpeggio note every few seconds, no percussion at all`
   **Prompt**: `[Instrumental] The ship at rest between crises, breathing slowly, sparse and spacious, background music that never demands attention, loop-ready sustained ending.`

### low_tension_unease
**When it plays**: heat ticking up, first anomaly detected, early scenario acts (tone 0.1–0.4).
**Feel**: something's slightly wrong, not yet dangerous. **Tempo**: ~62 BPM felt pulse. **Energy**: 2–3/10.

1. **Style**: `... , slightly dissonant second pad layer, arpeggio filter narrowing, faint irregular tick`
   **Prompt**: `[Instrumental] A quiet alarm you can't quite place, the same calm pad now half a step out of tune, patient unease, no release of tension, ends on a held dissonant chord for clean looping.`
2. **Style**: `... , low sub-bass pulse (very sparse), single detuned high pad, occasional metallic resonance`
   **Prompt**: `[Instrumental] Something drifting off-baseline on the sensors, restrained dread, mostly stillness with rare cold metallic accents, sustain into a static loop point.`
3. **Style**: `... , slow-rising filter sweep over the drone, arpeggio gains one extra note`
   **Prompt**: `[Instrumental] The first flicker of wrongness in an otherwise calm system, tension held rather than released, minimal and creeping, tail off into a steady drone for looping.`

### tense_crisis
**When it plays**: one active scenario mid-crisis — reactor failure, spreading contamination, hull
integrity dropping. **Feel**: urgent but claustrophobic, not action-movie. **Tempo**: ~85 BPM. **Energy**: 5/10.

1. **Style**: `... , driving sequenced sub-bass pulse, sparse metallic percussion tick (single hit per bar), arpeggio doubled in speed and narrowed`
   **Prompt**: `[Instrumental] Multiple systems failing at once, a steady mechanical pulse instead of a beat, pressure without spectacle, no big drums, keep it sparse and claustrophobic, resolve into a sustained low pad for looping.`
2. **Style**: `... , alarm-adjacent detuned stab (used sparingly, not rhythmic), pulsing analog bass sequence, tight filter`
   **Prompt**: `[Instrumental] Crew scrambling to contain a cascading failure, cold analog urgency, restrained and mechanical rather than orchestral, loop-friendly sustained ending, no cymbal crash finish.`
3. **Style**: `... , two interlocking arpeggios slightly out of phase, sub-bass throb, minimal reverb (dry and close)`
   **Prompt**: `[Instrumental] The moment a crisis stops being theoretical, dry and immediate, machine urgency rather than human panic, ends on a held bass note for seamless looping.`

### combat_danger
**When it plays**: boarding actions, forced entry, a second concurrent scenario overlapping the
first (heat ≥ ~0.75). **Feel**: propulsive threat, still restrained — never a full action cue.
**Tempo**: ~108 BPM. **Energy**: 6/10 (the loudest mood in the pack, still far from a "drop").

1. **Style**: `... , propulsive sequenced arpeggio (fast, tight), sparse mechanical percussion (single low tom-like hit, no kit), driving sub-bass ostinato`
   **Prompt**: `[Instrumental] A boarding craft matching velocity, cold mechanical threat, propulsive but minimal — a synth sequence under pressure, not a drum battle, no build-and-drop, sustain to a loopable ending.`
2. **Style**: `... , detuned stab accents on the downbeat only, relentless low arpeggio, tight claustrophobic filter`
   **Prompt**: `[Instrumental] Hostile contact closing in corridor by corridor, restrained aggression, repetitive and mechanical rather than triumphant, avoid cinematic swells, end on a sustained low tone for looping.`
3. **Style**: `... , faster arpeggio doubling every 8 bars, single sparse metallic percussion hit per bar, no cymbals`
   **Prompt**: `[Instrumental] Danger inside the hull itself, tense and driving but still a synth bed under gameplay — never a foreground action score, loop-ready fade on a held chord.`

### aftermath_somber
**When it plays**: immediately after a crew death; the forced `quiet_shift` recovery beat.
**Feel**: grief, stillness, the ship keeps running anyway. **Tempo**: rubato / no fixed pulse. **Energy**: 1/10.

1. **Style**: `... , single slow detuned pad (no arpeggio at all), long silences between phrases, faint tape warble`
   **Prompt**: `[Instrumental] The quiet after a death nobody could have stopped, sparse and elegiac, mostly silence with a single held synth tone, restrained grief without melody, end on near-silence for a natural loop.`
2. **Style**: `... , very slow two-note arpeggio (widely spaced), soft sub-bass drone, gentle tape hiss swelling and fading`
   **Prompt**: `[Instrumental] A ship observing a moment of mourning it has no ritual for, cold comfort, patient and hollow, tail into a sustained low pad for looping.`
3. **Style**: `... , detuned pad with slow pitch drift downward, no rhythmic element, distant faint hum`
   **Prompt**: `[Instrumental] Processing loss the way a machine processes anything — completely, slowly, without catharsis, ends on a held low drone for seamless looping.`

### eerie_derelict
**When it plays**: sensor-gap dread (*The Blind Spot*), unexplained anomalies (*Deadweight*),
derelict/mystery beats — dread from absence, never a jump scare. **Feel**: ambiguous, unresolved.
**Tempo**: rubato / no clear pulse. **Energy**: 2/10, high unease-to-energy ratio.

1. **Style**: `... , irregular arpeggio with random dropped notes (simulating a gap in sensor coverage), distant detuned high pad, occasional cold metallic resonance`
   **Prompt**: `[Instrumental] Something the sensors can't confirm or deny, patient dread built from absence and silence rather than stings, ambiguous and unresolved, end on an unstable held chord for looping.`
2. **Style**: `... , very sparse arpeggio (single notes every several seconds), sub-bass drone with slow breathing-like swell, faint tape wow`
   **Prompt**: `[Instrumental] A room that was dark to every camera for four minutes, cold uncertainty rather than horror, minimal and spacious, sustain into a loop-friendly drone.`
3. **Style**: `... , detuned pad clusters slowly rubbing against each other, no clear tonal center, distant faint mechanical groan`
   **Prompt**: `[Instrumental] The dread of a found object that shouldn't still be aboard, quiet wrongness, no resolution offered, fade to a static loop point.`

### overseer_ai_motif
**When it plays**: AI core focus, degraded-mode moments, any beat where the Overseer's own
"presence" as an entity is foregrounded (distinct from the ship's ambient hum). **Feel**: precise,
cold, faintly beautiful, mechanically exact. **Tempo**: ~70 BPM, clockwork-steady. **Energy**: 3/10.

1. **Style**: `... , crystalline glass-like polysynth tone, precisely repeating arpeggio pattern, subtle gradual detune over the loop, no percussion`
   **Prompt**: `[Instrumental] A machine mind thinking in perfect repeating cycles, cold and exact but not unfeeling, glassy and clean under the tape hiss, end on the repeating motif held for a seamless loop.`
2. **Style**: `... , same crystalline motif but audibly degrading — flatter tuning, small dropouts, tape wobble increasing`
   **Prompt**: `[Instrumental] The same machine thought process now damaged, the pattern still trying to repeat correctly and failing slightly each cycle, unsettling precision breaking down, end on a slightly corrupted held tone for looping.`
3. **Style**: `... , clockwork arpeggio locked to a steady sub-bass pulse, minimal reverb, very dry and close`
   **Prompt**: `[Instrumental] The Overseer quietly calculating in the background of everything, exact, patient, non-human rhythm, loop-ready ending on the held pulse.`

### main_menu_title
**When it plays**: title screen, campaign start. The one mood allowed slightly more presence —
still restrained, never busy. **Feel**: lonely, cold majesty. **Tempo**: slow build, ~60 BPM. **Energy**: 3–4/10.

1. **Style**: `... , slow-building detuned lead motif over a deep drone, distant radio-crackle texture, gentle arpeggio entering halfway through`
   **Prompt**: `[Instrumental] A lonely detuned synth theme opening over deep space, cold and majestic rather than triumphant, patient build with no percussion, end on a sustained final chord that can loop under a menu.`
2. **Style**: `... , twin slow pads a fourth apart, single recurring three-note motif (the arpeggio, slowed to a theme), tape hiss floor`
   **Prompt**: `[Instrumental] The ship AI's own theme, restrained and dignified, minimal analog synth rather than an orchestral fanfare, understated, end on a held drone for menu looping.`
3. **Style**: `... , very slow arpeggio building in layers over two minutes, warm sub-bass entering late, no climax or drop`
   **Prompt**: `[Instrumental] A title theme that never resolves into triumph, quiet dread under quiet beauty, patient and cold, fade to a sustained loop-friendly tail.`

### victory_arrival
**When it plays**: `crisis_resolved`, scenario win banners, leg complete / port arrival. **Feel**: a
quiet exhale, restrained relief — never a fanfare. **Tempo**: ~75 BPM. **Energy**: 3/10, short cues.

1. **Style**: `... , arpeggio resolves to a consonant pattern (still slow), warm pad swell, brief major-adjacent lift without becoming triumphant`
   **Prompt**: `[Instrumental] Exhaling after a held breath, quiet relief rather than triumph, brief rising figure settling back to a calm pad, natural resolved ending suitable for a short stinger, 45–60 seconds.`
2. **Style**: `... , single warm detuned pad rising gently, arpeggio slowing to a stop, soft tape hiss fading up then down`
   **Prompt**: `[Instrumental] The ship clearing danger and settling back into routine, restrained warmth, no fanfare, ends softly on a sustained pad for a clean loop back into calm_routine.`
3. **Style**: `... , sparse ascending three-note figure, gentle sub-bass swell, minimal reverb`
   **Prompt**: `[Instrumental] A leg completed, a port in sight, tired competence rather than celebration, brief and understated, end on a held consonant chord.`

---

## 4. Suno usage notes

- **Instrumental mode**: toggle Suno's Instrumental switch ON for every track in this pack. Leave
  the **Lyrics** field empty — do not rely on `[Instrumental]` in the lyrics box alone, the toggle
  is what actually suppresses vocal generation.
- **Style field vs. descriptive prompt**: put the comma-separated anchor + mood-specific tags in
  the **Style/genre** field (short, tag-like fragments — this is what Suno weights most heavily for
  timbre/instrumentation). Put the short scene-direction sentence in the main **Prompt/description**
  field — this is what steers mood, pacing, and the ending. Keep `[Instrumental]` at the start of
  the descriptive prompt too, as a second guardrail.
- **Loop-friendly endings**: every prompt above ends with an explicit instruction (e.g. "end on a
  sustained pad," "fade to a static loop point") — Suno defaults to a produced outro otherwise.
  Even so, always generate ~30–60s longer than you need and manually trim to a loop point in an
  editor, cutting on a sustained pad rather than a phrase boundary (per the convention already
  established in `docs/audio-direction.md`).
- **Exclude styles** (use Suno's negative/exclude-styles field if generating): `EDM`, `drum and
  bass`, `dubstep`, `trap`, `orchestral`, `cinematic strings`, `choir`, `rock`, `guitar solo`, `pop`,
  `vocals`, `four-on-the-floor kick`, `big room drop`, `festival build-up`.
- **Naming convention**: `<mood>_<NN>.mp3`, zero-padded two-digit index, matching the folder's
  snake_case name exactly — e.g. `assets/music/tense_crisis/tense_crisis_01.mp3`,
  `tense_crisis_02.mp3`. Generate at least 2–3 per folder so playback can rotate/shuffle within a
  mood without obvious repetition.
