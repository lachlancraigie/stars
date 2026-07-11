class_name CrewMember
extends Resource

# Mothership 1e character (docs/rules.md). Rewritten for the overhaul/mothership-rewrite
# branch — replaces the old ad-hoc Physical/Mental stat block with the real Four Stats +
# Three Saves + Class + Skills + Stress/Panic + Health/Wounds model. The pre-existing
# "needs" simulation (hunger/fatigue/fear/loneliness/boredom/morale + CrewStateMachine) is
# KEPT AS-IS below — it drives moment-to-moment autonomous behaviour (CrewBehavior) and is
# a different (complementary, not contradictory) layer from Mothership Stress/Panic, which
# governs discrete check-driven crises. `fear` (0-1, ambient) and `fear_save` (a Mothership
# stat, checked directly) are deliberately distinct fields.

# --- Identity ---
@export var crew_id: String = ""
@export var crew_name: String = ""
@export var role: String = ""              # "captain" | "engineer" | "medic" | "scientist" | "general" — job function, drives duty stations/visuals
@export var rank: String = "crew_mate"     # "captain" | "officer" | "crew_mate" — dialogue-spec rank dimension; exactly one captain per ship, never an Android (enforced by CrewGen)
@export var pronoun_subject: String = "they"
@export var pronoun_object: String = "them"
@export var pronoun_possessive: String = "their"
@export var archetype_tag: String = ""     # optional resources/dialogue/archetypes/*.json tag, e.g. "GR_ML_ENG_CM" (dialogue selects lines by this)
@export var age: int = 30                  # flavour-only (service record / info card display); no mechanical effect

# --- Mothership class ---
@export var mship_class: String = "Teamster"   # "Marine" | "Android" | "Scientist" | "Teamster"

# --- Four Stats (2d10+25 at creation, +class adjustments) ---
@export_group("Stats")
@export var strength: int = 36
@export var speed: int = 36
@export var intellect: int = 36
@export var combat: int = 36

# --- Three Saves (2d10+10 at creation, +class adjustments) ---
@export_group("Saves")
@export var sanity_save: int = 20
@export var fear_save: int = 20
@export var body_save: int = 20

# --- Health & Wounds ---
@export_group("Health")
@export var max_health: int = 15
@export var health: int = 15
@export var max_wounds: int = 1
@export var wounds: int = 0
@export var bleeding_per_round: int = 0
@export var conditions: Array[String] = []   # Panic Table / Wound Table conditions, persist until treated

# --- Stress & Panic ---
@export_group("Stress")
@export var stress: int = 2
@export var min_stress: int = 2
var lost_skill: String = ""       # Loss of Confidence: this skill's bonus is suppressed
var retired: bool = false          # Panic Table "RETIRE" — permanently stood down, not dead
var adrenaline_until: float = 0.0  # [+] all rolls while TimeManager.elapsed < this
var overwhelmed_until: float = 0.0 # [-] all rolls while TimeManager.elapsed < this
var frozen_until: float = 0.0      # Catatonic — CrewStateMachine.FROZEN while TimeManager.elapsed < this
var rage_until: float = 0.0        # [+] damage rolls (flavour only — no combat resolver yet)
var unconscious_until: float = 0.0
var death_save_at: float = -1.0    # >=0: death_save_mode resolves when TimeManager.elapsed passes this
var death_save_mode: String = ""   # "" | "pending_save" (roll a Death Save) | "dying" (dies outright)
var suffocation_round_timer: float = 0.0   # SuffocationModel's ~10s "round" accumulator

# --- Skills (skill_name -> "Trained" | "Expert" | "Master") ---
@export_group("Skills")
@export var skills: Dictionary = {}

# --- Equipment (docs/rules.md "Equipment"/"Weapons"/"Armor") ---
@export_group("Equipment")
@export var inventory: Array[String] = []   # item ids, see scripts/core/items.gd
@export var equipped_weapon: String = "unarmed"
@export var armor_item: String = ""

# Internal: cumulative Stress-overflow-style stat penalties (rules.md "Damage over 20
# reduces the most relevant Stat or Save by the overflow amount" + Wound Table stat hits).
var stat_penalties: Dictionary = {}

# --- Dynamic needs (existing autonomous-behaviour simulation — unchanged) ---
@export_group("Needs")
@export var hunger: float = 0.0
@export var fatigue: float = 0.0
@export var fear: float = 0.0
@export var pain: float = 0.0
@export var loneliness: float = 0.0
@export var boredom: float = 0.0

# --- Health and state (existing simulation layer — unchanged) ---
@export_group("SimHealth")
@export var morale: float = 1.0
@export var physical_health: float = 1.0
@export var psychological_health: float = 1.0
@export var is_alive: bool = true

@export_group("State")
@export var current_state: String = "idle"
@export var location: String = ""

# --- Personality (existing — unchanged) ---
@export_group("Personality")
@export var fears: Array[String] = []
@export var values: Array[String] = []
@export var goals: Array[String] = []

# --- Progression (docs/crew-progression-spec.md) — X-COM-style veterancy: history, not
# levels. `traits` holds earned trait ids (Traits.grant() is the one funnel that appends to
# it — see scripts/core/traits.gd); `skill_progress` is XP-lite crit-tally progress toward a
# tier upgrade (scripts/crew/crew_progression.gd), skill name -> 0..10.
@export_group("Progression")
@export var traits: Array[String] = []
@export var legs_served: int = 0
@export var skill_progress: Dictionary = {}

# --- Social (existing — unchanged) ---
@export_group("Social")
@export var ai_trust: float = 0.5
@export var willpower: float = 0.5           # legacy 0-1 simulation trait (fear-decay/compliance math); kept independent of fear_save
@export var relationships: Dictionary = {}

# Repeated door lockouts erode trust in the AI (see Door.gd) — tracked per-door so
# a single sticky door doesn't spam trust hits, only *repeated* ones do.
var door_lockout_counts: Dictionary = {}   # door_id -> int

# --- Status flags (docs/mission-system-spec.md §5/§6) ---
# Hidden narrative state a scenario can plant on a crew member (infected/changed/
# shaken/marked) that pays off legs later — deliberately NOT surfaced by any HUD
# element; only scenario/monitor logic and MissionManager's delayed-payoff scheduler
# (spec §10) read this. flag -> bool.
@export_group("Status")
@export var status_flags: Dictionary = {}

# Away ops (docs/mission-system-spec.md §6). True while this crew member has departed the
# ship (shuttle to a surface, or through the airlock to board something) and is being
# resolved off-screen by AwayResolver. They stay in GameState.crew the whole time (never
# removed from the roster) — only their CrewMemberNode visual is hidden/detached
# (CrewMemberNode.set_off_ship) and the on-ship simulation (CrewSystem/CrewBehavior/
# DialogueSystem) skips them, same spirit as the is_alive checks those systems already do.
@export var off_ship: bool = false


func set_status_flag(flag: String, value: bool) -> void:
	if bool(status_flags.get(flag, false)) == value:
		return
	status_flags[flag] = value
	EventBus.crew_status_flag_changed.emit(crew_id, flag, value)


func has_status_flag(flag: String) -> bool:
	return bool(status_flags.get(flag, false))


# --- Stat/Save/Skill accessors (used by Checks — the one roll-resolution utility) ---

func get_stat_or_save(name: String) -> int:
	var base: int = 0
	match name:
		"strength": base = strength
		"speed": base = speed
		"intellect": base = intellect
		"combat": base = combat
		"sanity": base = sanity_save
		"fear": base = fear_save
		"body": base = body_save
		_: base = 36
	# Unqualified trait stat/save bonuses only (Old Hand/Lifer's all-saves bump, Scar
	# Tissue's flat Body, Old Wound's flat Speed) — "vs X"-qualified ones like Iron Lungs
	# use the tag system instead, applied only at their specific check call site.
	base += Traits.sum_stat_bonus(traits, name)
	return maxi(1, base - int(stat_penalties.get(name, 0)))


func get_skill_bonus(skill_name: String) -> int:
	if skill_name == "" or skill_name == lost_skill:
		return 0
	var tier: String = String(skills.get(skill_name, ""))
	return int(Checks.TIER_BONUS.get(tier, 0)) + Traits.sum_skill_bonus(traits, skill_name)


# Highest-bonus skill name among `skill_names` (ties keep the first match) — used both to
# compute a bonus (best_skill_bonus below) and, at the call sites that matter for crew
# progression (Door bypass, RepairModel), passed on as Checks.perform_check's own
# `skill_name` so critical successes can be tallied by real skill family (see
# EventBus.crew_skill_critical) and Loss of Confidence / Set in Their Ways apply correctly.
func best_skill_name(skill_names: Array) -> String:
	var best_name: String = ""
	var best_bonus: int = -1
	for skill_name: String in skill_names:
		var bonus: int = get_skill_bonus(skill_name)
		if bonus > best_bonus:
			best_bonus = bonus
			best_name = skill_name
	return best_name


func best_skill_bonus(skill_names: Array) -> int:
	return get_skill_bonus(best_skill_name(skill_names))


func worst_save_name() -> String:
	var worst: String = "sanity"
	var worst_value: int = get_stat_or_save("sanity")
	for name: String in ["fear", "body"]:
		var v: int = get_stat_or_save(name)
		if v < worst_value:
			worst_value = v
			worst = name
	return worst


func apply_stat_penalty(stat_name: String, amount: int) -> void:
	if amount <= 0:
		return
	stat_penalties[stat_name] = int(stat_penalties.get(stat_name, 0)) + amount


# --- Stress ---

func add_stress(amount: int, source: String = "") -> void:
	if amount <= 0:
		return
	var old: int = stress
	# `source` is optional context ("death" is the only one read today) purely for trait
	# multipliers (Hardened) — most call sites never pass one, so the multiplier is a no-op.
	var scaled: int = int(round(float(amount) * Traits.stress_gain_mult(traits, source)))
	var raw: int = stress + scaled
	if raw > 20:
		# "Damage over 20 reduces the most relevant Stat or Save by the overflow
		# amount" — Warden-arbitrated which is "most relevant"; Sanity Save is the
		# sensible universal default since Stress is itself a Sanity-adjacent track.
		apply_stat_penalty("sanity", raw - 20)
		raw = 20
	stress = maxi(min_stress, raw)
	if stress != old:
		EventBus.crew_stress_changed.emit(crew_id, old, stress)


func reduce_stress(amount: int) -> void:
	if amount <= 0:
		return
	var old: int = stress
	stress = maxi(min_stress, stress - amount)
	if stress != old:
		EventBus.crew_stress_changed.emit(crew_id, old, stress)


# --- Environmental advantage/disadvantage (thin air, panic states — folded into
# every check automatically by Checks.perform_check) ---

func has_environmental_disadvantage() -> bool:
	if TimeManager.elapsed < overwhelmed_until:
		return true
	if "disadvantage_all" in conditions:
		return true
	return GameState.get_room_air(location) < LifeSupportModel.AIR_DISADVANTAGE_THRESHOLD


func has_environmental_advantage() -> bool:
	return TimeManager.elapsed < adrenaline_until


# Vacuum Nightmares (docs/crew-progression-spec.md §3): "fear checks at disadvantage in
# airlock/low-air rooms" — the one trait whose effect is a conditional Disadvantage rather
# than a flat bonus, so it gets its own read (Checks.perform_check calls this only when
# stat_name == "fear") instead of going through the tag/stat_bonus systems.
func has_vacuum_nightmares_disadvantage() -> bool:
	if "vacuum_nightmares" not in traits:
		return false
	var room: RoomBase = GameState.rooms.get(location) as RoomBase
	if room != null and room.room_function == "airlock":
		return true
	return GameState.get_room_air(location) < LifeSupportModel.AIR_DISADVANTAGE_THRESHOLD


# --- Health/Wounds/Damage flow (rules.md "Damage flow") ---

func apply_damage(amount: int, wound_type: String) -> void:
	if not is_alive or amount <= 0:
		return
	health -= amount
	if health <= 0:
		var carryover: int = -health
		health = max_health
		WoundTable.roll_and_apply(self, wound_type)
		if is_alive and carryover > 0:
			apply_damage(carryover, wound_type)


# --- Progression traits (same shape as the item accessors below) ---

func trait_bonus(tag: String) -> float:
	return Traits.sum_tag_bonus(traits, tag)


# --- Equipment ---

func item_bonus(tag: String) -> float:
	return Items.sum_tag_bonus(inventory, tag)


func best_item_bonus(tag: String) -> float:
	return Items.best_tag_bonus(inventory, tag)


func has_item_tag(tag: String) -> bool:
	return Items.has_tag(inventory, tag)


# For multiplicative tags (e.g. door_bypass_time_mult) where a lower value is better and
# 1.0 (no effect) is the default absence value — max()/sum() would pick the wrong item.
func item_time_multiplier(tag: String) -> float:
	var best: float = 1.0
	for item_id: String in inventory:
		var v: float = Items.tag_value(item_id, tag)
		if v > 0.0:
			best = minf(best, v)
	return best
