extends Node

# Orchestrates running scenarios: loads config, checks win/lose conditions,
# applies end-of-scenario situational deltas, and hands off to the next scenario.
#
# Multi-instance (docs/director-spec.md §5/§8 step 3): `active_scenarios` holds every
# currently-running scenario keyed by a unique instance id, so the Overseer can later
# start a second one alongside the first (step 5's overlap scheduling) without this
# file changing shape again. Today exactly one scenario ever runs at a time (nothing
# calls start_scenario() twice yet) — the dictionary-of-one is deliberate scaffolding,
# not speculative complexity: every check below already iterates active_scenarios so
# step 5 only has to add a second start_scenario() call and a compatibility check.
#
# Win is per-scenario: each instance's own win_flags are checked independently, and
# only THAT instance ends (leg delta applied, scenario_instance_ended emitted). The
# run-level scenario_ended signal — every existing listener's (HUD/main.gd/monitors)
# expectation — fires once active_scenarios drains to empty, so single-scenario runs
# behave exactly as before.
#
# Lose conditions (all three permadeath paths from CLAUDE.md's design decision) are
# RUN-level, not per-scenario, and stay global on purpose — a death spiral in one
# concurrent scenario ends the whole voyage, not just its own instance:
#   - all crew dead
#   - ship destroyed (GameState.ship_destroyed — stub hook, no in-game content sets it yet)
#   - AI decommissioned, via either of two paths:
#       1. crew vote to shut it down outright (ai_decommission_attempted, low trust)
#       2. the AI core sits in blackout with no crew willing/able to repair it for too
#          long (AI_CORE_NEGLECT_TIMEOUT) — the overhaul spec's "if the AI is at 0 with no
#          crew willing to repair, that's the AI decommissioned game-over"

const AI_CORE_NEGLECT_TIMEOUT: float = 90.0
const AI_CORE_REPAIR_TRUST_THRESHOLD: float = 0.35

# instance_id -> {id, scenario_id, config, started_at}. config is the same dictionary
# builders (QuarantineScenario.build(), etc) return — events/win_flags/leg_delta_*.
var active_scenarios: Dictionary = {}
var _next_instance_id: int = 0
var _run_active: bool = false   # guards against re-processing RUN-lose after it has already fired
var _ai_core_neglect_timer: float = 0.0


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.crew_died.connect(_on_crew_died)
	EventBus.ai_decommission_attempted.connect(_on_decommission_attempted)


# Starts a new scenario instance and returns its unique instance id (callers that
# don't care — every existing call site — can simply ignore the return value).
func start_scenario(config: Dictionary) -> String:
	var instance_id: String = "%s#%d" % [config.get("id", "scenario"), _next_instance_id]
	_next_instance_id += 1
	active_scenarios[instance_id] = {
		"id": instance_id,
		"scenario_id": config.get("id", "unknown"),
		"config": config,
		"started_at": TimeManager.elapsed,
	}
	_run_active = true
	# GameState.scenario_id/scenario_tone stay single-valued (the HUD/dialogue-facing
	# "current scenario") — they track the most recently started instance. A true
	# multi-scenario-aware HUD is out of scope until overlap (step 5) actually needs it.
	GameState.scenario_id = config.get("id", "unknown")
	GameState.scenario_tone = config.get("starting_tone", 0.2)
	ScenarioDirector.start_scenario(config.get("events", []))
	EventBus.scenario_event_triggered.emit("scenario_started")
	return instance_id


func _on_tick(_elapsed: float, delta: float) -> void:
	if active_scenarios.is_empty():
		return
	_check_run_lose_conditions(delta)
	if not _run_active:
		return
	_check_win_conditions()


# --- RUN-level lose conditions (global — end every active scenario at once) ---

func _check_run_lose_conditions(delta: float) -> void:
	if GameState.ship_destroyed:
		_end_run("ship_destroyed", "hull_breach")
		return

	# AI neglect path: blackout, nobody repairing, and trust too low for anyone to want to.
	if GameState.ai_core_status == "blackout" and not GameState.is_being_repaired("ai_core") \
			and _average_trust() < AI_CORE_REPAIR_TRUST_THRESHOLD:
		_ai_core_neglect_timer += delta
		if _ai_core_neglect_timer >= AI_CORE_NEGLECT_TIMEOUT:
			_end_run("ai_decommissioned", "crew_refused_repair")
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
		_end_run("crew_dead", "all_crew_dead")


# --- Per-scenario win conditions ---

func _check_win_conditions() -> void:
	# Snapshot the keys — _end_scenario_instance mutates active_scenarios mid-loop.
	for instance_id: String in active_scenarios.keys():
		var instance: Dictionary = active_scenarios.get(instance_id, {})
		if instance.is_empty():
			continue
		var config: Dictionary = instance.get("config", {})
		var win_flags: Array = config.get("win_flags", [])
		if win_flags.is_empty():
			continue
		var all_met: bool = true
		for flag in win_flags:
			if not ScenarioDirector.get_flag(flag):
				all_met = false
				break
		if all_met:
			_end_scenario_instance(instance_id, "success", "all_win_conditions_met")


func _on_crew_died(_crew_id: String, _cause: String) -> void:
	# Win/lose re-check happens next tick — avoids checking mid-cascade
	pass


func _on_decommission_attempted(_initiator: String) -> void:
	if not _run_active or active_scenarios.is_empty():
		return
	# Whether decommission succeeds depends on trust levels
	var avg_trust: float = _average_trust()
	if avg_trust < 0.3:
		_end_run("ai_decommissioned", "crew_voted_shutdown")


# Ends exactly one scenario instance (a win). Other active scenarios (step 5 overlap)
# keep running untouched; scenario_ended (the run-level signal) only fires once this
# was the LAST active instance, so single-scenario runs behave exactly as before.
func _end_scenario_instance(instance_id: String, outcome: String, reason: String) -> void:
	var instance: Dictionary = active_scenarios.get(instance_id, {})
	if instance.is_empty():
		return
	active_scenarios.erase(instance_id)
	_apply_leg_delta(instance.get("config", {}), outcome)
	EventBus.scenario_instance_ended.emit(instance_id, outcome)
	push_warning("ScenarioRunner: scenario instance ended — id=%s outcome=%s reason=%s" % [instance_id, outcome, reason])
	if active_scenarios.is_empty():
		EventBus.scenario_ended.emit(outcome)
		# TODO(campaign): hand off to CampaignManager for next scenario/leg load
	# else: a differently-paced concurrent scenario is still running — the run isn't over.


# Ends the whole run (a RUN-lose condition fired) — every active scenario ends at
# once, each applying its own leg_delta_<outcome> if it defines one (concurrent
# scenarios both losing stacks their penalties, which is the intended read: an
# overlap gone bad costs more than a single scenario going bad).
func _end_run(outcome: String, reason: String) -> void:
	if not _run_active:
		return
	_run_active = false
	for instance_id: String in active_scenarios.keys():
		var instance: Dictionary = active_scenarios[instance_id]
		_apply_leg_delta(instance.get("config", {}), outcome)
		EventBus.scenario_instance_ended.emit(instance_id, outcome)
	active_scenarios.clear()
	EventBus.scenario_ended.emit(outcome)
	push_warning("ScenarioRunner: RUN ended — outcome=%s reason=%s" % [outcome, reason])


# End-of-leg situational delta (rewards/penalties carried into the next leg) — keys
# are GameState.adjust_metric names ("battery_charge", "ai_core_integrity").
func _apply_leg_delta(config: Dictionary, outcome: String) -> void:
	var delta: Dictionary = config.get("leg_delta_%s" % outcome, {})
	for metric_name in delta:
		GameState.adjust_metric(metric_name, delta[metric_name])


func _average_trust() -> float:
	if GameState.ai_trust_scores.is_empty():
		return 0.5
	var total: float = 0.0
	for crew_id in GameState.ai_trust_scores:
		total += GameState.ai_trust_scores[crew_id]
	return total / GameState.ai_trust_scores.size()
