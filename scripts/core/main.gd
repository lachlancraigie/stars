extends Node2D

# Bootstrap main scene. Press F5 to run The Quarantine.
#
# Keyboard shortcuts for testing without a click UI:
#   SPACE  — pause / unpause time
#   D      — issue a test directive (AI recommends Vasquez report to medbay)
#   I      — isolate Vasquez and set pathogen_contained (trigger win)
#   F      — spike all crew fear to 0.9 (test panic cascade)
#   R      — print current resource levels to Output


func _ready() -> void:
	_setup_ship()
	_setup_crew()
	_add_hud()
	_connect_debug_output()
	_start_scenario()


# --- Setup ---

func _setup_ship() -> void:
	var config: ShipConfig = load("res://resources/ship_configs/class_1_scout.tres")
	if config == null:
		push_warning("Main: class_1_scout.tres failed to load — building config in code")
		config = _build_class1_config()
	ShipLayoutBuilder.build(config, self)


func _setup_crew() -> void:
	_make_crew("martinez", "Cmdr. Martinez", "captain",  0.55, 0.70, [], ["loyalty", "mission_completion"])
	_make_crew("vasquez",  "Vasquez",        "general",  0.50, 0.45, ["alien_biology"], ["survival"])
	_make_crew("okafor",   "Okafor",         "engineer", 0.50, 0.55, [], ["mission_completion"])
	_make_crew("chen",     "Dr. Chen",       "medic",    0.60, 0.60, [], ["crew_welfare", "integrity"])


func _make_crew(id: String, name: String, role: String, ai_trust: float, willpower: float,
		fears: Array, values: Array) -> void:
	var c := CrewMember.new()
	c.crew_id   = id
	c.crew_name = name
	c.role      = role
	c.willpower = willpower
	c.location  = "corridor_main"
	for f: String in fears:
		c.fears.append(f)
	for v: String in values:
		c.values.append(v)
	GameState.crew[id] = c
	GameState.set_ai_trust(id, ai_trust)   # also syncs c.ai_trust via GameState
	# Register in starting room without firing EventBus noise during setup
	var room: RoomBase = GameState.rooms.get("corridor_main") as RoomBase
	if room:
		room.occupants.append(id)


func _add_hud() -> void:
	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn")
	if hud_scene:
		add_child(hud_scene.instantiate())


func _start_scenario() -> void:
	ScenarioRunner.start_scenario(QuarantineScenario.build())
	print("[MAIN] ══════ THE QUARANTINE ══════")
	print("[MAIN] Crew: %s" % ", ".join(GameState.crew.keys()))
	print("[MAIN] Resources: %s" % str(GameState.resources))
	print("[MAIN] SPACE=pause  D=directive  I=isolate  F=fear  R=resources")


# --- Debug signals → Output panel ---

func _connect_debug_output() -> void:
	EventBus.scenario_event_triggered.connect(
		func(id): print("[EVENT]     %s" % id))
	EventBus.crew_state_changed.connect(
		func(cid, old, new_s): print("[CREW]      %s  %s → %s" % [cid, old, new_s]))
	EventBus.crew_died.connect(
		func(cid, cause): print("[CREW]      %s DIED (%s)" % [cid, cause]))
	EventBus.resource_critical.connect(
		func(res, val): print("[CRITICAL]  %s at %.0f%%" % [res, val * 100]))
	EventBus.directive_accepted.connect(
		func(cid, d): print("[DIRECTIVE] %s accepted — %s" % [cid, d.content]))
	EventBus.directive_rejected.connect(
		func(cid, d, reason): print("[DIRECTIVE] %s rejected (%s) — %s" % [cid, reason, d.content]))
	EventBus.ai_trust_changed.connect(
		func(cid, old, nw): print("[TRUST]     %s  %.2f → %.2f" % [cid, old, nw]))
	EventBus.scenario_ended.connect(
		func(outcome): print("[SCENARIO]  ══ ENDED: %s ══" % outcome.to_upper()))


# --- Keyboard test controls ---

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed:
		return
	match event.keycode:
		KEY_SPACE:
			if TimeManager.is_paused():
				TimeManager.unpause()
				print("[MAIN] ▶ Unpaused")
			else:
				TimeManager.pause()
				print("[MAIN] ⏸ Paused")

		KEY_D:
			var d := AIDirective.new()
			d.type        = AIDirective.Type.RECOMMENDATION
			d.target_type = AIDirective.TargetType.CREW
			d.target_id   = "vasquez"
			d.content     = "Vasquez, please report to medbay for a routine health check."
			d.confidence  = 0.85
			d.priority    = 2
			if not AISystem.issue_directive(d):
				print("[MAIN] Directive blocked (insufficient access)")

		KEY_I:
			ScenarioDirector.set_flag("vasquez_isolated")
			ScenarioDirector.set_flag("pathogen_contained")
			print("[MAIN] Vasquez isolated. Pathogen contained. Win condition met.")

		KEY_F:
			for crew_id: String in GameState.crew:
				var c: CrewMember = GameState.crew[crew_id] as CrewMember
				if c and c.is_alive:
					c.fear = 0.9
			print("[MAIN] Fear spiked to 0.9 for all crew.")

		KEY_R:
			print("[RESOURCES] %s" % str(GameState.resources))
			for crew_id: String in GameState.crew:
				var c: CrewMember = GameState.crew[crew_id] as CrewMember
				if c:
					print("  %s  trust=%.2f  fear=%.2f  fatigue=%.2f  state=%s" % [
						c.crew_name, c.ai_trust, c.fear, c.fatigue, c.current_state])


# --- Fallback ship config (in case .tres parse fails on first open) ---

func _build_class1_config() -> ShipConfig:
	var config := ShipConfig.new()
	config.ship_class = 1
	config.ship_name  = "Class 1 Scout"
	config.min_crew   = 3
	config.max_crew   = 6
	config.starting_resources = {
		"oxygen": 1.0, "power": 1.0, "food": 0.8,
		"water": 0.8, "fuel": 1.0, "spare_parts": 0.6, "medicine": 0.5,
	}
	for row in [
		["bridge",       "bridge",       1],
		["engineering",  "reactor",      0],
		["life_support", "life_support", 0],
		["medbay",       "medbay",       0],
		["quarters",     "quarters",     0],
		["cargo",        "cargo",        0],
		["corridor_main","corridor",     0],
	]:
		var rd := RoomDefinition.new()
		rd.room_id = row[0];  rd.room_function = row[1]
		rd.access_level = row[2];  rd.integrity = 1.0
		config.rooms.append(rd)
	for row in [
		["bridge",       "corridor_main", 1.0, "door_bridge",     false],
		["engineering",  "corridor_main", 1.0, "door_engineering", false],
		["life_support", "corridor_main", 1.0, "",                false],
		["medbay",       "corridor_main", 1.0, "",                false],
		["quarters",     "corridor_main", 1.0, "",                false],
		["cargo",        "corridor_main", 1.0, "door_cargo",      false],
		["engineering",  "life_support",  0.5, "",                true],
		["life_support", "cargo",         0.5, "",                true],
	]:
		var cd := ConnectionDefinition.new()
		cd.room_a_id = row[0];  cd.room_b_id = row[1]
		cd.weight = row[2];     cd.door_id = row[3];  cd.maintenance_only = row[4]
		config.connections.append(cd)
	return config
