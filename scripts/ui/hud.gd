extends CanvasLayer

# Compact power/life-support panel (left) replacing the old normalised resource bars,
# objective line (top centre), event feed (bottom left), win/lose banner, and an AI-core
# blackout overlay. Built programmatically like before. Updates live via EventBus; every
# mutation the player triggers here (power/life-support toggles) routes through GameState
# methods, never touching state directly (Architecture Rule 3).

const PANEL_PADDING: float = 6.0
const ROW_HEIGHT: float = 26.0
const PANEL_WIDTH: float = 260.0
const FEED_LINES: int = 7

const CRITICAL_COLOUR: Color = Color(0.9, 0.2, 0.1)
const NORMAL_COLOUR: Color = Color(0.2, 0.7, 0.3)
const WARNING_COLOUR: Color = Color(0.9, 0.7, 0.1)
const ACCENT: Color = Color(0.20, 0.80, 0.95)
const FEED_COLOUR: Color = Color(0.65, 0.72, 0.80)
const DIM_TEXT: Color = Color(0.55, 0.60, 0.68)

# --- Mission panel (docs/mission-system-spec.md §11/§12) ---
const MISSION_PANEL_GAP: float = 14.0        # vertical gap below the power panel
const MISSION_ROW_FONT: int = 13
const MISSION_BRIEFING_FONT: int = 12
const BRIEFING_DISPLAY_SECONDS: float = 14.0  # "first N seconds" collapsible window
const ACTIVE_OBJECTIVE_COLOUR: Color = Color(0.85, 0.87, 0.92)
const MISSION_BRIEFING_EST_HEIGHT: float = 58.0   # rough wrapped-briefing height budget
const MISSION_OBJECTIVE_ROW_HEIGHT: float = 17.0

# Player-readable text for scenario event ids (fallback: prettified id).
# "scenario_started" is handled dynamically in _on_scenario_event (multi-scenario).
const EVENT_TEXT: Dictionary = {
	# The Quarantine
	"pathogen_detected": "⚠ Biosensors flag an anomalous pathogen in a returning crew member's bloodwork.",
	"pathogen_spreads": "⚠ Secondary exposure — the ship's engineer's bioscan shows the same signature.",
	"symptoms_appear": "The infected crew member reports feeling feverish.",
	"containment_possible": "The ship's medic requests the full biosensor log.",
	"life_support_contaminated": "☣ Pathogen detected in the air recyclers.",
	"vasquez_isolated": "The infected crew member is isolated in the Medbay.",
	"pathogen_contained": "✔ Containment protocol complete.",
	# The Narrow Passage
	"shear_field_detected": "⚠ Shear field ahead. Captain's orders: reactor offline before entry, bridge and engine room stay powered.",
	"reactor_shutdown_complied": "Reactor secured for field transit — a clean, procedural shutdown.",
	"reactor_forced_scram": "⚠ Emergency scram at the field boundary — the reactor was still hot.",
	"field_entry": "The ship enters the shear field. Battery power only.",
	"medic_appeal": "Medic: keep the Medbay powered and breathing — the patient won't survive cold, thin air.",
	"field_turbulence": "⚠ Shear turbulence — battery reserves hit; the crossing lengthens.",
	"patient_crashing": "⚠ The patient in the Medbay is crashing.",
	"patient_lost": "☠ The medbay patient did not survive the crossing.",
	"ship_stranded": "⚠ Battery exhausted — the ship is dark inside the field.",
	"field_exited": "The ship clears the shear field. The reactor is cold.",
	"passage_cleared": "✔ Passage cleared.",
}

# Scenario id -> success-banner text. Narrow passage success text varies with the
# patient's fate (bible: a dead patient colors the ending, it doesn't gate the win).
const SUCCESS_TEXT: Dictionary = {
	"the_quarantine": "MISSION COMPLETE\nPathogen contained. The voyage continues.",
	"the_narrow_passage": "MISSION COMPLETE\nThe field is behind us. All hands accounted for.",
}
const SUCCESS_TEXT_NP_PATIENT_LOST: String = "MISSION COMPLETE\nThe field is behind us. Not everyone made it through."

var _objective_label: Label
var _feed_box: VBoxContainer

var _panel: Panel
var _reactor_label: Label
var _battery_label: Label
var _life_support_label: Label
var _shutdown_btn: Button          # scenario-requested reactor shutdown (flag-gated)
var _room_rows: Dictionary = {}   # room_id -> {power_btn: Button, ls_btn: Button, air_label: Label}

var _blackout_layer: CanvasLayer = null
var _blackout_time_label: Label

# --- Mission panel state ---
var _mission_panel: Panel
var _mission_title_label: Label
var _mission_giver_label: Label
var _mission_phase_label: Label
var _mission_briefing_label: Label
var _mission_objectives_box: VBoxContainer
var _mission_objective_rows: Dictionary = {}   # objective_id -> Label


func _ready() -> void:
	_build_power_panel()
	_build_mission_panel()
	_build_objective_label()
	_build_feed()
	EventBus.mission_started.connect(_on_mission_started)
	EventBus.mission_phase_changed.connect(_on_mission_phase_changed)
	EventBus.mission_objective_updated.connect(_on_mission_objective_updated)
	EventBus.mission_completed.connect(_on_mission_completed)
	EventBus.objective_changed.connect(_on_objective_changed)
	EventBus.scenario_event_triggered.connect(_on_scenario_event)
	EventBus.directive_accepted.connect(
		func(cid, d): _push_feed("%s: complying — %s" % [_crew_name(cid), d.content]))
	EventBus.directive_rejected.connect(
		func(cid, d, _r): _push_feed("%s: refuses — %s" % [_crew_name(cid), d.content]))
	EventBus.crew_died.connect(
		func(cid, _cause): _push_feed("☠ %s has died." % _crew_name(cid)))
	EventBus.crew_injury.connect(
		func(cid, severity, _wtype): _push_feed("%s: %s" % [_crew_name(cid), severity.capitalize().replace("_", " ")]))
	# Trait moments announce themselves diegetically (docs/crew-progression-spec.md §5).
	EventBus.crew_trait_gained.connect(
		func(cid, tid): _push_feed("★ %s: %s" % [_crew_name(cid), Traits.display_name(tid)]))
	EventBus.crew_skill_tier_up.connect(
		func(cid, skill, tier): _push_feed("★ %s: %s is now %s." % [_crew_name(cid), skill, tier]))
	# Away-op radio chatter (docs/mission-system-spec.md §6 step 2) — the away team is
	# off-ship, so this feed line IS the bubble for them (see event_bus.gd's radio_bark doc).
	EventBus.radio_bark.connect(
		func(text, _tone): _push_feed("📻 %s" % text))
	EventBus.scenario_ended.connect(_on_scenario_ended)

	EventBus.power_mode_changed.connect(func(_online): _refresh_power_panel())
	EventBus.battery_changed.connect(func(_c, _cap): _refresh_power_panel())
	EventBus.room_power_changed.connect(func(_rid, _p): _refresh_power_panel())
	EventBus.life_support_mode_changed.connect(func(_online): _refresh_power_panel())
	EventBus.room_air_changed.connect(func(_rid, _air): _refresh_power_panel())
	EventBus.reactor_failure.connect(func(_s): _push_feed("⚠ Reactor failure — ship on battery power."))
	EventBus.life_support_failure.connect(func(_s): _push_feed("⚠ Life support failure — air quality will degrade."))
	EventBus.power_low.connect(func(_c): _push_feed("⚠ Battery critically low."))
	EventBus.ai_core_status_changed.connect(_on_ai_core_status_changed)
	EventBus.repair_success.connect(func(target_id, _cid): _push_feed("✔ Repair complete: %s" % target_id.capitalize().replace("_", " ")))

	# Intruder sensor markers (docs/mission-system-spec.md §9 — minimal room-overlay
	# marker, extending this panel's existing per-room row pattern rather than a new
	# deck-space overlay). Any of the three signals can change what a room row should
	# show, so all three just re-run the same full refresh.
	EventBus.intruder_spawned.connect(func(_id, _room, _visible): _refresh_intruder_overlay())
	EventBus.intruder_moved.connect(func(_id, _from, _to): _refresh_intruder_overlay())
	EventBus.intruder_killed.connect(func(_id, _room): _refresh_intruder_overlay())

	_refresh_power_panel()


func _process(_delta: float) -> void:
	if _blackout_layer != null and is_instance_valid(_blackout_time_label):
		var elapsed_since: float = maxf(0.0, TimeManager.elapsed - GameState.ai_core_blackout_since)
		_blackout_time_label.text = "CORE OFFLINE\nElapsed: %s" % _format_duration(elapsed_since)


# --- Power / life support panel ---

func _build_power_panel() -> void:
	_panel = Panel.new()
	_panel.position = Vector2(10, 10)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(PANEL_PADDING, PANEL_PADDING)
	vbox.add_theme_constant_override("separation", 3)
	_panel.add_child(vbox)

	_reactor_label = _make_status_label()
	_battery_label = _make_status_label()
	_life_support_label = _make_status_label()
	vbox.add_child(_reactor_label)
	vbox.add_child(_battery_label)
	vbox.add_child(_life_support_label)

	# Reactor shutdown control — only visible while a scenario has set the
	# "reactor_shutdown_ordered" flag with the reactor still running (The Narrow
	# Passage's compliance window; any future scenario can reuse the same flag).
	_shutdown_btn = Button.new()
	_shutdown_btn.text = "TAKE REACTOR OFFLINE"
	_shutdown_btn.custom_minimum_size = Vector2(PANEL_WIDTH - PANEL_PADDING * 2, ROW_HEIGHT - 4)
	_shutdown_btn.visible = false
	_shutdown_btn.pressed.connect(_on_reactor_shutdown_pressed)
	vbox.add_child(_shutdown_btn)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	for room_id: String in GameState.rooms.keys():
		var room: RoomBase = GameState.rooms[room_id]
		if room != null and room.room_function == "corridor":
			continue
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(PANEL_WIDTH - PANEL_PADDING * 2, ROW_HEIGHT)

		var label := Label.new()
		label.text = _room_display_name(room_id)
		label.custom_minimum_size = Vector2(96, 0)
		label.add_theme_font_size_override("font_size", 12)

		var power_btn := Button.new()
		power_btn.custom_minimum_size = Vector2(22, 20)
		power_btn.tooltip_text = "Toggle power (battery mode only)"
		power_btn.pressed.connect(_on_power_toggle.bind(room_id))

		var ls_btn := Button.new()
		ls_btn.custom_minimum_size = Vector2(22, 20)
		ls_btn.tooltip_text = "Toggle life support (failure mode only)"
		ls_btn.pressed.connect(_on_life_support_toggle.bind(room_id))

		var air_label := Label.new()
		air_label.custom_minimum_size = Vector2(48, 0)
		air_label.add_theme_font_size_override("font_size", 12)
		air_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

		# Intruder sensor blip (docs/mission-system-spec.md §9) — "red blip + type label
		# when visible", hidden otherwise (mimic dormant, or an AI-core sensor-gapped room).
		var intruder_label := Label.new()
		intruder_label.custom_minimum_size = Vector2(70, 0)
		intruder_label.add_theme_font_size_override("font_size", 12)
		intruder_label.add_theme_color_override("font_color", CRITICAL_COLOUR)
		intruder_label.text = ""

		row.add_child(label)
		row.add_child(power_btn)
		row.add_child(ls_btn)
		row.add_child(air_label)
		row.add_child(intruder_label)
		vbox.add_child(row)

		_room_rows[room_id] = {"power_btn": power_btn, "ls_btn": ls_btn, "air_label": air_label, "intruder_label": intruder_label}

	# 4 header rows now: reactor/battery/life-support labels + the shutdown button.
	_panel.size = Vector2(PANEL_WIDTH, vbox.position.y * 2 + (4 + _room_rows.size()) * (ROW_HEIGHT + 3) + 10)


func _make_status_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 13)
	label.custom_minimum_size = Vector2(PANEL_WIDTH - PANEL_PADDING * 2, ROW_HEIGHT - 4)
	return label


func _on_power_toggle(room_id: String) -> void:
	if GameState.reactor_online:
		return
	GameState.set_room_powered(room_id, not GameState.get_room_powered(room_id))


func _on_life_support_toggle(room_id: String) -> void:
	if GameState.life_support_online:
		return
	GameState.set_room_life_supported(room_id, not GameState.get_room_life_supported(room_id))


func _on_reactor_shutdown_pressed() -> void:
	if GameState.reactor_online and ScenarioDirector.get_flag("reactor_shutdown_ordered"):
		GameState.set_reactor_online(false, "controlled_shutdown")


func _refresh_power_panel() -> void:
	if _reactor_label == null:
		return
	_reactor_label.text = "Reactor: ONLINE" if GameState.reactor_online else "Reactor: BATTERY MODE"
	_reactor_label.add_theme_color_override("font_color", NORMAL_COLOUR if GameState.reactor_online else WARNING_COLOUR)

	_shutdown_btn.visible = GameState.reactor_online \
		and ScenarioDirector.get_flag("reactor_shutdown_ordered")

	var battery_pct: float = 0.0 if GameState.battery_capacity <= 0.0 else \
		100.0 * GameState.battery_charge / GameState.battery_capacity
	_battery_label.text = "Battery: %d%%  (%d/%d rooms)" % [
		int(battery_pct), GameState.powered_rooms.size(), PowerModel.MAX_BATTERY_ROOMS]
	_battery_label.add_theme_color_override("font_color", _tier_colour(battery_pct / 100.0))

	_life_support_label.text = "Life Support: ONLINE" if GameState.life_support_online else "Life Support: FAILING"
	_life_support_label.add_theme_color_override("font_color",
		NORMAL_COLOUR if GameState.life_support_online else WARNING_COLOUR)

	for room_id: String in _room_rows:
		var row: Dictionary = _room_rows[room_id]
		var powered: bool = GameState.get_room_powered(room_id)
		var power_btn: Button = row["power_btn"]
		power_btn.text = "P" if powered else "p"
		power_btn.disabled = GameState.reactor_online
		power_btn.modulate = NORMAL_COLOUR if powered else DIM_TEXT

		var supported: bool = GameState.get_room_life_supported(room_id)
		var ls_btn: Button = row["ls_btn"]
		ls_btn.text = "A" if supported else "a"
		ls_btn.disabled = GameState.life_support_online
		ls_btn.modulate = NORMAL_COLOUR if supported else DIM_TEXT

		var air: float = GameState.get_room_air(room_id)
		var air_label: Label = row["air_label"]
		air_label.text = "%d%%" % int(air)
		air_label.add_theme_color_override("font_color", _tier_colour(air / 100.0))


func _tier_colour(fraction: float) -> Color:
	return NORMAL_COLOUR if fraction > 0.5 else (WARNING_COLOUR if fraction > 0.2 else CRITICAL_COLOUR)


# --- Intruder sensor overlay (docs/mission-system-spec.md §9) ---
# IntruderSystem is the source of truth (active_intruders()/intruder_in_room()); this
# just re-reads it into the existing per-room labels whenever a spawn/move/kill signal
# fires. Cheap even on a full re-scan — room counts here are small (a handful of rooms).

func _refresh_intruder_overlay() -> void:
	for room_id: String in _room_rows:
		var row: Dictionary = _room_rows[room_id]
		var label: Label = row.get("intruder_label")
		if label == null:
			continue
		var iid: String = IntruderSystem.intruder_in_room(room_id)
		if iid == "":
			label.text = ""
		else:
			label.text = "● %s" % IntruderSystem.type_of(iid).capitalize()


func _room_display_name(room_id: String) -> String:
	return room_id.capitalize().replace("_", " ")


# --- Mission panel (docs/mission-system-spec.md §11/§12) ---
# Compact top-left panel stacked directly below the power/life-support panel — pure
# render layer, same shape as the rest of this file: every field here is populated
# from EventBus signals MissionManager already emits (mission_started/
# mission_phase_changed/mission_objective_updated/mission_completed); nothing here
# mutates game state (Rule 3/5). Hidden until the first mission_started (so it's a
# no-op, invisible panel during legacy SHIPAI_SCENARIO boots).

func _build_mission_panel() -> void:
	_mission_panel = Panel.new()
	_mission_panel.position = Vector2(10, _panel.size.y + MISSION_PANEL_GAP)
	_mission_panel.visible = false
	add_child(_mission_panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(PANEL_PADDING, PANEL_PADDING)
	vbox.add_theme_constant_override("separation", 3)
	_mission_panel.add_child(vbox)

	_mission_title_label = _make_status_label()
	_mission_title_label.add_theme_color_override("font_color", ACCENT)
	_mission_giver_label = _make_status_label()
	_mission_phase_label = _make_status_label()
	vbox.add_child(_mission_title_label)
	vbox.add_child(_mission_giver_label)
	vbox.add_child(_mission_phase_label)

	_mission_briefing_label = Label.new()
	_mission_briefing_label.custom_minimum_size = Vector2(PANEL_WIDTH - PANEL_PADDING * 2, 0)
	_mission_briefing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_briefing_label.add_theme_font_size_override("font_size", MISSION_BRIEFING_FONT)
	_mission_briefing_label.add_theme_color_override("font_color", FEED_COLOUR)
	vbox.add_child(_mission_briefing_label)

	vbox.add_child(HSeparator.new())

	_mission_objectives_box = VBoxContainer.new()
	_mission_objectives_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_mission_objectives_box)


func _on_mission_started(_mission_id: String) -> void:
	var mission: MissionDef = MissionManager.current_mission
	if mission == null:
		return
	_mission_panel.visible = true
	_mission_title_label.text = mission.title
	_mission_giver_label.text = "Giver: %s" % mission.giver
	_mission_phase_label.text = "Phase: Transit out"
	_mission_briefing_label.text = mission.briefing
	_mission_briefing_label.visible = true

	_mission_objective_rows.clear()
	for child in _mission_objectives_box.get_children():
		child.queue_free()
	for obj: Dictionary in mission.objectives:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", MISSION_ROW_FONT)
		row.add_theme_color_override("font_color", ACTIVE_OBJECTIVE_COLOUR)
		row.text = _objective_line(obj, "active")
		row.custom_minimum_size = Vector2(PANEL_WIDTH - PANEL_PADDING * 2, 0)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_mission_objectives_box.add_child(row)
		_mission_objective_rows[String(obj.get("id", ""))] = row
	_resize_mission_panel()

	get_tree().create_timer(BRIEFING_DISPLAY_SECONDS).timeout.connect(func():
		if is_instance_valid(_mission_briefing_label):
			_mission_briefing_label.visible = false
			_resize_mission_panel())


func _resize_mission_panel() -> void:
	var briefing_h: float = MISSION_BRIEFING_EST_HEIGHT if _mission_briefing_label.visible else 0.0
	var obj_h: float = _mission_objectives_box.get_child_count() * MISSION_OBJECTIVE_ROW_HEIGHT
	var height: float = PANEL_PADDING * 2 + 3 * (ROW_HEIGHT - 4) + 3 * 3 + briefing_h + 10.0 + obj_h + 10.0
	_mission_panel.size = Vector2(PANEL_WIDTH, height)


func _on_mission_phase_changed(mission_id: String, phase: String) -> void:
	if MissionManager.current_mission == null or MissionManager.current_mission.id != mission_id:
		return
	_mission_phase_label.text = "Phase: %s" % phase.capitalize().replace("_", " ")


func _on_mission_objective_updated(_mission_id: String, objective_id: String, state: String) -> void:
	if not _mission_objective_rows.has(objective_id):
		return
	var mission: MissionDef = MissionManager.current_mission
	var obj_dict: Dictionary = {}
	if mission != null:
		for o: Dictionary in mission.objectives:
			if String(o.get("id", "")) == objective_id:
				obj_dict = o
				break
	var row: Label = _mission_objective_rows[objective_id]
	row.text = _objective_line(obj_dict, state)
	row.add_theme_color_override("font_color", _objective_state_colour(state))


func _on_mission_completed(_mission_id: String, outcome: String) -> void:
	_mission_phase_label.text = "Phase: Resolution (%s)" % outcome.replace("mission_", "").capitalize()


func _objective_line(obj: Dictionary, state: String) -> String:
	var glyph: String = "•"
	if state == "complete":
		glyph = "✓"
	elif state == "failed":
		glyph = "✗"
	var text: String = String(obj.get("text", obj.get("id", "")))
	var opt_tag: String = " (opt)" if bool(obj.get("optional", false)) else ""
	return "%s %s%s" % [glyph, text, opt_tag]


func _objective_state_colour(state: String) -> Color:
	match state:
		"complete": return NORMAL_COLOUR
		"failed": return CRITICAL_COLOUR
		_: return ACTIVE_OBJECTIVE_COLOUR


# --- Objective / feed ---

func _build_objective_label() -> void:
	_objective_label = Label.new()
	_objective_label.position = Vector2(360, 12)
	_objective_label.size = Vector2(1200, 30)
	_objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective_label.add_theme_font_size_override("font_size", 19)
	_objective_label.add_theme_color_override("font_color", ACCENT)
	_objective_label.text = ""
	add_child(_objective_label)


func _build_feed() -> void:
	_feed_box = VBoxContainer.new()
	_feed_box.position = Vector2(14, 1080 - 14 - FEED_LINES * 22)
	_feed_box.size = Vector2(760, FEED_LINES * 22)
	_feed_box.alignment = BoxContainer.ALIGNMENT_END
	add_child(_feed_box)


func _push_feed(text: String) -> void:
	var line := Label.new()
	line.text = text
	line.add_theme_font_size_override("font_size", 14)
	line.add_theme_color_override("font_color", FEED_COLOUR)
	_feed_box.add_child(line)
	while _feed_box.get_child_count() > FEED_LINES:
		_feed_box.get_child(0).free()


func _crew_name(crew_id: String) -> String:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	return crew.crew_name if crew else crew_id


func _on_objective_changed(text: String) -> void:
	_objective_label.text = text


func _on_scenario_event(event_id: String) -> void:
	if event_id == "scenario_started":
		_push_feed("Scenario started: %s" % GameState.scenario_id.capitalize())
	else:
		_push_feed(EVENT_TEXT.get(event_id, event_id.capitalize()))
	# Scenario events can flip flag-gated controls (the reactor shutdown window).
	_refresh_power_panel()


func _on_scenario_ended(outcome: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.size = Vector2(1920, 1080)
	add_child(dim)

	var banner := Label.new()
	var won: bool = outcome == "success"
	banner.text = _success_text() if won \
		else "MISSION FAILED\n%s" % outcome.capitalize().replace("_", " ")
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 44)
	banner.add_theme_color_override("font_color",
		Color(0.35, 0.95, 0.55) if won else Color(0.95, 0.30, 0.25))
	banner.position = Vector2(0, 460)
	banner.size = Vector2(1920, 160)
	add_child(banner)


func _success_text() -> String:
	if GameState.scenario_id == "the_narrow_passage" and ScenarioDirector.get_flag("patient_lost"):
		return SUCCESS_TEXT_NP_PATIENT_LOST
	return SUCCESS_TEXT.get(GameState.scenario_id,
		"MISSION COMPLETE\nThe voyage continues.")


# --- AI core blackout overlay ---
# A minimal "core offline" screen that dims/blocks the rest of the interface until the
# core is repaired — matches the spec's "the player loses nearly all controls and most
# UI ... until crew repair it." Lives in its own high-layer CanvasLayer so it sits above
# DirectiveMenu (layer 5) too, and its full-screen Control (mouse_filter STOP) swallows
# clicks before they reach anything underneath.

func _on_ai_core_status_changed(_old_status: String, new_status: String) -> void:
	if new_status == "blackout":
		_show_blackout()
	else:
		_hide_blackout()


func _show_blackout() -> void:
	if _blackout_layer != null:
		return
	_blackout_layer = CanvasLayer.new()
	_blackout_layer.layer = 20
	add_child(_blackout_layer)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.88)
	dim.size = Vector2(1920, 1080)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_blackout_layer.add_child(dim)

	_blackout_time_label = Label.new()
	_blackout_time_label.text = "CORE OFFLINE"
	_blackout_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blackout_time_label.add_theme_font_size_override("font_size", 40)
	_blackout_time_label.add_theme_color_override("font_color", Color(0.85, 0.25, 0.25))
	_blackout_time_label.position = Vector2(0, 470)
	_blackout_time_label.size = Vector2(1920, 140)
	_blackout_layer.add_child(_blackout_time_label)

	var hint := Label.new()
	hint.text = "Awaiting crew repair..."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", DIM_TEXT)
	hint.position = Vector2(0, 610)
	hint.size = Vector2(1920, 40)
	_blackout_layer.add_child(hint)


func _hide_blackout() -> void:
	if _blackout_layer == null:
		return
	_blackout_layer.queue_free()
	_blackout_layer = null
	_blackout_time_label = null


func _format_duration(seconds: float) -> String:
	var total: int = int(seconds)
	return "%02d:%02d" % [total / 60, total % 60]
