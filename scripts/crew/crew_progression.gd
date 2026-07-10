class_name CrewProgression
extends Node

# X-COM-style veterancy earn triggers + leg-boundary resolution (docs/crew-progression-spec.md
# §3/§4). Thin EventBus-listening layer over Traits/Checks, mirroring the
# CrewSystem/RelationshipBehavior split: this Node decides WHEN a trait moment happens,
# Traits.grant() decides HOW it's applied. Added by Main alongside CrewBehavior/
# RepairBehavior/RelationshipBehavior (see main.gd).
#
# Roll-based earns ("Every earn rolls a Save per Mothership idiom") are queued as PENDING
# rolls rather than resolved the instant the trigger fires — spec §4 point 2: "Pending
# trait rolls from the leg's history resolve" alongside Rest Saves at the leg boundary. Rows
# marked "(automatic)" in the spec's table have no roll and apply immediately instead — that
# split is exactly the "Immediate vs leg-boundary" distinction §3's intro paragraph sets up.
#
# FTL-style replacement-crew recruitment is explicitly out of scope here (PINNED, spec §6) —
# nothing below reads or writes a roster-replacement path.

# "Under stress" gate for Cool Hands (Bypassed a locked door under stress) — roughly half of
# Stress's practical 2-20 range.
const BYPASS_STRESS_THRESHOLD: int = 10
# General "someone died" stress hit for every OTHER living crew member (on top of
# RelationshipGraph's heavier partner-specific grief hit) — a documented approximation for
# "watched a crewmate die" since there's no per-event witness list, only "who's still alive".
const WITNESS_DEATH_STRESS: int = 3

const SKILL_CRIT_THRESHOLD: int = 2     # crits needed in one family, in one leg, to grow it
const SKILL_PROGRESS_PER_LEG: int = 2
const SKILL_PROGRESS_TIER_UP: int = 10
const TIER_CHAIN: Array[String] = ["Trained", "Expert", "Master"]

const OLD_HAND_LEG: int = 3
const LIFER_LEG: int = 6

# Pending trait rolls this leg: [{crew_id, roll_stat, buff_id, debuff_id}]. Resolved (each a
# real Checks.perform_check, so failure still costs stress like any other roll) at the leg
# boundary, then cleared.
var _pending_rolls: Array[Dictionary] = []
# "<crew_id>|<trigger>" -> true — caps every repeatable trigger (suffocation rounds,
# repeated panics, repeated wounds) at one queued roll per crew per leg, so a prolonged
# crisis doesn't spam duplicate pending rolls. Cleared at the leg boundary.
var _triggered_this_leg: Dictionary = {}
# crew_id -> {skill_name: crit_count}, tallied from EventBus.crew_skill_critical. Cleared
# at the leg boundary after being folded into skill_progress.
var _crit_tally: Dictionary = {}
# room_id -> last known air (crew_suffocation_check-adjacent proxy for "AI saved/harmed
# their life" — see _on_room_air_changed).
var _prev_room_air: Dictionary = {}


func _ready() -> void:
	EventBus.crew_suffocation_check.connect(_on_suffocation_check)
	EventBus.crew_panicked.connect(_on_panicked)
	EventBus.crew_died.connect(_on_crew_died)
	EventBus.crew_injury.connect(_on_crew_injury)
	EventBus.repair_success.connect(_on_repair_success)
	EventBus.door_bypass_result.connect(_on_door_bypass_result)
	EventBus.room_air_changed.connect(_on_room_air_changed)
	EventBus.crew_repeated_lockout.connect(_on_repeated_lockout)
	EventBus.crew_skill_critical.connect(_on_skill_critical)
	EventBus.leg_boundary_reached.connect(_on_leg_boundary)


# --- Queueing helper (roll-based earns) ---

func _queue_once(crew_id: String, trigger: String, roll_stat: String, buff_id: String, debuff_id: String) -> void:
	var dedup_key: String = "%s|%s" % [crew_id, trigger]
	if _triggered_this_leg.get(dedup_key, false):
		return
	_triggered_this_leg[dedup_key] = true
	_pending_rolls.append({"crew_id": crew_id, "roll_stat": roll_stat, "buff_id": buff_id, "debuff_id": debuff_id})


# --- Immediate earn triggers ---

# Survived suffocation/near-vacuum -> Body roll (Iron Lungs / Vacuum Nightmares).
func _on_suffocation_check(crew_id: String, survived: bool) -> void:
	if not survived:
		return
	_queue_once(crew_id, "suffocation", "body", "iron_lungs", "vacuum_nightmares")


# Survived a panic episode -> Sanity roll (Battle Calm / Jumpy). Checks.panic_check emits
# this even when the roll DIDN'T panic (effect == "") — only an actual panic counts.
func _on_panicked(crew_id: String, _roll: int, effect: String) -> void:
	if effect == "":
		return
	_queue_once(crew_id, "panic_episode", "sanity", "battle_calm", "jumpy_nerves")


# Watched a crewmate die -> Fear roll per bystander (Hardened / Survivor's Guilt), plus the
# stress hit that actually makes Hardened's halving matter. Partner died -> automatic
# Widowed (no roll) on top of whatever RelationshipGraph's own grief hit already does.
func _on_crew_died(dead_id: String, _cause: String) -> void:
	var partner_id: String = RelationshipGraph.partner_of(dead_id)
	for crew_id: String in GameState.crew:
		if crew_id == dead_id:
			continue
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew == null or not crew.is_alive:
			continue
		crew.add_stress(WITNESS_DEATH_STRESS, "death")
		_queue_once(crew_id, "witnessed_death", "fear", "hardened", "survivors_guilt")
	if partner_id != "":
		var partner: CrewMember = GameState.crew.get(partner_id) as CrewMember
		if partner != null and partner.is_alive:
			Traits.grant(partner, "widowed")


# Wounded (and still standing right after) -> Body roll (Scar Tissue / Old Wound).
# Simplification: there's no explicit "fully recovered" event in this codebase (no healing
# minigame beyond WoundTable.stabilize's death-clock cancel), so "recovered" is read as
# "survived the wound resolution" — documented here rather than left implicit.
func _on_crew_injury(crew_id: String, _severity: String, _wound_type: String) -> void:
	_queue_once(crew_id, "wounded", "body", "scar_tissue", "old_wound")


# Completed a crisis repair -> Intellect roll (Field-Certified only; no debuff column).
# The skill family is whichever skill the crew actually brought to bear (RepairModel's own
# best_skill_name pick), baked into the parametrized trait id "field_certified:<skill>".
func _on_repair_success(target_id: String, crew_id: String) -> void:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	if crew == null or not crew.is_alive:
		return
	var skill: String = crew.best_skill_name(RepairModel.REPAIR_SKILLS.get(target_id, []))
	if skill == "":
		skill = target_id  # pulled it off with no formal training — still worth certifying
	_queue_once(crew_id, "crisis_repair", "intellect", "field_certified:%s" % skill, "")


# Bypassed a locked door under stress -> Cool Hands, automatic (no roll in the spec table).
func _on_door_bypass_result(crew_id: String, _door_id: String, success: bool, _critical: bool) -> void:
	if not success:
		return
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	if crew == null or crew.stress < BYPASS_STRESS_THRESHOLD:
		return
	Traits.grant(crew, "cool_hands")


# AI harmed them: repeated door lockout (>=3, Door.LOCKOUT_TRUST_EVERY) -> Machine-Wary.
func _on_repeated_lockout(crew_id: String, _door_id: String, _count: int) -> void:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	if crew != null and crew.is_alive:
		Traits.grant(crew, "machine_wary")


# AI saved/harmed their life, air variant: a room's air crossing the critical suffocation
# threshold while occupied. Recovering INTO safety (a diversion decision landing in time) ->
# Believer; falling INTO critical while life support is actively in failure mode (an active
# diversion choice, not just ambient decay with nobody to blame) -> Machine-Wary. A
# documented proxy for "traceable to player action" — full causal tracing of which specific
# AI action saved/harmed a given crew member is a deeper feature than v1 needs.
func _on_room_air_changed(room_id: String, air: float) -> void:
	var prev: float = float(_prev_room_air.get(room_id, air))
	_prev_room_air[room_id] = air
	var threshold: float = LifeSupportModel.AIR_CRITICAL_THRESHOLD
	var room: RoomBase = GameState.rooms.get(room_id) as RoomBase
	if room == null:
		return
	var grant_id: String = ""
	if prev < threshold and air >= threshold:
		grant_id = "believer"
	elif prev >= threshold and air < threshold and not GameState.life_support_online:
		grant_id = "machine_wary"
	if grant_id == "":
		return
	for crew_id: String in room.occupants:
		var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
		if crew != null and crew.is_alive:
			Traits.grant(crew, grant_id)


# Crit-success tally toward crit-tally skill growth (spec §4 point 3), keyed by real skill
# name (see door.gd/repair_model.gd's best_skill_name change).
func _on_skill_critical(crew_id: String, skill_name: String) -> void:
	if not _crit_tally.has(crew_id):
		_crit_tally[crew_id] = {}
	var tally: Dictionary = _crit_tally[crew_id]
	tally[skill_name] = int(tally.get(skill_name, 0)) + 1


# --- Leg boundary (spec §4): Rest Saves, pending trait rolls, skill growth, service record ---

func _on_leg_boundary(leg: int) -> void:
	var living: Array[String] = []
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew == null or not crew.is_alive:
			continue
		living.append(crew_id)
		_rest_save(crew)
		crew.legs_served += 1
		_resolve_service_legs(crew)
	_resolve_pending_rolls()
	_resolve_skill_growth()
	_triggered_this_leg.clear()
	_crit_tally.clear()
	print("[PROGRESSION] leg boundary -> leg %d: %d Rest Saves, %d pending trait rolls resolved" % [
		leg, living.size(), _pending_rolls.size()])
	_pending_rolls.clear()


func _rest_save(crew: CrewMember) -> void:
	var outcome: Dictionary = Checks.rest_save(crew)
	var result: Checks.CheckResult = outcome["result"]
	EventBus.crew_rest_save_resolved.emit(crew.crew_id, result.success, String(outcome["worst_save"]))


# Survived N legs (spec §3): 3 -> Old Hand, 6 -> Lifer + Set in Their Ways, automatic.
func _resolve_service_legs(crew: CrewMember) -> void:
	if crew.legs_served == OLD_HAND_LEG:
		Traits.grant(crew, "old_hand")
	elif crew.legs_served == LIFER_LEG:
		Traits.grant(crew, "lifer")
		Traits.grant(crew, "set_in_their_ways")


func _resolve_pending_rolls() -> void:
	for entry: Dictionary in _pending_rolls:
		var crew: CrewMember = GameState.crew.get(String(entry["crew_id"])) as CrewMember
		if crew == null or not crew.is_alive:
			continue  # didn't live to see the boundary — no trait; the memorial covers them
		var result: Checks.CheckResult = Checks.perform_check(crew, String(entry["roll_stat"]))
		if result.success:
			Traits.grant(crew, String(entry["buff_id"]))
		else:
			var debuff_id: String = String(entry["debuff_id"])
			if debuff_id != "":
				Traits.grant(crew, debuff_id)


# XP-lite skill growth (spec §4 point 3): the one skill family with >=2 crits this leg
# gains +2 progress; at +10, a tier upgrade. Deliberately slow — "veterancy is mostly
# traits, not stats". Tier chain (Trained->Expert->Master) is the same simplification
# CrewGen's MASTER_PREREQS comment already flags: rules.md has no published skill tree, so
# this just walks the tier ladder for whichever single skill grew.
func _resolve_skill_growth() -> void:
	for crew_id: String in _crit_tally:
		var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
		if crew == null or not crew.is_alive:
			continue
		var tally: Dictionary = _crit_tally[crew_id]
		var best_family: String = ""
		var best_count: int = 0
		for skill_name: String in tally:
			var count: int = int(tally[skill_name])
			if count > best_count:
				best_count = count
				best_family = skill_name
		if best_family == "" or best_count < SKILL_CRIT_THRESHOLD:
			continue
		var progress: int = int(crew.skill_progress.get(best_family, 0)) + SKILL_PROGRESS_PER_LEG
		if progress >= SKILL_PROGRESS_TIER_UP:
			progress -= SKILL_PROGRESS_TIER_UP
			_tier_up(crew, best_family)
		crew.skill_progress[best_family] = progress


func _tier_up(crew: CrewMember, skill_name: String) -> void:
	var current: String = String(crew.skills.get(skill_name, ""))
	var idx: int = TIER_CHAIN.find(current)
	if idx >= TIER_CHAIN.size() - 1:
		return  # already Master (or an unrecognised tier) — nothing higher to grant
	var next_tier: String = TIER_CHAIN[idx + 1]
	crew.skills[skill_name] = next_tier
	EventBus.crew_skill_tier_up.emit(crew.crew_id, skill_name, next_tier)
