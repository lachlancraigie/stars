extends Node

# Hidden meta-layer — the player never observes this directly.
# Inspired by Alien Isolation's director AI: manages pacing, tone drift, and event timing
# independently from individual crew AI. Keeps tension in a playable range.
#
# The Director tracks:
#   - how long since the last "interesting" event (escalates if too quiet)
#   - how many bad things have happened recently (backs off if overwhelming)
#   - the current tone position and which direction it's drifting

const TENSION_DECAY_PER_TICK: float   = 0.00005
const TENSION_GAIN_ON_EVENT: float    = 0.15
const TONE_DRIFT_RATE: float          = 0.0002  # how fast tone slides per tick
const EVENT_COOLDOWN_MIN: float       = 60.0    # minimum seconds between director-fired events
const ESCALATION_IDLE_THRESHOLD: float = 120.0  # seconds quiet before director escalates

var tension: float = 0.0            # 0 = calm, 1 = maximum pressure
var scenario_flags: Dictionary = {} # string flags set by event outcomes
var _pool: EventPool = EventPool.new()
var _last_event_time: float = 0.0
var _scenario_start_time: float = 0.0


# ============================================================================
# THE OVERSEER (docs/director-spec.md) — Layer 1, omniscient, out-of-fiction.
# Grows this autoload rather than forking it: the tension/tone drift above
# stays the WITHIN-scenario pacing layer; everything below reads global
# performance and maintains `heat`, the Overseer's one difficulty dial.
# Build order step 1 (spec §8): heat + rolling performance score, READ ONLY —
# nothing consumes `heat`/`modifiers` for gameplay effect yet (that's step 2).
# ============================================================================

# --- Rolling performance-score window (spec §3 table) ---
const PERFORMANCE_WINDOW_SECONDS: float = 240.0   # rolling window; spec calls for 3-5 min
const SCORE_NORMALIZER: float = 10.0               # windowed push-sum / this = performance_score, clamped [-1,1]

# Discrete-event pushes — one timestamped sample per signal firing.
const PUSH_CREW_DEATH: float        = -4.0   # "strongly down"
const PUSH_INJURY: float            = -1.0
const PUSH_PANIC: float             = -1.0
const PUSH_AI_DAMAGED: float        = -1.0
const PUSH_REPAIR_REFUSED: float    = -0.8
const PUSH_REPAIR_SUCCESS: float    =  1.0
const PUSH_CRISIS_RESOLVED: float   =  2.0
const PUSH_OBJECTIVE_PROGRESS: float = 0.6   # a scenario flag transitioning false→true (see set_flag)

# Continuous per-second pushes — added every tick, scaled by delta, while the
# condition holds (so a sustained state saturates the window like a real crisis
# would; a momentary blip barely moves it).
const HIGH_STRESS_THRESHOLD: int   = 9
const CALM_STRESS_THRESHOLD: int   = 5
const LOW_TRUST_THRESHOLD: float   = 0.4
const LOW_BATTERY_PERCENT: float   = 30.0
const NO_BEAT_QUIET_SECONDS: float = 60.0    # reuses EVENT_COOLDOWN_MIN's cadence for "no active beat"
const BOREDOM_GRACE_SECONDS: float = 45.0    # wall-clock since last meaningful decision before boredom accrues

const PUSH_PER_SEC_HIGH_STRESS: float     = -0.05
const PUSH_PER_SEC_LOW_TRUST: float       = -0.05
const PUSH_PER_SEC_LOW_BATTERY: float     = -0.05
const PUSH_PER_SEC_LOW_AIR: float         = -0.05
const PUSH_PER_SEC_DOUBLE_OFFLINE: float  = -0.08  # reactor AND life support both down at once
const PUSH_PER_SEC_ALL_CALM: float        =  0.06  # calm crew + both systems green + no active beat
const PUSH_PER_SEC_BOREDOM: float         =  0.04  # wall-clock idle pressure

# --- Heat: hysteresis + slew (spec §3: "target must differ by >0.1 for 20s+
# before heat starts moving; slew-rate limited so it never oscillates visibly") ---
const HEAT_HYSTERESIS_THRESHOLD: float  = 0.1
const HEAT_HYSTERESIS_HOLD_SECONDS: float = 20.0
const HEAT_SLEW_PER_SEC: float = 0.015   # ~67s to cross the full [0,1] range once moving

var heat: float = 0.5                 # [0,1] — the Overseer's one difficulty dial
var performance_score: float = 0.0    # [-1,1] — rolling read of "how is the player doing"

var _perf_samples: Array[Dictionary] = []   # [{t: float, v: float}, ...] pruned to the window
var _perf_sum: float = 0.0                  # running sum of _perf_samples[].v (avoids an O(n) resum every tick)
var _heat_target: float = 0.5
var _heat_mismatch_since: float = -1.0
var _heat_moving: bool = false
var _last_decision_time: float = 0.0        # elapsed of the last meaningful player action (boredom clock)

var _debug: bool = false
var _debug_accum: float = 0.0
const DEBUG_PRINT_INTERVAL: float = 5.0


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.scenario_event_triggered.connect(_on_event_fired)
	_debug = OS.get_environment("SHIPAI_DIRECTOR_DEBUG") == "1"
	_connect_overseer_inputs()


func start_scenario(events: Array[ScenarioEvent]) -> void:
	_pool.load_events(events)
	_scenario_start_time = TimeManager.elapsed
	_last_event_time = TimeManager.elapsed
	_last_decision_time = TimeManager.elapsed
	scenario_flags.clear()
	tension = 0.0


func set_flag(flag: String, value: bool = true) -> void:
	# Objective-progress input (spec §3): the generic, scenario-agnostic proxy for
	# "the player moved a beat forward" — every scenario's win path sets a growing
	# trail of flags (vasquez_isolated, field_exited, ...) as it's cleared, so a
	# flag going false/unset -> true is treated as forward momentum. Re-setting an
	# already-true flag, or setting one false, is not progress and pushes nothing.
	var was_set: bool = scenario_flags.get(flag, false)
	scenario_flags[flag] = value
	if value and not was_set:
		_push(PUSH_OBJECTIVE_PROGRESS)


func get_flag(flag: String) -> bool:
	return scenario_flags.get(flag, false)


func fire_event(event: ScenarioEvent) -> void:
	event.last_fired = TimeManager.elapsed
	event.has_fired = true
	_last_event_time = TimeManager.elapsed
	tension = minf(1.0, tension + TENSION_GAIN_ON_EVENT)
	EventBus.scenario_event_triggered.emit(event.event_id)
	_apply_outcomes(event)


func _on_tick(elapsed: float, delta: float) -> void:
	tension = maxf(0.0, tension - TENSION_DECAY_PER_TICK)
	_drift_tone(elapsed)
	_consider_event(elapsed)
	_update_overseer(elapsed, delta)


func _drift_tone(elapsed: float) -> void:
	# Tone drifts toward Alien-end as tension accumulates; drifts back under calm.
	var target: float = tension
	var current: float = GameState.scenario_tone
	var drift: float = (target - current) * TONE_DRIFT_RATE * 100.0
	GameState.scenario_tone = clampf(current + drift, 0.0, 1.0)


func _consider_event(elapsed: float) -> void:
	var time_since_last: float = elapsed - _last_event_time
	# Only consider firing when past the minimum cooldown
	if time_since_last < EVENT_COOLDOWN_MIN:
		return
	# Probability of firing scales with idle time and tension
	var idle_pressure: float = clampf(
		(time_since_last - EVENT_COOLDOWN_MIN) / ESCALATION_IDLE_THRESHOLD, 0.0, 1.0)
	var fire_chance: float = idle_pressure * (0.3 + tension * 0.4)
	if randf() < fire_chance * TONE_DRIFT_RATE * 100.0:
		var event: ScenarioEvent = _pool.draw(GameState.scenario_tone, elapsed, scenario_flags)
		if event != null:
			fire_event(event)


func _on_event_fired(_event_id: String) -> void:
	pass  # Director receives its own fired events — hook for future chaining logic


func _apply_outcomes(event: ScenarioEvent) -> void:
	for outcome in event.outcomes:
		match outcome.get("type", ""):
			"resource_delta":
				GameState.adjust_metric(outcome.resource, outcome.amount)
			"crew_fear_spike":
				_spike_crew_fear(outcome.amount, outcome.get("all_crew", true))
			"set_flag":
				set_flag(outcome.flag, outcome.get("value", true))
			"spawn_event":
				var spawned: ScenarioEvent = _find_event(outcome.event_id)
				if spawned != null:
					fire_event(spawned)
			"ai_trust_delta":
				TrustModel.modify_all(outcome.amount)
			"scenario_end":
				EventBus.scenario_ended.emit(outcome.get("outcome", "unknown"))
			# --- Stub hooks for scenario-authored ship/AI damage (Mothership rewrite) ---
			"reactor_failure":
				GameState.damage_reactor(outcome.get("source", "scenario"))
			"life_support_failure":
				GameState.damage_life_support(outcome.get("source", "scenario"))
			"ai_core_damage":
				GameState.damage_ai_core(outcome.get("amount", 10.0), outcome.get("source", "scenario"))
			"ai_core_repair":
				GameState.repair_ai_core(outcome.get("amount", 10.0))
			"ship_destroyed":
				GameState.destroy_ship(outcome.get("reason", "scenario"))


func _spike_crew_fear(amount: float, all_crew: bool) -> void:
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive and (all_crew or crew.role == "general"):
			crew.fear = minf(1.0, crew.fear + amount)
			EventBus.crew_need_changed.emit(crew_id, "fear", crew.fear)


func _find_event(event_id: String) -> ScenarioEvent:
	for event in _pool._events:
		if event.event_id == event_id:
			return event
	return null


# ============================================================================
# THE OVERSEER — heat & performance window (spec §3). See the header comment
# near the constants above for the layer split; everything from here down is
# new for the Overseer and does not touch the tension/tone code above it.
# ============================================================================

# Discrete EventBus inputs (spec §3 table). Additive connections only — never
# assumes it's the only listener. `recent_event` is filtered to "crisis_resolved"
# since that's the only vocabulary entry the table calls out by name; the more
# specific typed signals below cover the rest without needing the lossy funnel.
func _connect_overseer_inputs() -> void:
	EventBus.crew_died.connect(func(_cid, _cause): _push(PUSH_CREW_DEATH))
	EventBus.crew_injury.connect(func(_cid, _sev, _wtype): _push(PUSH_INJURY))
	EventBus.crew_panicked.connect(func(_cid, _roll, _effect): _push(PUSH_PANIC))
	EventBus.ai_damaged.connect(func(_amt, _integrity, _source): _push(PUSH_AI_DAMAGED))
	EventBus.repair_refused.connect(func(_target, _reason): _push(PUSH_REPAIR_REFUSED))
	EventBus.repair_success.connect(func(_target, _cid): _push(PUSH_REPAIR_SUCCESS))
	EventBus.recent_event.connect(func(event_id, _data):
		if event_id == "crisis_resolved":
			_push(PUSH_CRISIS_RESOLVED))
	# Boredom clock (spec §3: "wall-clock time since last meaningful player
	# decision"): real AI actions — issuing a directive, toggling reactor power,
	# diverting battery power, starting a repair job — all reset the idle clock.
	EventBus.directive_issued.connect(func(_d): _mark_decision())
	EventBus.power_mode_changed.connect(func(_online): _mark_decision())
	EventBus.room_power_changed.connect(func(_rid, _powered): _mark_decision())
	EventBus.repair_started.connect(func(_tid, _cid): _mark_decision())


func _mark_decision() -> void:
	_last_decision_time = TimeManager.elapsed


func _push(value: float) -> void:
	if value == 0.0:
		return
	_perf_samples.append({"t": TimeManager.elapsed, "v": value})
	_perf_sum += value


func _update_overseer(elapsed: float, delta: float) -> void:
	_accumulate_continuous_pushes(elapsed, delta)
	_prune_samples(elapsed)
	performance_score = clampf(_perf_sum / SCORE_NORMALIZER, -1.0, 1.0)
	_update_heat(elapsed, delta)
	if _debug:
		_print_debug(elapsed, delta)


# Level-based conditions from the spec §3 table that aren't discrete signals —
# evaluated every tick and pushed scaled by delta, so a sustained bad (or good,
# or boring) state accumulates like a real trend instead of a one-off blip.
func _accumulate_continuous_pushes(elapsed: float, delta: float) -> void:
	if GameState.crew.is_empty():
		return
	var avg_stress: float = _average_living_stress()
	var avg_trust: float = _average_trust()
	var battery_pct: float = GameState.get_metric("battery_percent")
	var both_offline: bool = not GameState.reactor_online and not GameState.life_support_online
	var no_active_beat: bool = (elapsed - _last_event_time) > NO_BEAT_QUIET_SECONDS
	var all_calm: bool = avg_stress <= float(CALM_STRESS_THRESHOLD) \
		and GameState.reactor_online and GameState.life_support_online and no_active_beat
	var bored: bool = (elapsed - _last_decision_time) > BOREDOM_GRACE_SECONDS

	var v: float = 0.0
	if avg_stress > float(HIGH_STRESS_THRESHOLD):
		v += PUSH_PER_SEC_HIGH_STRESS
	if avg_trust < LOW_TRUST_THRESHOLD:
		v += PUSH_PER_SEC_LOW_TRUST
	if battery_pct < LOW_BATTERY_PERCENT:
		v += PUSH_PER_SEC_LOW_BATTERY
	if _any_room_air_low():
		v += PUSH_PER_SEC_LOW_AIR
	if both_offline:
		v += PUSH_PER_SEC_DOUBLE_OFFLINE
	if all_calm:
		v += PUSH_PER_SEC_ALL_CALM
	if bored:
		v += PUSH_PER_SEC_BOREDOM
	_push(v * delta)


func _prune_samples(elapsed: float) -> void:
	var cutoff: float = elapsed - PERFORMANCE_WINDOW_SECONDS
	while not _perf_samples.is_empty() and (_perf_samples[0] as Dictionary)["t"] < cutoff:
		var old: Dictionary = _perf_samples.pop_front()
		_perf_sum -= old["v"]


func _update_heat(elapsed: float, delta: float) -> void:
	_heat_target = clampf(0.5 + performance_score * 0.5, 0.0, 1.0)
	var diff: float = _heat_target - heat
	if absf(diff) > HEAT_HYSTERESIS_THRESHOLD:
		if _heat_mismatch_since < 0.0:
			_heat_mismatch_since = elapsed
		_heat_moving = (elapsed - _heat_mismatch_since) >= HEAT_HYSTERESIS_HOLD_SECONDS
	else:
		_heat_mismatch_since = -1.0
		_heat_moving = false

	if _heat_moving:
		heat = move_toward(heat, _heat_target, HEAT_SLEW_PER_SEC * delta)


func _average_living_stress() -> float:
	var total: float = 0.0
	var count: int = 0
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive:
			total += float(crew.stress)
			count += 1
	return (total / count) if count > 0 else 0.0


func _average_trust() -> float:
	if GameState.ai_trust_scores.is_empty():
		return 0.5
	var total: float = 0.0
	for crew_id in GameState.ai_trust_scores:
		total += GameState.ai_trust_scores[crew_id]
	return total / GameState.ai_trust_scores.size()


func _any_room_air_low() -> bool:
	for room_id in GameState.room_air:
		if GameState.get_room_air(room_id) < LifeSupportModel.AIR_DISADVANTAGE_THRESHOLD:
			return true
	return false


func _print_debug(elapsed: float, delta: float) -> void:
	_debug_accum += delta
	if _debug_accum < DEBUG_PRINT_INTERVAL:
		return
	_debug_accum = 0.0
	print("[OVERSEER] t=%.0fs heat=%.3f target=%.3f score=%.3f moving=%s samples=%d" % [
		elapsed, heat, _heat_target, performance_score, _heat_moving, _perf_samples.size()])
