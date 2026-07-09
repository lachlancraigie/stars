extends Node2D

# Bootstrap main scene. Press F5 to run The Quarantine.
#
# Keyboard shortcuts for testing:
#   SPACE  — pause / unpause time
#   D      — issue a test directive (AI recommends Vasquez report to medbay)
#   I      — isolate Vasquez and set pathogen_contained (trigger win)
#   F      — spike all crew fear to 0.9 (test panic cascade)
#   R      — print current resource levels to Output


const CREW_SCENE: String = "res://scenes/crew/CrewMember.tscn"
const DIRECTIVE_MENU_SCENE: String = "res://scenes/ui/DirectiveMenu.tscn"
const CLEAR_COLOR: Color = Color(0.055, 0.07, 0.10)

# View rect the deck is fitted into (leaves room for the HUD on the left).
const DECK_VIEW: Rect2 = Rect2(280, 40, 1600, 1000)

var _deck: Node2D


func _ready() -> void:
	RenderingServer.set_default_clear_color(CLEAR_COLOR)
	_setup_deck()
	_setup_ship()
	_fit_deck_to_view()
	_setup_crew()
	_spawn_crew_nodes()
	add_child(CrewBehavior.new())
	add_child(QuarantineMonitor.new())
	_add_hud()
	_add_directive_ui()
	_connect_debug_output()
	_start_scenario()
	_setup_autoshot()


# --- Setup ---

func _setup_deck() -> void:
	# One container for rooms, deck furniture, and crew: a single coordinate
	# space so painter's-order z-sorting works across the whole deck.
	_deck = Node2D.new()
	_deck.name = "ShipDeck"
	add_child(_deck)


func _setup_ship() -> void:
	var config: ShipConfig = load("res://resources/ship_configs/class_1_scout.tres")
	if config == null:
		push_warning("Main: class_1_scout.tres failed to load — building config in code")
		config = _build_class1_config()
	ShipLayoutBuilder.build(config, _deck)


func _fit_deck_to_view() -> void:
	var bounds: Rect2 = DeckPlan.deck_bounds()
	var s: float = minf(DECK_VIEW.size.x / bounds.size.x, DECK_VIEW.size.y / bounds.size.y)
	s = minf(s, 1.0)
	_deck.scale = Vector2(s, s)
	_deck.position = DECK_VIEW.get_center() - bounds.get_center() * s


func _setup_crew() -> void:
	_make_crew("martinez", "Cmdr. Martinez", "captain",  0.55, 0.70, "bridge",      [], ["loyalty", "mission_completion"])
	_make_crew("vasquez",  "Vasquez",        "general",  0.50, 0.45, "quarters",    ["alien_biology"], ["survival"])
	_make_crew("okafor",   "Okafor",         "engineer", 0.50, 0.55, "engineering", [], ["mission_completion"])
	_make_crew("chen",     "Dr. Chen",       "medic",    0.60, 0.60, "medbay",      [], ["crew_welfare", "integrity"])


func _make_crew(id: String, name: String, role: String, ai_trust: float, willpower: float,
		start_room: String, fears: Array, values: Array) -> void:
	var c := CrewMember.new()
	c.crew_id   = id
	c.crew_name = name
	c.role      = role
	c.willpower = willpower
	c.location  = start_room
	# Staggered starting needs so eat/sleep/work behaviours surface within
	# the first minutes of a session instead of all at once an hour in.
	c.hunger  = randf_range(0.15, 0.55)
	c.fatigue = randf_range(0.10, 0.50)
	c.boredom = randf_range(0.25, 0.60)
	for f: String in fears:
		c.fears.append(f)
	for v: String in values:
		c.values.append(v)
	GameState.crew[id] = c
	GameState.set_ai_trust(id, ai_trust)   # also syncs c.ai_trust via GameState
	# Register in starting room without firing EventBus noise during setup
	var room: RoomBase = GameState.rooms.get(start_room) as RoomBase
	if room:
		room.occupants.append(id)


func _spawn_crew_nodes() -> void:
	# One visual node per crew resource, inside the deck so coordinates and
	# z-sorting are shared with rooms and props.
	var crew_scene: PackedScene = load(CREW_SCENE)
	for crew_id: String in GameState.crew:
		var node: CrewMemberNode = crew_scene.instantiate()
		node.crew_data = GameState.crew[crew_id] as CrewMember
		_deck.add_child(node)


func _add_hud() -> void:
	var hud_scene: PackedScene = load("res://scenes/ui/HUD.tscn")
	if hud_scene:
		add_child(hud_scene.instantiate())


func _add_directive_ui() -> void:
	add_child(DirectiveActionHandler.new())
	var menu_scene: PackedScene = load(DIRECTIVE_MENU_SCENE)
	if menu_scene:
		add_child(menu_scene.instantiate())


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


# --- Headless verification: SHIPAI_AUTOSHOT=<dir> saves timed screenshots ---
# SHIPAI_AUTODEMO=1 additionally plays the quarantine win path via real
# directives (retrying refusals), exercising the whole loop end to end.

func _setup_autoshot() -> void:
	var dir: String = OS.get_environment("SHIPAI_AUTOSHOT")
	if dir == "":
		return
	var demo: bool = OS.get_environment("SHIPAI_AUTODEMO") != ""
	var shots: Array = [[2.0, "shot_02s"], [8.0, "shot_08s"], [16.0, "shot_16s"]] if not demo \
		else [[2.0, "demo_02s"], [20.0, "demo_20s"], [45.0, "demo_45s"], [70.0, "demo_70s"]]
	for shot in shots:
		get_tree().create_timer(shot[0]).timeout.connect(
			_save_screenshot.bind("%s/%s.png" % [dir, shot[1]]))
	get_tree().create_timer(18.0 if not demo else 72.0).timeout.connect(func(): get_tree().quit())
	if demo:
		_run_autodemo()


func _run_autodemo() -> void:
	# Skip the slow detection beat, then drive the containment plan with the
	# same directives a player would issue, retrying when crew refuse.
	get_tree().create_timer(3.0).timeout.connect(func():
		ScenarioDirector.set_flag("pathogen_detected")
		ScenarioDirector.set_flag("vasquez_infected")
		EventBus.scenario_event_triggered.emit("pathogen_detected"))
	var t := Timer.new()
	t.wait_time = 5.0
	t.timeout.connect(func():
		for pair in [["vasquez", "medbay"], ["chen", "medbay"]]:
			var crew: CrewMember = GameState.crew.get(pair[0]) as CrewMember
			if crew and crew.location != pair[1]:
				var d := AIDirective.new()
				d.type = AIDirective.Type.RECOMMENDATION
				d.target_type = AIDirective.TargetType.CREW
				d.target_id = pair[0]
				d.content = "Proceed to %s." % pair[1]
				d.move_to_room = pair[1]
				d.confidence = 0.9
				d.priority = 3
				AISystem.issue_directive(d))
	add_child(t)
	t.start()


func _save_screenshot(path: String) -> void:
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[AUTOSHOT] saved %s" % path)


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
			d.move_to_room = "medbay"
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
