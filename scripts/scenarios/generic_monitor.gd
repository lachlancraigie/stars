class_name GenericScenarioMonitor
extends Node

# Data-driven scenario monitor (docs/mission-system-spec.md §4.3, engine task D).
# Constructed with a scenario config the same shape ScenarioCatalog.build_config()
# returns (config["monitor"] is the raw JSON monitor program) and runs its own
# timers/watches/checks/objective_text without any scenario-specific GDScript —
# QuarantineMonitor/NarrowPassageMonitor stay hand-written (spec §4: "those two stay
# as bespoke GDScript builders"); every JSON-catalog scenario gets one of these instead
# (see scenario_runner.gd's _spawn_monitor).
#
# `monitor.cast` (name -> target selector string, e.g. {"lead": "best_skill:Computers"})
# is resolved to concrete crew_ids EXACTLY ONCE, in setup() — "stable for the scenario's
# life" per spec §4.3, so `cast:lead`/bare `lead` outcome targets always mean the SAME
# crew member even if a better-skilled crew member joins mid-run. Every check's own
# `crew` selector re-resolves fresh each time its interval fires (best_skill: etc. track
# whoever is currently best), while cast:/bare-cast-name selectors still resolve through
# the frozen _cast map via the ctx this monitor hands OutcomeApplier every time.
#
# All outcomes (timers/watches/checks' on_success/on_fail/on_crit_*/on_solved) route
# through OutcomeApplier.apply() — this file only owns the WHEN (interval/flag/condition
# bookkeeping), never the WHAT (outcome execution), matching the outcome_applier.gd
# class doc's "one interpreter for the whole closed outcome set."

var _config: Dictionary = {}
var _monitor: Dictionary = {}
var _cast: Dictionary = {}                 # name -> crew_id, resolved once (see class doc)
var _scenario_instance_id: String = ""

var _timer_state: Array[Dictionary] = []   # [{def, fired}]
var _watch_state: Array[Dictionary] = []   # [{def, fired}]  (fired only matters when once==true)
var _check_state: Dictionary = {}          # check id -> {elapsed, successes, solved}

var _elapsed: float = 0.0
var _last_objective_text: String = ""


func setup(config: Dictionary, scenario_instance_id: String = "") -> void:
	_config = config
	_monitor = config.get("monitor", {})
	_scenario_instance_id = scenario_instance_id

	_resolve_cast()

	_timer_state.clear()
	for t_v in _monitor.get("timers", []):
		_timer_state.append({"def": t_v as Dictionary, "fired": false})

	_watch_state.clear()
	for w_v in _monitor.get("watches", []):
		_watch_state.append({"def": w_v as Dictionary, "fired": false})

	_check_state.clear()
	for c_v in _monitor.get("checks", []):
		var c: Dictionary = c_v
		_check_state[String(c.get("id", ""))] = {"elapsed": 0.0, "successes": 0, "solved": false}

	_update_objective_text()   # show the "start" line immediately, don't wait for first tick


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	# Self-cleanup: when this monitor's own scenario instance ends (win, morph handoff,
	# or run-lose), the monitor must stop ticking — a morphed-away scenario's monitor
	# would otherwise keep re-emitting its start objective text and rolling checks
	# against the NEXT scenario's flag namespace. Instance ids are "<scenario_id>#<n>"
	# (ScenarioRunner.start_scenario) and the same scenario id never runs twice
	# concurrently (the overlap picker excludes already-active ids), so a prefix match
	# identifies this monitor's instance exactly.
	EventBus.scenario_instance_ended.connect(_on_instance_ended)


func _on_instance_ended(instance_id: String, _outcome: String) -> void:
	if instance_id.begins_with("%s#" % String(_config.get("id", ""))):
		queue_free()


func _resolve_cast() -> void:
	var cast_def: Dictionary = _monitor.get("cast", {})
	for name: String in cast_def.keys():
		var sel: String = String(cast_def[name])
		var targets: Array[CrewMember] = OutcomeApplier.resolve_targets(sel, {})
		if not targets.is_empty():
			_cast[name] = targets[0].crew_id
		else:
			push_warning("GenericScenarioMonitor(%s): cast '%s' selector '%s' resolved to nobody" % [
				String(_config.get("id", "?")), name, sel])


func _ctx() -> Dictionary:
	return {"cast": _cast, "away_team": [], "scenario_instance_id": _scenario_instance_id}


func _on_tick(_elapsed_time: float, delta: float) -> void:
	_elapsed += delta
	_tick_timers()
	_tick_watches()
	_tick_checks(delta)
	_update_objective_text()


func _flags_ok(flags: Array) -> bool:
	for f in flags:
		if not ScenarioDirector.get_flag(String(f)):
			return false
	return true


# --- Timers: "at" (elapsed seconds) + optional requires_flags gate. A timer that
# reaches `at` before its flags are true keeps waiting (re-checked every tick) rather
# than being skipped — content like false_alarm.json's 80s "It's back" timer requires a
# flag an EventPool-drawn event sets probabilistically, not on a fixed schedule. ---
func _tick_timers() -> void:
	for entry: Dictionary in _timer_state:
		if entry["fired"]:
			continue
		var def: Dictionary = entry["def"]
		if _elapsed < float(def.get("at", 0.0)):
			continue
		if not _flags_ok(def.get("requires_flags", [])):
			continue
		entry["fired"] = true
		OutcomeApplier.apply(def.get("outcomes", []), _ctx())


# --- Watches: conditions checked every tick (EventPool's shared condition vocabulary,
# §5's existing + new types). `once` fires exactly one time; without it, re-fires every
# tick its conditions hold — content authors reach for `once` almost always, but the
# JSON schema allows omitting it (defaults false), so a repeating watch is honoured. ---
func _tick_watches() -> void:
	for entry: Dictionary in _watch_state:
		var def: Dictionary = entry["def"]
		var once: bool = bool(def.get("once", false))
		if once and entry["fired"]:
			continue
		if not _conditions_ok(def.get("conditions", [])):
			continue
		entry["fired"] = true
		OutcomeApplier.apply(def.get("outcomes", []), _ctx())


func _conditions_ok(conditions: Array) -> bool:
	for c_v in conditions:
		if not EventPool.check_condition(c_v as Dictionary, ScenarioDirector.scenario_flags):
			return false
	return true


# --- Checks: the solve-path engine (spec §4.3). Periodic real Checks.perform_check dice
# against a selector-resolved crew member; successes accumulate toward successes_needed,
# then on_solved fires once and the check goes dormant. ---
func _tick_checks(delta: float) -> void:
	for cid: String in _check_state.keys():
		var state: Dictionary = _check_state[cid]
		if bool(state.get("solved", false)):
			continue
		var def: Dictionary = _find_check_def(cid)
		if def.is_empty():
			continue
		if not _flags_ok(def.get("requires_flags", [])):
			continue
		state["elapsed"] = float(state.get("elapsed", 0.0)) + delta
		var interval: float = float(def.get("interval", 30.0))
		if state["elapsed"] < interval:
			continue
		state["elapsed"] = 0.0
		_run_check(def, state)


func _find_check_def(cid: String) -> Dictionary:
	for c_v in _monitor.get("checks", []):
		var c: Dictionary = c_v
		if String(c.get("id", "")) == cid:
			return c
	return {}


func _run_check(def: Dictionary, state: Dictionary) -> void:
	var sel: String = String(def.get("crew", "random"))
	var targets: Array[CrewMember] = OutcomeApplier.resolve_targets(sel, _ctx())
	if targets.is_empty():
		return   # nobody available this interval (dead/departed/off-ship) — try again next
	var crew: CrewMember = targets[0]

	var stat_name: String = String(def.get("stat", "intellect"))
	var skill_name: String = String(def.get("skill", ""))
	var item_tag: String = String(def.get("item_tag", ""))
	var bonus: int = int(crew.item_bonus(item_tag)) if item_tag != "" else 0

	var result: Checks.CheckResult = Checks.perform_check(crew, stat_name, skill_name, false, false, bonus)
	var ctx: Dictionary = _ctx()

	if result.critical_success():
		OutcomeApplier.apply(def.get("on_crit_success", []), ctx)
	if result.critical_failure():
		OutcomeApplier.apply(def.get("on_crit_fail", []), ctx)

	if result.success:
		OutcomeApplier.apply(def.get("on_success", []), ctx)
		state["successes"] = int(state.get("successes", 0)) + 1
		if int(state["successes"]) >= int(def.get("successes_needed", 1)):
			state["solved"] = true
			OutcomeApplier.apply(def.get("on_solved", []), ctx)
	else:
		OutcomeApplier.apply(def.get("on_fail", []), ctx)


# --- Objective text (spec §4.3: "start" + flag-keyed swaps). Re-evaluated every tick
# (cheap — a handful of dictionary lookups) so the HUD line updates the moment a flag
# lands, not on some separate polling cadence. Later-declared flags win ties when
# several are simultaneously true — JSON authors order objective_text.flags as a
# natural progression, so "last matching" reads as "most recent progress". ---
func _update_objective_text() -> void:
	var obj_text: Dictionary = _monitor.get("objective_text", {})
	var flags_map: Dictionary = obj_text.get("flags", {})
	var candidate: String = String(obj_text.get("start", ""))
	for flag: String in flags_map.keys():
		if ScenarioDirector.get_flag(flag):
			candidate = String(flags_map[flag])
	if candidate != "" and candidate != _last_objective_text:
		_last_objective_text = candidate
		EventBus.objective_changed.emit(candidate)
