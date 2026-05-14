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


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.scenario_event_triggered.connect(_on_event_fired)


func start_scenario(events: Array[ScenarioEvent]) -> void:
	_pool.load_events(events)
	_scenario_start_time = TimeManager.elapsed
	_last_event_time = TimeManager.elapsed
	scenario_flags.clear()
	tension = 0.0


func set_flag(flag: String, value: bool = true) -> void:
	scenario_flags[flag] = value


func get_flag(flag: String) -> bool:
	return scenario_flags.get(flag, false)


func fire_event(event: ScenarioEvent) -> void:
	event.last_fired = TimeManager.elapsed
	event.has_fired = true
	_last_event_time = TimeManager.elapsed
	tension = minf(1.0, tension + TENSION_GAIN_ON_EVENT)
	EventBus.scenario_event_triggered.emit(event.event_id)
	_apply_outcomes(event)


func _on_tick(elapsed: float, _delta: float) -> void:
	tension = maxf(0.0, tension - TENSION_DECAY_PER_TICK)
	_drift_tone(elapsed)
	_consider_event(elapsed)


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
				var current: float = GameState.get_resource(outcome.resource)
				GameState.set_resource(outcome.resource, current + outcome.amount)
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
