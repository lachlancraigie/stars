extends CanvasLayer

# Click-on-environment contextual menu — the door/equipment counterpart to DirectiveMenu's
# click-on-crew menu. Two independent world-click targets share this one CanvasLayer:
#   a. Doors: Open/Close (cosmetic leaf state) + Lock/Unlock (the AI operating the door
#      directly — NOT a crew directive; see door.gd).
#   b. Damaged ship systems (reactor/life_support/ai_core): "Repair" opens a submenu to
#      designate a crew member (or "Nearest crew"), which issues a real repair AIDirective
#      through the normal directive/obedience flow — the crew may refuse. See
#      _issue_repair_directive() / DirectiveActionHandler for where acceptance actually
#      starts the repair job (Architecture Rule 1: this UI never calls
#      GameState.start_repair_job itself).
#
# Hit-testing mirrors DirectiveMenu exactly (world-space, CanvasLayer canvas-transform
# inversion) and explicitly checks crew FIRST via the shared CrewMemberNode.crew_at_world_point
# helper — a click that lands on a crew member is DirectiveMenu's to handle, never this
# layer's, even if a door or damaged room happens to be nearby.

const DOOR_CLICK_RADIUS: float = 45.0     # door gates are one deck tile — a tighter target than crew/rooms
const SYSTEM_CLICK_RADIUS: float = 90.0   # rooms are much bigger than a door gate; generous center-of-room target

const ACCENT: Color = Color(0.95, 0.70, 0.25)   # amber — visually distinct from DirectiveMenu's cyan crew accent
const PANEL_BG: Color = Color(0.09, 0.11, 0.15, 0.95)
const MENU_OFFSET: Vector2 = Vector2(30, -20)
const SUBMENU_GAP: float = 8.0
const SUBMENU_MAX_HEIGHT: float = 320.0

# Repair targets RepairModel resolves, mapped to the room TYPE the repairing crew member
# must be in (CrewSchedule.REPAIR_ROOM_TYPE — the same mapping RepairBehavior's own
# autonomous consideration already uses, reused here so "click the damaged room" and
# "which room the AI sends a directed crew member to" never disagree).
const REPAIR_TARGETS: Array[String] = ["reactor", "life_support", "ai_core"]
const SYSTEM_DISPLAY_NAME: Dictionary = {
	"reactor": "Reactor", "life_support": "Life Support", "ai_core": "AI Core",
}

var _menu: PanelContainer
var _submenu: PanelContainer
var _submenu_open: bool = false


func _ready() -> void:
	layer = 5  # same layer as DirectiveMenu — only one of the two ever has a menu open


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed):
		return

	var world_point: Vector2 = _world_mouse_pos()
	# Crew always wins a click over environment targets — DirectiveMenu handles this press.
	if CrewMemberNode.crew_at_world_point(world_point) != null:
		_close_menu()
		return

	var door: Door = _door_at(world_point)
	if door:
		_open_door_menu(door)
		return

	var target_id: String = _repairable_at(world_point)
	if target_id != "":
		_open_repair_menu(target_id)
		return

	_close_menu()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if ke.pressed and not ke.is_echo() and ke.keycode == KEY_ESCAPE:
		_close_menu()


# CanvasLayer isn't a CanvasItem — same manual canvas-transform inversion DirectiveMenu uses.
func _world_mouse_pos() -> Vector2:
	var vp: Viewport = get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_mouse_position()


func _screen_pos(world_pos: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_pos


# --- Hit-testing ---

func _door_at(world_point: Vector2) -> Door:
	var best: Door = null
	var best_dist: float = DOOR_CLICK_RADIUS
	for door_id: String in GameState.doors:
		var door: Door = GameState.doors[door_id]
		if door == null:
			continue
		var d: float = door.global_position.distance_to(world_point)
		if d <= best_dist:
			best = door
			best_dist = d
	return best


# Nearest damaged, repairable system whose room center is within range — "damaged" is
# authoritatively RepairModel.is_damaged() (overhaul spec: "Only show Repair on things
# RepairModel considers damaged/repairable").
func _repairable_at(world_point: Vector2) -> String:
	var best_id: String = ""
	var best_dist: float = SYSTEM_CLICK_RADIUS
	for target_id: String in REPAIR_TARGETS:
		if not RepairModel.is_damaged(target_id):
			continue
		var room_id: String = GameState.get_room_of_type(String(CrewSchedule.REPAIR_ROOM_TYPE.get(target_id, "")))
		var room: RoomBase = GameState.rooms.get(room_id) as RoomBase
		if room == null:
			continue
		var d: float = room.global_position.distance_to(world_point)
		if d <= best_dist:
			best_id = target_id
			best_dist = d
	return best_id


# --- Door menu: Open/Close + Lock/Unlock ---
#
# When locked, "Open" and "Unlock" collapse to the same action (ai_unlock() — you can't
# open a locked door without unlocking it), so only one button is shown rather than two
# that do the same thing. Otherwise Open/Close (purely cosmetic, ungated) and Lock (ungated
# — see door.gd) are independent, satisfying "lock must work in either open or closed
# state". A jammed door shows neither — ai_unlock() itself refuses while jammed; only a
# crew bypass attempt (door.gd's existing mechanic) clears a jam.

func _open_door_menu(door: Door) -> void:
	_close_menu()
	_menu = _make_panel()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_menu.add_child(vbox)

	var header := Label.new()
	header.text = "Door: %s ↔ %s" % [_room_display_name(door.room_a_id), _room_display_name(door.room_b_id)]
	header.add_theme_color_override("font_color", ACCENT)
	header.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(header)

	if door.jammed:
		_add_info_label(vbox, "JAMMED — awaiting a crew bypass.")
	else:
		if door.is_locked:
			var unlock_btn := Button.new()
			unlock_btn.text = "Unlock (opens the door)"
			unlock_btn.pressed.connect(_on_door_unlock.bind(door))
			vbox.add_child(unlock_btn)
		else:
			var open_close_btn := Button.new()
			open_close_btn.text = "Close" if door.is_open else "Open"
			open_close_btn.pressed.connect(_on_door_set_open.bind(door, not door.is_open))
			vbox.add_child(open_close_btn)

			var lock_btn := Button.new()
			lock_btn.text = "Lock"
			lock_btn.pressed.connect(_on_door_lock.bind(door))
			vbox.add_child(lock_btn)

	add_child(_menu)
	_position_panel(_menu, _screen_pos(door.global_position) + MENU_OFFSET)


func _on_door_set_open(door: Door, open_value: bool) -> void:
	door.set_open(open_value)
	_close_menu()


func _on_door_lock(door: Door) -> void:
	door.lock()
	_close_menu()


func _on_door_unlock(door: Door) -> void:
	door.ai_unlock()  # access-level/power/blackout/lag-gated — the real "AI operates the door" path
	_close_menu()


# --- Repair menu: "Repair ▸" -> designate a crew member, or Nearest crew ---

func _open_repair_menu(target_id: String) -> void:
	_close_menu()
	_menu = _make_panel()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_menu.add_child(vbox)

	var header := Label.new()
	header.text = "%s — DAMAGED" % String(SYSTEM_DISPLAY_NAME.get(target_id, target_id.capitalize()))
	header.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(header)

	if GameState.is_being_repaired(target_id):
		var crew_id: String = String((GameState.repair_jobs.get(target_id, {}) as Dictionary).get("crew_id", ""))
		_add_info_label(vbox, "Already being repaired by %s." % _crew_label(crew_id))

	var repair_btn := Button.new()
	repair_btn.text = "Repair ▸"
	repair_btn.pressed.connect(_on_repair_pressed.bind(target_id))
	vbox.add_child(repair_btn)

	add_child(_menu)
	var room_id: String = GameState.get_room_of_type(String(CrewSchedule.REPAIR_ROOM_TYPE.get(target_id, "")))
	var room: RoomBase = GameState.rooms.get(room_id) as RoomBase
	var anchor: Vector2 = (_screen_pos(room.global_position) if room else get_viewport().get_mouse_position()) + MENU_OFFSET
	_position_panel(_menu, anchor)


func _on_repair_pressed(target_id: String) -> void:
	if _submenu_open:
		_close_submenu()
		return
	_open_repair_submenu(target_id)


func _open_repair_submenu(target_id: String) -> void:
	_close_submenu()
	_submenu = _make_panel()
	_submenu_open = true

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(200, 0)
	_submenu.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.custom_minimum_size = Vector2(190, 0)
	scroll.add_child(vbox)

	var room_id: String = GameState.get_room_of_type(String(CrewSchedule.REPAIR_ROOM_TYPE.get(target_id, "")))
	var nearest_id: String = _nearest_living_crew(room_id)
	if nearest_id != "":
		var nearest_btn := Button.new()
		nearest_btn.text = "Nearest crew (%s)" % _crew_label(nearest_id)
		nearest_btn.pressed.connect(_issue_repair_directive.bind(target_id, nearest_id))
		vbox.add_child(nearest_btn)
		vbox.add_child(HSeparator.new())

	var crew_ids: Array[String] = []
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive:
			crew_ids.append(crew_id)
	crew_ids.sort()

	for crew_id: String in crew_ids:
		var btn := Button.new()
		btn.text = _crew_label(crew_id)
		btn.pressed.connect(_issue_repair_directive.bind(target_id, crew_id))
		vbox.add_child(btn)

	if crew_ids.is_empty():
		_add_info_label(vbox, "No living crew.")

	add_child(_submenu)
	_submenu.reset_size()
	scroll.custom_minimum_size.y = minf(SUBMENU_MAX_HEIGHT, _submenu.size.y)

	_menu.reset_size()
	var anchor: Vector2 = _menu.position + Vector2(_menu.size.x + SUBMENU_GAP, 0)
	_position_panel(_submenu, anchor)


func _close_submenu() -> void:
	_submenu_open = false
	if _submenu:
		_submenu.queue_free()
		_submenu = null


# Living crew member physically nearest the target room — a reasonable "closest available
# hand" for the "Nearest crew" shortcut. They may still refuse the directive like anyone else.
func _nearest_living_crew(room_id: String) -> String:
	var room: RoomBase = GameState.rooms.get(room_id) as RoomBase
	if room == null:
		return ""
	var best_id: String = ""
	var best_dist: float = INF
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew == null or not crew.is_alive:
			continue
		var node: CrewMemberNode = CrewMemberNode.nodes.get(crew_id) as CrewMemberNode
		if node == null:
			continue
		var d: float = node.global_position.distance_to(room.global_position)
		if d < best_dist:
			best_dist = d
			best_id = crew_id
	return best_id


# Issues the repair directive through the normal AIDirective/AISystem/ObedienceEngine flow
# — the crew evaluates it and may refuse (DirectiveEvaluator), same as any other directive.
# Only on ACCEPTANCE does DirectiveActionHandler actually call GameState.start_repair_job
# (Architecture Rule 1: this UI never sets crew or repair-job state directly).
func _issue_repair_directive(target_id: String, crew_id: String) -> void:
	var room_id: String = GameState.get_room_of_type(String(CrewSchedule.REPAIR_ROOM_TYPE.get(target_id, "")))
	var d := AIDirective.new()
	d.type = AIDirective.Type.INSTRUCTION
	d.target_type = AIDirective.TargetType.CREW
	d.target_id = crew_id
	d.content = "Repair the %s." % String(SYSTEM_DISPLAY_NAME.get(target_id, target_id.capitalize()))
	d.move_to_room = room_id
	d.repair_target = target_id
	d.confidence = 0.8
	d.priority = 3
	AISystem.issue_directive(d)
	_close_menu()


# --- Shared panel styling/positioning (mirrors DirectiveMenu's own — kept local rather
# than shared across files, matching this codebase's existing per-file UI-helper idiom,
# e.g. RosterPanel/DirectiveMenu each keep their own small _room_display_name/_crew_label). ---

func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _position_panel(panel: PanelContainer, anchor: Vector2) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	panel.reset_size()
	var pos: Vector2 = anchor
	pos.x = clampf(pos.x, 0.0, vp.x - panel.size.x)
	pos.y = clampf(pos.y, 0.0, vp.y - panel.size.y)
	panel.position = pos


func _add_info_label(container: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_color_override("font_color", Color(0.70, 0.74, 0.80))
	container.add_child(lbl)


func _close_menu() -> void:
	_close_submenu()
	if _menu:
		_menu.queue_free()
		_menu = null


func _room_display_name(room_id: String) -> String:
	if room_id == "corridor_main":
		return "Corridor"
	return room_id.capitalize()


func _crew_label(crew_id: String) -> String:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	return crew.crew_name if crew != null else crew_id
