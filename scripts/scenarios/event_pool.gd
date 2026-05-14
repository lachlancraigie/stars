class_name EventPool
extends RefCounted

# Weighted draw from a pool of ScenarioEvents filtered by tone and conditions.

var _events: Array[ScenarioEvent] = []


func load_events(events: Array[ScenarioEvent]) -> void:
	_events = events.duplicate()


func add_event(event: ScenarioEvent) -> void:
	_events.append(event)


func draw(tone: float, elapsed: float, flags: Dictionary) -> ScenarioEvent:
	var eligible: Array[ScenarioEvent] = _get_eligible(tone, elapsed, flags)
	if eligible.is_empty():
		return null
	return _weighted_pick(eligible)


func _get_eligible(tone: float, elapsed: float, flags: Dictionary) -> Array[ScenarioEvent]:
	var result: Array[ScenarioEvent] = []
	for event in _events:
		if event.one_shot and event.has_fired:
			continue
		if elapsed < event.min_elapsed:
			continue
		if elapsed - event.last_fired < event.cooldown:
			continue
		if tone < event.tone_min or tone > event.tone_max:
			continue
		if not _conditions_met(event, flags):
			continue
		result.append(event)
	return result


func _weighted_pick(eligible: Array[ScenarioEvent]) -> ScenarioEvent:
	var total_weight: float = 0.0
	for event in eligible:
		total_weight += event.weight
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for event in eligible:
		cumulative += event.weight
		if roll <= cumulative:
			return event
	return eligible.back()


func _conditions_met(event: ScenarioEvent, flags: Dictionary) -> bool:
	for condition in event.conditions:
		if not _check_condition(condition, flags):
			return false
	return true


func _check_condition(condition: Dictionary, flags: Dictionary) -> bool:
	match condition.get("type", ""):
		"resource_below":
			return GameState.get_resource(condition.resource) < condition.value
		"resource_above":
			return GameState.get_resource(condition.resource) > condition.value
		"flag_set":
			return flags.get(condition.flag, false)
		"flag_unset":
			return not flags.get(condition.flag, false)
		"crew_state_count":
			return _count_crew_in_state(condition.state) >= condition.min_count
		"ai_trust_below":
			return _any_trust_below(condition.value)
		"ai_suspicion_above":
			return 1.0 - GameState.ai_obedience_score > condition.value
		_:
			return true


func _count_crew_in_state(state: String) -> int:
	var count: int = 0
	for crew_id in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive and crew.current_state == state:
			count += 1
	return count


func _any_trust_below(threshold: float) -> bool:
	for crew_id in GameState.crew:
		if GameState.get_ai_trust(crew_id) < threshold:
			return true
	return false
