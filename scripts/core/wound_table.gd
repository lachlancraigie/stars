class_name WoundTable
extends RefCounted

# Mothership 1e Wounds Table + Death Save (docs/rules.md "Wounds Table" / "Death Save").
# A Wound is gained whenever Health reaches 0 or below (see CrewMember.apply_damage).
# Roll 1d10 (rows 00-09) on the column matching the weapon/hazard's wound type.
#
# Faithfulness note: the numeric/mechanical portion of every cell (Bleeding, Stress,
# stat penalties, Death Save timing) is transcribed exactly from rules.md. Purely
# descriptive flavour ("Awesome scar", "Sprained ankle") is kept as `text` for logging/
# dialogue but most cells collapse their "[-] on X" clause into a single `tag` condition
# string rather than a bespoke timed-disadvantage system per row — durations for those
# ("until wiped", "until catch breath") are undefined in the rulebook itself (Warden
# discretion), so they're modelled as a persistent Condition needing treatment, consistent
# with how the Panic Table's own Conditions are handled. Flagged `warden_arbitration` per
# the rules.md instruction where a cell describes something anatomically organ-specific
# that shouldn't apply as flavour text to an Android.

const ROUND_SECONDS: float = 10.0

const BLUNT: String = "blunt_force"
const BLEEDING: String = "bleeding"
const GUNSHOT: String = "gunshot"
const FIRE: String = "fire_explosives"
const GORE: String = "gore_massive"
const WOUND_TYPES: Array[String] = [BLUNT, BLEEDING, GUNSHOT, FIRE, GORE]

# death_save field: "" (none) | "delayed" | "immediate" | "instant_death"
static var TABLE: Array = [
	{ # 00 - Flesh Wound
		BLUNT:     {"severity": "flesh_wound", "text": "Knocked down", "tag": "knocked_down"},
		BLEEDING:  {"severity": "flesh_wound", "text": "Drop held item", "tag": "dropped_item"},
		GUNSHOT:   {"severity": "flesh_wound", "text": "Grazed, knocked down", "tag": "knocked_down"},
		FIRE:      {"severity": "flesh_wound", "text": "Hair burnt, gain 1d5 Stress", "stress_d5": true, "warden_arbitration": true},
		GORE:      {"severity": "flesh_wound", "text": "Vomit, [-] on next action", "tag": "disadvantage_next_action", "warden_arbitration": true},
	},
	{ # 01 - Minor Injury
		BLUNT:     {"severity": "minor_injury", "text": "Winded, [-] until catch breath", "tag": "disadvantage_temp"},
		BLEEDING:  {"severity": "minor_injury", "text": "Lots of blood, Close crew gain 1 Stress", "close_crew_stress": 1},
		GUNSHOT:   {"severity": "minor_injury", "text": "Bleeding +1", "bleeding_add": 1},
		FIRE:      {"severity": "minor_injury", "text": "Awesome scar, +1 Min Stress", "min_stress_add": 1},
		GORE:      {"severity": "minor_injury", "text": "Awesome scar, +1 Min Stress", "min_stress_add": 1},
	},
	{ # 02 - Minor Injury
		BLUNT:     {"severity": "minor_injury", "text": "Sprained ankle, [-] Speed Checks", "tag": "disadvantage_speed"},
		BLEEDING:  {"severity": "minor_injury", "text": "Blood in eyes, [-] until wiped", "tag": "disadvantage_temp"},
		GUNSHOT:   {"severity": "minor_injury", "text": "Broken rib", "tag": "broken_rib"},
		FIRE:      {"severity": "minor_injury", "text": "Singed, [-] next action", "tag": "disadvantage_next_action"},
		GORE:      {"severity": "minor_injury", "text": "Digit mangled", "tag": "digit_mangled", "warden_arbitration": true},
	},
	{ # 03 - Minor Injury
		BLUNT:     {"severity": "minor_injury", "text": "Concussion, [-] mental tasks", "tag": "disadvantage_mental"},
		BLEEDING:  {"severity": "minor_injury", "text": "Laceration, Bleeding +1", "bleeding_add": 1},
		GUNSHOT:   {"severity": "minor_injury", "text": "Fractured extremity", "tag": "fractured_extremity"},
		FIRE:      {"severity": "minor_injury", "text": "Shrapnel/large burn", "tag": "large_burn"},
		GORE:      {"severity": "minor_injury", "text": "Eyes gouged out", "tag": "blinded", "warden_arbitration": true},
	},
	{ # 04 - Minor Injury
		BLUNT:     {"severity": "minor_injury", "text": "Leg/foot broken, [-] Speed Checks", "tag": "disadvantage_speed"},
		BLEEDING:  {"severity": "minor_injury", "text": "Major cut, Bleeding +2", "bleeding_add": 2},
		GUNSHOT:   {"severity": "minor_injury", "text": "Internal bleeding, Bleeding +2", "bleeding_add": 2},
		FIRE:      {"severity": "minor_injury", "text": "Extensive burns, -1d10 Strength", "stat_penalty": "strength", "stat_penalty_dice": 1},
		GORE:      {"severity": "minor_injury", "text": "Ripped off flesh, -1d10 Strength", "stat_penalty": "strength", "stat_penalty_dice": 1, "warden_arbitration": true},
	},
	{ # 05 - Major Injury
		BLUNT:     {"severity": "major_injury", "text": "Arm/hand broken, [-] manual tasks", "tag": "disadvantage_manual"},
		BLEEDING:  {"severity": "major_injury", "text": "Fingers/toes severed, Bleeding +3", "bleeding_add": 3, "warden_arbitration": true},
		GUNSHOT:   {"severity": "major_injury", "text": "Lodged bullet, Surgery required", "tag": "surgery_required"},
		FIRE:      {"severity": "major_injury", "text": "Major burn, -2d10 Body Save", "stat_penalty": "body", "stat_penalty_dice": 2},
		GORE:      {"severity": "major_injury", "text": "Paralysed waist down", "tag": "paralysed", "warden_arbitration": true},
	},
	{ # 06 - Major Injury
		BLUNT:     {"severity": "major_injury", "text": "Snapped collarbone, [-] Strength Checks", "tag": "disadvantage_strength"},
		BLEEDING:  {"severity": "major_injury", "text": "Hand/foot severed, Bleeding +4", "bleeding_add": 4, "warden_arbitration": true},
		GUNSHOT:   {"severity": "major_injury", "text": "Gunshot wound to neck", "tag": "neck_wound"},
		FIRE:      {"severity": "major_injury", "text": "Skin grafts required, -2d10 Body Save", "stat_penalty": "body", "stat_penalty_dice": 2},
		GORE:      {"severity": "major_injury", "text": "Limb severed, Bleeding +5", "bleeding_add": 5, "warden_arbitration": true},
	},
	{ # 07 - Lethal Injury (Death Save in 1d10 rounds)
		BLUNT:     {"severity": "lethal_injury", "text": "Back broken, [-] all rolls", "tag": "disadvantage_all", "death_save": "delayed"},
		BLEEDING:  {"severity": "lethal_injury", "text": "Limb severed, Bleeding +5", "bleeding_add": 5, "death_save": "delayed", "warden_arbitration": true},
		GUNSHOT:   {"severity": "lethal_injury", "text": "Major blood loss, Bleeding +4", "bleeding_add": 4, "death_save": "delayed"},
		FIRE:      {"severity": "lethal_injury", "text": "Limb on fire, 2d10 DMG/round", "tag": "burning_dot", "death_save": "delayed"},
		GORE:      {"severity": "lethal_injury", "text": "Impaled, Bleeding +6", "bleeding_add": 6, "death_save": "delayed"},
	},
	{ # 08 - Lethal Injury (Death Save in 1d10 rounds)
		BLUNT:     {"severity": "lethal_injury", "text": "Skull fracture, [-] all rolls", "tag": "disadvantage_all", "death_save": "delayed"},
		BLEEDING:  {"severity": "lethal_injury", "text": "Major artery cut, Bleeding +6", "bleeding_add": 6, "death_save": "delayed"},
		GUNSHOT:   {"severity": "lethal_injury", "text": "Sucking chest wound, Bleeding +5", "bleeding_add": 5, "death_save": "delayed"},
		FIRE:      {"severity": "lethal_injury", "text": "Body on fire, 3d10 DMG/round", "tag": "burning_dot_heavy", "death_save": "delayed"},
		GORE:      {"severity": "lethal_injury", "text": "Guts spooled on floor, Bleeding +7", "bleeding_add": 7, "death_save": "delayed", "warden_arbitration": true},
	},
	{ # 09 - Fatal Injury (Death Save)
		BLUNT:     {"severity": "fatal_injury", "text": "Spine/neck broken, Death Save", "death_save": "immediate"},
		BLEEDING:  {"severity": "fatal_injury", "text": "Throat slit or heart pierced, Death Save", "death_save": "immediate", "warden_arbitration": true},
		GUNSHOT:   {"severity": "fatal_injury", "text": "Headshot, Death Save", "death_save": "immediate"},
		FIRE:      {"severity": "fatal_injury", "text": "Engulfed in fiery explosion, Death Save", "death_save": "immediate"},
		GORE:      {"severity": "fatal_injury", "text": "Head explodes. No Death Save. You have died.", "death_save": "instant_death", "warden_arbitration": true},
	},
]


# Rolls a Wound and applies its full mechanical effect to `crew`. Returns the
# resolved cell (for logging/dialogue) with `row` added.
static func roll_and_apply(crew: CrewMember, wound_type: String) -> Dictionary:
	var row: int = randi_range(0, 9)
	var cell: Dictionary = (TABLE[row].get(wound_type, TABLE[row][BLUNT]) as Dictionary).duplicate()
	cell["row"] = row

	crew.wounds += 1
	crew.bleeding_per_round += int(cell.get("bleeding_add", 0))
	crew.min_stress += int(cell.get("min_stress_add", 0))
	if cell.get("stress_d5", false):
		crew.add_stress(Checks.roll_d10() % 5 + 1)
	if cell.has("stat_penalty"):
		var amount: int = Checks.roll_d10s(int(cell.get("stat_penalty_dice", 1)))
		crew.apply_stat_penalty(String(cell["stat_penalty"]), amount)
	if cell.get("close_crew_stress", 0) > 0:
		for crew_id: String in GameState.crew:
			var other: CrewMember = GameState.crew[crew_id] as CrewMember
			if other != null and other != crew and other.is_alive:
				other.add_stress(int(cell["close_crew_stress"]))
	var tag: String = String(cell.get("tag", ""))
	if tag != "" and tag not in crew.conditions:
		crew.conditions.append(tag)

	EventBus.crew_injury.emit(crew.crew_id, String(cell.get("severity", "")), wound_type)

	if cell.get("death_save") == "instant_death":
		CrewLifecycle.kill(crew, "gore_massive_fatal")
	elif cell.get("death_save") == "immediate":
		death_save(crew)
	elif cell.get("death_save") == "delayed":
		crew.death_save_at = TimeManager.elapsed + Checks.roll_d10() * ROUND_SECONDS
		crew.death_save_mode = "pending_save"

	# Hitting Max Wounds forces a Death Save regardless of the column result
	# (rules.md "Damage flow" step 3), unless the column already ended the
	# character outright.
	if crew.is_alive and crew.wounds >= crew.max_wounds and cell.get("death_save", "") not in ["instant_death", "immediate"]:
		death_save(crew)

	return cell


# Death Save (rules.md "Death Save"). Returns the outcome string.
static func death_save(crew: CrewMember) -> String:
	if not crew.is_alive:
		return "dead"
	# current_state is deliberately NOT set directly here — CrewStateMachine.evaluate()
	# (polled once per tick by CrewSystem) already returns INCAPACITATED whenever
	# unconscious_until/death_save_at/"comatose" apply, and routing the transition through
	# that normal per-tick evaluation (rather than mutating current_state inline) is what
	# makes CrewSystem emit crew_state_changed with a correct old_state — see the FROZEN/
	# INCAPACITATED checks added to CrewStateMachine.evaluate() for this rewrite.
	var roll: int = randi_range(0, 9)
	if roll == 0:
		crew.unconscious_until = TimeManager.elapsed + Checks.roll_d10s(2) * 6.0  # 2d10 min, compressed
		crew.max_health = maxi(1, crew.max_health - (Checks.roll_d10() % 5 + 1))
		return "unconscious"
	elif roll <= 2:
		crew.death_save_at = TimeManager.elapsed + (Checks.roll_d10() % 5 + 1) * ROUND_SECONDS
		crew.death_save_mode = "dying"
		if "dying" not in crew.conditions:
			crew.conditions.append("dying")
		return "unconscious_dying"
	elif roll <= 4:
		if "comatose" not in crew.conditions:
			crew.conditions.append("comatose")
		return "comatose"
	else:
		CrewLifecycle.kill(crew, "death_save_failed")
		return "dead"


# Resolves an expired death_save_at clock. Called once per crew per tick from
# CrewSystem. "dying" clocks kill outright without intervention; "pending_save"
# clocks roll a fresh Death Save (rules.md: Lethal Injury rows "Death Save in 1d10
# rounds").
static func tick_death_clock(crew: CrewMember) -> void:
	if not crew.is_alive or crew.death_save_at < 0.0 or TimeManager.elapsed < crew.death_save_at:
		return
	var mode: String = crew.death_save_mode
	crew.death_save_at = -1.0
	crew.death_save_mode = ""
	if mode == "dying":
		CrewLifecycle.kill(crew, "died_without_intervention")
	elif mode == "pending_save":
		death_save(crew)


# Called when a dying/unconscious crew member reaches safety/treatment before
# their death_save_at clock expires (stub hook — full medical-care minigame is
# out of scope; Field Medicine/Surgery skill checks can call this).
static func stabilize(crew: CrewMember) -> void:
	crew.death_save_at = -1.0
	crew.death_save_mode = ""
	crew.conditions.erase("dying")
