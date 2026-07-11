class_name RepairModel
extends RefCounted

# Generic repair-job resolver for the three repairable ship systems (reactor, life_support,
# ai_core). GameState.repair_jobs holds the authoritative {target_id -> {crew_id,
# elapsed_since_check, progress}} state; WHETHER a job gets started is a crew-behaviour
# decision (see scripts/crew/repair_behavior.gd — trust-gated for ai_core per the overhaul
# spec) — this file only resolves an already-started job tick by tick via Checks, the one
# roll-resolution utility, so repair rolls gain Stress-on-failure/Panic-on-crit-fail for
# free like every other check in the game.

const CHECK_INTERVAL: float = 4.0          # seconds between repair-roll attempts
const PROGRESS_ON_SUCCESS: float = 18.0
const PROGRESS_ON_CRIT_SUCCESS: float = 45.0
const PROGRESS_ON_FAILURE: float = 0.0
const SETBACK_ON_CRIT_FAILURE: float = 12.0

# Skills a crew member can bring to bear on each target, checked via Intellect
# (docs/rules.md: Engineering/Robotics/Cybernetics/AI are all Intellect-adjacent Master
# skills; Mechanical Repair/Jury-Rigging are the Expert/Trained rungs under them).
const REPAIR_SKILLS: Dictionary = {
	"reactor":      ["Engineering", "Mechanical Repair", "Jury-Rigging", "Industrial Equipment"],
	"life_support":  ["Engineering", "Mechanical Repair", "Jury-Rigging", "Industrial Equipment"],
	"ai_core":      ["Artificial Intelligence", "Engineering", "Robotics", "Cybernetics", "Mechanical Repair"],
	# Shuttle (docs/mission-system-spec.md §7): hull damage from away-op strain beats,
	# repaired with the same mechanical skill family as the reactor/life-support.
	"shuttle":      ["Engineering", "Mechanical Repair", "Jury-Rigging", "Industrial Equipment"],
}


# Whether `target_id` currently needs repair — the single authority both RepairBehavior's
# autonomous consideration and EnvironmentMenu's "click damaged equipment" hit-test read,
# so a UI-visible Repair option and the crew's own willingness to start a job never disagree
# about what counts as "damaged" (overhaul spec: "Only show Repair on things RepairModel
# considers damaged/repairable").
static func is_damaged(target_id: String) -> bool:
	match target_id:
		"reactor":
			return not GameState.reactor_online
		"life_support":
			return not GameState.life_support_online
		"ai_core":
			return GameState.ai_core_status != "online"
		"shuttle":
			# ShuttleSystem is a Node MissionManager creates unconditionally in its own
			# _ready() (regardless of mission_mode), so this is always safe to read — see
			# shuttle_system.gd's class doc.
			return MissionManager.shuttle_system != null and MissionManager.shuttle_system.shuttle_hull < 100.0
		_:
			return false


static func tick(delta: float) -> void:
	for target_id: String in GameState.repair_jobs.keys():
		_tick_job(target_id, delta)


static func _tick_job(target_id: String, delta: float) -> void:
	var job: Dictionary = GameState.repair_jobs.get(target_id, {})
	if job.is_empty():
		return
	var crew: CrewMember = GameState.crew.get(job.get("crew_id", ""), null) as CrewMember
	if crew == null or not crew.is_alive:
		GameState.cancel_repair_job(target_id)
		return

	job["elapsed_since_check"] = float(job.get("elapsed_since_check", 0.0)) + delta
	if float(job["elapsed_since_check"]) < CHECK_INTERVAL:
		return
	job["elapsed_since_check"] = 0.0

	# Named skill (not folded into extra_bonus) — see door.gd's identical comment; needed
	# for crew-progression's crit tally and correct Loss of Confidence / Set in Their Ways.
	var skill_name: String = crew.best_skill_name(REPAIR_SKILLS.get(target_id, []))
	var item_bonus: int = int(crew.item_bonus("repair_bonus")) + int(crew.trait_bonus("repair_bonus"))
	# Overseer mercy knob (docs/director-spec.md §4): +5 max, hard-capped by
	# ScenarioDirector itself — never visible to the player, never announced.
	var mercy_bonus: int = int(ScenarioDirector.modifiers.get("check_bonus", 0))
	var result: Checks.CheckResult = Checks.perform_check(crew, "intellect", skill_name, false, false, item_bonus + mercy_bonus)

	var progress_delta: float = 0.0
	if result.critical_success():
		progress_delta = PROGRESS_ON_CRIT_SUCCESS
	elif result.success:
		progress_delta = PROGRESS_ON_SUCCESS
	elif result.critical_failure():
		progress_delta = -SETBACK_ON_CRIT_FAILURE
	else:
		progress_delta = PROGRESS_ON_FAILURE

	var progress: float = clampf(float(job.get("progress", 0.0)) + progress_delta, 0.0, 100.0)
	job["progress"] = progress
	GameState.repair_jobs[target_id] = job
	EventBus.repair_progress.emit(target_id, crew.crew_id, progress)

	if progress >= 100.0:
		_complete(target_id, crew)


static func _complete(target_id: String, crew: CrewMember) -> void:
	GameState.cancel_repair_job(target_id)
	match target_id:
		"reactor":
			GameState.set_reactor_online(true)
		"life_support":
			GameState.set_life_support_online(true)
		"ai_core":
			GameState.restart_ai_core_manual()
			GameState.repair_ai_core(100.0)
		"shuttle":
			if MissionManager.shuttle_system != null:
				MissionManager.shuttle_system.repair_hull(100.0)
	EventBus.repair_success.emit(target_id, crew.crew_id)
