class_name NeedsModel
extends RefCounted

# Per-tick need rates (1x speed, 0.25s per tick).
# At these rates with 4 crew: ~10 min to starvation, ~14 min to exhaustion.
const HUNGER_PER_TICK: float           = 0.00008
const HUNGER_RECOVERY_PER_TICK: float  = 0.001
const FATIGUE_IDLE_PER_TICK: float     = 0.00005
const FATIGUE_WORK_PER_TICK: float     = 0.00009
const FATIGUE_SLEEP_RECOVERY: float    = 0.0003
const FEAR_DECAY_PER_TICK: float       = 0.00008   # willpower scales this up
const FEAR_OXYGEN_BONUS: float         = 0.0003    # extra fear per tick when O2 < threshold
const OXYGEN_FEAR_THRESHOLD: float     = 0.3
const LONELINESS_PER_TICK: float       = 0.00004
const LONELINESS_RECOVERY: float       = 0.0001
const BOREDOM_IDLE_PER_TICK: float     = 0.0006  # idle -> working shift in ~3-4 min
const BOREDOM_WORK_RECOVERY: float     = 0.0003
const NEED_CRITICAL_THRESHOLD: float   = 0.85


static func tick(crew: CrewMember) -> void:
	_tick_hunger(crew)
	_tick_fatigue(crew)
	_tick_fear(crew)
	_tick_loneliness(crew)
	_tick_boredom(crew)
	crew.morale = _calculate_morale(crew)
	_emit_need_criticals(crew)


static func _tick_hunger(crew: CrewMember) -> void:
	if crew.current_state == CrewStateMachine.EATING:
		crew.hunger = maxf(0.0, crew.hunger - HUNGER_RECOVERY_PER_TICK)
		return
	crew.hunger = minf(1.0, crew.hunger + HUNGER_PER_TICK)


static func _tick_fatigue(crew: CrewMember) -> void:
	match crew.current_state:
		CrewStateMachine.SLEEPING:
			crew.fatigue = maxf(0.0, crew.fatigue - FATIGUE_SLEEP_RECOVERY)
		CrewStateMachine.WORKING:
			crew.fatigue = minf(1.0, crew.fatigue + FATIGUE_WORK_PER_TICK)
		_:
			crew.fatigue = minf(1.0, crew.fatigue + FATIGUE_IDLE_PER_TICK)


static func _tick_fear(crew: CrewMember) -> void:
	# Willpower increases the natural decay rate
	var decay: float = FEAR_DECAY_PER_TICK * (0.5 + crew.willpower * 0.5)
	crew.fear = maxf(0.0, crew.fear - decay)
	# Thin air in the crew member's own room adds fear proportional to how bad it is
	# (replaces the old ship-wide "oxygen" resource-bar check with the per-room air model).
	var air: float = GameState.get_room_air(crew.location) / 100.0
	if air < OXYGEN_FEAR_THRESHOLD:
		var scarcity_ratio: float = (OXYGEN_FEAR_THRESHOLD - air) / OXYGEN_FEAR_THRESHOLD
		crew.fear = minf(1.0, crew.fear + FEAR_OXYGEN_BONUS * scarcity_ratio)


static func _tick_loneliness(crew: CrewMember) -> void:
	var room: RoomBase = GameState.rooms.get(crew.location) as RoomBase
	if room != null and room.occupants.size() > 1:
		crew.loneliness = maxf(0.0, crew.loneliness - LONELINESS_RECOVERY)
	else:
		crew.loneliness = minf(1.0, crew.loneliness + LONELINESS_PER_TICK)
	# Widowed (docs/crew-progression-spec.md §3): "loneliness floor raised" — a continuous
	# clamp, not a one-time bump, so it holds even after recovery ticks would otherwise
	# have drained loneliness back down.
	crew.loneliness = maxf(crew.loneliness, Traits.loneliness_floor(crew.traits))


static func _tick_boredom(crew: CrewMember) -> void:
	if crew.current_state == CrewStateMachine.WORKING:
		crew.boredom = maxf(0.0, crew.boredom - BOREDOM_WORK_RECOVERY)
	elif crew.current_state == CrewStateMachine.IDLE:
		crew.boredom = minf(1.0, crew.boredom + BOREDOM_IDLE_PER_TICK)


static func _calculate_morale(crew: CrewMember) -> float:
	var pressure: float = (
		crew.hunger     * 0.25 +
		crew.fatigue    * 0.20 +
		crew.fear       * 0.30 +
		crew.pain       * 0.15 +
		crew.loneliness * 0.05 +
		crew.boredom    * 0.05
	)
	return clampf(1.0 - pressure, 0.0, 1.0)


static func _emit_need_criticals(crew: CrewMember) -> void:
	var needs: Dictionary = {
		"hunger": crew.hunger, "fatigue": crew.fatigue, "fear": crew.fear,
		"pain": crew.pain, "loneliness": crew.loneliness,
	}
	for need_name: String in needs:
		if needs[need_name] >= NEED_CRITICAL_THRESHOLD:
			EventBus.crew_need_critical.emit(crew.crew_id, need_name, needs[need_name])
