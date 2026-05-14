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
# Lose conditions: all crew dead, ship life support fails, AI decommissioned.

static func build() -> Dictionary:
	return {
		"id": "the_quarantine",
		"title": "The Quarantine",
		"starting_tone": 0.15,
		"win_flags": ["pathogen_contained"],

		# Resource delta applied on success (light resupply at next waypoint)
		"resource_delta_success": {
			"food": 0.1, "medicine": 0.15, "spare_parts": 0.05
		},
		# Resource delta on crew_dead (the ship limps on, badly depleted)
		"resource_delta_crew_dead": {
			"food": -0.2, "medicine": -0.3, "oxygen": -0.1
		},

		"events": _build_events(),
	}


static func _build_events() -> Array[ScenarioEvent]:
	var events: Array[ScenarioEvent] = []

	# --- Act 1: Detection ---

	var detection := ScenarioEvent.new()
	detection.event_id = "pathogen_detected"
	detection.title = "Anomalous Bioscan"
	detection.description = (
		"Biosensor array flags an anomalous protein signature in crew member Vasquez's "
		"bloodwork. Pattern matches no known organism in the medical database. The AI "
		"has this data. The crew does not."
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
		"Vasquez shares a meal with Engineer Okafor in the crew quarters. "
		"Biosensors register the same protein signature in Okafor's next scan."
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
		{type = "resource_delta", resource = "medicine", amount = -0.05},
	]
	events.append(spread)

	# --- Act 3: Symptoms (crew start noticing something is wrong) ---

	var symptoms := ScenarioEvent.new()
	symptoms.event_id = "symptoms_appear"
	symptoms.title = "Crew Member Unwell"
	symptoms.description = (
		"Vasquez reports feeling feverish and requests permission to rest. "
		"The symptoms are consistent with several minor conditions — and also "
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
		"Dr. Chen requests access to the full biosensor log to investigate. "
		"The AI has had this data since the survey return. How it is presented "
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
		"The pathogen has adapted. Biosensors detect trace proteins in the air "
		"recycler output. Life support is now a vector. Every hour without "
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
		{type = "resource_delta", resource = "medicine", amount = -0.15},
	]
	events.append(ls_contamination)

	return events
