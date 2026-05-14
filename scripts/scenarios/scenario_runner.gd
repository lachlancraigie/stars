extends Node

# Orchestrates a running scenario: loads config, checks win/lose conditions,
# applies end-of-scenario resource deltas, and hands off to the next scenario.

var _config: Dictionary = {}    # scenario definition (id, events, win/lose, resource_delta)
var _active: bool = false


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.crew_died.connect(_on_crew_died)
	EventBus.ai_decommission_attempted.connect(_on_decommission_attempted)


func start_scenario(config: Dictionary) -> void:
	_config = config
	_active = true
	GameState.scenario_id = config.get("id", "unknown")
	GameState.scenario_tone = config.get("starting_tone", 0.2)
	ScenarioDirector.start_scenario(config.get("events", []))
	EventBus.scenario_event_triggered.emit("scenario_started")


func _on_tick(_elapsed: float, _delta: float) -> void:
	if not _active:
		return
	_check_lose_conditions()
	_check_win_conditions()


func _check_lose_conditions() -> void:
	# Lose if AI is decommissioned (handled via signal)
	# Lose if ship destroyed
	if GameState.get_resource("oxygen") <= 0.0:
		_end_scenario("crew_dead", "oxygen_depleted")
		return
	# Lose if all crew are dead
	var any_alive: bool = false
	for crew_id in GameState.crew:
		if (GameState.crew[crew_id] as CrewMember).is_alive:
			any_alive = true
			break
	if not any_alive:
		_end_scenario("crew_dead", "all_crew_dead")


func _check_win_conditions() -> void:
	var win_flags: Array = _config.get("win_flags", [])
	if win_flags.is_empty():
		return
	for flag in win_flags:
		if not ScenarioDirector.get_flag(flag):
			return
	_end_scenario("success", "all_win_conditions_met")


func _on_crew_died(_crew_id: String, _cause: String) -> void:
	# Win/lose re-check happens next tick — avoids checking mid-cascade


func _on_decommission_attempted(_initiator: String) -> void:
	if not _active:
		return
	# Whether decommission succeeds depends on trust levels
	var avg_trust: float = _average_trust()
	if avg_trust < 0.3:
		_end_scenario("ai_decommissioned", "crew_voted_shutdown")


func _end_scenario(outcome: String, reason: String) -> void:
	if not _active:
		return
	_active = false
	# Apply end-of-scenario resource delta (rewards/penalties for the next leg)
	var delta: Dictionary = _config.get("resource_delta_%s" % outcome, {})
	for resource_name in delta:
		GameState.set_resource(resource_name,
			GameState.get_resource(resource_name) + delta[resource_name])
	EventBus.scenario_ended.emit(outcome)
	push_warning("ScenarioRunner: scenario ended — outcome=%s reason=%s" % [outcome, reason])
	# TODO(campaign): hand off to CampaignManager for next scenario load


func _average_trust() -> float:
	if GameState.ai_trust_scores.is_empty():
		return 0.5
	var total: float = 0.0
	for crew_id in GameState.ai_trust_scores:
		total += GameState.ai_trust_scores[crew_id]
	return total / GameState.ai_trust_scores.size()
