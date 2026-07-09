class_name PanicTable
extends RefCounted

# Mothership 1e Panic Table (docs/rules.md "Panic Checks"). Rolled 1d20 whenever a Panic
# Check fails (roll <= current Stress) — see Checks.panic_check(). Effects are mapped onto
# existing game systems wherever a mechanical hook exists (flee -> PANICKING state, freeze ->
# a new transient FROZEN state, adrenaline -> a temporary check bonus + stress relief);
# rules that need genuine multiplayer table-talk ("range bands", "the Warden") or persistent
# character-sheet UI that doesn't exist here are stubbed as a named Condition tag on the
# crew member (visible to dialogue/UI later) plus the closest mechanical approximation.
#
# "Close" crewmembers (rules.md range-band term) has no spatial range-band model in this
# game — approximated as "every other living crew member", which is the sensible reading
# for a small-crew single-ship simulation. Flagged inline where this simplification applies.

const ADRENALINE_BONUS_SECS: float = 120.0   # 2d10 min -> compressed to a flat 2 real-time minutes
const OVERWHELMED_SECS: float = 60.0         # 1d10 min compressed similarly
const CATATONIC_SECS: float = 20.0           # 2d10 min of table-time -> a short real freeze
const RAGE_SECS: float = 90.0
const HEART_ATTACK_SECS: float = 60.0


static func apply(crew: CrewMember, roll: int) -> String:
	match roll:
		1:
			return _adrenaline_rush(crew)
		2:
			return _nervous(crew)
		3:
			return _jumpy(crew)
		4:
			return _overwhelmed(crew)
		5:
			return _tag_condition(crew, "coward")
		6:
			return _tag_condition(crew, "frightened")
		7:
			return _tag_condition(crew, "nightmares")
		8:
			return _loss_of_confidence(crew)
		9:
			return _tag_condition(crew, "deflated")
		10:
			return _tag_condition(crew, "doomed")
		11:
			return _tag_condition(crew, "suspicious")
		12:
			return _tag_condition(crew, "haunted")
		13:
			return _tag_condition(crew, "death_wish")
		14:
			return _prophetic_vision(crew)
		15:
			return _catatonic(crew)
		16:
			return _rage(crew)
		17:
			return _tag_condition(crew, "spiraling")
		18:
			return _compounding_problems(crew)
		19:
			return _heart_attack(crew)
		20:
			return _retire(crew)
		_:
			return "unknown"


static func _adrenaline_rush(crew: CrewMember) -> String:
	crew.adrenaline_until = TimeManager.elapsed + ADRENALINE_BONUS_SECS
	crew.reduce_stress(Checks.roll_d10() % 5 + 1)  # 1d5
	return "adrenaline_rush"


static func _nervous(crew: CrewMember) -> String:
	crew.add_stress(1)
	return "nervous"


static func _jumpy(crew: CrewMember) -> String:
	crew.add_stress(1)
	for other: CrewMember in _close_crew(crew):
		other.add_stress(2)
	return "jumpy"


static func _overwhelmed(crew: CrewMember) -> String:
	crew.overwhelmed_until = TimeManager.elapsed + OVERWHELMED_SECS
	crew.min_stress += 1
	return "overwhelmed"


static func _loss_of_confidence(crew: CrewMember) -> String:
	if not crew.skills.is_empty() and crew.lost_skill == "":
		crew.lost_skill = String(crew.skills.keys()[randi() % crew.skills.size()])
	crew.conditions.append("loss_of_confidence")
	return "loss_of_confidence"


static func _prophetic_vision(crew: CrewMember) -> String:
	crew.min_stress += 2
	return "prophetic_vision"


static func _catatonic(crew: CrewMember) -> String:
	crew.frozen_until = TimeManager.elapsed + CATATONIC_SECS
	crew.reduce_stress(Checks.roll_d10())
	return "catatonic"


static func _rage(crew: CrewMember) -> String:
	crew.rage_until = TimeManager.elapsed + RAGE_SECS
	for other: CrewMember in _all_crew_including(crew):
		other.add_stress(1)
	return "rage"


static func _compounding_problems(crew: CrewMember) -> String:
	crew.min_stress += 1
	# Roll twice more on this table (guard against pathological chaining by
	# excluding another compounding-problems result from the re-roll).
	for _i in 2:
		var reroll: int = Checks.roll_panic_die()
		if reroll == 18:
			reroll = 4
		apply(crew, reroll)
	return "compounding_problems"


static func _heart_attack(crew: CrewMember) -> String:
	if crew.mship_class == "Android":
		crew.conditions.append("short_circuit")
	else:
		crew.conditions.append("heart_attack")
	crew.max_wounds = maxi(1, crew.max_wounds - 1)
	crew.overwhelmed_until = TimeManager.elapsed + HEART_ATTACK_SECS
	crew.min_stress += 1
	return "heart_attack_short_circuit"


static func _retire(crew: CrewMember) -> String:
	# "Roll a new character" has no mid-scenario character-creation flow here —
	# the sensible approximation is permanent incapacitation (crew remains alive
	# but plays no further active part), distinct from death. current_state is not
	# set directly — CrewStateMachine.evaluate() already returns INCAPACITATED once
	# crew.retired is true, and routing through CrewSystem's normal per-tick
	# evaluation is what makes it emit crew_state_changed with a correct old_state.
	crew.retired = true
	return "retire"


static func _tag_condition(crew: CrewMember, tag: String) -> String:
	if tag not in crew.conditions:
		crew.conditions.append(tag)
	return tag


static func _close_crew(crew: CrewMember) -> Array[CrewMember]:
	var result: Array[CrewMember] = []
	for crew_id: String in GameState.crew:
		var other: CrewMember = GameState.crew[crew_id] as CrewMember
		if other != null and other != crew and other.is_alive:
			result.append(other)
	return result


static func _all_crew_including(crew: CrewMember) -> Array[CrewMember]:
	var result: Array[CrewMember] = _close_crew(crew)
	result.append(crew)
	return result
