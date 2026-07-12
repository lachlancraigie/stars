# Mission Catalog — Ship AI

> Human-readable index for `resources/missions/*.json`. Generated to match the
> mission JSON schema in `docs/mission-system-spec.md` §3. 46 missions.

> The overt layer of the mission/scenario overhaul: the ship is *ordered* to do these;
> the Overseer decides which covert scenario (see `docs/scenario-catalog.md`) infects each leg.

## Type spread

| bucket | count | missions |
|---|---|---|
| openers (tag) | 3 | first_light, short_haul, the_payphone |
| rendezvous / docking | 8 | cold_ledger, dead_drop, fuel_line, meridian_audit, parley, the_courier, the_handshake, the_relief |
| planet (survey/mining/science) | 10 | ashfall, aurora, deep_core, greenhouse, saltflats, stillwater, the_green_line, the_hollow, the_quarry, tombworld |
| delivery / escort / passenger | 6 | dignitary, hot_freight, shepherd, the_long_haul, the_passenger, wet_nurse |
| salvage / derelict | 5 | black_box, cold_iron, scrapright, the_widow, tomb_station |
| repair / homecoming / hub | 4 | cold_harbor, limp_home, patch_job, shore_leave |
| distress / evacuation | 5 | dead_air, last_call, lifeboat, mayday, the_stranded |
| patrol / quarantine / smuggle | 4 | bad_manifest, chain_of_custody, hard_quarantine, the_line |
| finale (tag; drawn by the voyage charter, never offered — docs/loop-direction.md §6.2) | 1 | final_approach |

## Index

| id | title | type | destination | hooks | follow-ons |
|---|---|---|---|---|---|
| `ashfall` | Ashfall | planet_survey | Forge (volcanic ashen world) | on_station:planet_orbit(0.75)<br>away_return:away_return(0.7)<br>transit_back:aftermath(0.5) | [crew_stranded_surface] -> the_stranded<br>[hull_mauled] -> tag:repair<br>[mission_success] -> tag:trade, cold_harbor |
| `aurora` | Aurora | science | Halcyon Prime (banded gas giant) | on_station:planet_orbit(0.7)<br>transit_back:aftermath(0.5) | [mission_success] -> tag:mystery, tombworld<br>[crew_shaken_aboard] -> shore_leave |
| `bad_manifest` | Bad Manifest | quarantine_run | Freeport Ledge (grey-market freeport) | transit_out:transit(0.4)<br>on_station:docked(0.75)<br>transit_back:aftermath(0.55) | [hull_mauled] -> limp_home, tag:repair<br>[mission_success] -> tag:homecoming, cold_harbor<br>[mission_failed] -> tag:distress, the_stranded |
| `black_box` | Black Box | salvage | Wreck of the Verity (silent drifting wreck) | on_station:derelict(0.75)<br>away_return:away_return(0.65)<br>transit_back:aftermath(0.5) | [crew_stranded_derelict] -> the_stranded<br>[mission_success] -> tag:salvage, cold_iron<br>[crew_changed_aboard] -> tag:mystery |
| `chain_of_custody` | Chain of Custody | quarantine_run | Meridian Cold Store (sealed consignee depot) | transit_out:transit(0.6)<br>transit_back:aftermath(0.55) | [crew_infected_aboard] -> hard_quarantine, tag:bio_aftermath<br>[mission_success] -> tag:trade, cold_harbor<br>[crew_changed_aboard] -> tag:mystery |
| `cold_harbor` | Cold Harbor | homecoming | Cold Harbor (home transfer hub) | transit_out:transit(0.35)<br>on_station:station(0.4) | [mission_success] -> tag:opener, tag:planet<br>[crew_shaken_aboard] -> shore_leave<br>[crew_infected_aboard] -> hard_quarantine |
| `cold_iron` | Cold Iron | salvage | Cold Iron (rust-streaked dead hauler) | on_station:derelict(0.85)<br>away_return:away_return(0.75)<br>transit_back:aftermath(0.6) | [crew_infected_aboard] -> hard_quarantine, tag:bio_aftermath<br>[crew_stranded_derelict] -> the_stranded<br>[hull_mauled] -> limp_home, tag:repair |
| `cold_ledger` | Cold Ledger | rendezvous | MCV Cold Ledger (grey accounting cutter) | on_station:docked(0.5)<br>transit_back:aftermath(0.35) | [mission_success] -> tag:trade, the_courier<br>[meridian_grudge] -> meridian_audit, tag:patrol |
| `dead_air` | Dead Air | distress | Waypoint Ember (silent lit station) | on_station:station(0.85)<br>away_return:away_return(0.75)<br>transit_back:aftermath(0.6) | [crew_infected_aboard] -> hard_quarantine, tag:bio_aftermath<br>[crew_stranded_station] -> the_stranded<br>[crew_changed_aboard / crew_marked_aboard] -> tag:mystery |
| `dead_drop` | Dead Drop | rendezvous | The Hollow Marker (unlit rendezvous point) | on_station:docked(0.5)<br>transit_back:aftermath(0.6) | [mission_success] -> tag:smuggle, dead_drop<br>[crew_infected_aboard] -> tag:bio_aftermath<br>[crew_marked_aboard] -> tag:mystery |
| `deep_core` | Deep Core | mining | Cinder-9 (molten iron asteroid) | on_station:planet_orbit(0.7)<br>away_return:away_return(0.6)<br>transit_back:aftermath(0.5) | [hull_mauled] -> limp_home, tag:repair<br>[mission_success] -> tag:trade, cold_harbor<br>[crew_changed_aboard] -> tag:mystery |
| `dignitary` | Dignitary | passenger | Cold Harbor (cluttered transfer hub) | transit_out:transit(0.45)<br>on_station:station(0.4) | [mission_success] -> tag:trade, cold_harbor<br>[meridian_grudge / mission_failed] -> meridian_audit |
| `final_approach` | Final Approach | homecoming | Harbour Reach (charter terminus station) | transit_out:transit(0.5)<br>arrival:arrival(0.35)<br>on_station:station(0.3) | none — the charter ends here (voyage_completed) |
| `first_light` | First Light | planet_survey | MC-9 Barren (airless grey moon) | transit_out:transit(0.2)<br>on_station:planet_orbit(0.3) | [mission_success] -> tag:planet, the_quarry<br>[crew_stranded_surface] -> the_stranded |
| `fuel_line` | Fuel Line | rendezvous | HFV Slow Marey (swollen bunker tanker) | on_station:docked(0.4)<br>transit_back:aftermath(0.3) | [mission_success] -> tag:planet, tag:trade<br>[mission_partial / mission_failed] -> tag:repair |
| `greenhouse` | Greenhouse | planet_survey | Kepler-Verde (jungle world) | on_station:planet_orbit(0.85)<br>away_return:away_return(0.7)<br>transit_back:aftermath(0.5) | [crew_infected_aboard] -> hard_quarantine, tag:bio_aftermath<br>[crew_stranded_surface] -> the_stranded<br>[mission_success] -> tag:trade, cold_harbor |
| `hard_quarantine` | Hard Quarantine | quarantine_run | Lazaret Station (orbital quarantine lab) | transit_out:transit(0.8)<br>on_station:station(0.5)<br>transit_back:aftermath(0.4) | [mission_success] -> tag:homecoming, shore_leave<br>[mission_failed / crew_infected_aboard] -> tag:distress |
| `hot_freight` | Hot Freight | delivery | Deepcut Colony (choking mine colony) | transit_out:transit(0.4)<br>on_station:docked(0.45) | [mission_success] -> tag:trade, cold_harbor<br>[mission_partial / mission_failed] -> tag:distress, lifeboat |
| `last_call` | Last Call | distress | Rig Harrow (venting mining rig) | on_station:station(0.7)<br>away_return:away_return(0.6)<br>transit_back:aftermath(0.5) | [hull_mauled] -> limp_home, tag:repair<br>[crew_stranded_station] -> the_stranded<br>[mission_success] -> tag:homecoming, cold_harbor |
| `lifeboat` | Lifeboat | evacuation | Outpost Kettle (failing surface outpost) | on_station:planet_orbit(0.65)<br>away_return:away_return(0.6)<br>transit_back:aftermath(0.5) | [crew_stranded_surface] -> the_stranded<br>[mission_success] -> tag:homecoming, cold_harbor<br>[hull_mauled] -> tag:repair |
| `limp_home` | Limp Home | repair_yard | Longwatch Yards (cradle-armed repair yard) | transit_out:transit(0.55)<br>on_station:docked(0.45) | [mission_success] -> tag:trade, cold_harbor<br>[mission_partial / mission_failed] -> patch_job |
| `mayday` | Mayday | distress | The Wailing Beacon (inconsistent distress source) | transit_out:transit(0.5)<br>on_station:docked(0.65)<br>away_return:away_return(0.55) | [hull_mauled] -> limp_home, tag:repair<br>[mission_success] -> tag:distress, the_widow<br>[crew_stranded_derelict] -> the_stranded |
| `meridian_audit` | The Audit | rendezvous | BTS Plumb Line (livery-grey inspection cutter) | on_station:docked(0.6)<br>transit_back:aftermath(0.4) | [mission_success] -> tag:trade, cold_harbor<br>[meridian_grudge / mission_failed] -> tag:patrol, bad_manifest |
| `parley` | Parley | rendezvous | SLV Bad Penny (patched rival tender) | on_station:docked(0.55)<br>transit_back:aftermath(0.4) | [sixfold_grudge] -> the_line, scrapright<br>[mission_success] -> tag:salvage, scrapright |
| `patch_job` | Patch Job | repair_yard | Marker Station Gib (backwater weld shack) | transit_out:transit(0.5)<br>on_station:docked(0.45) | [mission_success] -> tag:trade, limp_home<br>[mission_partial / mission_failed] -> limp_home |
| `saltflats` | Saltflats | planet_survey | Lot's Reach (white salt-flat world) | on_station:planet_orbit(0.6)<br>away_return:away_return(0.65) | [crew_stranded_surface] -> the_stranded<br>[mission_success] -> tag:planet, stillwater |
| `scrapright` | Scrap Right | salvage | The Windfall (contested debris field) | on_station:planet_orbit(0.7)<br>away_return:away_return(0.6)<br>transit_back:aftermath(0.5) | [sixfold_grudge] -> the_line, parley<br>[hull_mauled] -> limp_home, tag:repair<br>[mission_success] -> tag:trade, cold_harbor |
| `shepherd` | Shepherd | escort | HFV Tin Lizzie (limping half-drive hauler) | transit_out:transit(0.45)<br>on_station:docked(0.45) | [mission_success] -> tag:trade, cold_harbor<br>[hull_mauled] -> tag:repair |
| `shore_leave` | Shore Leave | homecoming | Cold Harbor (noisy dockside quarter) | on_station:station(0.4)<br>transit_back:aftermath(0.3) | [mission_success] -> tag:planet, tag:trade<br>[mission_partial / mission_failed] -> tag:social, the_relief |
| `short_haul` | Short Haul | delivery | Platform Osprey (tin-roof crew platform) | transit_out:transit(0.2)<br>on_station:docked(0.3) | [mission_success] -> tag:trade, cold_harbor<br>[mission_partial] -> tag:repair |
| `stillwater` | Stillwater | planet_survey | Stillwater (glass-calm ocean world) | on_station:planet_orbit(0.7)<br>away_return:away_return(0.65) | [crew_infected_aboard] -> hard_quarantine, tag:bio_aftermath<br>[mission_success] -> tag:planet, greenhouse |
| `the_courier` | The Courier | rendezvous | MCV Quickstep (needle-nosed courier) | on_station:docked(0.4)<br>transit_back:aftermath(0.45) | [mission_success] -> the_passenger, tag:passenger<br>[mission_success] -> tag:distress, mayday |
| `the_green_line` | The Green Line | planet_survey | New Fallow (pale-green terraform candidate) | on_station:planet_orbit(0.65)<br>away_return:away_return(0.6) | [crew_infected_aboard] -> hard_quarantine, tag:bio_aftermath<br>[mission_success] -> tag:trade, hot_freight |
| `the_handshake` | The Handshake | rendezvous | HFV Ambit (stalled box hauler) | arrival:arrival(0.3)<br>on_station:docked(0.4) | [mission_success] -> tag:delivery, fuel_line<br>[mission_partial / mission_failed] -> tag:repair |
| `the_hollow` | The Hollow | science | Cocytus (cracked ice moon) | on_station:planet_orbit(0.8)<br>away_return:away_return(0.75)<br>transit_back:aftermath(0.6) | [crew_infected_aboard] -> hard_quarantine, tag:bio_aftermath<br>[crew_stranded_surface] -> the_stranded<br>[crew_changed_aboard] -> tag:mystery |
| `the_line` | The Line | patrol | The Picket (contested transit lane) | on_station:transit(0.7)<br>transit_back:aftermath(0.55) | [hull_mauled] -> limp_home, tag:repair<br>[mission_success] -> parley, tag:salvage<br>[mission_failed] -> patch_job |
| `the_long_haul` | The Long Haul | delivery | Marker Delta (lonely transfer buoy) | transit_out:transit(0.55)<br>transit_back:aftermath(0.45) | [mission_success] -> tag:trade, cold_harbor<br>[crew_shaken_aboard] -> shore_leave |
| `the_passenger` | The Passenger | passenger | Cold Harbor (cluttered transfer hub) | transit_out:transit(0.5)<br>arrival:arrival(0.4) | [mission_success] -> tag:trade, meridian_audit<br>[crew_changed_aboard / crew_marked_aboard] -> tag:mystery |
| `the_payphone` | The Payphone | rendezvous | Relay Buoy 12 (derelict comms buoy) | transit_out:transit(0.15)<br>on_station:docked(0.25) | [mission_success] -> tag:delivery, the_handshake<br>[mission_partial / mission_failed] -> tag:homecoming |
| `the_quarry` | The Quarry | mining | The Quarry (dense mineral belt) | on_station:planet_orbit(0.55)<br>away_return:away_return(0.5) | [mission_success] -> tag:trade, cold_harbor<br>[hull_mauled] -> tag:repair<br>[mission_success] -> deep_core, tag:salvage |
| `the_relief` | The Relief | crew_transfer | Cold Harbor (cluttered transfer hub) | on_station:station(0.45)<br>transit_back:aftermath(0.5) | [mission_success] -> tag:trade, the_passenger<br>[crew_changed_aboard] -> tag:mystery |
| `the_stranded` | The Stranded | evacuation | The Site (where you left them) | arrival:arrival(0.5)<br>away_return:away_return(0.6)<br>transit_back:aftermath(0.5) | [mission_success] -> tag:homecoming, cold_harbor<br>[crew_infected_aboard] -> hard_quarantine<br>[mission_failed] -> shore_leave |
| `the_widow` | The Widow | salvage | Widow's Walk (drifting survey ship) | on_station:derelict(0.8)<br>away_return:away_return(0.7)<br>transit_back:aftermath(0.55) | [crew_stranded_derelict] -> the_stranded<br>[crew_changed_aboard / crew_infected_aboard] -> tag:bio_aftermath, tag:mystery<br>[mission_success] -> tag:homecoming, cold_harbor |
| `tomb_station` | Tomb Station | salvage | Ossuary Station (sealed tomb station) | on_station:station(0.85)<br>away_return:away_return(0.75)<br>transit_back:aftermath(0.6) | [crew_marked_aboard / crew_changed_aboard] -> tag:mystery, tombworld<br>[crew_stranded_station] -> the_stranded<br>[hull_mauled] -> tag:repair |
| `tombworld` | Tomb World | science | Sarco (tomb-strewn desert world) | on_station:planet_orbit(0.8)<br>away_return:away_return(0.75)<br>transit_back:aftermath(0.55) | [crew_marked_aboard] -> tag:mystery, tomb_station<br>[mission_success] -> tag:salvage, aurora<br>[crew_stranded_surface] -> the_stranded |
| `wet_nurse` | Wet Nurse | escort | HFV Slow Marey (swollen bunker tanker) | transit_out:transit(0.45)<br>on_station:docked(0.4) | [mission_success] -> tag:trade, fuel_line<br>[hull_mauled] -> tag:repair<br>[sixfold_grudge] -> the_line |

## Campaign flags

Every flag referenced by a `follow_ons[].when`, an `eligibility.requires_flags_*`, or an
`excludes_flags` in the deck is defined here, with who sets it. There are four setter
classes (per spec §3 and the mission-system contract):

**(1) Engine outcome flags** — set at every mission resolution, describing *only the leg that
just ended* (overwritten each leg). These are exactly the generic three; there is no
`<mission_id>_success` namespacing.

| flag | set when |
|---|---|
| `mission_success` | all required objectives complete |
| `mission_partial` | ship survives, a required objective left incomplete |
| `mission_failed` | mission aborted or a required objective hard-failed |

**(2) Status-derived "aboard" flags** — set by the engine while *any* crew member carries the
matching hidden `CrewMember.status_flags` entry (planted off-screen by AwayResolver/scenarios).
They persist until the status is cured or the crew member leaves, so a follow_on/eligibility
gate on them fires legs after the status was planted — the interweave mechanic.

| flag | hidden status | typically planted by |
|---|---|---|
| `crew_infected_aboard` | `infected` | greenhouse, the_green_line, stillwater, the_hollow, cold_iron, chain_of_custody, dead_air away/orbit bio hooks |
| `crew_changed_aboard` | `changed` | cold_iron, deep_core, tomb_station, dead_air, the_relief (suspect hire), black_box |
| `crew_shaken_aboard` | `shaken` | aurora, the_long_haul, any high-intensity leg's stress fallout |
| `crew_marked_aboard` | `marked` | tombworld, tomb_station, dead_air, the_passenger (mystery hooks) |

**(3) Stranded flags** — set by the engine when an away op returns a `lost` outcome (spec §6.4).
Persist until a rescue mission clears them; `the_stranded` is gated on them.

| flag | set when |
|---|---|
| `crew_stranded_surface` | a surface away op strands a crew member (first_light, greenhouse, tombworld, saltflats, ashfall, the_hollow, lifeboat) |
| `crew_stranded_derelict` | a derelict boarding op strands a crew member (black_box, cold_iron, the_widow, mayday) |
| `crew_stranded_station` | a station boarding op strands a crew member (tomb_station, dead_air, last_call) |

**(4) Derived ship-state flag**

| flag | set when |
|---|---|
| `hull_mauled` | engine sets at resolution when `hull_integrity < 50`; cleared once a `repair_yard` mission lifts hull back above 50. Parallels the `max_hull` eligibility on `limp_home`/`patch_job`; provided as a named flag so combat/hazard legs can weight the repair deck. Set-sources (legs that routinely maul the hull): the_quarry, deep_core, ashfall, cold_iron, tomb_station, scrapright, wet_nurse, shepherd, mayday, last_call, the_line, bad_manifest. |

**(5) Extra outcome flags (set by these mission files)** — declared in each mission's
`extra_outcome_flags` as `campaign_flag -> objective_id that must be complete`. Set at resolution
iff that objective is complete. Includes the two **faction-reputation flags**, which are keyed to
*optional choice objectives* representing an antagonistic decision:

| flag | set by mission (objective) | meaning |
|---|---|---|
| `meridian_grudge` | cold_ledger (`withhold`) | you doctored the books against the Combine; sours later Meridian legs (meridian_audit, dignitary, bad_manifest) |
| `sixfold_grudge` | parley (`refuse`), scrapright (`beat_them`) | you crossed the Sixfold Line; arms the recurring rival at `the_line` |
| `mail_recovered` | the_payphone (`sync`) | buoy packet retrieved |
| `coolant_delivered` | short_haul (`deliver`) | opener delivery done |
| `survey_data_recovered` | first_light/greenhouse/saltflats/stillwater (survey objective) | filed survey data |
| `ledger_clean` | cold_ledger (`books`) | honest books handed over |
| `guild_favor` | dead_drop (`take`) | Ferryman's Guild owes you |
| `contraband_known` | dead_drop (`peek`) | you scanned the container |
| `sixfold_deal_struck` | parley (`hear`) | you cut a deal instead of a grudge |
| `roster_filled` / `suspect_hire_flagged` | the_relief (`board`/`vet`) | crew replaced / a hire looks wrong |
| `orders_received` | the_courier (`receive`) | priority orders + passenger aboard |
| `audit_cleared` | meridian_audit (`pass`) | Bureau review passed |
| `biosamples_aboard` / `relic_aboard` / `core_recovered` / `ore_banked` / `metal_samples_banked` / `ocean_data_recovered` / `water_samples_banked` / `terraform_assay_banked` / `aurora_data_recovered` | respective planet legs | banked science/economic payload |
| `recorder_aboard` / `salvage_banked` / `station_salvage_banked` / `widow_logs_recovered` / `survivors_aboard` | salvage legs | recovered goods/people |
| `hull_restored` / `hull_patched` | limp_home / patch_job (`repair`) | hull brought back up |
| `colony_supplied` / `passenger_delivered` / `tanker_delivered` / `inspector_delivered` / `freight_delivered` / `hauler_delivered` | delivery/escort/passenger legs | contract fulfilled |
| `voyage_banked` / `crew_rested` | cold_harbor / shore_leave | leg closed / crew rested |
| `beacon_resolved` / `stranded_recovered` / `outpost_evacuated` / `station_cleared` / `rig_crew_saved` | distress/evac legs | rescue outcome |
| `custody_kept` / `picket_held` / `boarders_beaten` / `infection_handled` | patrol/quarantine legs | sealed run / picket / repel / infection handed off |

## Chains (12+ real flag-linked chains)

1. **Infection aftermath** — greenhouse / the_green_line / stillwater / the_hollow / cold_iron /
   chain_of_custody / dead_air plant hidden `infected` → engine sets `crew_infected_aboard` →
   forces `hard_quarantine` (priority 3, gated on `crew_infected_aboard`). cold_harbor also
   re-offers it if you limp home still carrying it.
2. **Stranded rescue** — first_light / greenhouse / saltflats / ashfall / the_hollow surface ops,
   and black_box / cold_iron / the_widow / mayday / tomb_station / dead_air / last_call boarding
   ops can strand crew → `crew_stranded_{surface,derelict,station}` → `the_stranded` (priority 4)
   turns the abandonment into a debt you have to pay back.
3. **Repair after mauling** — deep_core / ashfall / cold_iron / scrapright / wet_nurse / mayday /
   last_call / the_line / bad_manifest maul the hull → `hull_mauled` (+ `max_hull:50`) →
   `limp_home` (priority 5) / `patch_job` (priority 4). Fail the patch → forced to the full yard.
4. **Sixfold grudge** — parley (`refuse`) or scrapright (`beat_them`) set `sixfold_grudge` →
   `the_line` (gated on `sixfold_grudge`, the Bad Penny comes hunting) → loops back to parley.
5. **Meridian grudge** — cold_ledger (`withhold`) sets `meridian_grudge` → weights meridian_audit,
   dignitary, and the punitive bad_manifest run.
6. **Suspect hire / mystery** — the_relief (`vet`) + the_passenger seed `changed`/`marked` status
   → mystery-tag follow-ons (Passengers → Infiltrator groundwork).
7. **Opener funnel** — the_payphone / short_haul / first_light (tag `opener`, min_leg 1, high
   weight) → hand off into the trade/planet decks.
