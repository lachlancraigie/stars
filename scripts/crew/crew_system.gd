extends Node

# Ticks all crew needs and states each game tick.
# Also propagates resource crisis events into crew fear responses.

func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.resource_critical.connect(_on_resource_critical)


func _on_tick(_elapsed: float, _delta: float) -> void:
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id]
		if not crew.is_alive:
			continue
		NeedsModel.tick(crew)
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
		crew.is_alive = false
		EventBus.crew_died.emit(crew.crew_id, "physical_health_depleted")


func _on_resource_critical(resource_name: String, _value: float) -> void:
	var fear_amount: float = _resource_fear_spike(resource_name)
	if fear_amount <= 0.0:
		return
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id]
		if not crew.is_alive:
			continue
		# High willpower reduces the fear response
		var actual_fear: float = fear_amount * (1.0 - crew.willpower * 0.4)
		crew.fear = minf(1.0, crew.fear + actual_fear)
		EventBus.crew_need_changed.emit(crew_id, "fear", crew.fear)


func _resource_fear_spike(resource_name: String) -> float:
	match resource_name:
		"oxygen": return 0.05
		"power":  return 0.02
		"food":   return 0.01
		_:        return 0.0
