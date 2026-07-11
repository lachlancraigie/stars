extends Node

# Autoload IntruderSystem (docs/mission-system-spec.md §9). Room-granular hostile
# presence — NO pathfinding sprite this sprint (the player is a ship AI; it sees
# sensor contacts, not a walking monster — cheaper and scarier). Registered in
# project.godot after MissionManager; depends only on EventBus/GameState/TimeManager,
# all already booted by the time any scenario/monitor spawns an intruder.
#
# Data-driven per docs/mission-system-spec.md §9's three types — extend INTRUDER_TABLE
# for a new type; nothing else in this file needs to change.
#   stalker — moves room-to-room, prefers rooms adjacent to isolated crew.
#   nest    — static, steadily degrades its room's air quality.
#   mimic   — dormant (hidden) until a crew member has shared its room on two separate
#             occasions, then activates and behaves like a stalker from then on.
#
# Combat (spec: "WoundTable/apply_damage — FINALLY its first caller", CLAUDE.md backlog
# item 3): every tick a living, aboard crew member shares a room with an intruder, a
# combat round resolves. Marine-class or any crew with a real weapon equipped fight back
# (Checks.perform_check "combat" stat -> weapon damage_dice against the intruder's own
# small health pool); the intruder strikes back at a random fighter via
# CrewMember.apply_damage (the real Health/Wounds pipeline — WoundTable rolls once health
# hits 0, same as any other damage source). Unarmed/civilian crew take a Fear save
# ("hazard roll") and, on failure, are pushed straight into CrewStateMachine.PANICKING —
# CrewBehavior already flees a panicking crew member to a random neighbouring room on its
# own next decision tick, so no new movement code is written here (reuses the existing
# panic/flee state machinery exactly as instructed).

const INTRUDER_TABLE: Dictionary = {
	"stalker": {
		"max_health": 25, "move_min": 20.0, "move_max": 40.0, "static": false,
		"hidden_until_contact": false, "wound_type": "gore_massive", "damage_dice": "2d10",
		"air_drain_per_sec": 0.0, "combat_interval": 8.0,
	},
	"nest": {
		"max_health": 40, "move_min": 0.0, "move_max": 0.0, "static": true,
		"hidden_until_contact": false, "wound_type": "gore_massive", "damage_dice": "1d5",
		"air_drain_per_sec": 0.6, "combat_interval": 10.0,
	},
	"mimic": {
		"max_health": 20, "move_min": 20.0, "move_max": 40.0, "static": false,
		"hidden_until_contact": true, "wound_type": "blunt_force", "damage_dice": "1d10+1",
		"air_drain_per_sec": 0.0, "combat_interval": 6.0, "trigger_shares_needed": 2,
	},
}

const COMBAT_FEAR_SPIKE: float = 0.15
const FLEE_FEAR_ON_FAIL: float = 1.0     # guarantees CrewStateMachine.PANICKING next evaluation
const FLEE_FEAR_ON_SUCCESS: float = 0.2

var _intruders: Dictionary = {}   # id -> {id, type, room, health, max_health, move_timer,
                                   #        combat_timer, visible, dormant, was_occupied, occupancy_events}
var _next_id: int = 0


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)


# ============================================================================
# Public API
# ============================================================================

# `room_selector`: a room TYPE ("cargo"), a literal room id, or "random" — same
# grammar as GameState.resolve_room_selector (spec §5's spawn_intruder outcome params).
func spawn(intruder_type: String, room_selector: String) -> String:
	if not INTRUDER_TABLE.has(intruder_type):
		push_warning("IntruderSystem: unknown intruder_type '%s'" % intruder_type)
		return ""
	var room_id: String = GameState.resolve_room_selector(room_selector)
	if room_id == "":
		push_warning("IntruderSystem: spawn — no room resolves from selector '%s'" % room_selector)
		return ""
	var table: Dictionary = INTRUDER_TABLE[intruder_type]
	var id: String = "intr_%d" % _next_id
	_next_id += 1
	var dormant: bool = bool(table.get("hidden_until_contact", false))
	var state: Dictionary = {
		"id": id, "type": intruder_type, "room": room_id,
		"health": int(table.get("max_health", 20)), "max_health": int(table.get("max_health", 20)),
		"move_timer": randf_range(float(table.get("move_min", 20.0)), float(table.get("move_max", 40.0))),
		"combat_timer": float(table.get("combat_interval", 8.0)),
		"dormant": dormant, "was_occupied": false, "occupancy_events": 0,
	}
	state["visible"] = not dormant and not GameState.is_room_sensor_gapped(room_id)
	_intruders[id] = state
	EventBus.intruder_spawned.emit(id, room_id, state["visible"])
	print("[INTRUDER] spawned %s (%s) in %s visible=%s" % [id, intruder_type, room_id, state["visible"]])
	return id


# Removes an intruder from the board — combat death and a narrative despawn
# (spec's `intruder_remove` outcome: "fled/died narratively") both route here and
# both fire intruder_killed, the only "gone from the sensor board" signal the spec
# defines (§11's closed EventBus signal list has no separate despawn signal).
func despawn(id: String) -> void:
	if not _intruders.has(id):
		return
	var room_id: String = String((_intruders[id] as Dictionary).get("room", ""))
	_intruders.erase(id)
	EventBus.intruder_killed.emit(id, room_id)
	print("[INTRUDER] removed %s from %s" % [id, room_id])


func despawn_all() -> void:
	for id: String in _intruders.keys():
		despawn(id)


func active_intruders() -> Array[String]:
	var out: Array[String] = []
	for id: String in _intruders.keys():
		out.append(id)
	return out


func room_of(id: String) -> String:
	return String((_intruders[id] as Dictionary).get("room", "")) if _intruders.has(id) else ""


func type_of(id: String) -> String:
	return String((_intruders[id] as Dictionary).get("type", "")) if _intruders.has(id) else ""


func is_visible(id: String) -> bool:
	return _intruders.has(id) and bool((_intruders[id] as Dictionary).get("visible", false))


# First VISIBLE intruder currently in `room_id`, or "" — the one HUD.gd's room-overlay
# marker needs (spec §9: "red blip + type label when visible").
func intruder_in_room(room_id: String) -> String:
	for id: String in _intruders.keys():
		var state: Dictionary = _intruders[id]
		if String(state.get("room", "")) == room_id and bool(state.get("visible", false)):
			return id
	return ""


# AI counterplay (spec §9: "direct a hunt — hunt_intruder directive type via
# DirectiveActionHandler"). Issues one directive per eligible marine/armed crew member
# (Architecture Rule 1 respected: this only ISSUES directives, same as ShuttleSystem's
# away-op request — DirectiveActionHandler plays out the actual movement, and only once
# each crew member individually accepts via the normal ObedienceEngine path).
func request_hunt(intruder_id: String) -> Dictionary:
	if not _intruders.has(intruder_id):
		return {"ok": false, "reason": "No such contact."}
	var room_id: String = room_of(intruder_id)
	var candidates: Array[String] = []
	for crew_id: String in GameState.crew:
		var c: CrewMember = GameState.crew[crew_id] as CrewMember
		if c == null or not c.is_alive or c.off_ship:
			continue
		if c.current_state in [CrewStateMachine.INCAPACITATED, CrewStateMachine.FROZEN]:
			continue
		if c.mship_class == "Marine" or (c.equipped_weapon != "" and c.equipped_weapon != "unarmed"):
			candidates.append(crew_id)
	if candidates.is_empty():
		return {"ok": false, "reason": "No armed crew available to send."}
	for crew_id: String in candidates:
		var d := AIDirective.new()
		d.type = AIDirective.Type.INSTRUCTION
		d.target_type = AIDirective.TargetType.CREW
		d.target_id = crew_id
		d.content = "Contact in %s — investigate and engage." % _room_display(room_id)
		d.confidence = 0.75
		d.priority = 4
		d.content_tags = ["danger"]
		d.hunt_intruder_id = intruder_id
		AISystem.issue_directive(d)
	return {"ok": true, "reason": ""}


func _room_display(room_id: String) -> String:
	return room_id.capitalize().replace("_", " ")


# ============================================================================
# Tick
# ============================================================================

func _on_tick(_elapsed: float, delta: float) -> void:
	for id: String in _intruders.keys():
		if not _intruders.has(id):   # despawned earlier this same tick (e.g. combat death)
			continue
		_tick_one(id, delta)


func _tick_one(id: String, delta: float) -> void:
	var state: Dictionary = _intruders[id]
	var table: Dictionary = INTRUDER_TABLE.get(String(state.get("type", "")), {})
	if table.is_empty():
		return

	if bool(state.get("dormant", false)):
		_tick_mimic_dormant(id, state, table)
		if bool(state.get("dormant", false)):
			return   # still hasn't triggered — no movement/combat/air-drain yet

	var drain: float = float(table.get("air_drain_per_sec", 0.0))
	if drain > 0.0:
		var room_id: String = String(state.get("room", ""))
		GameState.set_room_air(room_id, GameState.get_room_air(room_id) - drain * delta)

	if not bool(table.get("static", false)):
		state["move_timer"] = float(state.get("move_timer", 0.0)) - delta
		if state["move_timer"] <= 0.0:
			_attempt_move(id, state, table)
			state["move_timer"] = randf_range(float(table.get("move_min", 20.0)), float(table.get("move_max", 40.0)))

	var occupants: Array[CrewMember] = _living_crew_in_room(String(state.get("room", "")))
	if occupants.is_empty():
		state["combat_timer"] = float(table.get("combat_interval", 8.0))
		return
	state["combat_timer"] = float(state.get("combat_timer", 0.0)) - delta
	if state["combat_timer"] <= 0.0:
		state["combat_timer"] = float(table.get("combat_interval", 8.0))
		_resolve_combat_round(id, state, table, occupants)


func _tick_mimic_dormant(id: String, state: Dictionary, table: Dictionary) -> void:
	var room_id: String = String(state.get("room", ""))
	var occupied: bool = not _living_crew_in_room(room_id).is_empty()
	var was_occupied: bool = bool(state.get("was_occupied", false))
	if occupied and not was_occupied:
		state["occupancy_events"] = int(state.get("occupancy_events", 0)) + 1
	state["was_occupied"] = occupied
	var needed: int = int(table.get("trigger_shares_needed", 2))
	if int(state.get("occupancy_events", 0)) < needed:
		return
	state["dormant"] = false
	state["visible"] = not GameState.is_room_sensor_gapped(room_id)
	state["move_timer"] = randf_range(float(table.get("move_min", 20.0)), float(table.get("move_max", 40.0)))
	state["combat_timer"] = float(table.get("combat_interval", 6.0))
	print("[INTRUDER] mimic '%s' triggered in %s" % [id, room_id])
	EventBus.intruder_moved.emit(id, room_id, room_id)   # no room change — signals "now visible" to any HUD listener


func _attempt_move(id: String, state: Dictionary, table: Dictionary) -> void:
	var current_room: String = String(state.get("room", ""))
	var graph: ShipGraph = GameState.ship_graph
	if graph == null:
		return
	var blocked: Array[String] = GameState.get_locked_doors()
	var neighbours: Array[String] = graph.get_neighbours(current_room, false, blocked)
	if neighbours.is_empty():
		return
	var target: String = _pick_move_target(state, neighbours)
	state["room"] = target
	state["visible"] = not GameState.is_room_sensor_gapped(target)
	print("[INTRUDER] %s (%s) moved %s -> %s" % [id, state.get("type", ""), current_room, target])
	EventBus.intruder_moved.emit(id, current_room, target)


# Stalkers prefer a room with exactly one crew member (isolated prey); nest never moves
# (static, filtered out before this is called); mimic (once triggered) behaves like a
# plain stalker too — same preference logic applies regardless of type name.
func _pick_move_target(state: Dictionary, neighbours: Array[String]) -> String:
	var isolated: Array[String] = []
	var occupied: Array[String] = []
	for room_id: String in neighbours:
		var count: int = _living_crew_in_room(room_id).size()
		if count == 1:
			isolated.append(room_id)
		elif count > 1:
			occupied.append(room_id)
	if not isolated.is_empty():
		return isolated[randi() % isolated.size()]
	if not occupied.is_empty() and randf() < 0.5:
		return occupied[randi() % occupied.size()]
	return neighbours[randi() % neighbours.size()]


func _living_crew_in_room(room_id: String) -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for crew_id: String in GameState.crew:
		var c: CrewMember = GameState.crew[crew_id] as CrewMember
		if c != null and c.is_alive and not c.off_ship and c.location == room_id:
			out.append(c)
	return out


func _resolve_combat_round(id: String, state: Dictionary, table: Dictionary, occupants: Array[CrewMember]) -> void:
	for c: CrewMember in occupants:
		c.fear = minf(1.0, c.fear + COMBAT_FEAR_SPIKE)
		EventBus.crew_need_changed.emit(c.crew_id, "fear", c.fear)

	var fighters: Array[CrewMember] = []
	var civilians: Array[CrewMember] = []
	for c: CrewMember in occupants:
		if c.mship_class == "Marine" or (c.equipped_weapon != "" and c.equipped_weapon != "unarmed"):
			fighters.append(c)
		else:
			civilians.append(c)

	print("[INTRUDER] combat round: %s (%s) in %s — fighters=%d civilians=%d hp=%d/%d" % [
		id, state.get("type", ""), state.get("room", ""), fighters.size(), civilians.size(),
		int(state.get("health", 0)), int(state.get("max_health", 0))])

	if fighters.is_empty():
		for c: CrewMember in civilians:
			_attempt_flee(c)
		return

	for f: CrewMember in fighters:
		var result: Checks.CheckResult = Checks.perform_check(f, "combat", "", false, false)
		if result.success:
			var weapon_id: String = f.equipped_weapon if f.equipped_weapon != "" else "unarmed"
			var dmg: int = _roll_dice_string(String(Items.get_item(weapon_id).get("damage_dice", "1d5")), f)
			state["health"] = maxi(0, int(state.get("health", 0)) - dmg)

	if int(state.get("health", 0)) <= 0:
		despawn(id)
		return

	var target: CrewMember = fighters[randi() % fighters.size()]
	var dmg2: int = _roll_dice_string(String(table.get("damage_dice", "1d5")))
	target.apply_damage(dmg2, String(table.get("wound_type", "blunt_force")))

	for c: CrewMember in civilians:
		_attempt_flee(c)


# "Hazard roll" — a Fear save; failure pushes the crew member straight into
# CrewStateMachine.PANICKING (fear >= 0.85 threshold) so CrewBehavior's own next
# decision tick flees them to a random neighbouring room. No new movement code.
func _attempt_flee(c: CrewMember) -> void:
	var result: Checks.CheckResult = Checks.perform_check(c, "fear", "", false, false)
	c.fear = FLEE_FEAR_ON_FAIL if not result.success else minf(1.0, c.fear + FLEE_FEAR_ON_SUCCESS)
	EventBus.crew_need_changed.emit(c.crew_id, "fear", c.fear)


static func _roll_dice_string(dice_str: String, crew: CrewMember = null) -> int:
	if dice_str == "STR/10":
		return int(float(crew.strength) / 10.0) if crew != null else 3
	var plus_split: PackedStringArray = dice_str.split("+")
	var base: String = plus_split[0]
	var bonus: int = int(plus_split[1]) if plus_split.size() > 1 else 0
	var dm: PackedStringArray = base.split("d")
	if dm.size() != 2:
		return 1
	var count: int = int(dm[0])
	var sides: int = maxi(int(dm[1]), 1)
	var total: int = 0
	for _i in count:
		total += randi_range(1, sides)
	return total + bonus
