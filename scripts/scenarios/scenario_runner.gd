extends Node

# Orchestrates a running scenario: loads config, checks win/lose conditions,
# applies end-of-scenario situational deltas, and hands off to the next scenario.
#
# Lose conditions (all three permadeath paths from CLAUDE.md's design decision):
#   - all crew dead
#   - ship destroyed (GameState.ship_destroyed — stub hook, no in-game content sets it yet)
#   - AI decommissioned, via either of two paths:
#       1. crew vote to shut it down outright (ai_decommission_attempted, low trust)
#       2. the AI core sits in blackout with no crew willing/able to repair it for too
#          long (AI_CORE_NEGLECT_TIMEOUT) — the overhaul spec's "if the AI is at 0 with no
#          crew willing to repair, that's the AI decommissioned game-over"

const AI_CORE_NEGLECT_TIMEOUT: float = 90.0
const AI_CORE_REPAIR_TRUST_THRESHOLD: float = 0.35

var _config: Dictionary = {}    # scenario definition (id, events, win/lose, end-of-leg deltas)
var _active: bool = false
var _ai_core_neglect_timer: float = 0.0


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


func _on_tick(_elapsed: float, delta: float) -> void:
	if not _active:
		return
	_check_lose_conditions(delta)
	_check_win_conditions()


func _check_lose_conditions(delta: float) -> void:
	if GameState.ship_destroyed:
		_end_scenario("ship_destroyed", "hull_breach")
		return

	# AI neglect path: blackout, nobody repairing, and trust too low for anyone to want to.
	if GameState.ai_core_status == "blackout" and not GameState.is_being_repaired("ai_core") \
			and _average_trust() < AI_CORE_REPAIR_TRUST_THRESHOLD:
		_ai_core_neglect_timer += delta
		if _ai_core_neglect_timer >= AI_CORE_NEGLECT_TIMEOUT:
			_end_scenario("ai_decommissioned", "crew_refused_repair")
			return
	else:
		_ai_core_neglect_timer = 0.0

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
	pass


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
	# Apply end-of-leg situational delta (rewards/penalties carried into the next leg) —
	# keys are GameState.adjust_metric names ("battery_charge", "ai_core_integrity").
	var delta: Dictionary = _config.get("leg_delta_%s" % outcome, {})
	for metric_name in delta:
		GameState.adjust_metric(metric_name, delta[metric_name])
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
