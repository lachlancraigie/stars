class_name OutcomeApplier
extends RefCounted

# THE one place the docs/mission-system-spec.md §5 outcome vocabulary executes
# (engine task D). ScenarioDirector._apply_outcomes delegates here for every existing
# ScenarioEvent outcome (byte-identical behaviour — the match bodies below are moved
# verbatim from scenario_director.gd, not rewritten) and GenericScenarioMonitor routes
# every timer/watch/check outcome list through the same apply() entry point, so there
# is exactly one interpreter for the whole closed outcome set.
#
# Stateless by design (RefCounted, static methods only — same shape as Checks/WoundTable/
# PanicTable/Items elsewhere in scripts/core): every call carries its own `ctx` dictionary
# rather than this class holding any per-scenario state. `ctx` shape:
#   {"cast": Dictionary (name -> crew_id, resolved once at scenario start by whichever
#            monitor owns it), "away_team": Array[String] (optional explicit override —
#            see resolve_targets' away_team handling), "scenario_instance_id": String}
# ScenarioDirector's own ad-hoc ScenarioEvent outcomes (drawn by EventPool, no monitor
# cast) call apply() with an empty ctx — every new selector still degrades sensibly
# (best_skill/role/random/status/away_team all resolve from live GameState; only
# cast:/bare-cast-name selectors need a non-empty ctx.cast, which legacy events never use).

const CREW_SCENE: String = "res://scenes/crew/CrewMember.tscn"

# crew_injury severity (light|serious|grave) -> WoundTable row range (0-9, low rows are
# flesh_wound/minor_injury, high rows are lethal/fatal — see wound_table.gd's TABLE
# comment). Approximates the spec's three-tier severity vocabulary onto WoundTable's own
# five descriptive tiers without inventing a second wound model.
const INJURY_SEVERITY_ROWS: Dictionary = {
	"light": [0, 3], "serious": [4, 6], "grave": [7, 9],
}


# ============================================================================
# Entry point
# ============================================================================

static func apply(outcomes: Array, ctx: Dictionary = {}) -> void:
	for outcome_v in outcomes:
		var outcome: Dictionary = outcome_v
		_apply_one(outcome, ctx)


static func _apply_one(outcome: Dictionary, ctx: Dictionary) -> void:
	match String(outcome.get("type", "")):
		# --- Existing outcomes (moved verbatim from ScenarioDirector._apply_outcomes) ---
		"resource_delta":
			GameState.adjust_metric(outcome.resource, outcome.amount)
		"crew_fear_spike":
			_spike_crew_fear(outcome.amount, outcome.get("all_crew", true))
		"set_flag":
			ScenarioDirector.set_flag(outcome.flag, outcome.get("value", true))
		"spawn_event":
			ScenarioDirector.trigger_spawned_event(String(outcome.event_id))
		"ai_trust_delta":
			TrustModel.modify_all(outcome.amount)
		"scenario_end":
			EventBus.scenario_ended.emit(outcome.get("outcome", "unknown"))
		"reactor_failure":
			GameState.damage_reactor(outcome.get("source", "scenario"))
		"life_support_failure":
			GameState.damage_life_support(outcome.get("source", "scenario"))
		"ai_core_damage":
			GameState.damage_ai_core(outcome.get("amount", 10.0), outcome.get("source", "scenario"))
		"ai_core_repair":
			GameState.repair_ai_core(outcome.get("amount", 10.0))
		"ship_destroyed":
			GameState.destroy_ship(outcome.get("reason", "scenario"))

		# --- New outcomes (docs/mission-system-spec.md §5 table) ---
		"crew_injury":
			_do_crew_injury(outcome, ctx)
		"crew_stress":
			for crew: CrewMember in resolve_targets(String(outcome.get("target", "random")), ctx):
				crew.add_stress(int(outcome.get("amount", 1)))
		"crew_status_flag":
			for crew: CrewMember in resolve_targets(String(outcome.get("target", "random")), ctx):
				crew.set_status_flag(String(outcome.get("flag", "")), bool(outcome.get("value", true)))
		"crew_join":
			_do_crew_join(outcome)
		"crew_leave":
			for crew: CrewMember in resolve_targets(String(outcome.get("target", "random")), ctx):
				_do_crew_leave(crew, String(outcome.get("reason", "scenario")))
		"crew_kill":
			for crew: CrewMember in resolve_targets(String(outcome.get("target", "random")), ctx):
				CrewLifecycle.kill(crew, String(outcome.get("cause", "scenario")))
		"grant_item":
			var item_id: String = String(outcome.get("item_id", ""))
			for crew: CrewMember in resolve_targets(String(outcome.get("target", "random")), ctx):
				if item_id != "" and item_id not in crew.inventory:
					crew.inventory.append(item_id)
		"remove_item":
			var rm_item: String = String(outcome.get("item_id", ""))
			for crew: CrewMember in resolve_targets(String(outcome.get("target", "random")), ctx):
				crew.inventory.erase(rm_item)
		"hull_damage":
			GameState.adjust_metric("hull_integrity", -float(outcome.get("amount", 0.0)))
		"hull_repair":
			GameState.adjust_metric("hull_integrity", float(outcome.get("amount", 0.0)))
		"spawn_intruder":
			IntruderSystem.spawn(String(outcome.get("intruder_type", "stalker")), String(outcome.get("room", "random")))
		"intruder_remove":
			var iid: String = String(outcome.get("intruder_id", "all"))
			if iid == "all":
				IntruderSystem.despawn_all()
			else:
				IntruderSystem.despawn(iid)
		"radio_line":
			_do_radio_line(outcome, ctx)
		"objective_complete":
			MissionManager.force_complete_objective(String(outcome.get("objective_id", "")))
		"objective_fail":
			MissionManager.force_fail_objective(String(outcome.get("objective_id", "")))
		"mission_abort":
			MissionManager.mission_abort(String(outcome.get("reason", "scenario")))
		"door_lock_room":
			_do_door_lock_room(String(outcome.get("room", "")))
		"air_vent_room":
			_do_air_vent_room(String(outcome.get("room", "")), float(outcome.get("amount", 0.0)))
		_:
			push_warning("OutcomeApplier: unknown outcome type '%s' — skipped" % String(outcome.get("type", "")))


# ============================================================================
# Existing-outcome helpers (moved from ScenarioDirector)
# ============================================================================

static func _spike_crew_fear(amount: float, all_crew: bool) -> void:
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive and (all_crew or crew.role == "general"):
			crew.fear = minf(1.0, crew.fear + amount)
			EventBus.crew_need_changed.emit(crew_id, "fear", crew.fear)


# ============================================================================
# New-outcome helpers
# ============================================================================

static func _do_crew_injury(outcome: Dictionary, ctx: Dictionary) -> void:
	var severity: String = String(outcome.get("severity", "serious"))
	var rows: Array = INJURY_SEVERITY_ROWS.get(severity, INJURY_SEVERITY_ROWS["serious"])
	var wound_type: String = String(outcome.get("wound_type", ""))
	for crew: CrewMember in resolve_targets(String(outcome.get("target", "random")), ctx):
		var this_wound_type: String = wound_type
		if this_wound_type == "" or this_wound_type not in WoundTable.WOUND_TYPES:
			this_wound_type = WoundTable.WOUND_TYPES[randi() % WoundTable.WOUND_TYPES.size()]
		WoundTable.roll_and_apply(crew, this_wound_type, int(rows[0]), int(rows[1]))


static func _do_crew_join(outcome: Dictionary) -> void:
	# archetype (spec: optional) — CrewGen's archetype selection is role/rank-driven,
	# not a literal lookup by tag, so this mirrors AwayResolver._do_survivor()'s
	# "rescued stranger" pattern rather than threading a specific archetype through.
	var gen_seed: int = randi()
	var roster: Array[CrewMember] = CrewGen.generate_roster(gen_seed, 1, [])
	if roster.is_empty():
		return
	var new_crew: CrewMember = roster[0]
	new_crew.crew_id = "joined_%d" % gen_seed
	new_crew.rank = "crew_mate"

	var room_id: String = GameState.get_room_of_type("airlock")
	if room_id == "":
		room_id = GameState.resolve_room_selector("random")
	new_crew.location = room_id

	GameState.crew[new_crew.crew_id] = new_crew
	GameState.set_ai_trust(new_crew.crew_id, 0.4)   # a new face — trust starts low, not default
	if room_id != "":
		var room: RoomBase = GameState.rooms.get(room_id) as RoomBase
		if room:
			room.occupants.append(new_crew.crew_id)

	var crew_scene: PackedScene = load(CREW_SCENE)
	if crew_scene == null:
		return
	var node: CrewMemberNode = crew_scene.instantiate()
	node.crew_data = new_crew
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	var deck: Node = tree.current_scene.get_node_or_null("ShipDeck")
	if deck != null:
		deck.add_child(node)


static func _do_crew_leave(crew: CrewMember, reason: String) -> void:
	var room: RoomBase = GameState.rooms.get(crew.location) as RoomBase
	if room != null:
		room.remove_occupant(crew.crew_id)
	var node: CrewMemberNode = CrewMemberNode.nodes.get(crew.crew_id) as CrewMemberNode
	if node != null:
		node.queue_free()
	GameState.crew.erase(crew.crew_id)
	GameState.ai_trust_scores.erase(crew.crew_id)
	push_warning("OutcomeApplier: crew_leave — %s departed (%s)" % [crew.crew_id, reason])


static func _do_radio_line(outcome: Dictionary, ctx: Dictionary) -> void:
	var text: String = String(outcome.get("text", ""))
	if text == "":
		return
	var speaker_sel: String = String(outcome.get("speaker", "contact"))
	if speaker_sel == "" or speaker_sel == "contact":
		EventBus.radio_bark.emit(text, "contact")
		return
	var targets: Array[CrewMember] = resolve_targets(speaker_sel, ctx)
	if targets.is_empty():
		# Degrades to an off-ship voice rather than silently dropping the line —
		# same "never hard-fail on an unresolved target" spirit as every other
		# selector consumer in this file.
		EventBus.radio_bark.emit(text, "contact")
		return
	var speaker: CrewMember = targets[0]
	if speaker.off_ship:
		# An away-team crew member speaking through the radio_line vocabulary — same
		# "tense" default AwayResolver's own barks use for anything short of good/bad news.
		EventBus.radio_bark.emit(text, "tense")
	else:
		# Reuses the exact bubble path DialogueSystem._speak() drives (line_key ""
		# skips the voice-file lookup safely — see CrewMemberNode._play_voice_line).
		EventBus.line_spoken.emit(speaker.crew_id, "", text, "speech")


static func _do_door_lock_room(room_selector: String) -> void:
	if room_selector == "":
		return
	var room_ids: Array[String] = GameState.get_rooms_of_type(room_selector)
	if room_ids.is_empty() and GameState.rooms.has(room_selector):
		room_ids = [room_selector]
	if room_ids.is_empty():
		push_warning("OutcomeApplier: door_lock_room — no room matches '%s'" % room_selector)
		return
	for door_id: String in GameState.doors:
		var door: Door = GameState.doors[door_id]
		if door.room_a_id in room_ids or door.room_b_id in room_ids:
			door.lock()


static func _do_air_vent_room(room_selector: String, amount: float) -> void:
	if room_selector == "" or amount <= 0.0:
		return
	var room_id: String = GameState.resolve_room_selector(room_selector)
	if room_id == "":
		push_warning("OutcomeApplier: air_vent_room — no room matches '%s'" % room_selector)
		return
	GameState.set_room_air(room_id, GameState.get_room_air(room_id) - amount)


# ============================================================================
# Target selector grammar (docs/mission-system-spec.md §5 / tools/missions/validate_content.py
# selector_ok / BEST_SKILL_SELECTOR) — implemented 1:1 with the validator's closed grammar:
#   random | all | away_team | role:<role> | cast:<name> | status:<flag> | a bare cast
#   name | best_skill:<Skill>. "contact" is radio_line-only and handled by its own outcome
#   above, never resolved to a CrewMember here.
# ============================================================================

static func resolve_targets(selector: String, ctx: Dictionary = {}) -> Array[CrewMember]:
	var sel: String = selector.strip_edges()
	var cast: Dictionary = ctx.get("cast", {})
	# NB: every branch returns through an explicitly-typed Array[CrewMember] local,
	# never a bare []/[x] literal inside a ternary — GDScript leaves ternary array
	# literals untyped at runtime, which fails assignment at typed call sites.
	var none: Array[CrewMember] = []

	if sel == "" or sel == "contact":
		return none
	if sel == "random":
		var living: Array[CrewMember] = _aboard_living_crew()
		if living.is_empty():
			return none
		var one: Array[CrewMember] = [living[randi() % living.size()]]
		return one
	if sel == "all":
		return _aboard_living_crew()
	if sel == "away_team":
		return _away_team_crew(ctx)
	if sel.begins_with("role:"):
		return _crew_with_role(sel.substr(5))
	if sel.begins_with("status:"):
		return _crew_with_status(sel.substr(7))
	if sel.begins_with("cast:"):
		return _cast_lookup(cast, sel.substr(5))
	if sel.begins_with("best_skill:"):
		return _best_skill_target(sel.substr(11))
	if cast.has(sel):   # bare cast name (any key of the scenario's monitor.cast)
		return _cast_lookup(cast, sel)

	push_warning("OutcomeApplier: unresolvable target selector '%s'" % sel)
	return none


static func _aboard_living_crew() -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for crew_id: String in GameState.crew:
		var c: CrewMember = GameState.crew[crew_id] as CrewMember
		if c != null and c.is_alive and not c.off_ship:
			out.append(c)
	return out


static func _crew_with_role(role: String) -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for crew_id: String in GameState.crew:
		var c: CrewMember = GameState.crew[crew_id] as CrewMember
		if c != null and c.is_alive and c.role == role:
			out.append(c)
	return out


static func _crew_with_status(flag: String) -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for crew_id: String in GameState.crew:
		var c: CrewMember = GameState.crew[crew_id] as CrewMember
		if c != null and c.is_alive and c.has_status_flag(flag):
			out.append(c)
	return out


# ctx.away_team, if supplied, is an explicit crew_id list (e.g. an away_return-context
# scenario's own bookkeeping); otherwise falls back to a live scan for whoever is
# currently off_ship — always available with zero setup, matching "most recent op's
# members" for the common case of exactly one active away op.
static func _away_team_crew(ctx: Dictionary) -> Array[CrewMember]:
	var ids: Array = ctx.get("away_team", [])
	var out: Array[CrewMember] = []
	if not ids.is_empty():
		for crew_id in ids:
			var c: CrewMember = GameState.crew.get(String(crew_id)) as CrewMember
			if c != null and c.is_alive:
				out.append(c)
		return out
	for crew_id: String in GameState.crew:
		var c: CrewMember = GameState.crew[crew_id] as CrewMember
		if c != null and c.is_alive and c.off_ship:
			out.append(c)
	return out


static func _cast_lookup(cast: Dictionary, name: String) -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	var crew_id: String = String(cast.get(name, ""))
	if crew_id == "":
		return out
	var c: CrewMember = GameState.crew.get(crew_id) as CrewMember
	if c != null and c.is_alive:
		out.append(c)
	return out


# Highest-bonus living crew member (aboard) in the named skill — same resolution as
# monitor-check crew selection (spec §5: "the natural whoever attempted the solve").
static func _best_skill_target(skill: String) -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	var living: Array[CrewMember] = _aboard_living_crew()
	if living.is_empty():
		return out
	var best: CrewMember = living[0]
	var best_bonus: int = best.get_skill_bonus(skill)
	for c: CrewMember in living:
		var bonus: int = c.get_skill_bonus(skill)
		if bonus > best_bonus:
			best_bonus = bonus
			best = c
	out.append(best)
	return out
