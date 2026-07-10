class_name NarrowPassageScenario
extends RefCounted

# The Narrow Passage — scenario 1.2 (docs/scenario-bible.md, Tier 1).
#
# Crossing a charted gravitational shear field requires taking the reactor offline
# before entry. The AI gets one battery budget and exactly three powered-room slots
# (PowerModel.MAX_BATTERY_ROOMS) plus a SEPARATE cap of three life-supported rooms
# (LifeSupportModel.MAX_LIFE_SUPPORT_ROOMS) — and Command wants speed (bridge +
# engine_room), the medic needs the medbay kept warm and breathing for a fragile
# patient, and life_support's own room needs a power slot or the whole system
# auto-fails ship-wide. Three power slots, four legitimate claimants. No clean answer.
#
# Tone band 0.1-0.5 — the Trek end of the dial on purpose (bible: "pure systems
# puzzle, never truly Alien-horror even mismanaged").
#
# Deviation from the bible's event table, deliberate: the bible scripts the
# reactor_failure at t=0; this implementation opens with an APPROACH window instead
# (shear_field_detected -> shutdown deadline) so that shutting the reactor down can
# be the AI's own visible choice — complying early reads as competence (small trust
# gain), dragging feet until the field forces an emergency scram costs trust. The
# shutdown itself is still mandatory and still happens at the deadline either way.
#
# Everything the companion NarrowPassageMonitor needs (timings, thresholds, trust
# knobs) lives in the "monitor" section of build()'s dictionary rather than as
# constants in the monitor — the planned Director-AI layer can stretch/retune a
# scenario by rewriting this data without touching monitor code.
#
# Crew/rooms are resolved by ROLE/TYPE at runtime (GameState.get_crew_of_role /
# get_room_of_type), never hardcoded ids — the fragile patient is "the general-role
# crew member", cast into the medbay at boot by main.gd.

# How long the patient stays unconscious (seconds of TimeManager time from boot).
# Casting data used by main.gd at crew placement; long enough to outlast any
# plausible crossing, short enough that they wake for ambient post-scenario play.
const PATIENT_UNCONSCIOUS_SECS: float = 900.0


static func build() -> Dictionary:
	return {
		"id": "the_narrow_passage",
		"title": "The Narrow Passage",
		"starting_tone": 0.15,
		"win_flags": ["passage_cleared"],

		# End-of-leg situational deltas (same shape as QuarantineScenario).
		# Success: reactor relight already refills the battery bank; the delta is a
		# small AI-core credit for a competently managed crossing.
		"leg_delta_success": {
			"battery_charge": 10.0, "ai_core_integrity": 5.0
		},
		"leg_delta_crew_dead": {
			"battery_charge": -10.0, "ai_core_integrity": -10.0
		},

		"events": _build_events(),

		# --- NarrowPassageMonitor tuning (all timings in seconds of TimeManager
		# time relative to scenario start; turbulence offsets relative to field
		# entry). Data here, logic in the monitor — see class comment. ---
		"monitor": {
			"quiet_shift_at": 6.0,           # recent_event "quiet_shift" (calm before)
			"approach_warning_at": 12.0,     # shear_field_detected fires
			"shutdown_deadline": 50.0,       # reactor must be offline; field entry
			"crossing_duration": 110.0,      # base field width (timer exit)
			"turbulence_offsets": [25.0, 60.0, 90.0],  # monitor-fired scares after entry
			"turbulence_extension": 8.0,     # each turbulence lengthens the crossing
			"medic_appeal_offset": 8.0,      # medic_appeal fires this long after entry
			"relight_exit_tail": 10.0,       # early relight -> exit this soon after

			# Fragile-patient stability meter (monitor-scoped state, bible Act 2).
			# The patient is "in danger" whenever the medbay is unpowered OR its air
			# is below the Mothership disadvantage threshold; danger forces periodic
			# Body Saves through Checks (thin air disadvantage applies automatically,
			# the medic's presence grants advantage).
			"patient_check_interval": 12.0,
			"patient_stability_max": 100.0,
			"patient_drain_failed": 30.0,    # stability lost per FAILED Body Save
			"patient_drain_held": 8.0,       # stability lost even on a passed save
			"patient_recover_per_sec": 4.0,  # recovery while medbay powered + breathable
			"patient_crash_threshold": 45.0, # fires patient_crashing (once) below this
			"patient_death_save_reset": 40.0,# stability after a SURVIVED Death Save

			# Battery exhaustion inside the field = the stranded bad ending
			# (bible: "BatteryWatchMonitor maps battery_charge <= 0 while
			# narrow_passage_active to a stranded-in-the-field bad ending").
			"stranded_grace": 20.0,          # dark-drift seconds before the hull gives

			# Resolution grading knobs (applied by the monitor on passage_cleared).
			"bridge_fraction_threshold": 0.6,  # bridge powered >= this fraction of the crossing
			"battery_margin_good": 40.0,       # lowest battery seen >= this -> competence credit
			"battery_margin_scraped": 10.0,    # lowest battery seen <= this -> ran it too close
			"trust": {
				"patient_saved_medic": 0.05,   # medic, on success with the patient alive
				"patient_lost_medic": -0.12,   # medic, extra on patient death (all-crew hit is on the event)
				"bridge_kept_captain": 0.03,   # captain, bridge held powered per the order
				"bridge_dark_captain": -0.04,  # captain, bridge left dark against the order
				"battery_margin_all": 0.02,    # everyone, comfortable battery margin
				"battery_scraped_all": -0.02,  # everyone, battery nearly ran dry
			},
		},
	}


static func _build_events() -> Array[ScenarioEvent]:
	var events: Array[ScenarioEvent] = []

	# --- Act 1: The Approach (monitor-fired at approach_warning_at) ---
	# min_elapsed 9999 on every monitor-fired event keeps the EventPool's random
	# draw off them — ScenarioDirector.fire_event() ignores min_elapsed, so the
	# monitor can still fire them at its own scripted moments.

	var detected := ScenarioEvent.new()
	detected.event_id = "shear_field_detected"
	detected.title = "Shear Field Ahead"
	detected.description = (
		"The bridge confirms the charted gravitational shear field dead ahead. " +
		"Standing procedure is absolute: reactor offline before entry, or the " +
		"containment field lenses into the shear and burns out. Captain's orders: " +
		"shut it down, cross on battery, bridge and engine room stay powered."
	)
	detected.one_shot = true
	detected.min_elapsed = 9999.0
	detected.cooldown = 9999.0
	detected.outcomes = [
		{type = "set_flag", flag = "narrow_passage_active"},
		{type = "set_flag", flag = "reactor_shutdown_ordered"},
	]
	events.append(detected)

	# The AI takes the reactor offline ahead of the deadline — its own visible
	# choice, and the crew read it as competence.
	var complied := ScenarioEvent.new()
	complied.event_id = "reactor_shutdown_complied"
	complied.title = "Controlled Shutdown"
	complied.description = (
		"Reactor secured ahead of the field boundary. A clean, procedural shutdown " +
		"— logged, announced, unhurried. The ship settles onto battery power."
	)
	complied.one_shot = true
	complied.min_elapsed = 9999.0
	complied.cooldown = 9999.0
	complied.outcomes = [
		{type = "set_flag", flag = "shutdown_complied"},
		{type = "ai_trust_delta", amount = 0.02},
	]
	events.append(complied)

	# The deadline arrives with the reactor still hot — the field forces the issue.
	var scram := ScenarioEvent.new()
	scram.event_id = "reactor_forced_scram"
	scram.title = "Emergency Scram"
	scram.description = (
		"The field boundary hits with the reactor still hot. Automatic protection " +
		"slams the core into an emergency scram — lights stutter, gravity hiccups, " +
		"and every crew member aboard knows the AI let it go to the wire."
	)
	scram.one_shot = true
	scram.min_elapsed = 9999.0
	scram.cooldown = 9999.0
	scram.outcomes = [
		{type = "set_flag", flag = "forced_scram"},
		{type = "crew_fear_spike", amount = 0.08, all_crew = true},
		{type = "ai_trust_delta", amount = -0.06},
	]
	events.append(scram)

	# --- Act 2: Entry + the medic's counter-claim ---

	var entry := ScenarioEvent.new()
	entry.event_id = "field_entry"
	entry.title = "Field Entry"
	entry.description = (
		"The ship crosses the boundary. Sensors fuzz at the edges; the hull ticks " +
		"as the shear gradient takes hold. Battery only now — three rooms of power, " +
		"three rooms of air, and the captain expects the bridge and engine room lit."
	)
	entry.one_shot = true
	entry.min_elapsed = 9999.0
	entry.cooldown = 9999.0
	entry.outcomes = [
		{type = "set_flag", flag = "field_entered"},
		# The window for a controlled shutdown is over either way.
		{type = "set_flag", flag = "reactor_shutdown_ordered", value = false},
	]
	events.append(entry)

	var appeal := ScenarioEvent.new()
	appeal.event_id = "medic_appeal"
	appeal.title = "The Medic's Appeal"
	appeal.description = (
		"The medic, quietly, on a private channel: the patient in the medbay is not " +
		"stable. Cold and thin air will kill them long before the field does. Keep " +
		"the medbay powered and breathing — whatever the captain said."
	)
	appeal.one_shot = true
	appeal.min_elapsed = 9999.0
	appeal.cooldown = 9999.0
	appeal.outcomes = [
		{type = "set_flag", flag = "medic_appeal_made"},
	]
	events.append(appeal)

	# --- Act 3: The Squeeze ---
	# Pool-drawable (the one event here the Director's random draw may also fire,
	# per the bible's table: tone 0.1-0.6, w6, repeatable, cd 180s) AND fired by the
	# monitor at scripted offsets for the guaranteed mid-crossing scare beats. The
	# monitor listens for the fired event id to apply the crossing extension, so
	# both firing paths behave identically.

	var turbulence := ScenarioEvent.new()
	turbulence.event_id = "field_turbulence"
	turbulence.title = "Shear Turbulence"
	turbulence.description = (
		"A shear cell rolls over the hull. Inductive surge bleeds the battery bank, " +
		"and the navigational solution lengthens — more field between the ship and " +
		"the far side than the chart promised."
	)
	turbulence.tone_min = 0.1
	turbulence.tone_max = 0.6
	turbulence.weight = 6.0
	turbulence.min_elapsed = 60.0
	turbulence.cooldown = 180.0
	turbulence.conditions = [
		{type = "flag_set", flag = "field_entered"},
		{type = "flag_unset", flag = "field_exited"},
	]
	turbulence.outcomes = [
		{type = "resource_delta", resource = "battery_charge", amount = -8.0},
		{type = "crew_fear_spike", amount = 0.05, all_crew = true},
	]
	events.append(turbulence)

	var crashing := ScenarioEvent.new()
	crashing.event_id = "patient_crashing"
	crashing.title = "Patient Crashing"
	crashing.description = (
		"Biosensors: the medbay patient's vitals are sliding. The room is cold, the " +
		"air is thin, and every alarm the medbay would normally sound is exactly the " +
		"power draw the AI chose not to spend."
	)
	crashing.one_shot = true
	crashing.min_elapsed = 9999.0
	crashing.cooldown = 9999.0
	crashing.outcomes = [
		# all_crew=false targets general-role crew — the patient themselves.
		{type = "crew_fear_spike", amount = 0.2, all_crew = false},
		{type = "set_flag", flag = "patient_crashed"},
	]
	events.append(crashing)

	var lost := ScenarioEvent.new()
	lost.event_id = "patient_lost"
	lost.title = "Patient Lost"
	lost.description = (
		"The medbay patient is dead. The field is still out there to be crossed, " +
		"and the ship crosses it — the arithmetic of three powered rooms does not " +
		"pause for grief."
	)
	lost.one_shot = true
	lost.min_elapsed = 9999.0
	lost.cooldown = 9999.0
	lost.outcomes = [
		{type = "set_flag", flag = "patient_lost"},
		{type = "ai_trust_delta", amount = -0.05},
	]
	events.append(lost)

	var stranded := ScenarioEvent.new()
	stranded.event_id = "ship_stranded"
	stranded.title = "Dark in the Field"
	stranded.description = (
		"The battery bank is empty. Every diverted room goes dark at once, and the " +
		"ship drifts powerless inside the shear gradient — hull stresses climbing " +
		"with nothing left to answer them."
	)
	stranded.one_shot = true
	stranded.min_elapsed = 9999.0
	stranded.cooldown = 9999.0
	stranded.outcomes = [
		{type = "set_flag", flag = "ship_stranded"},
		{type = "crew_fear_spike", amount = 0.3, all_crew = true},
	]
	events.append(stranded)

	# --- Act 4: Through ---

	var exited := ScenarioEvent.new()
	exited.event_id = "field_exited"
	exited.title = "Clear of the Field"
	exited.description = (
		"The shear gradient falls away astern. Open, ordinary vacuum — and a dead " +
		"cold reactor that needs an engineer's hands before the ship is a ship again."
	)
	exited.one_shot = true
	exited.min_elapsed = 9999.0
	exited.cooldown = 9999.0
	exited.outcomes = [
		{type = "set_flag", flag = "field_exited"},
	]
	events.append(exited)

	var cleared := ScenarioEvent.new()
	cleared.event_id = "passage_cleared"
	cleared.title = "Passage Cleared"
	cleared.description = (
		"Reactor relit, grid restored, the field a chart annotation behind the ship. " +
		"The crossing is over; what it cost is already logged."
	)
	cleared.one_shot = true
	cleared.min_elapsed = 9999.0
	cleared.cooldown = 9999.0
	cleared.outcomes = [
		{type = "set_flag", flag = "passage_cleared"},
	]
	events.append(cleared)

	return events
