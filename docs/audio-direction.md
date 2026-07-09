# Audio Direction — Music & SFX Generation List

> Generation-ready prompt list for the game's non-dialogue audio. Music prompts are written for
> **Suno** (instrumental mode); SFX prompts work in Suno's soundscape mode but are also phrased to
> drop straight into ElevenLabs' sound-effects generator if Suno fights you on short one-shots.
> Dialogue voice is separate — see `tools/audio_gen/` + `resources/dialogue/voices.md`.
>
> Conventions: files land in `assets/audio/music/` and `assets/audio/sfx/`, snake_case names below.
> "Loop" means trim head/tail silence and loop-point it in an editor after generation; Suno tracks
> loop best if you cut on a sustained pad rather than a phrase boundary.

Tone reference (from the GDD): competent procedural Star Trek voyages through claustrophobic
Alien (1979) horror. Working-class far future. Analog warmth over digital gloss — tape hiss,
detuned synths, machinery as percussion.

---

## Music (Suno, instrumental)

Priority order — the first six cover a full play session.

| # | File | Use / trigger | Suno style prompt | Length |
|---|------|---------------|-------------------|--------|
| 1 | `music_cruise_calm_01` | Default underway state, quiet shifts | "ambient space drone, warm analog synth pads, slow tape-saturated arpeggio, distant engine hum, weightless, patient, 70s sci-fi, instrumental, no percussion" | 3–4 min, loop |
| 2 | `music_tension_low_01` | ScenarioDirector tension rising, first anomaly | "dark ambient, pulsing low synth heartbeat, sparse metallic percussion, held dissonant string pad, creeping dread, submarine thriller, instrumental" | 3 min, loop |
| 3 | `music_crisis_01` | Active crisis: reactor failure, outbreak spreading, hull breach | "urgent industrial percussion, driving analog bass sequence, alarm-like synth stabs, claustrophobic sci-fi thriller, relentless, instrumental" | 2–3 min, loop |
| 4 | `music_horror_01` | Deaths, panic cascades, blackout horror beats | "atonal horror drone, groaning metal textures, breathing-like swells, sub-bass throbs, distant scraping, Alien 1979 score, terrifying stillness, instrumental" | 3 min, loop |
| 5 | `music_aftermath_grief_01` | Post-crisis, after a crew death | "sparse melancholic piano over soft static and ship hum, long silences, elegiac, restrained, tape warble, instrumental" | 2–3 min |
| 6 | `music_title_theme` | Title screen / campaign start | "slow-building retro-futurist synth theme, lonely detuned lead over deep drone, distant radio crackle, majestic but cold, 70s space epic, instrumental" | 2–3 min |
| 7 | `music_mess_radio_01` | Diegetic: mess-hall radio during recreation/meals | "lo-fi spaceport country-blues, dusty slide guitar, tape-worn, jukebox in a truck stop at the end of the universe, instrumental" | 2 min |
| 8 | `music_mess_radio_02` | Diegetic alternate | "scratchy old-time jazz ballad through a cheap speaker, warm vinyl crackle, wistful, heard from another room, instrumental" | 2 min |
| 9 | `music_ai_core_theme` | AI core room focus / degraded-mode moments | "crystalline glass-like synth motif, precise repeating pattern that subtly decays and detunes, cold, beautiful, machine consciousness, instrumental" | 2 min, loop |
| 10 | `music_gameover_decommission` | AI decommissioned ending | "single synth motif slowing and pitch-dropping as if powering down, collapsing into silence and tape stop, funereal, instrumental" | 60–90 s |
| 11 | `music_gameover_crew` | Crew dead / ship lost ending | "hollow wind-like drone, faint far-off distress beacon pulse, desolate, drifting, instrumental" | 90 s |
| 12 | `music_mission_complete` | Scenario success banner | "restrained warm synth resolution, quiet triumph, exhale after held breath, brief rising figure settling to calm pad, instrumental" | 45–60 s |

Wiring note: `ScenarioDirector` already tracks tension/tone drift — the intended mapping is
cruise ↔ tension ↔ crisis ↔ horror as tension bands, with grief/aftermath cued by
`crew_death`/`crisis_resolved` events and the radio tracks played diegetically in the mess only.

## SFX (one-shots and loops)

Grouped by system; **Trigger** names the EventBus signal or situation that plays it.

### Doors & airlocks
| File | Trigger | Prompt |
|------|---------|--------|
| `sfx_door_open` | door opens | "heavy pneumatic sci-fi door sliding open with hydraulic hiss and metal clunk" |
| `sfx_door_close` | door closes | "heavy pneumatic sci-fi door sliding shut, hydraulic hiss ending in solid metallic seal" |
| `sfx_door_locked_clunk` | crew hits a locked door (`door_locked_on_crew`) | "electronic access-denied buzz followed by a dull heavy bolt clunk" |
| `sfx_door_bypass_loop` | bypass attempt in progress (`door_bypass_started`) | "electrical panel tinkering loop: wire sparks, small ratchet clicks, occasional arc buzz" |
| `sfx_door_jam` | crit-fail bypass (`door_bypass_result` critical fail) | "grinding servo failure, metal screech seizing into hard stop, sparks" |
| `sfx_airlock_cycle` | airlock use | "long airlock depressurization cycle: pumps, escalating hiss, pressure equalization thump" |

### Power, reactor & AI core
| File | Trigger | Prompt |
|------|---------|--------|
| `sfx_reactor_hum_loop` | engine_room ambience, reactor online | "deep steady fusion reactor hum with slow subharmonic pulse, industrial room tone" |
| `sfx_reactor_failure` | `reactor_failure` | "massive industrial power-down: turbine winding down, electrical crackle, lights thunking off in sequence" |
| `sfx_battery_mode_loop` | battery power active | "thin fragile electrical hum with intermittent flicker buzz, backup power, unsteady" |
| `sfx_power_low_alarm` | `power_low` | "soft urgent triple-beep alarm, repeating, muffled institutional PA" |
| `sfx_room_power_off` | `room_power_changed` false | "breaker clack then electronics whining down to silence" |
| `sfx_room_power_on` | `room_power_changed` true | "relay thunk, fluorescent flicker-buzz stabilizing into clean hum" |
| `sfx_ai_damaged_glitch` | `ai_damaged` | "digital glitch burst: corrupted data screech, stuttering static, detuned tone" |
| `sfx_core_offline` | AI blackout begins | "catastrophic system shutdown: descending pitch sweep, hard relay clacks, then ringing silence with faint static" |
| `sfx_core_reboot` | repair success on ai_core | "server farm boot sequence: fans spinning up, ascending chimes, relays clicking on in rows" |

### Life support & atmosphere
| File | Trigger | Prompt |
|------|---------|--------|
| `sfx_vents_loop` | life support online room tone | "soft continuous air circulation vent hiss, comfortable ship room tone" |
| `sfx_life_support_fail` | `life_support_failure` | "large fans winding down, air flow choking off, ominous quiet settling in" |
| `sfx_air_thin_loop` | room air < 40 | "strained thin air ambience, faint high-pressure whistle through a failing seal, oppressive" |
| `sfx_hull_breach` | `hull_breach` | "explosive decompression: bang, violent roaring air rush, debris rattle, alarms triggering" |
| `sfx_hull_groan_01` | random deep-space ambience | "distant deep metallic groan of ship hull flexing, whale-like, unsettling" |

### Crew & rooms
| File | Trigger | Prompt |
|------|---------|--------|
| `sfx_footsteps_metal_loop` | crew walking | "single person's boots walking on metal deck grating, steady, mid-distance" |
| `sfx_repair_loop` | repair job active (`repair_started`) | "mechanical repair loop: socket wrench ratchets, panel taps, occasional welding sizzle" |
| `sfx_medbay_loop` | medbay ambience | "quiet medical bay: slow EKG-style beep, soft equipment hum" |
| `sfx_mess_clatter_loop` | mess at meal time | "sparse canteen ambience: cutlery on metal trays, low murmur, chair scrape" |
| `sfx_panic_heartbeat_loop` | a visible crew member panicking (`crew_panicked`) | "accelerating muffled heartbeat with tightening high drone, panic attack from inside a helmet" |
| `sfx_wound_impact` | `injury` | "blunt body impact with cloth rustle and pained grunt-adjacent thud (no voice)" |
| `sfx_death_sting` | `crew_death` | "single dark orchestral-synth sting, short, final, cold reverb tail" |

### UI (the player IS the ship's computer — UI sounds are the AI's own voice)
| File | Trigger | Prompt |
|------|---------|--------|
| `sfx_ui_click` | button press | "minimal clean computer terminal click, single, dry" |
| `sfx_ui_confirm` | directive issued | "short affirmative two-tone computer chirp, 70s terminal" |
| `sfx_ui_deny` | directive refused / access denied | "flat negative computer buzz, curt, slightly distorted" |
| `sfx_ui_alert` | event feed new entry | "soft single sonar-like ping with short tail" |
| `sfx_ui_objective` | objective changed | "three ascending soft terminal tones, businesslike" |
| `sfx_ui_typing_loop` | AI 'thinking'/text printing | "rapid teletype character printing, soft dot-matrix chatter" |

### Alarms
| File | Trigger | Prompt |
|------|---------|--------|
| `sfx_alarm_general_loop` | crisis state active | "classic slow two-tone ship klaxon, distant, institutional, looping" |
| `sfx_alarm_critical_loop` | lose-condition countdowns | "harsh fast strobing klaxon with PA crackle, urgent, oppressive" |

---

### Generation tips
- Suno: prefix SFX prompts with "sound effect, no music, " — it fights the urge to add melody.
  Generate long, harvest the best 2–10 s slice.
- Keep everything mono except music and room-tone loops; the game pans one-shots by room position.
- Loudness: normalize SFX to around −18 LUFS, music to −16 LUFS, so mixing in-engine starts sane.
- Naming is load-bearing: code will look files up by these exact snake_case names.
