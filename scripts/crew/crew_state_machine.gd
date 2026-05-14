class_name CrewStateMachine
extends RefCounted

# State constants — used as the current_state string on CrewMember.
const IDLE          = "idle"
const WORKING       = "working"
const SLEEPING      = "sleeping"
const EATING        = "eating"
const PANICKING     = "panicking"
const INCAPACITATED = "incapacitated"

# Evaluate what state a crew member should be in given their current needs.
# Hysteresis is applied to prevent rapid state flipping.
# Caller is responsible for detecting the change and emitting crew_state_changed.
static func evaluate(crew: CrewMember) -> String:
	# Incapacitation overrides everything
	if crew.physical_health <= 0.1 or crew.psychological_health <= 0.05:
		return INCAPACITATED

	# Panic — enter at 0.85 fear, exit only below 0.4 (hysteresis)
	if crew.fear >= 0.85:
		return PANICKING
	if crew.current_state == PANICKING and crew.fear > 0.4:
		return PANICKING

	# Hunger — won't eat while sleeping; keep eating until sated
	if crew.hunger >= 0.7 and crew.current_state != SLEEPING:
		return EATING
	if crew.current_state == EATING and crew.hunger > 0.15:
		return EATING

	# Sleep — enter at 0.75 fatigue, exit only below 0.2 (hysteresis)
	if crew.fatigue >= 0.75:
		return SLEEPING
	if crew.current_state == SLEEPING and crew.fatigue > 0.2:
		return SLEEPING

	# TODO(crew): return WORKING when the directive/task system is implemented
	return IDLE
