class_name Checks
extends RefCounted

# Mothership 1e roll-resolution utility (docs/rules.md "Implementation Notes for Code" +
# "Stat Checks" / "Saves" / "Panic Checks"). ALL skill/stat/save-gated actions in the game
# should resolve through perform_check() (or the lower-level stat_check() if no CrewMember
# is available, e.g. contractor/NPC rolls) rather than hand-rolling randf() comparisons —
# this is the one place doubles/90-99/00/stress/panic wiring lives.

const TIER_BONUS: Dictionary = {"Trained": 10, "Expert": 15, "Master": 20}

const STATS: Array[String] = ["strength", "speed", "intellect", "combat"]
const SAVES: Array[String] = ["sanity", "fear", "body"]


class CheckResult:
	var roll: int
	var target: int
	var success: bool
	var critical: bool
	var advantage: bool
	var disadvantage: bool

	func _init(p_roll: int, p_target: int, p_success: bool, p_critical: bool,
			p_advantage: bool = false, p_disadvantage: bool = false) -> void:
		roll = p_roll
		target = p_target
		success = p_success
		critical = p_critical
		advantage = p_advantage
		disadvantage = p_disadvantage

	func critical_success() -> bool:
		return critical and success

	func critical_failure() -> bool:
		return critical and not success


# --- Dice primitives ---

static func roll_d10() -> int:
	return randi_range(1, 10)


static func roll_d10s(count: int) -> int:
	var total: int = 0
	for _i in count:
		total += roll_d10()
	return total


static func roll_d100() -> int:
	# Two d10s, tens + ones. Each d10 reads 0-9 here (00 is a valid tens digit,
	# 0 a valid ones digit) so the combined range is 0-99 with 00+0 = 0, matching
	# the rulebook's percentile convention exactly.
	return (randi_range(0, 9) * 10) + randi_range(0, 9)


static func roll_panic_die() -> int:
	return randi_range(1, 20)


static func roll_stat_block() -> int:
	return roll_d10s(2) + 25


static func roll_save_block() -> int:
	return roll_d10s(2) + 10


static func roll_max_health() -> int:
	return roll_d10() + 10


# --- Advantage/disadvantage ---

# Multiple sources of [+]/[-] cancel out net-to-net rather than stacking
# ("Advantage and Disadvantage cancel each other out (net zero regardless of
# multiples)" — rules.md). Callers that accumulate several sources should tally
# counts and call this before rolling.
static func net_advantage(advantage_sources: int, disadvantage_sources: int) -> Dictionary:
	var net: int = advantage_sources - disadvantage_sources
	return {"advantage": net > 0, "disadvantage": net < 0}


static func _roll_target_d100(advantage: bool, disadvantage: bool) -> int:
	if advantage and not disadvantage:
		return mini(roll_d100(), roll_d100())
	elif disadvantage and not advantage:
		return maxi(roll_d100(), roll_d100())
	return roll_d100()


# --- Core roll-resolution pattern (rules.md pseudocode, ported 1:1) ---

static func stat_check(stat_value: int, skill_bonus: int = 0,
		advantage: bool = false, disadvantage: bool = false) -> CheckResult:
	var effective_target: int = stat_value + skill_bonus
	var roll: int = _roll_target_d100(advantage, disadvantage)

	# 90-99 always fails, regardless of stat value.
	if roll >= 90:
		return CheckResult.new(roll, effective_target, false, roll == 99, advantage, disadvantage)
	# 00 is always a Critical Success.
	if roll == 0:
		return CheckResult.new(roll, effective_target, true, true, advantage, disadvantage)
	# Doubles are Criticals (success-doubles = crit success, failure-doubles = crit failure).
	var is_double: bool = (roll / 10) == (roll % 10)
	var success: bool = roll < effective_target
	return CheckResult.new(roll, effective_target, success, is_double, advantage, disadvantage)


# Saves use the identical mechanic against a Save value — kept as a distinctly
# named wrapper so call sites read clearly (a Save check vs a Stat check).
static func save_check(save_value: int, skill_bonus: int = 0,
		advantage: bool = false, disadvantage: bool = false) -> CheckResult:
	return stat_check(save_value, skill_bonus, advantage, disadvantage)


# High-level entry point: resolves a check against a live CrewMember, applying
# Stress gain on failure and triggering a Panic Check on a Critical Failure —
# exactly the two rules.md side effects every gated action needs. `stat_name`
# is one of Checks.STATS or Checks.SAVES. `skill_name`, if given, looks up the
# crew's own skill tier bonus (see CrewMember.get_skill_bonus). Environmental
# disadvantage (thin air — see LifeSupportModel) is folded in automatically
# whenever a CrewMember is supplied, since this is the one utility everything
# routes through.
static func perform_check(crew: CrewMember, stat_name: String, skill_name: String = "",
		advantage: bool = false, disadvantage: bool = false, extra_bonus: int = 0) -> CheckResult:
	var value: int = crew.get_stat_or_save(stat_name)
	var bonus: int = (crew.get_skill_bonus(skill_name) if skill_name != "" else 0) + extra_bonus
	var net: Dictionary = net_advantage(
		int(advantage or crew.has_environmental_advantage()),
		int(disadvantage or crew.has_environmental_disadvantage()))
	var result: CheckResult = stat_check(value, bonus, net.advantage, net.disadvantage)

	if not result.success:
		crew.add_stress(1)
	if result.critical_failure():
		panic_check(crew)
	return result


# --- Panic Check (d20 vs Stress) ---

static func panic_check(crew: CrewMember) -> Dictionary:
	var roll: int = roll_panic_die()
	var panicked: bool = roll <= crew.stress
	var effect: String = ""
	if panicked:
		effect = PanicTable.apply(crew, roll)
	EventBus.crew_panicked.emit(crew.crew_id, roll, effect)
	return {"roll": roll, "panicked": panicked, "effect": effect}


# --- Rest Save (Stress relief in a safe location) ---

static func rest_save(crew: CrewMember, advantage: bool = false, disadvantage: bool = false) -> Dictionary:
	var worst_save: String = crew.worst_save_name()
	var result: CheckResult = save_check(crew.get_stat_or_save(worst_save), 0, advantage, disadvantage)
	if result.success:
		crew.reduce_stress(result.roll % 10)
	else:
		crew.add_stress(1)
	return {"result": result, "worst_save": worst_save}
