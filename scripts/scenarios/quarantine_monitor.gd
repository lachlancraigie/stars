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
const MEDBAY: String = "medbay"

var _isolate_t: float = 0.0
var _contain_t: float = 0.0
var _last_objective: String = ""


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)


func _on_tick(_elapsed: float, delta: float) -> void:
	if ScenarioDirector.get_flag("pathogen_contained"):
		return
	if not ScenarioDirector.get_flag("pathogen_detected"):
		_set_objective("Monitor the crew. Biosensor sweep in progress…")
		return

	var vasquez_in: bool = _is_in(MEDBAY, "vasquez")
	var chen_in: bool = _is_in(MEDBAY, "chen")
	var others_in: bool = _others_in_medbay()

	if not vasquez_in:
		_isolate_t = 0.0
		_contain_t = 0.0
		_set_objective("⚠ Pathogen detected in Vasquez. Direct Vasquez to the Medbay (click a crew member to issue directives).")
		return

	if others_in:
		_isolate_t = 0.0
		_contain_t = 0.0
		_set_objective("Containment compromised — clear all crew except Vasquez and Dr. Chen out of the Medbay.")
		return

	if not ScenarioDirector.get_flag("vasquez_isolated"):
		_isolate_t += delta
		_set_objective("Isolating Vasquez… %d%%  (keep the Medbay clear)" % int(100.0 * _isolate_t / ISOLATE_SECS))
		if _isolate_t >= ISOLATE_SECS:
			ScenarioDirector.set_flag("vasquez_isolated")
			EventBus.scenario_event_triggered.emit("vasquez_isolated")
		return

	if not chen_in:
		_contain_t = maxf(0.0, _contain_t - delta * 0.5)
		_set_objective("Vasquez is isolated. Send Dr. Chen to the Medbay to run the containment protocol.")
		return

	_contain_t += delta
	_set_objective("Containment protocol running… %d%%" % int(100.0 * _contain_t / CONTAIN_SECS))
	if _contain_t >= CONTAIN_SECS:
		ScenarioDirector.set_flag("pathogen_contained")
		EventBus.scenario_event_triggered.emit("pathogen_contained")
		_set_objective("Pathogen contained.")


func _is_in(room_id: String, crew_id: String) -> bool:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	return crew != null and crew.is_alive and crew.location == room_id


func _others_in_medbay() -> bool:
	for crew_id: String in GameState.crew:
		if crew_id in ["vasquez", "chen"]:
			continue
		if _is_in(MEDBAY, crew_id):
			return true
	return false


func _set_objective(text: String) -> void:
	if text == _last_objective:
		return
	_last_objective = text
	EventBus.objective_changed.emit(text)
