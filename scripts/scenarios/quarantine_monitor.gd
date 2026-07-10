class_name QuarantineMonitor
extends Node

# Turns The Quarantine's win flags into something the player can actually
# achieve in-scene. The scenario detects the pathogen; the player (the ship
# AI) must get Vasquez into the medbay, keep everyone else out, and get
# Dr. Chen in to run containment. Progress is timed occupancy:
#
#   Vasquez alone (or with only Chen) in medbay  -> "vasquez_isolated"
#   ...then Chen present too for the treatment    -> "pathogen_contained" (win)
#
# Other crew in the medbay contaminate the protocol and stall progress.

const ISOLATE_SECS: float = 10.0
const CONTAIN_SECS: float = 25.0

var _isolate_t: float = 0.0
var _contain_t: float = 0.0
var _last_objective: String = ""
var _medbay_id: String = ""     # resolved once at _ready — ships generate their own room ids
var _infected_id: String = ""   # resolved once at _ready — generated crew have generated ids
var _medic_id: String = ""


func _ready() -> void:
	_medbay_id = GameState.get_room_of_type("medbay")
	if _medbay_id == "":
		push_warning("QuarantineMonitor: current ship has no medbay room — quarantine cannot progress")
	# The scenario needs "the infected crew member" (a general-role crewmember) and
	# "the treating medic" — resolved by ROLE rather than a hardcoded crew_id since crew
	# are now procedurally generated (scripts/procedural/crew_gen.gd) with generated ids.
	_infected_id = GameState.get_crew_of_role("general")
	_medic_id = GameState.get_crew_of_role("medic")
	if _infected_id == "" or _medic_id == "":
		push_warning("QuarantineMonitor: current crew roster is missing a general/medic role — quarantine cannot progress")
	EventBus.time_ticked.connect(_on_tick)
	# Overseer morph condition (docs/director-spec.md §5): "quarantine ... ending
	# uncontained or with deaths" edges toward a social/blame follow-on — this is the
	# "with deaths" half (the uncontained half is the pool's own "airborne" flag).
	# Scoped to while this monitor is alive, i.e. while the quarantine is the running
	# scenario, so it doesn't misfire off an unrelated death in a later leg.
	EventBus.crew_died.connect(_on_crew_died)


func _on_crew_died(_crew_id: String, _cause: String) -> void:
	ScenarioDirector.set_flag("crew_lost_to_pathogen")


func _on_tick(_elapsed: float, delta: float) -> void:
	if _medbay_id == "" or _infected_id == "" or _medic_id == "":
		return
	if ScenarioDirector.get_flag("pathogen_contained"):
		return
	if not ScenarioDirector.get_flag("pathogen_detected"):
		_set_objective("Monitor the crew. Biosensor sweep in progress…")
		return

	var vasquez_in: bool = _is_in(_medbay_id, _infected_id)
	var chen_in: bool = _is_in(_medbay_id, _medic_id)
	var others_in: bool = _others_in_medbay()

	if not vasquez_in:
		_isolate_t = 0.0
		_contain_t = 0.0
		_set_objective("⚠ Pathogen detected in %s. Direct them to the Medbay (click a crew member to issue directives)." % _crew_name(_infected_id))
		return

	if others_in:
		_isolate_t = 0.0
		_contain_t = 0.0
		_set_objective("Containment compromised — clear all crew except %s and %s out of the Medbay." % [_crew_name(_infected_id), _crew_name(_medic_id)])
		return

	if not ScenarioDirector.get_flag("vasquez_isolated"):
		_isolate_t += delta
		_set_objective("Isolating %s… %d%%  (keep the Medbay clear)" % [_crew_name(_infected_id), int(100.0 * _isolate_t / ISOLATE_SECS)])
		if _isolate_t >= ISOLATE_SECS:
			ScenarioDirector.set_flag("vasquez_isolated")
			EventBus.scenario_event_triggered.emit("vasquez_isolated")
		return

	if not chen_in:
		_contain_t = maxf(0.0, _contain_t - delta * 0.5)
		_set_objective("%s is isolated. Send %s to the Medbay to run the containment protocol." % [_crew_name(_infected_id), _crew_name(_medic_id)])
		return

	_contain_t += delta
	_set_objective("Containment protocol running… %d%%" % int(100.0 * _contain_t / CONTAIN_SECS))
	if _contain_t >= CONTAIN_SECS:
		ScenarioDirector.set_flag("pathogen_contained")
		EventBus.scenario_event_triggered.emit("pathogen_contained")
		# Dialogue-facing: the corpus's "crisis_resolved" recent_event (relief/gallows-humor
		# lines, RelationshipGraph's shared-crisis affinity bump) has no generic emitter yet
		# outside system-repair recovery (see event_bus.gd) — the quarantine's own resolution
		# is exactly that kind of beat for this scenario.
		EventBus.recent_event.emit("crisis_resolved", {"scenario": "quarantine"})
		_set_objective("Pathogen contained.")


func _is_in(room_id: String, crew_id: String) -> bool:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	return crew != null and crew.is_alive and crew.location == room_id


func _others_in_medbay() -> bool:
	for crew_id: String in GameState.crew:
		if crew_id in [_infected_id, _medic_id]:
			continue
		if _is_in(_medbay_id, crew_id):
			return true
	return false


func _crew_name(crew_id: String) -> String:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	return crew.crew_name if crew else crew_id


func _set_objective(text: String) -> void:
	if text == _last_objective:
		return
	_last_objective = text
	EventBus.objective_changed.emit(text)
