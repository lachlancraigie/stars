class_name CrewGen
extends RefCounted

# Random Mothership 1e character generation (docs/rules.md "Character Stats"/"Classes"/
# "Skills"/"Health & Wounds"/"Equipment"). Seeded from GameState.ship_seed + a per-slot
# index so a given ship seed always produces the same crew (mirrors ShipLayoutGen's
# determinism contract).
#
# ARCHETYPES (docs/dialogue_spec.md "Archetype dimensions & tags"): archetypes are
# dimensional — personality (gruff/cheerful/even/paranoid) × gender (male/female) × career
# (scientist_medic/android/teamster_engineer/marine, mapping 1:1 to Mothership class) ×
# rank (captain/officer/crew_mate). Archetype JSON files under
# resources/dialogue/archetypes/ are an OPTIONAL soft dependency (owned by a parallel
# agent, READ-ONLY here; may not exist yet) — every field is looked up with a default, so
# generation works identically with zero archetype files. When an archetype matches, its
# stat_tendencies/save_tendencies are applied as flat modifiers on the standard rolls, a
# name is picked at random from names[], and preferred_skills are prioritized within the
# normal class skill rules.
#
# HARD RANK RULES (dialogue spec): every generated ship crew has EXACTLY ONE captain-rank
# member, and an Android can never be the captain.

const CLASSES: Array[String] = ["Marine", "Android", "Scientist", "Teamster"]

# Career dimension (dialogue spec) -> Mothership class, 1:1.
const CAREER_CLASS: Dictionary = {
	"scientist_medic": "Scientist",
	"android": "Android",
	"teamster_engineer": "Teamster",
	"marine": "Marine",
}

const RANKS: Array[String] = ["captain", "officer", "crew_mate"]

const CLASS_BASE_SKILLS: Dictionary = {
	"Marine": [{"skill": "Military Training", "tier": "Trained"}, {"skill": "Athletics", "tier": "Trained"}],
	"Android": [{"skill": "Linguistics", "tier": "Trained"}, {"skill": "Computers", "tier": "Trained"}, {"skill": "Mathematics", "tier": "Trained"}],
	"Teamster": [{"skill": "Industrial Equipment", "tier": "Trained"}, {"skill": "Zero-G", "tier": "Trained"}],
}

const TRAINED_SKILLS: Array[String] = [
	"Archaeology", "Art", "Athletics", "Botany", "Chemistry", "Computers", "Geology",
	"Industrial Equipment", "Jury-Rigging", "Linguistics", "Mathematics", "Military Training",
	"Rimwise", "Theology", "Zero-G", "Zoology",
]
const EXPERT_SKILLS: Array[String] = [
	"Asteroid Mining", "Ecology", "Explosives", "Field Medicine", "Firearms", "Hacking",
	"Hand-to-Hand Combat", "Mechanical Repair", "Mysticism", "Pathology", "Pharmacology",
	"Physics", "Piloting", "Psychology", "Wilderness Survival",
]
const MASTER_SKILLS: Array[String] = [
	"Artificial Intelligence", "Command", "Cybernetics", "Engineering", "Exobiology",
	"Hyperspace", "Planetology", "Robotics", "Sophontology", "Surgery", "Xenoesotericism",
]
# rules.md doesn't publish a full skill tree beyond the tier lists — this is a reasonable,
# documented simplification giving each Master skill one plausible Expert+Trained prereq
# chain for Scientist character generation ("1 Master Skill + its Expert and Trained
# prerequisites").
const MASTER_PREREQS: Dictionary = {
	"Artificial Intelligence": ["Hacking", "Computers"],
	"Command": ["Psychology", "Military Training"],
	"Cybernetics": ["Mechanical Repair", "Industrial Equipment"],
	"Engineering": ["Mechanical Repair", "Industrial Equipment"],
	"Exobiology": ["Pathology", "Botany"],
	"Hyperspace": ["Physics", "Mathematics"],
	"Planetology": ["Physics", "Geology"],
	"Robotics": ["Mechanical Repair", "Mathematics"],
	"Sophontology": ["Psychology", "Linguistics"],
	"Surgery": ["Field Medicine", "Chemistry"],
	"Xenoesotericism": ["Mysticism", "Theology"],
}

# Job-function role (drives duty stations/visuals, see CrewBehavior/CrewMemberNode) ->
# skills that satisfy the scenario's role-coverage requirement mechanically, not just
# cosmetically (an "engineer" who actually rolls no engineering-adjacent skill wouldn't be
# able to repair anything).
const ROLE_SKILL_POOL: Dictionary = {
	"captain":  ["Command", "Piloting", "Military Training"],
	"engineer": ["Engineering", "Mechanical Repair", "Jury-Rigging", "Industrial Equipment"],
	"medic":    ["Surgery", "Field Medicine", "Pathology", "Pharmacology"],
	"general":  ["Athletics", "Zero-G", "Rimwise"],
}
# role -> preferred career (dialogue-spec career dimension) when picking an archetype and
# when no archetype forces a class. "" = any career.
const ROLE_CAREER_HINT: Dictionary = {
	"captain": "", "engineer": "teamster_engineer", "medic": "scientist_medic", "general": "",
}
# role -> fallback Mothership class when there's no archetype
const ROLE_CLASS_HINT: Dictionary = {
	"captain": "Marine", "engineer": "Teamster", "medic": "Scientist", "general": "Teamster",
}

# Fallback names when no archetype supplies a names[] list.
const FIRST_NAMES: Array[String] = [
	"Alex", "Sam", "Jordan", "Rin", "Kass", "Nadia", "Priya", "Tomas", "Yusuf", "Elin",
	"Marcus", "Dana", "Owen", "Freya", "Idris", "Mika", "Soo-Jin", "Bram", "Talia", "Reyes",
]
const LAST_NAMES: Array[String] = [
	"Vance", "Okafor", "Solano", "Reyes", "Novak", "Ibarra", "Kessler", "Doyle", "Amara",
	"Hollis", "Petrova", "Chen", "Nakamura", "Fenn", "Osei", "Larkin", "Vasquez", "Marsh",
]

# Deliberately uses the engine's global RNG (seed()/randi()/randf()) rather than a private
# RandomNumberGenerator instance, so Checks.roll_stat_block()/roll_save_block()/
# roll_max_health() (which also use the global RNG) participate in the same deterministic
# seeded sequence — reseeding per crew slot below makes the whole roster reproducible from
# GameState.ship_seed exactly like ShipLayoutGen's ship layouts are.
var _archetypes: Array = []
var _archetypes_loaded: bool = false
var _skill_lookup: Dictionary = {}   # normalized name ("mechanical_repair") -> canonical ("Mechanical Repair")


# Builds a full crew roster with guaranteed role coverage: at least one command-skilled,
# one engineering-skilled, and one medical-skilled crew member (the overhaul spec's
# explicit requirement, since scenarios like The Quarantine need a recognisable
# medic/engineer). `required_roles` fills the first slots in order; any remaining slots
# (count > required_roles.size()) get a random role. crew_id is "<role>_<index>".
# Exactly one crew member holds captain RANK (the captain-role slot if present, else
# slot 0), and that member is never an Android.
static func generate_roster(ship_seed: int, count: int,
		required_roles: Array[String] = ["captain", "engineer", "medic", "general"]) -> Array[CrewMember]:
	var gen := CrewGen.new()
	gen._load_archetypes()
	gen._build_skill_lookup()

	# Which slot carries captain rank: the first "captain"-role slot, else slot 0.
	var captain_slot: int = 0
	for i in mini(count, required_roles.size()):
		if required_roles[i] == "captain":
			captain_slot = i
			break

	var roster: Array[CrewMember] = []
	for i in count:
		seed(ship_seed + i * 1000003 + 17)
		var role: String = required_roles[i] if i < required_roles.size() else gen._random_role()
		var rank: String = "captain" if i == captain_slot else RANKS[1 + randi() % 2]
		var archetype: Dictionary = gen._pick_archetype(role, rank)
		roster.append(gen._generate_one("%s_%d" % [role, i], role, rank, archetype))
	gen._ensure_role_coverage(roster)
	gen._enforce_rank_rules(roster)
	return roster


func _random_role() -> String:
	return ROLE_SKILL_POOL.keys()[randi() % ROLE_SKILL_POOL.size()]


func _load_archetypes() -> void:
	if _archetypes_loaded:
		return
	_archetypes_loaded = true
	var dir_path: String = "res://resources/dialogue/archetypes/"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return  # no archetypes present — fully optional, generation continues unbiased
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			var text: String = FileAccess.get_file_as_string(dir_path + file_name)
			var parsed: Variant = JSON.parse_string(text)
			# Only dimensional-schema archetypes participate (legacy pilot files that
			# predate the dimensions{} schema are skipped, per the spec's deprecation note).
			if parsed is Dictionary and (parsed as Dictionary).has("dimensions"):
				_archetypes.append(parsed)
		file_name = dir.get_next()
	dir.list_dir_end()


# Normalized skill-name lookup so archetype preferred_skills (lowercase snake_case, e.g.
# "mechanical_repair", "zero_g") resolve to the canonical rules.md names ("Mechanical
# Repair", "Zero-G") regardless of formatting.
func _build_skill_lookup() -> void:
	for pool: Array in [TRAINED_SKILLS, EXPERT_SKILLS, MASTER_SKILLS]:
		for skill_name: String in pool:
			_skill_lookup[_normalize_skill(skill_name)] = skill_name


func _normalize_skill(name: String) -> String:
	var out: String = ""
	for ch in name.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
	return out


func _canonical_skill(name: String) -> String:
	return String(_skill_lookup.get(_normalize_skill(name), ""))


# Archetype selection: prefer matching career AND rank; fall back to career-only, then
# rank-only, then any. Android-career archetypes are excluded outright for captain rank.
func _pick_archetype(role: String, rank: String) -> Dictionary:
	if _archetypes.is_empty():
		return {}
	var career_hint: String = String(ROLE_CAREER_HINT.get(role, ""))

	var career_and_rank: Array = []
	var career_only: Array = []
	var rank_only: Array = []
	var any_valid: Array = []
	for archetype: Dictionary in _archetypes:
		var dims: Dictionary = archetype.get("dimensions", {})
		var a_career: String = String(dims.get("career", ""))
		var a_rank: String = String(dims.get("rank", ""))
		if rank == "captain" and a_career == "android":
			continue  # androids can never be captains
		any_valid.append(archetype)
		var career_ok: bool = career_hint == "" or a_career == career_hint
		var rank_ok: bool = a_rank == rank
		if career_ok and rank_ok:
			career_and_rank.append(archetype)
		elif career_ok:
			career_only.append(archetype)
		elif rank_ok:
			rank_only.append(archetype)

	for pool: Array in [career_and_rank, career_only, rank_only, any_valid]:
		if not pool.is_empty():
			return pool[randi() % pool.size()] as Dictionary
	return {}


func _generate_one(crew_id: String, role: String, rank: String, archetype: Dictionary) -> CrewMember:
	var crew := CrewMember.new()
	crew.crew_id = crew_id
	crew.role = role
	crew.rank = rank
	crew.archetype_tag = String(archetype.get("tag", ""))
	crew.crew_name = _pick_name(archetype)
	_assign_pronouns(crew, archetype)

	crew.mship_class = _resolve_class(role, rank, archetype)

	_roll_stats(crew, archetype)
	_apply_class_adjustments(crew)
	_roll_health(crew)
	_assign_skills(crew, role, archetype)
	_assign_equipment(crew)

	crew.stress = crew.min_stress
	return crew


func _resolve_class(role: String, rank: String, archetype: Dictionary) -> String:
	var mship_class: String = ""
	# Career dimension is authoritative when present (career maps 1:1 to class).
	var dims: Dictionary = archetype.get("dimensions", {})
	var career: String = String(dims.get("career", ""))
	if career in CAREER_CLASS:
		mship_class = String(CAREER_CLASS[career])
	elif archetype.has("mothership_class"):
		mship_class = String(archetype["mothership_class"])
	else:
		mship_class = String(ROLE_CLASS_HINT.get(role, "Teamster"))
	if mship_class not in CLASSES:
		mship_class = CLASSES[randi() % CLASSES.size()]
	# Hard rule: the captain is never an Android.
	if rank == "captain" and mship_class == "Android":
		mship_class = "Marine"
	return mship_class


func _pick_name(archetype: Dictionary) -> String:
	var names: Array = archetype.get("names", [])
	if not names.is_empty():
		return String(names[randi() % names.size()])
	var first: String = FIRST_NAMES[randi() % FIRST_NAMES.size()]
	var last: String = LAST_NAMES[randi() % LAST_NAMES.size()]
	return "%s %s" % [first, last]


func _assign_pronouns(crew: CrewMember, archetype: Dictionary) -> void:
	var dims: Dictionary = archetype.get("dimensions", {})
	var gender: String = String(dims.get("gender", ""))
	var roll: int = randi() % 3
	if gender == "male":
		roll = 0
	elif gender == "female":
		roll = 1
	match roll:
		0:
			crew.pronoun_subject = "he"; crew.pronoun_object = "him"; crew.pronoun_possessive = "his"
		1:
			crew.pronoun_subject = "she"; crew.pronoun_object = "her"; crew.pronoun_possessive = "her"
		_:
			crew.pronoun_subject = "they"; crew.pronoun_object = "them"; crew.pronoun_possessive = "their"


func _roll_stats(crew: CrewMember, archetype: Dictionary) -> void:
	# stat/save tendencies are flat modifiers on top of the standard rolls (dialogue spec).
	var stat_tendencies: Dictionary = archetype.get("stat_tendencies", {})
	var save_tendencies: Dictionary = archetype.get("save_tendencies", {})
	crew.strength = Checks.roll_stat_block() + int(stat_tendencies.get("strength", 0))
	crew.speed = Checks.roll_stat_block() + int(stat_tendencies.get("speed", 0))
	crew.intellect = Checks.roll_stat_block() + int(stat_tendencies.get("intellect", 0))
	crew.combat = Checks.roll_stat_block() + int(stat_tendencies.get("combat", 0))
	crew.sanity_save = Checks.roll_save_block() + int(save_tendencies.get("sanity", 0))
	crew.fear_save = Checks.roll_save_block() + int(save_tendencies.get("fear", 0))
	crew.body_save = Checks.roll_save_block() + int(save_tendencies.get("body", 0))
	crew.willpower = clampf(float(crew.fear_save) / 60.0, 0.0, 1.0)


func _apply_class_adjustments(crew: CrewMember) -> void:
	match crew.mship_class:
		"Marine":
			crew.combat += 10
			crew.body_save += 10
			crew.fear_save += 20
			crew.max_wounds += 1
		"Android":
			crew.intellect += 20
			var stat_names: Array[String] = ["strength", "speed", "combat"]
			var penalized: String = stat_names[randi() % stat_names.size()]
			crew.apply_stat_penalty(penalized, 10)
			crew.fear_save += 60
			crew.max_wounds += 1
		"Scientist":
			crew.intellect += 10
			var boost_names: Array[String] = ["strength", "speed", "combat"]
			var boosted: String = boost_names[randi() % boost_names.size()]
			match boosted:
				"strength": crew.strength += 5
				"speed": crew.speed += 5
				"combat": crew.combat += 5
			crew.sanity_save += 30
		"Teamster":
			crew.strength += 5
			crew.speed += 5
			crew.intellect += 5
			crew.combat += 5
			crew.sanity_save += 10
			crew.fear_save += 10
			crew.body_save += 10


func _roll_health(crew: CrewMember) -> void:
	crew.max_health = Checks.roll_max_health()
	crew.health = crew.max_health


# Skills follow the normal class rules; archetype preferred_skills (if any) are
# prioritized whenever a rule says "pick a skill of tier X" (dialogue spec: "takes skills
# honoring class rules with preferred_skills prioritized").
func _assign_skills(crew: CrewMember, role: String, archetype: Dictionary) -> void:
	var preferred: Array[String] = _preferred_skills(archetype)

	match crew.mship_class:
		"Scientist":
			# 1 Master Skill + its Expert and Trained prerequisites, + 1 bonus Trained.
			var master: String = _pick_tiered(MASTER_SKILLS, preferred)
			crew.skills[master] = "Master"
			var prereqs: Array = MASTER_PREREQS.get(master, [])
			if prereqs.size() > 0:
				crew.skills[String(prereqs[0])] = "Expert"
			if prereqs.size() > 1:
				crew.skills[String(prereqs[1])] = "Trained"
			crew.skills[_pick_tiered(TRAINED_SKILLS, preferred)] = "Trained"
		_:
			for entry: Dictionary in CLASS_BASE_SKILLS.get(crew.mship_class, []):
				crew.skills[String(entry.get("skill", ""))] = String(entry.get("tier", "Trained"))
			# Bonus: 1 Expert OR 2 Trained (Marine/Android); Teamster gets 1 Trained + 1 Expert.
			if crew.mship_class == "Teamster":
				crew.skills[_pick_tiered(TRAINED_SKILLS, preferred)] = "Trained"
				crew.skills[_pick_tiered(EXPERT_SKILLS, preferred)] = "Expert"
			elif randf() < 0.5:
				crew.skills[_pick_tiered(EXPERT_SKILLS, preferred)] = "Expert"
			else:
				crew.skills[_pick_tiered(TRAINED_SKILLS, preferred)] = "Trained"
				crew.skills[_pick_tiered(TRAINED_SKILLS, preferred)] = "Trained"

	# Guarantee the role actually has a mechanically-relevant skill even if the
	# archetype/class roll didn't happen to grant one (role-coverage requirement).
	var pool: Array = ROLE_SKILL_POOL.get(role, [])
	if crew.best_skill_bonus(pool) <= 0 and not pool.is_empty():
		crew.skills[String(pool[randi() % pool.size()])] = "Trained"


func _preferred_skills(archetype: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for raw in (archetype.get("preferred_skills", []) as Array):
		var canonical: String = _canonical_skill(String(raw))
		if canonical != "":
			result.append(canonical)
	return result


# Picks a skill of the given tier: a preferred skill of that tier when available,
# otherwise a uniform random draw from the tier list.
func _pick_tiered(tier_pool: Array[String], preferred: Array[String]) -> String:
	var candidates: Array[String] = []
	for skill_name: String in preferred:
		if skill_name in tier_pool:
			candidates.append(skill_name)
	if not candidates.is_empty():
		return candidates[randi() % candidates.size()]
	return tier_pool[randi() % tier_pool.size()]


func _assign_equipment(crew: CrewMember) -> void:
	crew.inventory = Items.loadout_for_class(crew.mship_class)
	for item_id: String in crew.inventory:
		var item: Dictionary = Items.get_item(item_id)
		match String(item.get("kind", "")):
			"weapon", "tool_weapon":
				if crew.equipped_weapon == "unarmed":
					crew.equipped_weapon = item_id
			"armor":
				if crew.armor_item == "":
					crew.armor_item = item_id


# Post-generation safety net: guarantees at least one command/engineering/medical-skilled
# crew member exists on the roster regardless of how individual rolls landed, per the
# overhaul spec's explicit role-coverage requirement.
func _ensure_role_coverage(roster: Array[CrewMember]) -> void:
	for required_role: String in ["captain", "engineer", "medic"]:
		var pool: Array = ROLE_SKILL_POOL.get(required_role, [])
		var covered: bool = false
		for crew: CrewMember in roster:
			if crew.best_skill_bonus(pool) > 0:
				covered = true
				break
		if not covered and not roster.is_empty():
			var fallback: CrewMember = roster[0]
			for crew: CrewMember in roster:
				if crew.role == required_role:
					fallback = crew
					break
			if not pool.is_empty():
				fallback.skills[String(pool[0])] = "Trained"


# Post-generation safety net for the dialogue spec's hard rank rules: exactly one
# captain-rank member per roster, never an Android. generate_roster() already assigns
# ranks that satisfy this, so these fixups only fire if a future caller misuses the API.
func _enforce_rank_rules(roster: Array[CrewMember]) -> void:
	if roster.is_empty():
		return
	var captains: Array[CrewMember] = []
	for crew: CrewMember in roster:
		if crew.rank == "captain":
			captains.append(crew)
	# Demote extras (keep the first).
	for i in range(1, captains.size()):
		captains[i].rank = "officer"
	# Promote someone if nobody holds the rank — first non-Android.
	if captains.is_empty():
		for crew: CrewMember in roster:
			if crew.mship_class != "Android":
				crew.rank = "captain"
				captains.append(crew)
				break
	# The captain must not be an Android (should be unreachable given _resolve_class).
	if not captains.is_empty() and captains[0].mship_class == "Android":
		captains[0].mship_class = "Marine"
