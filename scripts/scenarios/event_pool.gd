class_name EventPool
extends RefCounted

# Weighted draw from a pool of ScenarioEvents filtered by tone and conditions.
#
# Overseer knob hooks (docs/director-spec.md §4/§6): cooldowns and crisis-event
# weights read a single shared surface, ScenarioDirector.modifiers, rather than
# each maintaining separate pressure/mercy logic — "no scattered special cases".
# An event counts as a "crisis" event (eligible for the crisis_weight_mult knob)
# if any of its outcomes are one of CRISIS_OUTCOME_TYPES; this is a generic,
# content-agnostic classification so future scenarios opt in for free just by
# using those outcome types.

const CRISIS_OUTCOME_TYPES: Array[String] = [
	"reactor_failure", "life_support_failure", "ai_core_damage", "ship_destroyed", "crew_fear_spike",
]

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
	var cooldown_mult: float = float(ScenarioDirector.modifiers.get("cooldown_mult", 1.0))
	for event in _events:
		if event.one_shot and event.has_fired:
			continue
		if elapsed < event.min_elapsed:
			continue
		if elapsed - event.last_fired < event.cooldown * cooldown_mult:
			continue
		if tone < event.tone_min or tone > event.tone_max:
			continue
		if not _conditions_met(event, flags):
			continue
		result.append(event)
	return result


func _weighted_pick(eligible: Array[ScenarioEvent]) -> ScenarioEvent:
	var weights: Array[float] = []
	var total_weight: float = 0.0
	for event in eligible:
		var w: float = _effective_weight(event)
		weights.append(w)
		total_weight += w
	var roll: float = randf() * total_weight
	var cumulative: float = 0.0
	for i in eligible.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return eligible[i]
	return eligible.back()


# Crisis-flagged events get the Overseer's crisis_weight_mult; everything else
# draws at its authored weight, unmodified.
func _effective_weight(event: ScenarioEvent) -> float:
	if not _is_crisis_event(event):
		return event.weight
	return event.weight * float(ScenarioDirector.modifiers.get("crisis_weight_mult", 1.0))


func _is_crisis_event(event: ScenarioEvent) -> bool:
	for outcome in event.outcomes:
		if String(outcome.get("type", "")) in CRISIS_OUTCOME_TYPES:
			return true
	return false


func _conditions_met(event: ScenarioEvent, flags: Dictionary) -> bool:
	for condition in event.conditions:
		if not _check_condition(condition, flags):
			return false
	return true


func _check_condition(condition: Dictionary, flags: Dictionary) -> bool:
	return check_condition(condition, flags)


# Shared condition-checker (docs/mission-system-spec.md §5 — "New conditions" table).
# Static so GenericScenarioMonitor's watches (engine task D) read the EXACT same
# vocabulary this pool's own eligibility filter does, without needing a live EventPool
# instance. Every new type is guarded to degrade to `false` rather than error if the
# autoload it reads (MissionManager/IntruderSystem) hasn't finished booting yet —
# both are always-registered autoloads today, so this is defensive, not load-bearing.
static func check_condition(condition: Dictionary, flags: Dictionary) -> bool:
	match String(condition.get("type", "")):
		"resource_below":
			return GameState.get_metric(condition.resource) < float(condition.value)
		"resource_above":
			return GameState.get_metric(condition.resource) > float(condition.value)
		"flag_set":
			return flags.get(condition.flag, false)
		"flag_unset":
			return not flags.get(condition.flag, false)
		"crew_state_count":
			return _count_crew_in_state(condition.state) >= int(condition.min_count)
		"ai_trust_below":
			return _any_trust_below(float(condition.value))
		"ai_suspicion_above":
			return 1.0 - GameState.ai_obedience_score > float(condition.value)
		"crew_has_skill":
			return _any_crew_has_skill(String(condition.get("skill", "")), String(condition.get("tier", "")))
		"item_aboard":
			return _item_aboard(String(condition.get("item_id", "")))
		"mission_phase":
			return is_instance_valid(MissionManager) and MissionManager.mission_phase == String(condition.get("phase", ""))
		"away_team_out":
			return _away_team_out()
		"crew_status_any":
			return GameState.any_crew_status(String(condition.get("flag", "")))
		"intruder_present":
			return is_instance_valid(IntruderSystem) and not IntruderSystem.active_intruders().is_empty()
		"docked":
			return is_instance_valid(MissionManager) and MissionManager.is_docked()
		"leg_at_least":
			return ScenarioDirector.current_leg >= int(condition.get("leg", 0))
		"crew_count_below":
			return _living_crew_count() < int(condition.get("value", 0))
		"hull_below":
			return GameState.hull_integrity < float(condition.get("value", 0.0))
		_:
			return true


static func _count_crew_in_state(state: String) -> int:
	var count: int = 0
	for crew_id in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive and crew.current_state == state:
			count += 1
	return count


static func _any_trust_below(threshold: float) -> bool:
	for crew_id in GameState.crew:
		if GameState.get_ai_trust(crew_id) < threshold:
			return true
	return false


const SKILL_TIER_RANK: Dictionary = {"": 0, "Trained": 1, "Expert": 2, "Master": 3}


static func _any_crew_has_skill(skill: String, tier: String) -> bool:
	if skill == "":
		return false
	var min_rank: int = int(SKILL_TIER_RANK.get(tier, 0))
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew == null or not crew.is_alive:
			continue
		var have_tier: String = String(crew.skills.get(skill, ""))
		if have_tier == "":
			continue
		if int(SKILL_TIER_RANK.get(have_tier, 0)) >= min_rank:
			return true
	return false


static func _item_aboard(item_id: String) -> bool:
	if item_id == "":
		return false
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive and not crew.off_ship and item_id in crew.inventory:
			return true
	return false


static func _away_team_out() -> bool:
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive and crew.off_ship:
			return true
	return false


static func _living_crew_count() -> int:
	var count: int = 0
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive:
			count += 1
	return count
