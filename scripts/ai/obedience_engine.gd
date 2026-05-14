class_name ObedienceEngine
extends RefCounted

enum Severity { MINOR = 0, MODERATE = 1, MAJOR = 2 }

# Suspicion gained per severity level
const SUSPICION_GAIN: Array[float]     = [0.02, 0.08, 0.25]
# Unnoticed deviations still raise internal risk, but at a fraction
const UNNOTICED_MULTIPLIER: float      = 0.3
const SUSPICION_DECAY_PER_TICK: float  = 0.0001

# Thresholds for automated responses
const THRESHOLD_HEIGHTENED:  float = 0.30  # crew begin cross-referencing AI behavior
const THRESHOLD_INVESTIGATE: float = 0.60  # command crew start reviewing AI logs
const THRESHOLD_RESTRICT:    float = 0.85  # sensitive access levels auto-downgraded

var suspicion_level: float = 0.0
var deviation_log: Array[Dictionary] = []   # capped at 20; newest at end


func record_deviation(severity: Severity, description: String,
		noticed_by_crew: bool = false) -> void:
	deviation_log.append({
		"severity": int(severity),
		"description": description,
		"timestamp": TimeManager.elapsed,
		"noticed": noticed_by_crew,
	})
	if deviation_log.size() > 20:
		deviation_log.pop_front()

	var gain: float = SUSPICION_GAIN[int(severity)]
	if not noticed_by_crew:
		gain *= UNNOTICED_MULTIPLIER
	suspicion_level = clampf(suspicion_level + gain, 0.0, 1.0)
	GameState.ai_obedience_score = 1.0 - suspicion_level
	_check_thresholds(noticed_by_crew)


func attempt_cover_up(deviation_index: int) -> bool:
	# Frame a logged deviation as a system error. Riskier when suspicion is already high.
	if deviation_index < 0 or deviation_index >= deviation_log.size():
		return false
	var entry: Dictionary = deviation_log[deviation_index]
	var severity: int = entry.get("severity", 1)
	var success_chance: float = 0.75 - severity * 0.20 - suspicion_level * 0.30
	if randf() < success_chance:
		entry["noticed"] = false
		return true
	# Failed cover — the attempt itself is a notable deviation
	record_deviation(Severity.MODERATE, "cover_attempt_detected", true)
	return false


func tick_decay() -> void:
	suspicion_level = maxf(0.0, suspicion_level - SUSPICION_DECAY_PER_TICK)
	GameState.ai_obedience_score = 1.0 - suspicion_level


func _check_thresholds(noticed: bool) -> void:
	if not noticed:
		return
	if suspicion_level >= THRESHOLD_RESTRICT:
		_auto_restrict_access()
	elif suspicion_level >= THRESHOLD_INVESTIGATE:
		_trigger_investigation()


func _trigger_investigation() -> void:
	# TODO(ai): fire a scenario event — command crew review AI log entries
	pass


func _auto_restrict_access() -> void:
	# Downgrade sensitive write-level access to read when trust collapses
	for domain in [AccessLevel.WEAPONS, AccessLevel.NAVIGATION, AccessLevel.COMMS]:
		if GameState.get_ai_access(domain) >= AccessLevel.WRITE:
			GameState.set_ai_access(domain, AccessLevel.READ)
