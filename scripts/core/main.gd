extends Node2D

# Bootstrap main scene. Press F5 to run the selected scenario (The Quarantine by
# default; SHIPAI_SCENARIO=narrow_passage selects The Narrow Passage).
#
# Keyboard shortcuts for testing:
#   SPACE  — pause / unpause time
#   D      — issue a test directive (AI recommends Vasquez report to medbay)
#   I      — isolate Vasquez and set pathogen_contained (trigger win)
#   F      — spike all crew fear to 0.9 (test panic cascade)
#   R      — print current resource levels to Output
#
# Camera: mouse wheel zooms toward the cursor, left/middle/right-drag pans
# (left has a small threshold so click-on-crew still works), WASD/arrows pan
# too. See scripts/ship/deck_camera.gd for the fit/clamp math.


const CREW_SCENE: String = "res://scenes/crew/CrewMember.tscn"
const DIRECTIVE_MENU_SCENE: String = "res://scenes/ui/DirectiveMenu.tscn"
const ROSTER_PANEL_SCENE: String = "res://scenes/ui/RosterPanel.tscn"
const ENVIRONMENT_MENU_SCENE: String = "res://scenes/ui/EnvironmentMenu.tscn"
const CLEAR_COLOR: Color = Color(0.055, 0.07, 0.10)

# Rect (screen px) the deck is auto-fitted into at the default zoom — kept
# narrower than the full 1920x1080 canvas to leave headroom for the HUD's
# power panel in the top-left. DeckCamera.configure() uses only .size (the
# camera centers on the full viewport, not this rect's offset centre — see
# deck_camera.gd for why: it'd otherwise fight the pan-clamp's own centering
# behaviour when zoomed all the way out).
const DECK_VIEW: Rect2 = Rect2(280, 40, 1600, 1000)

var _deck: Node2D
var _camera: DeckCamera

# Scenario selection (SHIPAI_SCENARIO env var): "quarantine" (default) or
# "narrow_passage". Chosen before crew placement so scenario casting (e.g. the
# narrow passage's medbay patient) can happen at setup time.
var _scenario_key: String = "quarantine"

# Mission mode (docs/mission-system-spec.md §12) is the default boot path. Setting
# SHIPAI_SCENARIO still boots the legacy scenario-only path unchanged — every
# existing AUTODEMO/acceptance run stays green — so this flag is decided once in
# _choose_scenario() and gates which path _ready() takes at the bottom of setup.
var _legacy_scenario_boot: bool = false


func _ready() -> void:
	RenderingServer.set_default_clear_color(CLEAR_COLOR)
	_choose_ship_seed()
	_choose_scenario()
	_setup_starfield()
	_setup_approach_visual()
	_setup_deck()
	_setup_ship()
	_setup_camera()
	_setup_crew()
	_spawn_crew_nodes()
	add_child(CrewBehavior.new())
	add_child(RepairBehavior.new())
	add_child(RelationshipBehavior.new())
	add_child(CrewProgression.new())
	add_child(AICoreSystem.new())
	_add_hud()
	_add_directive_ui()
	_connect_debug_output()
	if _legacy_scenario_boot:
		_start_scenario()
		_setup_autoshot()
		_setup_force_flags()
		_setup_force_kill()
	else:
		_start_mission_mode()


# --- Setup ---

# Ships are procedurally generated every load (seeded RNG) so layouts differ
# run to run while staying governed by ShipLayoutGen's ruleset. The seed is
# stored on GameState so a save can reproduce the exact same layout later.
# SHIPAI_SEED lets tooling (screenshots, demos, tests) pin a specific layout.
# Chosen before the starfield/ship are built so both can use the same seed.
func _choose_ship_seed() -> void:
	var seed_env: String = OS.get_environment("SHIPAI_SEED")
	GameState.ship_seed = int(seed_env) if seed_env != "" else randi()
	GameState.ship_class_id = "freighter"


# SHIPAI_SCENARIO env override selects the scripted scenario; quarantine stays the
# default. Unknown values fall back to quarantine with a warning rather than failing.
func _choose_scenario() -> void:
	var env: String = OS.get_environment("SHIPAI_SCENARIO").to_lower().strip_edges()
	if env == "":
		return
	_legacy_scenario_boot = true
	if env in ["quarantine", "narrow_passage"]:
		_scenario_key = env
	else:
		push_warning("Unknown SHIPAI_SCENARIO '%s' — falling back to quarantine" % env)


func _setup_starfield() -> void:
	# Wrapped in its own CanvasLayer so it stays fixed to the viewport instead
	# of panning/zooming with DeckCamera — a Camera2D's transform applies to
	# the WHOLE viewport's canvas, not just its own subtree, so merely being a
	# non-ShipDeck sibling (the old no-camera trick) is no longer enough once
	# DeckCamera exists. A negative layer keeps it behind the un-layered world
	# content (rooms/hull, drawn at the implicit layer 0) and behind the HUD
	# (default layer 1); very low z_index within its own layer keeps it behind
	# nothing else matters there since it's the only thing on this layer.
	var layer := CanvasLayer.new()
	layer.name = "StarfieldLayer"
	layer.layer = -10
	add_child(layer)

	var field := Starfield.new()
	field.name = "Starfield"
	field.set_seed_value(GameState.ship_seed)
	layer.add_child(field)


# Mission destination art (docs/mission-system-spec.md §8) — same fixed-to-viewport
# CanvasLayer trick as _setup_starfield above (see its comment for why), layered
# between the starfield (-10) and the ship deck's implicit layer 0 so destination
# art reads as background behind rooms/hull but in front of the stars. Added
# unconditionally (harmless/idle in legacy scenario mode — it only reacts to
# mission_phase_changed/destination_sighted, neither of which fire outside mission
# mode) so nothing else in setup needs to branch on _legacy_scenario_boot.
func _setup_approach_visual() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ApproachVisualLayer"
	layer.layer = -5
	add_child(layer)

	var visual := ApproachVisual.new()
	visual.name = "ApproachVisual"
	layer.add_child(visual)


func _setup_deck() -> void:
	# One container for rooms, deck furniture, and crew: a single coordinate
	# space so painter's-order z-sorting works across the whole deck.
	_deck = Node2D.new()
	_deck.name = "ShipDeck"
	add_child(_deck)


func _setup_ship() -> void:
	var config: ShipConfig = ShipLayoutGen.generate(GameState.ship_seed, GameState.ship_class_id)
	GameState.ship_name = config.ship_name
	print("[MAIN] Ship seed: %d (%s)" % [GameState.ship_seed, GameState.ship_class_id])
	ShipLayoutBuilder.build(config, _deck)


func _setup_camera() -> void:
	# _deck itself stays at identity transform now — DeckCamera owns all
	# fit/zoom/pan framing (previously baked as a static scale/position onto
	# ShipDeck). Sibling of _deck (both direct children of Main), not a child
	# of it: Camera2D.current re-frames the whole viewport regardless of tree
	# position, so nothing about ShipDeck's own contents needs to change.
	_camera = DeckCamera.new()
	_camera.name = "DeckCamera"
	add_child(_camera)
	_camera.configure(DeckPlan.deck_bounds(), DECK_VIEW)


const ROLE_START_ROOM_TYPE: Dictionary = {
	"captain": "bridge", "engineer": "engine_room", "medic": "medbay", "general": "quarters",
}
const ROLE_START_TRUST: Dictionary = {
	"captain": 0.55, "engineer": 0.50, "medic": 0.60, "general": 0.50,
}
const ROLE_FEARS: Dictionary = {
	"general": ["alien_biology"],
}
const ROLE_VALUES: Dictionary = {
	"captain": ["loyalty", "mission_completion"],
	"engineer": ["mission_completion"],
	"medic": ["crew_welfare", "integrity"],
	"general": ["survival"],
}


# Crew are generated by CrewGen (Mothership 1e stats/saves/skills/equipment), seeded from
# the same GameState.ship_seed as the ship layout so a given seed always produces the same
# roster. Role coverage (a command/engineering/medical-skilled crew member) is guaranteed
# by the generator itself — see CrewGen.generate_roster(). Start rooms are resolved by
# TYPE, not hardcoded id — room ids vary per generated ship (e.g. "quarters_1"), but
# there's always exactly one bridge/medbay/engine_room and at least one quarters (see
# ShipLayoutGen ruleset).
func _setup_crew() -> void:
	var roster: Array[CrewMember] = CrewGen.generate_roster(GameState.ship_seed, 4,
		["captain", "engineer", "medic", "general"])
	for crew in roster:
		_place_crew(crew)


func _place_crew(crew: CrewMember) -> void:
	var start_room_type: String = ROLE_START_ROOM_TYPE.get(crew.role, "quarters")
	# Scenario casting (The Narrow Passage, bible Act 2): the general-role crew
	# member starts as the fragile patient — unconscious in the medbay, alongside
	# the medic (whose start room is already the medbay). Setup-time initial state,
	# same territory as the needs/fears/values seeding below — the running scenario
	# itself never sets crew state directly (Rule 1).
	if _scenario_key == "narrow_passage" and crew.role == "general":
		start_room_type = "medbay"
		crew.unconscious_until = NarrowPassageScenario.PATIENT_UNCONSCIOUS_SECS
	var start_room: String = GameState.get_room_of_type(start_room_type)
	crew.location = start_room
	# Staggered starting needs so eat/sleep/work behaviours surface within
	# the first minutes of a session instead of all at once an hour in.
	crew.hunger = randf_range(0.15, 0.55)
	crew.fatigue = randf_range(0.10, 0.50)
	crew.boredom = randf_range(0.25, 0.60)
	for f: String in (ROLE_FEARS.get(crew.role, []) as Array):
		crew.fears.append(f)
	for v: String in (ROLE_VALUES.get(crew.role, []) as Array):
		crew.values.append(v)
	GameState.crew[crew.crew_id] = crew
	GameState.set_ai_trust(crew.crew_id, ROLE_START_TRUST.get(crew.role, 0.5))   # also syncs crew.ai_trust
	# Register in starting room without firing EventBus noise during setup
	var room: RoomBase = GameState.rooms.get(start_room) as RoomBase
	if room:
		room.occupants.append(crew.crew_id)


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
	var roster_scene: PackedScene = load(ROSTER_PANEL_SCENE)
	if roster_scene:
		add_child(roster_scene.instantiate())
	var env_scene: PackedScene = load(ENVIRONMENT_MENU_SCENE)
	if env_scene:
		add_child(env_scene.instantiate())


func _start_scenario() -> void:
	var config: Dictionary
	match _scenario_key:
		"narrow_passage":
			config = NarrowPassageScenario.build()
			var monitor := NarrowPassageMonitor.new()
			monitor.setup(config)   # builder data + monitor logic share one dictionary
			add_child(monitor)
		_:
			config = QuarantineScenario.build()
			add_child(QuarantineMonitor.new())
	ScenarioRunner.start_scenario(config)
	print("[MAIN] ══════ %s ══════" % String(config.get("title", "SCENARIO")).to_upper())
	print("[MAIN] Crew: %s" % ", ".join(GameState.crew.keys()))
	print("[MAIN] Reactor online=%s  battery=%.0f%%  life_support=%s  ai_core=%.0f (%s)" % [
		GameState.reactor_online, GameState.battery_charge, GameState.life_support_online,
		GameState.ai_core_integrity, GameState.ai_core_status])
	print("[MAIN] SPACE=pause  D=directive  I=isolate  F=fear  R=status")


# --- Mission mode boot (docs/mission-system-spec.md §12) ---
# The default path whenever SHIPAI_SCENARIO isn't set: MissionManager owns picking
# and running missions from here on (scripts/missions/mission_manager.gd). Reuses
# the same ship seed the layout/crew were generated from (GameState.ship_seed,
# already resolved from SHIPAI_SEED-or-random in _choose_ship_seed) so one seed
# governs the whole boot deterministically. SHIPAI_MISSION=<id> (read inside
# MissionManager.begin_campaign) forces the opener.
func _start_mission_mode() -> void:
	MissionManager.begin_campaign(GameState.ship_seed)
	print("[MAIN] Mission mode — crew: %s" % ", ".join(GameState.crew.keys()))
	print("[MAIN] Reactor online=%s  battery=%.0f%%  life_support=%s  ai_core=%.0f (%s)" % [
		GameState.reactor_online, GameState.battery_charge, GameState.life_support_online,
		GameState.ai_core_integrity, GameState.ai_core_status])
	print("[MAIN] SPACE=pause  D=directive  R=status")


# --- Debug signals → Output panel ---

func _connect_debug_output() -> void:
	EventBus.scenario_event_triggered.connect(
		func(id): print("[EVENT]     %s" % id))
	EventBus.crew_state_changed.connect(
		func(cid, old, new_s): print("[CREW]      %s  %s → %s" % [cid, old, new_s]))
	EventBus.crew_died.connect(
		func(cid, cause): print("[CREW]      %s DIED (%s)" % [cid, cause]))
	EventBus.power_low.connect(
		func(charge): print("[CRITICAL]  battery at %.0f%%" % charge))
	EventBus.reactor_failure.connect(
		func(source): print("[CRITICAL]  reactor failure (%s)" % source))
	EventBus.life_support_failure.connect(
		func(source): print("[CRITICAL]  life support failure (%s)" % source))
	EventBus.ai_core_status_changed.connect(
		func(old_s, new_s): print("[AI CORE]   %s → %s" % [old_s, new_s]))
	EventBus.directive_accepted.connect(
		func(cid, d): print("[DIRECTIVE] %s accepted — %s" % [cid, d.content]))
	EventBus.directive_rejected.connect(
		func(cid, d, reason): print("[DIRECTIVE] %s rejected (%s) — %s" % [cid, reason, d.content]))
	EventBus.ai_trust_changed.connect(
		func(cid, old, nw): print("[TRUST]     %s  %.2f → %.2f" % [cid, old, nw]))
	EventBus.scenario_ended.connect(
		func(outcome): print("[SCENARIO]  ══ ENDED: %s ══" % outcome.to_upper()))
	EventBus.line_spoken.connect(
		func(cid, _key, text, line_type): print("[%s]     %s: \"%s\"" % [
			"THOUGHT" if line_type == "declaration" else "SAY", _crew_label(cid), text]))
	EventBus.conversation_started.connect(
		func(a, b, room_id): print("[CONVO]     %s <-> %s in %s" % [_crew_label(a), _crew_label(b), room_id]))
	EventBus.crew_romance_started.connect(
		func(a, b): print("[ROMANCE]   %s + %s" % [_crew_label(a), _crew_label(b)]))
	EventBus.crew_trait_gained.connect(
		func(cid, tid): print("[TRAIT]     %s earned %s" % [_crew_label(cid), Traits.display_name(tid)]))
	EventBus.crew_skill_tier_up.connect(
		func(cid, skill, tier): print("[SKILL]     %s: %s -> %s" % [_crew_label(cid), skill, tier]))
	EventBus.crew_rest_save_resolved.connect(
		func(cid, success, worst): print("[REST]      %s rest save (%s): %s" % [_crew_label(cid), worst, "success" if success else "failure"]))


func _crew_label(crew_id: String) -> String:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	return crew.crew_name if crew != null else crew_id


# --- Dev-only: SHIPAI_FORCE_FLAG=<flag>[,<flag>...] forces scenario flags a few
# seconds after boot (docs/director-spec.md §5/§8 step 4 — "force conditions in a
# dev run and watch the [morph] handoff fire"). Never read outside this hook; no
# effect at all unless the env var is set. Comma-separated so a single run can force
# every flag a morph edge's condition_flags needs (e.g. NarrowPassage's morph needs
# BOTH field_exited AND battery_critically_low).

func _setup_force_flags() -> void:
	var raw: String = OS.get_environment("SHIPAI_FORCE_FLAG")
	if raw == "":
		return
	var flags: PackedStringArray = raw.split(",", false)
	get_tree().create_timer(3.0).timeout.connect(func():
		for flag: String in flags:
			var f: String = flag.strip_edges()
			if f == "":
				continue
			print("[FORCE-FLAG] setting '%s'" % f)
			ScenarioDirector.set_flag(f))


# --- Dev-only: SHIPAI_FORCE_KILL=<role> kills that role's crew member 2s after boot
# through the normal CrewLifecycle funnel — exists to soak-test the crew-progression death
# path (memorial entry, witnessed-death trait rolls, Widowed) without waiting for an
# organic death (docs/crew-progression-spec.md §7 point 5's forced verification run).
# Fires BEFORE _setup_force_flags' 3s flag timer on purpose, so a forced death lands
# inside the leg whose boundary those forced flags then trigger. Never read outside this
# hook; no effect at all unless the env var is set.

const FORCE_KILL_DELAY: float = 2.0

func _setup_force_kill() -> void:
	var role: String = OS.get_environment("SHIPAI_FORCE_KILL")
	if role == "":
		return
	get_tree().create_timer(FORCE_KILL_DELAY).timeout.connect(func():
		var crew_id: String = GameState.get_crew_of_role(role)
		var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
		if crew == null:
			push_warning("SHIPAI_FORCE_KILL: no crew with role '%s'" % role)
			return
		print("[FORCE-KILL] killing %s (%s)" % [crew_id, role])
		CrewLifecycle.kill(crew, "forced_debug"))


# --- Headless verification: SHIPAI_AUTOSHOT=<dir> saves timed screenshots ---
# SHIPAI_AUTODEMO=1 additionally plays the current scenario's win path via real
# player actions (directives with refusal retries, power/air diversion),
# exercising the whole loop end to end. The quarantine demo keeps its original
# AUTOSHOT-coupled timing; the narrow-passage demo self-paces off scenario flags
# and quits itself on scenario_ended (no AUTOSHOT required).

func _setup_autoshot() -> void:
	var demo: bool = OS.get_environment("SHIPAI_AUTODEMO") != ""
	if demo and _scenario_key == "narrow_passage":
		_run_np_autodemo()
		return
	var dir: String = OS.get_environment("SHIPAI_AUTOSHOT")
	if dir == "":
		return
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
		var medbay_id: String = GameState.get_room_of_type("medbay")
		var infected_id: String = GameState.get_crew_of_role("general")
		var medic_id: String = GameState.get_crew_of_role("medic")
		for pair in [[infected_id, medbay_id], [medic_id, medbay_id]]:
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


# --- Narrow Passage autodemo (SHIPAI_AUTODEMO=1 + SHIPAI_SCENARIO=narrow_passage) ---
# Plays the intended win line with the same calls a player's UI actions make:
# comply with the shutdown order early (the HUD reactor control's exact call),
# divert power to the engine room + medbay and air to medbay/engine room/bridge,
# then direct the engineer to the engine room for the relight (retrying refusals).
# Paced off scenario flags rather than wall-clock timers so it stays correct if
# the builder's timings are retuned. Quits on scenario_ended (or a hard cap).

var _np_demo_stage: int = 0
var _np_demo_mark: float = -1.0

func _run_np_autodemo() -> void:
	print("[NP-DEMO] armed — playing The Narrow Passage win path")
	EventBus.time_ticked.connect(_np_demo_tick)
	EventBus.scenario_ended.connect(func(outcome: String):
		print("[NP-DEMO] scenario ended: %s" % outcome)
		get_tree().create_timer(4.0).timeout.connect(func(): get_tree().quit()))
	get_tree().create_timer(360.0).timeout.connect(func():
		print("[NP-DEMO] TIMED OUT without scenario end")
		get_tree().quit())


func _np_demo_tick(elapsed: float, _delta: float) -> void:
	match _np_demo_stage:
		0:  # wait for the bridge's shutdown order
			if ScenarioDirector.get_flag("reactor_shutdown_ordered"):
				_np_demo_mark = elapsed
				_np_demo_stage = 1
		1:  # comply early — the AI's own choice, ahead of the deadline
			if elapsed - _np_demo_mark >= 2.0:
				if GameState.reactor_online:
					GameState.set_reactor_online(false, "controlled_shutdown")
					print("[NP-DEMO] complied — reactor offline ahead of the deadline")
				_np_demo_mark = elapsed
				_np_demo_stage = 2
		2:  # allocate after life support's power-cut cascade has landed (~1 tick)
			if elapsed - _np_demo_mark >= 1.0:
				_np_demo_allocate()
				_np_demo_stage = 3
		3:  # wait for field entry before spending the engineer on the relight
			if ScenarioDirector.get_flag("field_entered"):
				_np_demo_mark = -999.0
				_np_demo_stage = 4
			elif GameState.reactor_online and ScenarioDirector.get_flag("reactor_shutdown_ordered"):
				# The engineer jumped the gun on a relight (RepairBehavior acts on
				# its own — bible: the engineer WANTS an early relight attempt).
				# Re-secure before the boundary, same call as re-pressing the HUD
				# control, or the field forces an emergency scram at a trust cost.
				GameState.set_reactor_online(false, "controlled_shutdown")
				print("[NP-DEMO] re-secured the reactor after an early crew relight")
		4:  # push the engineer to the engine room until the relight job is running
			if GameState.reactor_online:
				print("[NP-DEMO] reactor relit")
				_np_demo_stage = 5
			elif not GameState.is_being_repaired("reactor") and elapsed - _np_demo_mark >= 8.0:
				_np_demo_mark = elapsed
				_np_demo_direct_engineer()
		5:  # monitor handles exit -> passage_cleared; nothing left to do
			pass


func _np_demo_allocate() -> void:
	var engine_id: String = GameState.get_room_of_type("engine_room")
	var medbay_id: String = GameState.get_room_of_type("medbay")
	var bridge_id: String = GameState.get_room_of_type("bridge")
	# Two powered rooms, not three — the slower battery drain is the margin that
	# makes the crossing comfortable (the same tradeoff a thoughtful player finds).
	for room_id: String in [engine_id, medbay_id]:
		print("[NP-DEMO] power %s -> %s" % [room_id, GameState.set_room_powered(room_id, true)])
	for room_id: String in [medbay_id, engine_id, bridge_id]:
		print("[NP-DEMO] air   %s -> %s" % [room_id, GameState.set_room_life_supported(room_id, true)])


func _np_demo_direct_engineer() -> void:
	var engineer_id: String = GameState.get_crew_of_role("engineer")
	var engine_id: String = GameState.get_room_of_type("engine_room")
	if engineer_id == "" or engine_id == "":
		return
	var engineer: CrewMember = GameState.crew.get(engineer_id) as CrewMember
	if engineer != null and engineer.location == engine_id:
		return  # already on site — RepairBehavior will pick the job up
	var d := AIDirective.new()
	d.type = AIDirective.Type.INSTRUCTION
	d.target_type = AIDirective.TargetType.CREW
	d.target_id = engineer_id
	d.content = "Proceed to the engine room and begin the reactor relight."
	d.move_to_room = engine_id
	d.confidence = 0.9
	d.priority = 4
	print("[NP-DEMO] directive engineer->engine_room issued=%s" % AISystem.issue_directive(d))


# --- Keyboard test controls ---

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.is_echo():
		return
	# NOTE(camera): D is also a WASD pan key (DeckCamera polls Input.is_key_pressed
	# directly, so it doesn't conflict with this event-based handler either way) —
	# the is_echo() guard above is what stops holding D from spamming the debug
	# directive via OS key-repeat now that D gets held down for panning.
	match event.keycode:
		KEY_SPACE:
			if TimeManager.is_paused():
				TimeManager.unpause()
				print("[MAIN] ▶ Unpaused")
			else:
				TimeManager.pause()
				print("[MAIN] ⏸ Paused")

		KEY_D:
			var target_id: String = GameState.get_crew_of_role("general")
			if target_id != "":
				var d := AIDirective.new()
				d.type        = AIDirective.Type.RECOMMENDATION
				d.target_type = AIDirective.TargetType.CREW
				d.target_id   = target_id
				d.content     = "%s, please report to medbay for a routine health check." % (GameState.crew[target_id] as CrewMember).crew_name
				d.confidence  = 0.85
				d.priority    = 2
				d.move_to_room = GameState.get_room_of_type("medbay")
				if not AISystem.issue_directive(d):
					print("[MAIN] Directive blocked (insufficient access, or AI core offline)")

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
			print("[STATUS] reactor=%s battery=%.0f%% life_support=%s ai_core=%.0f(%s)" % [
				GameState.reactor_online, GameState.battery_charge, GameState.life_support_online,
				GameState.ai_core_integrity, GameState.ai_core_status])
			for crew_id: String in GameState.crew:
				var c: CrewMember = GameState.crew[crew_id] as CrewMember
				if c:
					print("  %s (%s/%s)  trust=%.2f  fear=%.2f  stress=%d  state=%s  air=%.0f%%" % [
						c.crew_name, c.role, c.mship_class, c.ai_trust, c.fear, c.stress,
						c.current_state, GameState.get_room_air(c.location)])
