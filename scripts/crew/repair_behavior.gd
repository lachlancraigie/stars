class_name RepairBehavior
extends Node

# Crew-side decision of WHETHER to start repairing a damaged ship system. This lives in
# crew-behaviour space (not scripts/ai/) per Architecture Rule 1 and the overhaul spec's
# explicit instruction: "the AI-repair decision happens in crew behavior/directive
# evaluation space, not scripts/ai/ setting crew state." RepairModel (scripts/ship/) only
# resolves a job that has already been started here.
#
# An eligible crew member is one with a relevant skill (see RepairModel.REPAIR_SKILLS)
# who is currently IN the target system's room — the player has to actually get an
# engineer-type crew member to the ai_core/life_support/engine_room for repairs to begin,
# which gives the existing directive system (DirectiveMenu "go to <room>") real stakes.
#
# ai_core repairs are additionally trust-gated (spec: "if average crew trust is too low,
# they refuse/delay") — reactor/life_support are not, since nothing in the spec asks for
# that and ungating them avoids a reactor-down/no-trust soft-lock.

const CONSIDER_INTERVAL: float = 5.0
const AI_CORE_TRUST_THRESHOLD: float = 0.35

var _timer: float = 0.0


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)


func _on_tick(_elapsed: float, delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CONSIDER_INTERVAL
	_consider("reactor", "engine_room", false)
	_consider("life_support", "life_support", false)
	_consider("ai_core", "ai_core", true)


func _consider(target_id: String, room_type: String, trust_gated: bool) -> void:
	if not _needs_repair(target_id):
		return
	if GameState.is_being_repaired(target_id):
		return
	if trust_gated and _average_trust() < AI_CORE_TRUST_THRESHOLD:
		EventBus.repair_refused.emit(target_id, "low_trust")
		return
	var room_id: String = GameState.get_room_of_type(room_type)
	if room_id == "":
		return
	var engineer: CrewMember = _find_eligible_crew(target_id, room_id)
	if engineer == null:
		return
	GameState.start_repair_job(target_id, engineer.crew_id)


func _needs_repair(target_id: String) -> bool:
	return RepairModel.is_damaged(target_id)


func _find_eligible_crew(target_id: String, room_id: String) -> CrewMember:
	var skills: Array = RepairModel.REPAIR_SKILLS.get(target_id, [])
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew == null or not crew.is_alive or crew.location != room_id:
			continue
		if crew.current_state == CrewStateMachine.INCAPACITATED or crew.current_state == CrewStateMachine.FROZEN:
			continue
		if crew.best_skill_bonus(skills) > 0:
			return crew
	return null


func _average_trust() -> float:
	if GameState.ai_trust_scores.is_empty():
		return 0.5
	var total: float = 0.0
	for crew_id in GameState.ai_trust_scores:
		total += GameState.ai_trust_scores[crew_id]
	return total / GameState.ai_trust_scores.size()
