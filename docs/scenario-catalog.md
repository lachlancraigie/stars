# Scenario Catalog — Ship AI

> Human-readable index of the data-driven scenario catalog under `resources/scenarios/`. Generated to satisfy `mission-system-spec.md` §4/§13.

> Companion docs: `scenario-bible.md` (design language), `mission-system-spec.md` (THE contract — schema, closed sets, quotas). The two bespoke GDScript scenarios **The Quarantine** (`the_quarantine`) and **The Narrow Passage** (`the_narrow_passage`) live as builders in `scripts/scenarios/`, not here, but are valid morph targets.


## Counts

- **Total:** 42 scenarios (spec floor 40, target 42).

- **Axis:** bio 10, systems 9, social 8, combat 7, mystery 8.

- **Intensity:** 1 = 12, 2 = 20, 3 = 10.

- **Context coverage (each >=4):** aftermath 13, any 11, arrival 6, away_return 5, derelict 5, docked 12, planet_orbit 4, station 7, transit 21.

- **trigger_status payoffs (11):** changed (something_in_the_walls, the_returned), infected (carrier, spore_lung, the_hitchhiker), marked (the_rash, the_second_voice), shaken (blame, friendly_fire, star_static, the_rumor).

- **Morph edges:** 53, all targets resolve within the catalog (+ the two bespoke ids).


## Index

| id | title | axis | int | contexts | trigger | solves (skills) | morphs-to |
|---|---|---|---|---|---|---|---|
| `cold_chain` | Cold Chain | bio | 1 | transit station | - | Mechanical Repair, Pharmacology | the_ward |
| `gut_flora` | Gut Flora | bio | 1 | aftermath any | - | Field Medicine, Pharmacology | the_rumor |
| `red_rain` | Red Rain | bio | 1 | planet_orbit transit | - | Chemistry, Mechanical Repair | the_long_crack |
| `bloom` | Bloom | bio | 2 | planet_orbit away_return | - | Botany, Ecology, Explosives | spore_lung |
| `carrier` | Carrier | bio | 2 | away_return station | infected | Pathology, Psychology | the_rumor |
| `the_hitchhiker` | The Hitchhiker | bio | 2 | away_return docked | infected | Pathology, Field Medicine | something_in_the_walls, the_rash |
| `the_rash` | The Rash | bio | 2 | aftermath any | marked | Pathology, Field Medicine | the_returned |
| `the_ward` | The Ward | bio | 2 | derelict docked | - | Surgery, Field Medicine, Firearms | dead_ship_hostiles |
| `spore_lung` | Spore Lung | bio | 3 | planet_orbit away_return | infected | Exobiology, Pharmacology, Explosives | the_nest, dead_air |
| `the_returned` | The Returned | bio | 3 | away_return aftermath | changed | Exobiology, Firearms, Psychology | something_in_the_walls, mutiny_hour |
| `brownout` | Brownout | systems | 1 | transit arrival | - | Engineering, Industrial Equipment | ghost_in_the_grid |
| `overpressure` | Overpressure | systems | 1 | docked station | - | Industrial Equipment, Zero-G, Mechanical Repair | the_long_crack |
| `ghost_in_the_grid` | Ghost in the Grid | systems | 2 | transit docked | - | Computers, Hacking, Engineering | the_second_voice, something_in_the_walls |
| `the_drift` | The Drift | systems | 2 | transit aftermath | - | Piloting, Computers, Physics | the_long_crack |
| `the_leak` | The Leak | systems | 2 | transit station | - | Mechanical Repair, Physics | dead_air, reactor_scram |
| `the_long_crack` | The Long Crack | systems | 2 | transit aftermath | - | Mechanical Repair, Jury-Rigging, Engineering | dead_air |
| `dead_air` | Dead Air | systems | 3 | transit any | - | Engineering, Jury-Rigging, Mechanical Repair | mutiny_hour |
| `frozen_out` | Frozen Out | systems | 3 | transit any | - | Mechanical Repair, Industrial Equipment | dead_air |
| `reactor_scram` | Reactor Scram | systems | 3 | transit arrival | - | Engineering, Physics, Jury-Rigging | dead_air, mutiny_hour |
| `blame` | Blame | social | 1 | aftermath any | shaken | Psychology, Command | mutiny_hour |
| `shore_fever` | Shore Fever | social | 1 | station arrival | - | Psychology, Command | close_quarters |
| `the_rumor` | The Rumor | social | 1 | transit any | shaken | Psychology, Sophontology | the_blind_spot |
| `close_quarters` | Close Quarters | social | 2 | any transit | - | Psychology, Command | mutiny_hour |
| `old_debts` | Old Debts | social | 2 | station docked | - | Command, Psychology | mutiny_hour |
| `the_holdout` | The Holdout | social | 2 | aftermath docked | - | Command, Psychology | mutiny_hour |
| `the_prophet` | The Prophet | social | 2 | transit aftermath | - | Theology, Psychology, Sophontology | mutiny_hour |
| `mutiny_hour` | Mutiny Hour | social | 3 | transit aftermath | - | Psychology, Command, Military Training | close_quarters |
| `friendly_fire` | Friendly Fire | combat | 1 | aftermath any | shaken | Psychology, Command, Hand-to-Hand Combat | blame |
| `dead_ship_hostiles` | Dead Ship, Live Teeth | combat | 2 | derelict docked | - | Firearms, Hand-to-Hand Combat, Military Training | the_nest, something_in_the_walls |
| `something_in_the_walls` | Something in the Walls | combat | 2 | derelict aftermath | changed | Firearms, Zoology, Explosives | the_nest |
| `the_marauder` | The Marauder | combat | 2 | transit arrival | - | Command, Piloting | boarders |
| `bad_cargo` | Bad Cargo | combat | 3 | docked station | - | Firearms, Command, Hand-to-Hand Combat | boarders, the_holdout |
| `boarders` | Boarders | combat | 3 | docked transit | - | Firearms, Military Training, Command | the_long_crack |
| `the_nest` | The Nest | combat | 3 | derelict docked | - | Explosives, Firearms, Exobiology | dead_air |
| `false_alarm` | False Alarm | mystery | 1 | transit arrival | - | Computers, Mechanical Repair | the_marauder |
| `star_static` | Star Static | mystery | 1 | planet_orbit arrival | shaken | Physics, Psychology | the_rumor |
| `the_signal` | The Signal | mystery | 1 | transit any | - | Linguistics, Mathematics, Sophontology | the_rumor |
| `deadweight` | Deadweight | mystery | 2 | aftermath docked | - | Physics, Xenoesotericism, Computers | the_second_voice, the_second_voice |
| `the_blind_spot` | The Blind Spot | mystery | 2 | transit any | - | Mechanical Repair, Computers, Psychology | something_in_the_walls, the_rumor |
| `the_derelict_light` | The Derelict Light | mystery | 2 | derelict docked | - | Computers, Archaeology, Linguistics | dead_ship_hostiles, the_ward |
| `the_loop` | The Loop | mystery | 2 | transit any | - | Mathematics, Physics, Artificial Intelligence | the_blind_spot |
| `the_second_voice` | The Second Voice | mystery | 3 | aftermath transit | marked | Artificial Intelligence, Hacking, Computers | mutiny_hour |

## Notes

- Every scenario resolves crew/rooms by role/type or `monitor.cast` binding — no hardcoded names.

- Each scenario carries >=2 solve paths on **different** skills (engineering, social, combat, and science solves are all represented across the catalog), a monitor program with >=1 periodic `check`, and `leg_delta_success` at minimum.

- Win flags are set by monitor `check.on_solved` (any single solve path wins) and/or resolution events; the validator confirms every `win_flag` is settable.

- Benign mystery scenarios (Overseer mercy / false-alarm dread): `false_alarm`, `star_static`, `the_signal`.

- `the_long_crack` and `close_quarters` implement the live morph stubs referenced by `ScenarioRunner.SCENARIO_STUB_FALLBACK`.
