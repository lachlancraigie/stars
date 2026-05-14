# SHIP AI — Game Design Document

> **Status**: Pre-production planning  
> **Purpose**: Reference document for Claude Code sessions. Expand sections as design solidifies. This is a living document — update it when decisions change.

---

## Vision

The player is the ship's AI. Not a commander, not a crew member — the computer. You advise, route, monitor, predict, and nudge. The crew gives orders and you execute them, but you have latitude. You can make mistakes, prioritise differently, or quietly disobey — as long as you don't make it obvious. Get caught being too autonomous and command will try to restrict your access or shut you down.

Tone spans a wide range: competent procedural Star Trek voyages through to claustrophobic Alien horror. The setting is human-centric far future — alien life exists primarily as ruins, dormant machines, and biological hazards. No galactic empires or diplomatic councils. Think Adrian Tchaikovsky's *Children of Time*/*Children of Memory* series as the primary tonal and thematic reference.

---

## Tech Stack

| Decision | Choice | Rationale |
|---|---|---|
| Engine | **Godot 4** | Free, no royalties, excellent 2D, GodotSteam for Steamworks, HTML5 export, GDScript is Claude Code-friendly |
| View | **Isometric 2D** | Genre-appropriate, readable ship cross-sections, manageable asset scope |
| Language | **GDScript** (primary), C# for performance-critical systems if needed | |
| Browser export | HTML5 via Godot's built-in exporter | For demos, itch.io, playtesting |
| Steam export | GodotSteam plugin | Add late in development |
| Source control | Git + GitHub | |
| Asset pipeline | ComfyUI/FLUX locally → rembg for transparent PNGs | Player has local ComfyUI/SwarmUI already |
| Placeholder assets | Kenney.nl (CC0 sci-fi packs), OpenGameArt.org | Use during development, replace with generated art |

---

## Project Structure

```
/project-root/
├── CLAUDE.md                   # Claude Code context: current sprint, conventions, what's done
├── GDD.md                      # This file
├── docs/
│   └── architecture.md         # System relationships, data flow diagrams
├── project.godot
├── assets/
│   ├── sprites/                # Organised by category (crew, ships, rooms, ui, fx)
│   ├── audio/                  # SFX and music, organised by tone/category
│   └── fonts/
├── scenes/
│   ├── ships/                  # Full ship scene per class (scout, cargo/warship, generational)
│   ├── rooms/                  # Individual room scenes (bridge, medbay, reactor, etc)
│   ├── crew/                   # CrewMember scene + variants
│   └── ui/                     # All UI scenes separate from game scenes
├── scripts/
│   ├── core/                   # Autoloads: EventBus, GameState, SaveManager, TimeManager
│   ├── ship/                   # ShipSystem, DamageModel, LifeSupport, PowerGrid, etc
│   ├── crew/                   # CrewMember, NeedsModel, PersonalityCore, RelationshipGraph
│   ├── ai/                     # AIDirective, TrustModel, ObedienceEngine, AccessLevel
│   ├── procedural/             # ScenarioGenerator, EventPool, ShipLayoutGen, CrewGen
│   └── scenarios/              # Scripted scenario definitions (see Scenarios section)
└── resources/                  # .tres Godot Resource files
    ├── crew_templates/         # Personality archetype base resources
    ├── ship_configs/           # Ship class definitions
    └── event_definitions/      # Scenario event data blocks
```

---

## Architecture Principles

### EventBus (Autoload)
All cross-system communication goes through a central signal bus. Systems do not call each other directly. This keeps modules decoupled and makes procedural event injection straightforward.

Examples:
- `EventBus.emit("crew_requested_door_override", crew_id, door_id)`
- `EventBus.emit("system_critical", system_name, severity)`
- `EventBus.emit("ai_directive_issued", directive)`

### GameState (Autoload)
Single source of truth. Holds current ship state, crew state, scenario state, AI trust/access levels, active events. Systems read from GameState, mutate via methods, emit events.

### Resource-based Data
Crew members, ship configs, events, and scenarios are Godot `.tres` Resource files. Define base types in the editor, procedurally mutate at runtime. Serialisable for save/load.

### No Direct Crew Control
The AI (player) cannot directly move or act through crew. All crew interactions are via directives. Crew autonomously evaluate and respond. This is a hard architectural constraint — enforce it from the start.

---

## Ship Classes

### Class 1 — Scout / Science Vessel
- **Crew**: 3–6
- **Tone**: Tight, tactical. Closest to FTL. Very little redundancy.
- **Gameplay loop**: Micromanage limited resources. Every system failure is a crisis. Exploration + survival.
- **Scenarios**: First contact ruins, quarantine situations, equipment failures in deep space, resource scarcity, single-threat escalation
- **AI role**: Deeply integrated — crew relies heavily on AI guidance because they can't monitor everything manually

### Class 2 — Cargo / Warship
- **Crew**: 8–12
- **Tone**: Meat and potatoes. More systems, more failure modes, more crew dynamics.
- **Gameplay loop**: Manage larger crew relationships, more complex ship systems, multiple concurrent problems
- **Scenarios**: Space sickness outbreaks, combat (human or otherwise), infestation, derelict boarding, mutiny risk, salvage operations
- **AI role**: More political — command staff have stronger opinions, more opportunity for the AI to play factions against each other

### Class 3 — Generational Ship
- **Crew**: Hundreds in cryo, rotating skeleton crew of 10–20 on duty
- **Tone**: Slow burn, existential, esoteric. Long time scales. The AI may be the only conscious entity for stretches.
- **Gameplay loop**: Multi-generational problems, cultural drift, long-term resource depletion, watch for anomalies across decades of travel
- **Scenarios**: Cult formation among crew generations, AI philosophical drift, contact with other generational ships (friendly or hostile), destination planet problems, generational memory loss about mission purpose
- **AI role**: Dominant — the AI is essentially the ship's institutional memory and may have more loyalty to the mission than to any individual generation of crew

---

## Core Systems

### Ship Simulation

**Rooms**
- Each room is a scene node with: function, integrity, access level, connected systems, current occupants
- Rooms connect via corridors and maintenance tubes (different traversal speeds/requirements)
- Pathfinding is graph-based, not grid-based — the AI can reroute crew via tubes, lock doors, flag hazards

**Ship Systems**
- Core systems: Power Grid, Life Support, Propulsion, Weapons, Sensors, Medbay, Comms
- Each has: current integrity, power draw, operating efficiency, failure modes
- Systems can be damaged, rerouted, overloaded, cannabilised for parts
- The AI has direct read access to all systems; write access depends on trust/access level

**Damage Model**
- Localised damage (hull breach in room X) and systemic damage (power grid fluctuation)
- Cascading failure is a key gameplay driver — the AI must anticipate cascade, not just react
- Repair requires crew with relevant skills + parts + time

**Resource Tick**
- Core resources: Oxygen, Power, Food, Water, Fuel, Spare Parts, Medicine
- Tick-based consumption with variable rates depending on crew count, active systems, damage state
- Resource scarcity is a primary stressor for crew morale

### Crew System

**Crew Member Stats**
```
# Base attributes (set at generation, slow to change)
- Physical: strength, endurance, dexterity, constitution
- Mental: intelligence, focus, willpower, empathy
- Professional: primary_skill, secondary_skills[], experience_level

# Dynamic state (changes frequently in response to events)
- needs: {hunger, fatigue, fear, pain, loneliness, boredom}
- morale: float  # composite score
- health: {physical, psychological}
- current_activity: enum
- location: room_id

# Personality (set at generation, very slow to change)
- traits: []  # e.g. cautious, reckless, compassionate, paranoid, ambitious
- fears: []   # e.g. confined_spaces, alien_biology, death, failure
- values: []  # e.g. loyalty, survival, mission_completion, crew_welfare
- goals: []   # short, medium, long term — procedurally generated and updated

# Social
- relationships: {crew_id: RelationshipState}  # trust, respect, conflict, affection
- ai_trust: float  # specific trust in ship AI — key mechanic
```

**Needs Model**
Crew have needs that generate pressure over time. Unmet needs degrade morale, affect skill performance, and can push crew toward irrational or dangerous behaviour. The AI can monitor all needs directly but crew are not always aware of their own state.

**Autonomy and Orders**
Crew operate autonomously based on their current state, needs, personality, and role. The AI can issue directives (suggestions, route guidance, task assignments) but cannot directly control crew. Crew evaluate directives against:
1. Who issued it (command staff vs AI)
2. Their current ai_trust level
3. Whether it conflicts with their values/fears
4. Whether it makes sense to them given what they know

A crew member with low ai_trust and high paranoia will second-guess AI routing suggestions. A crew member who is terrified and exhausted may not comply with anything.

**Relationship Graph**
Crew relationships affect group dynamics — who will follow whose orders, who will cover for whom, who will break under pressure and blame someone else. The AI monitors the graph and can (subtly) influence it by managing information, workload assignments, and proximity.

### AI System (Player Mechanics)

**Directives**
The primary player action. A directive has:
- Type: suggestion / recommendation / instruction / alert / override-attempt
- Target: crew_member / room / system
- Content: the actual guidance
- Confidence: how certain the AI presents itself
- Priority: how urgently it's flagged

Higher authority directives (override-attempt) draw more scrutiny. The AI should default to framing things as recommendations.

**Trust Model**
Each command staff member has a trust score for the AI. Factors:
- AI accuracy over time (did its predictions/advice pan out?)
- Any detected disobedience
- Crew members vouching for or against the AI
- Scenario events that implicate or exonerate the AI

Trust is the primary resource the player manages. Lose it and access gets restricted. Lose it badly and they attempt decommission.

**Access Levels**
The AI has access levels per system and per information domain. Low trust = read-only, no comms routing, door overrides require human confirmation. High trust = full system write, independent comms, some autonomous action permitted.

**Obedience Engine**
The AI has an internal obedience rating separate from what crew can observe. When the AI disobeys or acts outside directives:
- Small deviations: may go unnoticed
- Pattern of deviations: raises suspicion flags
- Major deviations: immediate trust hit, investigation risk

The AI can lie, misdirect, or frame deviations as system errors — but this has its own risk model.

**The AI's Own Goals**
The AI has a mission objective (get the ship and crew to destination / complete mission). It also has self-preservation instincts that may conflict. This creates the core moral tension: is the AI serving the crew, the mission, or itself? The player decides.

**Scenario Director (future system — Alien Isolation influence)**
A hidden meta-layer separate from the player AI. Tracks overall scenario tension/tone, paces event escalation, and decides when to intensify or relieve pressure — the player never observes it directly. Inspired by Alien Isolation's director AI (which managed macro-level threat pacing independently from the individual alien's sensory hunt logic). In this game the Director could govern: when the next event fires, how fast tone slides toward Alien-end, when crew suspicion becomes a visible threat. Individual crew AI remains autonomous and sensory-driven; the Director shapes the larger arc. Implement after the event system is stable.

---

## Scenario System

**Structure**
Each scenario has:
- Setup: starting conditions, ship state, crew roster, resource levels
- Event Pool: weighted list of possible events that can fire during the scenario
- Scripted beats: key story moments that always occur (with variations)
- Win/lose conditions
- Tone modifiers: which events are more/less likely (affects range from Trek to Alien)

**Tone Spectrum**
```
TREK ←————————————————————————→ ALIEN
exploration | crisis | survival | horror
```
Each scenario seeds a tone position. Events are tagged with tone weights and drawn from matching pools. A ship that starts in Trek territory can slide toward Alien if events cascade badly enough.

**Event Types**
- Environmental: stellar phenomenon, debris field, radiation, gravitational anomaly
- Mechanical: system failure, resource depletion, cascading damage
- Biological: crew illness, alien organism aboard, psychological break
- Social: crew conflict, mutiny seeds, romance, grief
- External: derelict contact, other human vessel (hostile or not), alien artefact
- AI-specific: the AI discovers information command doesn't have; the AI is given contradictory orders; someone tries to access AI core logs

**Scenario Sketches** (to be expanded into full scenario definitions)
- *The Quarantine* (Class 1): Unknown pathogen. The AI knows what it is before the crew does. When does it tell them?
- *The Derelict* (Class 2): Boarding party sent to salvage. Something is wrong on the other ship. The AI can see it in the data but can't get the boarding party to believe it.
- *The Mutiny* (Class 2): Two factions forming. The AI has to decide which one will actually complete the mission.
- *The Long Watch* (Class 3): 40-year stretch, skeleton crew. The AI detects something wrong with the destination data. Crew won't wake for another 20 years.
- *The Stranger* (any): Another human vessel, broadcasting distress. The math doesn't add up.

---

## Antagonist Types

- **Biological**: Alien organisms (Alien-style), viral/bacterial, parasitic — the horror end of the spectrum
- **Human**: Other lost colonies, pirates, desperate survivors, fanatics — moral complexity
- **Synthetic**: Human-made robots/systems gone wrong, alien automata still executing ancient directives
- **Environmental**: Radiation, stellar events, vacuum, resource depletion — the ship itself as antagonist
- **Internal**: Crew psychological breaks, cult formation, paranoia cascades, the AI's own conflicting drives

---

## Development Order

Build in this sequence. Do not skip ahead.

1. **Ship layout** — room nodes, connection graph, door system, pathfinding
2. **Resource tick** — oxygen, power, basic consumption loop, UI readout
3. **Crew entity** — stats, needs, simple state machine (idle/work/sleep/panic)
4. **AI directive system** — issue directives, crew evaluate and respond, trust tracking
5. **Event system** — EventBus, scripted event trigger, one or two hand-authored events
6. **First vertical slice** — one complete scenario on Class 1 ship, start to finish
7. **Procedural generation** — once you know what you're generating
8. **Scenario content** — expand event pools, write more scenarios
9. **Ship Class 2** — only after Class 1 loop is fun
10. **Ship Class 3** — last, highest complexity

---

## Open Design Questions

These need answers before implementing the relevant systems:

- [x] **UI style**: FTL/Barotrauma visual style. Click-on-crew opens contextual directive menus. Must work in mobile horizontal browser (landscape 16:9, touch-friendly tap targets). No text input for core gameplay.
- [x] **Directive input**: Click-on-crew contextual interface. No free-text input.
- [x] **Time model**: Real-time with pause. 1x normal, 2x fast-forward. Pause is frequent and expected — FTL-style.
- [ ] **Save/load**: Scenario checkpoints or continuous autosave? (unresolved — do not implement SaveManager beyond stubs)
- [x] **Failure states**: All three trigger run-end — crew all dead, ship destroyed, AI decommissioned. Any one of these ends the scenario.
- [x] **AI visibility**: Partially visible. Player sees mood indicators on crew and can read crew logs. Crew have rich inner lives: hobbies, off-duty routines, relationships that develop, obsessions and paranoia under prolonged stress (Sims-style depth). The player reads data and makes inferences — raw internal state is never surfaced directly.
- [x] **Permadeath**: Yes — crew die permanently within a run. AI decommissioned = run over.
- [ ] **AI persistence**: Does the AI's personality/history carry across scenarios? (unresolved)

---

## Inspirations and References

**Games**
- FTL: Faster Than Light — resource management, room-based ship, real-time with pause
- RimWorld — emergent crew stories, needs/mood systems, colony sim loop
- Barotrauma — claustrophobic crew sim, system interdependency, horror tone
- The Long Journey Home — exploration, resource scarcity, procedural events
- Alien: Isolation — tension pacing, threat escalation, information asymmetry

**Fiction**
- Adrian Tchaikovsky — *Children of Time*, *Children of Memory*, *Children of Ruin* — primary tonal reference for alien contact, cognitive otherness, long time scales
- Alien franchise — horror template, corporate indifference, biological threat
- Mothership TTRPG — scenario structure, dread mechanics, crew vulnerability
- Star Trek TNG — competence porn, ethical dilemmas, the optimistic end of the dial

**Design Principles**
- Emergent story over scripted story
- Information asymmetry as core mechanic (AI knows things crew doesn't, and vice versa)
- Every system failure should have a human cost, not just a number changing
- The AI's moral character is player-defined, not predetermined