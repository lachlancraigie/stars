extends Node

# Ticks all crew needs and states each game tick.
# Also propagates ship-crisis signals (reactor/life-support/power) into crew fear responses.

func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.reactor_failure.connect(func(_source): _spike_all_fear(0.05))
	EventBus.life_support_failure.connect(func(_source): _spike_all_fear(0.08))
	EventBus.power_low.connect(func(_charge): _spike_all_fear(0.03))
	EventBus.ai_core_status_changed.connect(_on_ai_core_status_changed)


func _on_tick(_elapsed: float, delta: float) -> void:
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id]
		if not crew.is_alive:
			continue
		NeedsModel.tick(crew)
		SuffocationModel.tick(crew, delta)
		WoundTable.tick_death_clock(crew)
		_evaluate_state(crew)
		_check_death(crew)


func _evaluate_state(crew: CrewMember) -> void:
	var new_state: String = CrewStateMachine.evaluate(crew)
	if new_state == crew.current_state:
		return
	var old_state: String = crew.current_state
	crew.current_state = new_state
	EventBus.crew_state_changed.emit(crew.crew_id, old_state, new_state)


func _check_death(crew: CrewMember) -> void:
	if crew.physical_health <= 0.0:
		CrewLifecycle.kill(crew, "physical_health_depleted")


func _on_ai_core_status_changed(_old_status: String, new_status: String) -> void:
	if new_status == "blackout":
		_spike_all_fear(0.10)
	elif new_status == "degraded":
		_spike_all_fear(0.04)


func _spike_all_fear(fear_amount: float) -> void:
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id]
		if not crew.is_alive:
			continue
		# High willpower reduces the fear response
		var actual_fear: float = fear_amount * (1.0 - crew.willpower * 0.4)
		crew.fear = minf(1.0, crew.fear + actual_fear)
		EventBus.crew_need_changed.emit(crew_id, "fear", crew.fear)
