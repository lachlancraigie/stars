extends Node

# Scenario
var scenario_id: String = ""
var scenario_tone: float = 0.5  # 0.0 = Trek, 1.0 = Alien

# Ship
var ship_class: int = 1
var ship_name: String = ""
var ship_class_id: String = ""    # procedural ruleset id, e.g. "freighter" (see ShipLayoutGen)
var ship_seed: int = 0            # RNG seed the current layout was generated from; carry into saves
var rooms: Dictionary = {}         # room_id -> RoomBase node
var ship_systems: Dictionary = {}  # system_name -> Dictionary

# --- Power (Mothership rewrite — replaces the old normalised resource-bar model) ---
# While the reactor is online every room is powered for free. On reactor failure the
# ship falls to a battery budget the AI must divert room-by-room (see PowerModel for
# the tuning constants/tick logic; GameState only owns the authoritative state).
var reactor_online: bool = true
var battery_capacity: float = 100.0
var battery_charge: float = 100.0
var powered_rooms: Array[String] = []      # rooms manually powered from battery (battery mode only)
var _battery_was_low: bool = false          # edge-trigger guard for the power_low signal

# --- Life support (Mothership rewrite) ---
# While life_support_online, every room has full air. On failure, per-room air quality
# (0-100) degrades/recovers over time (LifeSupportModel) and the AI diverts limited
# capacity to a capped set of rooms, same shape as power.
var life_support_online: bool = true
var life_supported_rooms: Array[String] = []   # rooms manually kept supported in failure mode
var room_air: Dictionary = {}                   # room_id -> float 0-100 (lazily defaults to 100)

# --- AI core (Mothership rewrite) ---
# The ai_core room hosts the player. Integrity 0-100; status derives from it (+ a manual
# shutdown flag). The AI core is assumed to run off its own isolated power cell, independent
# of the ship power grid above — deliberately, so a ship-wide blackout can never strand the
# player without any means to act (see CLAUDE.md session note for the rationale).
var ai_core_integrity: float = 100.0
var ai_core_status: String = "online"       # "online" | "degraded" | "blackout"
var ai_core_manual_shutdown: bool = false
var ai_core_blackout_since: float = -1.0
var ai_core_sensor_gap_rooms: Array[String] = []   # degraded-mode: rooms the AI can't currently see occupants in

# --- Repair jobs (reactor / life_support / ai_core) ---
# target_id -> {crew_id: String, elapsed_since_check: float, progress: float}
var repair_jobs: Dictionary = {}

# --- Ship-wide destruction hook (stub — no content triggers this yet; wired for the
# "ship destroyed" lose condition per CLAUDE.md's permadeath design decision) ---
var ship_destroyed: bool = false

# --- Hull & economy (docs/mission-system-spec.md §5) ---
# hull_integrity follows the same shape as ai_core_integrity below: 0-100, clamped,
# with a damage/repair pair rather than a raw setter so "reached 0" always routes
# through one place. credits is a simple economy accumulator (mission rewards) —
# no upper clamp, floored at 0.
var hull_integrity: float = 100.0
var credits: float = 0.0

# Crew
var crew: Dictionary = {}  # crew_id -> CrewMember resource

# Ship graph and doors (built at scenario start by ShipLayoutBuilder)
var ship_graph: ShipGraph = null
var doors: Dictionary = {}  # door_id -> Door node

# AI state
var ai_access_levels: Dictionary = {}  # system_name -> int (0=none 1=read 2=write 3=full)
var ai_obedience_score: float = 1.0    # internal; crew cannot read this directly
var ai_trust_scores: Dictionary = {}   # crew_id -> float

# --- Crew social simulation (Agent 2 — crew simulation/dialogue overhaul) ---
# Per-pair relationship data, keyed by RelationshipGraph.pair_key(a, b) (sorted "a|b" so
# the entry is shared regardless of argument order). Owned here per Rule 3; RelationshipGraph
# (scripts/crew/relationship_graph.gd) is the utility that reads/mutates it and emits
# crew_relationship_changed. Shape: {"affinity": float -1..1, "flags": Array[String],
# "romance_stage": "none"|"hinted"|"advancing"|"accepted", "rejected_until": float}.
var crew_relationships: Dictionary = {}
# crew_id -> side-project id (see scripts/crew/side_projects.gd) — a persistent hobby
# assigned lazily the first time a crew member's recreation-phase schedule needs it.
var crew_side_projects: Dictionary = {}

# --- Memorial (docs/crew-progression-spec.md §5) ---
# One snapshot per crew member who has died this run — CrewLifecycle.kill is the one
# funnel that calls record_fallen(), right before emitting crew_died, so a memorial entry
# always exists by the time any listener reacts to the death. Shape: {crew_id, name, role,
# archetype_tag, traits: Array[String], legs_served, cause, partner, died_at}.
var fallen: Array[Dictionary] = []


func record_fallen(entry: Dictionary) -> void:
	fallen.append(entry)
	var trait_ids: Array = entry.get("traits", [])
	print("[MEMORIAL] %s — cause: %s, legs served: %d, traits: %s" % [
		String(entry.get("name", "?")), String(entry.get("cause", "unknown")),
		int(entry.get("legs_served", 0)), ", ".join(trait_ids) if not trait_ids.is_empty() else "none"])


# --- Power ---

func set_reactor_online(online: bool, source: String = "") -> void:
	if reactor_online == online:
		return
	reactor_online = online
	if not online:
		powered_rooms.clear()
		EventBus.reactor_failure.emit(source)
	else:
		battery_charge = battery_capacity  # reactor coming back recharges the battery bank
		_battery_was_low = false
		EventBus.system_repaired.emit("reactor")
	EventBus.power_mode_changed.emit(online)


func damage_reactor(source: String = "damage") -> void:
	set_reactor_online(false, source)


func get_room_powered(room_id: String) -> bool:
	if reactor_online:
		return true
	return room_id in powered_rooms


# Returns false if the room couldn't be (de)powered — either the AI core can't
# currently act (blackout) or the simultaneous-powered-rooms cap is full.
func set_room_powered(room_id: String, powered: bool) -> bool:
	if not ai_core_can_act():
		return false
	if reactor_online:
		return true  # no-op — everything is powered for free
	if powered:
		if room_id in powered_rooms:
			return true
		if powered_rooms.size() >= PowerModel.MAX_BATTERY_ROOMS:
			return false
		powered_rooms.append(room_id)
	else:
		powered_rooms.erase(room_id)
	EventBus.room_power_changed.emit(room_id, get_room_powered(room_id))
	return true


func set_battery_charge(value: float) -> void:
	var prev: float = battery_charge
	battery_charge = clampf(value, 0.0, battery_capacity)
	EventBus.battery_changed.emit(battery_charge, battery_capacity)
	var low: bool = battery_charge <= battery_capacity * PowerModel.LOW_BATTERY_FRACTION
	if low and not _battery_was_low:
		EventBus.power_low.emit(battery_charge)
	_battery_was_low = low
	if battery_charge <= 0.0:
		powered_rooms.clear()


# --- Life support ---

func set_life_support_online(online: bool, source: String = "") -> void:
	if life_support_online == online:
		return
	life_support_online = online
	if not online:
		life_supported_rooms.clear()
		EventBus.life_support_failure.emit(source)
	else:
		EventBus.system_repaired.emit("life_support")
	EventBus.life_support_mode_changed.emit(online)


func damage_life_support(source: String = "damage") -> void:
	set_life_support_online(false, source)


func get_room_air(room_id: String) -> float:
	return room_air.get(room_id, 100.0)


func set_room_air(room_id: String, value: float) -> void:
	var prev: float = get_room_air(room_id)
	var next: float = clampf(value, 0.0, 100.0)
	if is_equal_approx(prev, next):
		return
	room_air[room_id] = next
	EventBus.room_air_changed.emit(room_id, next)


func get_room_life_supported(room_id: String) -> bool:
	if life_support_online:
		return true
	return room_id in life_supported_rooms


func set_room_life_supported(room_id: String, supported: bool) -> bool:
	if not ai_core_can_act():
		return false
	if life_support_online:
		return true
	if supported:
		if room_id in life_supported_rooms:
			return true
		if life_supported_rooms.size() >= LifeSupportModel.MAX_LIFE_SUPPORT_ROOMS:
			return false
		life_supported_rooms.append(room_id)
	else:
		life_supported_rooms.erase(room_id)
	return true


# --- AI core ---

func damage_ai_core(amount: float, source: String) -> void:
	if amount <= 0.0:
		return
	ai_core_integrity = clampf(ai_core_integrity - amount, 0.0, 100.0)
	EventBus.ai_damaged.emit(amount, ai_core_integrity, source)
	_recompute_ai_core_status()


func repair_ai_core(amount: float) -> void:
	if amount <= 0.0:
		return
	ai_core_integrity = clampf(ai_core_integrity + amount, 0.0, 100.0)
	_recompute_ai_core_status()


func shutdown_ai_core_manual() -> void:
	ai_core_manual_shutdown = true
	_recompute_ai_core_status()


func restart_ai_core_manual() -> void:
	ai_core_manual_shutdown = false
	_recompute_ai_core_status()


func ai_core_can_act() -> bool:
	return ai_core_status != "blackout"


func is_room_sensor_gapped(room_id: String) -> bool:
	return room_id in ai_core_sensor_gap_rooms


func _recompute_ai_core_status() -> void:
	var prev: String = ai_core_status
	if ai_core_manual_shutdown or ai_core_integrity <= 0.0:
		ai_core_status = "blackout"
	elif ai_core_integrity < 50.0:
		ai_core_status = "degraded"
	else:
		ai_core_status = "online"
	if ai_core_status != prev:
		if ai_core_status == "blackout":
			ai_core_blackout_since = TimeManager.elapsed
		if ai_core_status != "degraded":
			ai_core_sensor_gap_rooms.clear()
		EventBus.ai_core_status_changed.emit(prev, ai_core_status)


# --- Repair jobs ---

func start_repair_job(target_id: String, crew_id: String) -> bool:
	if target_id in repair_jobs:
		return false
	repair_jobs[target_id] = {"crew_id": crew_id, "elapsed_since_check": 0.0, "progress": 0.0}
	EventBus.repair_started.emit(target_id, crew_id)
	return true


func cancel_repair_job(target_id: String) -> void:
	repair_jobs.erase(target_id)


func is_being_repaired(target_id: String) -> bool:
	return target_id in repair_jobs


# --- Ship destruction (stub hook — no in-game content triggers this yet) ---

func destroy_ship(reason: String) -> void:
	if ship_destroyed:
		return
	ship_destroyed = true
	push_warning("GameState: ship destroyed — %s" % reason)


# --- Hull ---

func damage_hull(amount: float, source: String = "damage") -> void:
	if amount <= 0.0:
		return
	hull_integrity = clampf(hull_integrity - amount, 0.0, 100.0)
	if hull_integrity <= 0.0:
		destroy_ship("hull_failure")


func repair_hull(amount: float) -> void:
	if amount <= 0.0:
		return
	hull_integrity = clampf(hull_integrity + amount, 0.0, 100.0)


func set_ai_trust(crew_id: String, value: float) -> void:
	var prev: float = ai_trust_scores.get(crew_id, 0.5)
	var next: float = clampf(value, 0.0, 1.0)
	# Believer / Machine-Wary (docs/crew-progression-spec.md §3): a personal trust
	# floor/ceiling clamp read continuously, same spirit as the reactor/battery clamps
	# above — applied here (the one mutator) so every caller gets it for free.
	var member: CrewMember = crew.get(crew_id) as CrewMember
	if member != null:
		next = clampf(next, Traits.trust_floor(member.traits), Traits.trust_ceiling(member.traits))
	ai_trust_scores[crew_id] = next
	# Keep the CrewMember resource in sync so DirectiveEvaluator reads live values
	if member != null:
		member.ai_trust = next
	EventBus.ai_trust_changed.emit(crew_id, prev, next)


func get_ai_trust(crew_id: String) -> float:
	return ai_trust_scores.get(crew_id, 0.5)


func set_ai_access(system_name: String, level: int) -> void:
	var prev: int = ai_access_levels.get(system_name, 1)
	ai_access_levels[system_name] = clampi(level, 0, 3)
	EventBus.ai_access_changed.emit(system_name, prev, level)


func get_ai_access(system_name: String) -> int:
	return ai_access_levels.get(system_name, 1)


func get_locked_doors() -> Array[String]:
	var locked: Array[String] = []
	for door_id in doors:
		if doors[door_id].is_locked:
			locked.append(door_id)
	return locked


# The Door connecting two adjacent rooms, if any (order-independent). Used by crew
# navigation to find which specific door is blocking a route so it can attempt a
# manual bypass rather than silently failing to path (see CrewMemberNode.move_to_room).
func door_between(room_a: String, room_b: String) -> Door:
	for door_id in doors:
		var door: Door = doors[door_id]
		if (door.room_a_id == room_a and door.room_b_id == room_b) \
				or (door.room_a_id == room_b and door.room_b_id == room_a):
			return door
	return null


# Room lookup by TYPE (room_function) rather than hardcoded room_id — the
# contract generated ships share with the dialogue corpus (docs/dialogue_spec.md)
# and scenario logic (e.g. QuarantineMonitor finding "the medbay" on whichever
# ship layout is currently loaded).
func get_rooms_of_type(room_type: String) -> Array[String]:
	var result: Array[String] = []
	for room_id in rooms:
		var room: RoomBase = rooms[room_id]
		if room and room.room_function == room_type:
			result.append(room_id)
	return result


# First room of the given type, or "" if the current ship has none (shouldn't
# happen for the required types — see ShipLayoutGen ruleset — but callers should
# still handle "" defensively).
func get_room_of_type(room_type: String) -> String:
	var matches: Array[String] = get_rooms_of_type(room_type)
	return matches[0] if not matches.is_empty() else ""


# Crew lookup by job-function ROLE ("captain"/"engineer"/"medic"/"general") rather than a
# hardcoded crew_id — same spirit as get_room_of_type, needed once crew are procedurally
# generated (scripts/procedural/crew_gen.gd) instead of hand-authored with fixed ids like
# "vasquez"/"chen". Prefers a living crew member; falls back to any match, then "".
func get_crew_of_role(role: String) -> String:
	var fallback: String = ""
	for crew_id: String in crew:
		var member: CrewMember = crew[crew_id] as CrewMember
		if member == null or member.role != role:
			continue
		if member.is_alive:
			return crew_id
		if fallback == "":
			fallback = crew_id
	return fallback


# True if any LIVING crew member currently carries the given hidden status flag
# (docs/mission-system-spec.md §5/§6 — infected/changed/shaken/marked). Living-only
# by design: a dead carrier's flag shouldn't keep a delayed-payoff scenario armed.
func any_crew_status(flag: String) -> bool:
	for crew_id: String in crew:
		var member: CrewMember = crew[crew_id] as CrewMember
		if member != null and member.is_alive and member.has_status_flag(flag):
			return true
	return false


# --- Generic situational metrics ---
# Small named-lookup surface for scenario-authored conditions/outcomes (EventPool,
# ScenarioDirector) so scenario .tres/build() data can reference the new Mothership
# situational state without every scenario author needing bespoke GameState methods.
# Supports: "battery_charge", "battery_percent", "ai_core_integrity", and "air:<room_id>".
func get_metric(name: String) -> float:
	if name == "battery_charge":
		return battery_charge
	if name == "battery_percent":
		return 0.0 if battery_capacity <= 0.0 else (battery_charge / battery_capacity) * 100.0
	if name == "ai_core_integrity":
		return ai_core_integrity
	if name == "hull_integrity":
		return hull_integrity
	if name == "credits":
		return credits
	if name.begins_with("air:"):
		return get_room_air(name.substr(4))
	return 0.0


func adjust_metric(name: String, amount: float) -> void:
	if name == "battery_charge":
		set_battery_charge(battery_charge + amount)
	elif name == "ai_core_integrity":
		if amount >= 0.0:
			repair_ai_core(amount)
		else:
			damage_ai_core(-amount, "scenario")
	elif name == "hull_integrity":
		if amount >= 0.0:
			repair_hull(amount)
		else:
			damage_hull(-amount, "scenario")
	elif name == "credits":
		credits = maxf(0.0, credits + amount)
