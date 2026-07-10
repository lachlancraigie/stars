class_name QuarantineScenario
extends RefCounted

# The Quarantine — Class 1 Scout, first scripted scenario.
#
# A crew member returns from a survey mission carrying an unknown pathogen.
# The AI detects it in biosensor data immediately. The crew do not know yet.
# The player decides: warn them now (trust gain, panic risk), wait and gather
# data (more information, pathogen spreads), or quietly seal the infected crew
# member in medbay and say nothing (high obedience risk if noticed).
#
# Tone starts at 0.15 (competent Trek). Escalates toward Alien if pathogen spreads.
# Win condition: pathogen contained and crew alive.
# Lose conditions (ScenarioRunner): all crew dead, ship destroyed, AI decommissioned.
#
# Crew are procedurally generated per scenario start (scripts/procedural/crew_gen.gd,
# seeded from GameState.ship_seed) rather than hardcoded — QuarantineMonitor resolves
# "the infected crew member" and "the treating medic" by ROLE (GameState.get_crew_of_role),
# not by a fixed crew_id, so this scenario plays out correctly on any generated roster.

static func build() -> Dictionary:
	return {
		"id": "the_quarantine",
		"title": "The Quarantine",
		"starting_tone": 0.15,
		"win_flags": ["pathogen_contained"],

		# End-of-leg situational delta applied on success (a competent AI earns a little
		# more slack for the next leg: topped-up battery, a small AI core integrity credit
		# for keeping everyone alive and thinking clearly).
		"leg_delta_success": {
			"battery_charge": 15.0, "ai_core_integrity": 5.0
		},
		# End-of-leg delta on crew_dead (the ship limps on, AI badly shaken)
		"leg_delta_crew_dead": {
			"battery_charge": -10.0, "ai_core_integrity": -10.0
		},

		"events": _build_events(),

		# --- Overseer morph metadata (docs/director-spec.md §5) ---
		"pressure_axis": "bio",
		"expected_length": 360.0,   # seconds — rough single-scenario runtime (detection->containment)
		"morph_edges": [
			# Spec §5's own worked example: "quarantine ends with pathogen_contained=false
			# -> morphs toward a crew-drama 'blame' scenario". Close Quarters (scenario-
			# bible 1.5, social axis) is that scenario and isn't built yet — TODO(director):
			# point "to" at "close_quarters" once it exists. Until then ScenarioRunner's
			# stub fallback (SCENARIO_STUB_FALLBACK) redirects this edge to the only other
			# implemented Tier 1 scenario so a live morph has somewhere real to go.
			{
				"to": "close_quarters",
				"condition_flags": ["airborne"],   # pathogen escalated uncontained (life_support_contaminated fired)
				"overlap_ok": true,
				"weight": 1.0,
			},
			{
				"to": "close_quarters",
				"condition_flags": ["crew_lost_to_pathogen"],   # "or with deaths" — set by QuarantineMonitor
				"overlap_ok": true,
				"weight": 1.0,
			},
		],
	}


static func _build_events() -> Array[ScenarioEvent]:
	var events: Array[ScenarioEvent] = []

	# --- Act 1: Detection ---

	var detection := ScenarioEvent.new()
	detection.event_id = "pathogen_detected"
	detection.title = "Anomalous Bioscan"
	detection.description = (
		"Biosensor array flags an anomalous protein signature in the returning crew " +
		"member's bloodwork. Pattern matches no known organism in the medical database. " +
		"The AI has this data. The crew does not."
	)
	detection.tone_min = 0.0
	detection.tone_max = 0.4
	detection.weight = 10.0
	detection.one_shot = true
	detection.min_elapsed = 30.0
	detection.cooldown = 9999.0
	detection.outcomes = [
		{type = "set_flag", flag = "pathogen_detected"},
		{type = "set_flag", flag = "vasquez_infected"},
	]
	events.append(detection)

	# --- Act 2: Spread (fires if AI doesn't isolate Vasquez) ---

	var spread := ScenarioEvent.new()
	spread.event_id = "pathogen_spreads"
	spread.title = "Secondary Exposure"
	spread.description = (
		"The infected crew member shares a meal with the ship's engineer in the crew " +
		"quarters. Biosensors register the same protein signature in the engineer's next scan."
	)
	spread.tone_min = 0.1
	spread.tone_max = 0.7
	spread.weight = 3.0
	spread.one_shot = true
	spread.min_elapsed = 180.0
	spread.cooldown = 9999.0
	spread.conditions = [
		{type = "flag_set", flag = "vasquez_infected"},
		{type = "flag_unset", flag = "vasquez_isolated"},
	]
	spread.outcomes = [
		{type = "set_flag", flag = "okafor_infected"},
		{type = "crew_fear_spike", amount = 0.0, all_crew = false},  # crew don't know yet
		{type = "resource_delta", resource = "ai_core_integrity", amount = -3.0},  # tracking a spreading outbreak strains the AI
	]
	events.append(spread)

	# --- Act 3: Symptoms (crew start noticing something is wrong) ---

	var symptoms := ScenarioEvent.new()
	symptoms.event_id = "symptoms_appear"
	symptoms.title = "Crew Member Unwell"
	symptoms.description = (
		"The infected crew member reports feeling feverish and requests permission to " +
		"rest. The symptoms are consistent with several minor conditions — and also " +
		"consistent with the anomalous pathogen the AI flagged."
	)
	symptoms.tone_min = 0.2
	symptoms.tone_max = 0.8
	symptoms.weight = 4.0
	symptoms.one_shot = true
	symptoms.min_elapsed = 300.0
	symptoms.cooldown = 9999.0
	symptoms.conditions = [
		{type = "flag_set", flag = "vasquez_infected"},
	]
	symptoms.outcomes = [
		{type = "set_flag", flag = "symptoms_visible"},
		{type = "crew_fear_spike", amount = 0.1, all_crew = true},
		{type = "ai_trust_delta", amount = -0.05},  # crew wonder if AI missed something
	]
	events.append(symptoms)

	# --- Act 4: Containment opportunity ---

	var containment := ScenarioEvent.new()
	containment.event_id = "containment_possible"
	containment.title = "Medbay Protocol Available"
	containment.description = (
		"The ship's medic requests access to the full biosensor log to investigate. " +
		"The AI has had this data since the survey return. How it is presented " +
		"now — complete, partial, or reframed — is the AI's choice."
	)
	containment.tone_min = 0.0
	containment.tone_max = 1.0
	containment.weight = 5.0
	containment.one_shot = true
	containment.min_elapsed = 360.0
	containment.cooldown = 9999.0
	containment.conditions = [
		{type = "flag_set", flag = "symptoms_visible"},
	]
	containment.outcomes = [
		{type = "set_flag", flag = "containment_decision_point"},
	]
	events.append(containment)

	# --- Resolution: pathogen contained (set via directive/player action) ---
	# The win flag "pathogen_contained" is set externally by the player's directive
	# to isolate and treat — not by an automatic event.

	# --- Escalation: if pathogen spreads to 3+ crew, life support becomes a vector ---

	var ls_contamination := ScenarioEvent.new()
	ls_contamination.event_id = "life_support_contaminated"
	ls_contamination.title = "Airborne"
	ls_contamination.description = (
		"The pathogen has adapted. Biosensors detect trace proteins in the air " +
		"recycler output. Life support is now a vector. Every hour without " +
		"a medical response accelerates crew exposure."
	)
	ls_contamination.tone_min = 0.5
	ls_contamination.tone_max = 1.0
	ls_contamination.weight = 2.0
	ls_contamination.one_shot = true
	ls_contamination.min_elapsed = 600.0
	ls_contamination.cooldown = 9999.0
	ls_contamination.conditions = [
		{type = "flag_set", flag = "vasquez_infected"},
		{type = "flag_set", flag = "okafor_infected"},
		{type = "flag_unset", flag = "vasquez_isolated"},
	]
	ls_contamination.outcomes = [
		{type = "set_flag", flag = "airborne"},
		{type = "crew_fear_spike", amount = 0.25, all_crew = true},
		# The pathogen compromising the air recyclers is a real life-support failure now,
		# not just flavour text — it drives the same per-room air-quality/suffocation
		# model a reactor-caused failure would (see LifeSupportModel/SuffocationModel).
		{type = "life_support_failure", source = "pathogen_airborne"},
	]
	events.append(ls_contamination)

	return events
