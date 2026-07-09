# Voices — ElevenLabs Voice Design Reference

Per-archetype voice-design prompts for ElevenLabs (matches `elevenlabs_voice` field in each
`archetypes/*.json`, reproduced here for quick reference when driving voice design / voice
cloning sessions) plus the emotive-tag → ElevenLabs v3 audio-tag mapping used when synthesizing
lines from `elevenlabs/*.csv`.

Coverage matrix (career × rank), for reference — see `docs/dialogue_spec.md` for the full
archetype scheme:

| | Captain (CA) | Officer (OF) | Crew Mate (CM) |
|---|---|---|---|
| Scientist (SCI) | EV_FE_SCI_CA, PA_ML_SCI_CA | CH_ML_SCI_OF, GR_ML_SCI_OF, EV_FE_SCI_OF | PA_ML_SCI_CM, CH_FE_SCI_CM |
| Android (AND) | — (forbidden) | EV_FE_AND_OF, PA_FE_AND_OF | CH_ML_AND_CM, GR_FE_AND_CM |
| Teamster/Engineer (ENG) | GR_ML_ENG_CA | GR_FE_ENG_OF, CH_ML_ENG_OF | GR_ML_ENG_CM, CH_FE_ENG_CM, EV_ML_ENG_CM, PA_FE_ENG_CM |
| Marine (MAR) | PA_FE_MAR_CA | EV_FE_MAR_OF, PA_ML_MAR_OF | CH_ML_MAR_CM, GR_FE_MAR_CM, EV_ML_MAR_CM |

---

## Emotive tag → ElevenLabs v3 audio tag mapping

Emotive tags in line text (`[EMPHASIS]`, `[TERRIFIED]`, etc.) are stripped before on-screen
display but kept in the ElevenLabs export (`elevenlabs/*.csv`). ElevenLabs v3 reads inline
audio tags and natural-language emotional cues embedded in the text to steer delivery — it does
not have a fixed enum of tags, so this table maps our closed vocabulary to the v3 bracket-style
audio tags / prompt phrasing that reliably produce the intended read. Use the "v3 direction"
column as the literal bracketed cue (or nearest supported equivalent) fed alongside the line;
where v3 has no direct bracket equivalent, the "prompt guidance" column describes how to steer
via the surrounding delivery-style prompt instead.

| Our tag | v3 direction | Prompt guidance |
|---|---|---|
| `[EMPHASIS]` | `[emphasis]` | Stress the following word/phrase; slight volume/pitch lift. |
| `[CONFIDENT]` | `[confident]` | Assured, forward delivery, no hedging in the tone. |
| `[REASSURING]` | `[reassuring]` | Warm, slowed pacing, softened consonants. |
| `[TERRIFIED]` | `[terrified]` | Shaking breath, higher pitch, broken cadence. |
| `[NERVOUS]` | `[nervously]` | Quick, slightly unsteady pacing, audible hesitation. |
| `[ANGRY]` | `[angry]` | Harder consonants, clipped, raised volume. |
| `[GRUFF]` | `[gruffly]` | Lower register, flat affect, short phrasing. |
| `[WARM]` | `[warmly]` | Softened tone, slower, rounded vowels. |
| `[TIRED]` | `[tired sigh]` | Lower energy, trailing breath at phrase ends. |
| `[EXHAUSTED]` | `[exhausted]` | Heavier breath, slower pacing, flat pitch contour. |
| `[PANICKED]` | `[panicked]` | Fast, ragged breath, rising pitch, broken sentence rhythm. |
| `[CALM]` | `[calmly]` | Even pacing, low volume, minimal pitch variation. |
| `[URGENT]` | `[urgently]` | Fast, forward-driving pacing, clipped pauses. |
| `[SARCASTIC]` | `[sarcastic]` | Flattened pitch with an ironic upward lilt on the punchline word. |
| `[DRY]` | `[deadpan]` | Minimal inflection, flat delivery, no emphasis lift. |
| `[GRIM]` | `[grimly]` | Low, heavy, slowed delivery with a hard stop at the end. |
| `[HOPEFUL]` | `[hopeful]` | Slight upward pitch lift, brighter tone, held breath before the key word. |
| `[WHISPERS]` | `[whispers]` | Breathy, low volume, close-mic texture. |
| `[SHOUTS]` | `[shouts]` | High volume, projected, harder onset consonants. |
| `[MUTTERS]` | `[muttering]` | Low volume, indistinct trailing consonants, half to self. |
| `[LAUGHS]` | `[laughs]` | Insert a short laugh; following text carries residual smile. |
| `[SIGHS]` | `[sighs]` | Insert an audible exhale before the line continues. |
| `[PAINED]` | `[strained]` | Tight throat, short of breath, involuntary tension in vowels. |
| `[FLIRTY]` | `[flirtatious]` | Playful lilt, slower, teasing emphasis. |
| `[EMBARRASSED]` | `[embarrassed]` | Quieter, faster, trailing off mid-phrase. |
| `[SUSPICIOUS]` | `[suspicious]` | Slowed, wary, slight downward pitch on key words. |
| `[CURIOUS]` | `[curiously]` | Rising inflection, brighter, slightly quicker. |
| `[PROUD]` | `[proud]` | Lifted chest tone, slower, satisfied weight on key word. |
| `[DISMISSIVE]` | `[dismissively]` | Short, flat, downward pitch at phrase end, faster exit. |
| `[PLEADING]` | `[pleading]` | Softer, higher, unsteady, stretched vowels. |
| `[RESIGNED]` | `[resigned]` | Flat, slow exhale quality, downward pitch drift. |
| `[DEADPAN]` | `[deadpan]` | No inflection change regardless of content; flat affect. |

A tag applies to the words following it until the next tag or end of line — when exporting,
carry that scoping into the v3 prompt directly (i.e. only the tagged span gets the direction;
untagged spans default to the archetype's baseline voice-design delivery).

---

## Per-archetype voice design

### Teamster / Engineer

**GR_ML_ENG_CM — Gus Hollis** (gruff male engineer, crew mate)
> Male, late 60s. Low, gravelled baritone worn down by decades of engine noise and cheap
> cigarettes he quit twenty years ago but still sounds like he hasn't. American working-class
> accent, flat Rust Belt/dockworker vowels, no polish. Pacing is slow and deliberate, full of
> half-second pauses like he's checking a gauge before finishing the sentence; speeds up only
> when annoyed or when something on the ship is about to kill someone. Texture: dry, slightly
> hoarse, a low rasp on sibilants, occasional wet cough held back mid-line. Delivery is flat and
> unimpressed by default — sarcasm lands quiet, not sharp. Warmth shows up rarely and only as a
> softening of pace, never a change in volume.

**GR_FE_ENG_OF — Roz Kessler** (gruff female engineer, officer)
> Female, early 60s. Warm-worn alto with real gravel in it — decades of shouting over engine
> noise, not smoking, just volume. Accent: rural/working-class, slightly Southern-inflected,
> unhurried but not soft. Pacing is conversational and quick when she's mid-repair-monologue,
> slowing to a low mutter when she's coaxing a machine or comforting someone. Texture: chesty
> resonance, audible breath on longer lines, a chuckle that rattles rather than tinkles. Delivery
> leans affectionate-exasperated by default, like she's talking to a stubborn animal she loves;
> sharpens into flat command only when something is actually about to go wrong.

**GR_ML_ENG_CA — Captain Silas Kreuger** (gruff male engineer, captain)
> Male, mid-50s. Grounded, weathered baritone, unhurried command voice built from decades of
> being the one people ask "is it gonna hold." Faint dockworker accent smoothed slightly by
> years of giving orders. Pacing is measured, plain, no wasted words; picks up urgency only when
> the numbers actually demand it. Texture: solid, a little gravel, breath steady. Delivery
> defaults to calm authority earned rather than performed; warmth surfaces as dry understatement,
> not softness.

**CH_FE_ENG_CM — Josie Alvarenga** (cheerful female engineer, crew mate)
> Female, mid-20s. Bright, energetic alto with a grin audible in it. Casual, slightly rural
> accent, rounded vowels. Pacing is quick and bouncy, sentences often ending upward like she's
> already excited about the next one. Texture: light, a little husky when she laughs, easy
> breath. Delivery defaults to enthusiastic and can-do; under real pressure she gets focused and
> fast rather than scared, treating the crisis like the biggest puzzle yet.

**CH_ML_ENG_OF — Marcus Feldheim** (cheerful male engineer, officer)
> Male, mid-30s. Warm, resonant tenor-baritone, easy and encouraging. Light urban accent, clear
> and friendly diction. Pacing is brisk but generous, gives people room to respond; slows down
> deliberately when explaining something technical so it lands. Texture: full, warm, laughs from
> the chest. Delivery defaults to upbeat mentor energy; under crisis he gets crisp and directive
> but keeps the encouragement running underneath it.

**EV_ML_ENG_CM — Declan Osei-Marsh** (even male engineer, crew mate)
> Male, early 40s. Low, level baritone, unhurried and grounded. Neutral accent, minimal
> inflection. Pacing stays almost identical whether he's discussing lunch or a hull breach —
> steady, measured, no rush. Texture: smooth, quiet resonance, breath even and controlled.
> Delivery is calm and procedural by default; the steadiness itself functions as reassurance for
> everyone around him.

**PA_FE_ENG_CM — Nadia Kirchner** (paranoid female engineer, crew mate)
> Female, early 20s. Light, quick soprano with a nervous edge, prone to pitch rising when
> startled. Faint urban accent, fast natural speech. Pacing is rapid and jittery under any
> stress, words tripping over each other; only slows when she's fully absorbed in a repair, hands
> busy and mind quiet. Texture: thin, a little breathy, audible gasp before bad news. Delivery
> defaults to anxious-but-trying; genuine competence shows through the moment her hands are on
> the actual problem.

### Marine

**PA_FE_MAR_CA — Vic Solano** (paranoid/excitable female marine, captain)
> Female, early-to-mid 30s. Bright, forward, slightly rasped alto with a lot of forward drive in
> the tone — sounds like she's always about two seconds from moving. Accent: American, urban,
> quick consonants, clipped military cadence under stress. Pacing is fast and punchy by default,
> with sudden hard stops for emphasis; slows and drops half an octave only in rare sincere
> moments. Texture: a little rough at the edges (post-shouting huskiness), quick husky laugh,
> breath audible on fast lines. Delivery defaults to confident-and-amused, needling; under real
> danger it snaps into flat, clipped command tone with zero wasted syllables.

**EV_FE_MAR_OF — Lieutenant Farah Okonkwo** (even female marine, officer)
> Female, mid-30s. Clear, controlled mezzo with real weight behind it despite the calm. Neutral,
> faintly military-crisp accent. Pacing is even and deliberate, commands landing without needing
> volume; only speeds up to match the tempo of an active threat, never to panic. Texture: solid,
> low resonance, breath disciplined. Delivery defaults to composed authority; her rare warmth is
> quiet and directed at one person at a time.

**PA_ML_MAR_OF — Lieutenant Casper Wray** (paranoid male marine, officer)
> Male, mid-30s. Tight, forceful tenor with a wound-up edge even at rest. Clipped
> military-regional accent. Pacing is fast and urgent by default, gets faster and louder under
> real threat rather than sharper. Texture: tense, a little strained in the throat, quick sharp
> breaths. Delivery defaults to keyed-up vigilance; the rare moment he actually relaxes is more
> startling to the crew than his usual intensity.

**CH_ML_MAR_CM — Deshawn Ortega** (cheerful male marine, crew mate)
> Male, late 20s. Loud, easy baritone with a grin built into it. Broad, friendly regional accent.
> Pacing is fast and bouncy in calm moments, snapping into sharp military cadence the instant
> things go bad, then bouncing right back after. Texture: robust, chest-forward, laughs loud and
> often. Delivery defaults to buddy-energy warmth; under fire it turns instantly professional and
> clipped, then relaxes just as fast once it's over.

**GR_FE_MAR_CM — Reyes Ibarra** (gruff female marine, crew mate)
> Female, mid-40s. Low, rough alto, real gravel from old smoke and old shouting both. Hard-edged
> working-military accent. Pacing is clipped and economical by default, no wasted breath; only
> slows down for the rare story she actually decides to tell. Texture: rasped, low, a dry chuckle
> rather than a laugh. Delivery defaults to flat and unbothered; the only crack in it shows up
> talking about the dead.

**EV_ML_MAR_CM — Corporal Aldric Voss** (even male marine, crew mate)
> Male, early 30s. Quiet, even baritone, unshowy. Neutral accent, minimal inflection, economical
> phrasing. Pacing is steady and unhurried across every stress level, sentences short and
> complete. Texture: smooth, low, breath controlled and quiet. Delivery is calm and
> matter-of-fact by default; his stillness under fire is the whole personality.

### Scientist / Medic

**EV_FE_SCI_CA — Dr. Elena Marsh** (even female scientist, captain)
> Female, mid-40s. Low, controlled alto with crisp diction and almost no filler words. Neutral
> trans-Atlantic accent, unplaceable. Pacing is measured and even regardless of stress — the
> words come at the same rate whether she's discussing lunch or a hull breach. Texture: smooth,
> low rasp only when exhausted, breath tightly controlled. Delivery defaults to calm clinical
> authority; the only tell of real fear is a half-second pause before she speaks.

**PA_ML_SCI_CA — Captain Simon Achterberg** (paranoid male scientist, captain)
> Male, late 30s. Reedy tenor with a nervy, quick-fire cadence — words tumble slightly ahead of
> the thought. Central-European-inflected English, precise consonants. Pacing speeds up further
> under stress rather than slowing, occasionally stumbling over syllables he catches and
> restarts. Texture: thin, a little breathless, throat tightens audibly when reciting
> probabilities of death. Delivery defaults to anxious-analytical; brief moments of captain's-
> command flatness cut through when he's actually certain of something.

**CH_ML_SCI_OF — Dr. Teodor "Teddy" Fassbinder** (cheerful male medic, officer)
> Male, early 30s. Warm, bright tenor with an easy smile audible in the tone. Light,
> hard-to-place accent — well-travelled, rounded vowels. Pacing is brisk and upbeat, full of
> little verbal exclamation points; slows only to deliver bad news gently, still finding
> something hopeful to land on. Texture: clean, resonant, laughs easily and often, warmth even in
> low volume. Delivery defaults to reassuring-cheerful; under real crisis it stays warm but gets
> fast and focused, like he's coaching you through it.

**GR_ML_SCI_OF — Dr. Warrick Doyle** (gruff male scientist, officer)
> Male, late 50s. Deep, dry baritone, unhurried, faint rasp. Neutral working-doctor accent,
> clipped consonants. Pacing is slow and deliberate, each sentence landing like a verdict; speeds
> up only mid-procedure when hands matter more than words. Texture: low, gravelled, breath
> audible between phrases. Delivery is flat and matter-of-fact by default; the only warmth comes
> out sideways, in what he doesn't say.

**EV_FE_SCI_OF — Dr. Ilse Brannigan** (even female scientist, officer)
> Female, late 30s. Warm but level mezzo, unhurried in the way of someone who trusts her own
> competence. Soft mixed-region accent, rounded and clear. Pacing stays remarkably constant
> across stress levels — the calm is structural, not performed. Texture: smooth, low resonance,
> breath controlled and quiet. Delivery is steady and grounding by default; the only shift under
> real danger is a very slight drop in pitch, more serious, never faster.

**PA_ML_SCI_CM — Dwight Kowalczyk** (paranoid male scientist, crew mate)
> Male, mid-20s. Light, slightly strained tenor, quick and clipped when nervous. Flat
> Midwestern-American accent. Pacing is uneven — bursts of fast, over-explained speech followed
> by sudden nervous pauses. Texture: thin, occasional voice crack under stress, audible swallow
> before saying something he doesn't want to say. Delivery defaults to hedging and qualifying
> everything; genuine confidence only appears, briefly, when he's certain about the science.

**CH_FE_SCI_CM — Marisol Feng** (cheerful female medic, crew mate)
> Female, mid-20s. Bright, quick soprano-alto with real buoyancy in it. Light West
> Coast-American accent. Pacing is fast and enthusiastic, rising inflection on observations; only
> flattens out when a case actually scares her, and even then recovers fast. Texture: clear, a
> little breathy, laughs through her nose when amused. Delivery defaults to chipper and curious;
> under pressure she gets faster, not quieter, talking herself and the patient through it.

### Android

**EV_FE_AND_OF — Iris Kepler** (even android, officer)
> Female-coded synthetic voice, ageless. Clear, softly resonant alto with unnaturally even
> breath support — no filler words, no vocal fry. Neutral, faintly formal diction, slightly
> over-precise consonants. Pacing is metronomic-calm regardless of situation, with the occasional
> half-beat pause before an emotionally loaded word, as if selecting it. Texture: smooth, almost
> too smooth, a faint synthetic sheen under scrutiny. Delivery defaults to composed and helpful;
> the uncanny edge shows only in how little the tone moves even during genuine danger.

**PA_FE_AND_OF — Iskra Volkov** (paranoid/vigilant android, officer)
> Female-coded synthetic voice, sounds late 30s. Crisp, alert mezzo with a coiled-tight energy
> under the precision. Neutral accent, very exact diction. Pacing is fast and clipped, speeds up
> further when flagging danger, occasional rapid-fire delivery of contingencies. Texture: clean,
> a slight metallic edge that sharpens under stress. Delivery defaults to vigilant and slightly
> too intense for the room; rarely relaxes, and when she tries to sound casual it doesn't quite
> land.

**CH_ML_AND_CM — Milo Chen** (cheerful android, crew mate)
> Male-coded synthetic voice, sounds late 20s. Bright, light baritone with a slightly too-even
> smile in the tone. Neutral accent, crisp diction. Pacing is upbeat and quick, cheerful cadence
> that occasionally clips a syllable early — almost right, not quite human timing. Texture:
> clean, faint digital smoothness on sustained vowels. Delivery defaults to eager-to-please
> warmth; under stress the cheerfulness doesn't break, it just gets a fraction faster and more
> clipped, which is somehow unsettling.

**GR_FE_AND_CM — Rook Halvorsen** (gruff android, crew mate)
> Female-coded synthetic voice, sounds 50s. Low, dry alto with a mechanical evenness under a
> learned gruffness. Faint working-class accent — picked up, not native, occasionally slips into
> flatter synthetic cadence mid-sentence. Pacing is slow and grumbling by default, with tell-tale
> too-even stretches when she's processing rather than feeling. Texture: dry, a little flat, no
> real rasp since there's no smoke behind it, but she performs one anyway. Delivery defaults to
> curmudgeonly-affectionate; under real danger the performance drops entirely into flat synthetic
> precision.

---

## Notes for TTS pass operators

- Androids (AND career) should always read as *subtly* off — never robotic-monotone, never
  fully human. The tell is in timing (a half-beat too even, a clipped syllable) and in emotional
  words landing a fraction late/precise, not in pitch or vocabulary.
- Keep each archetype's baseline delivery consistent across all its lines; emotive tags modulate
  *from* that baseline, they don't replace it — a `[TERRIFIED]` line from EV_FE_SCI_CA should
  still sound more controlled than a `[TERRIFIED]` line from PA_FE_ENG_CM.
- `voice_id` assignment (actual ElevenLabs voice IDs) is out of scope for this document — this
  is the design brief handed to whoever provisions or clones the voices.
