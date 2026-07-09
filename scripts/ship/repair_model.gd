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
}


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

	var skill_bonus: int = crew.best_skill_bonus(REPAIR_SKILLS.get(target_id, []))
	var item_bonus: int = int(crew.item_bonus("repair_bonus"))
	var result: Checks.CheckResult = Checks.perform_check(crew, "intellect", "", false, false, skill_bonus + item_bonus)

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
	EventBus.repair_success.emit(target_id, crew.crew_id)
