extends CanvasLayer

# Click-on-environment contextual menu — the door/equipment counterpart to DirectiveMenu's
# click-on-crew menu. Shares one CanvasLayer with (eventually) damaged-equipment repair
# menus; this pass wires up doors:
#   Doors: Open/Close (cosmetic leaf state) + Lock/Unlock (the AI operating the door
#   directly — NOT a crew directive; see door.gd).
#
# Hit-testing mirrors DirectiveMenu exactly (world-space, CanvasLayer canvas-transform
# inversion) and explicitly checks crew FIRST via the shared CrewMemberNode.crew_at_world_point
# helper — a click that lands on a crew member is DirectiveMenu's to handle, never this
# layer's, even if a door happens to be nearby.

const DOOR_CLICK_RADIUS: float = 45.0     # door gates are one deck tile — a tighter target than crew/rooms

const ACCENT: Color = Color(0.95, 0.70, 0.25)   # amber — visually distinct from DirectiveMenu's cyan crew accent
const PANEL_BG: Color = Color(0.09, 0.11, 0.15, 0.95)
const MENU_OFFSET: Vector2 = Vector2(30, -20)

var _menu: PanelContainer


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
	if _menu:
		_menu.queue_free()
		_menu = null


func _room_display_name(room_id: String) -> String:
	if room_id == "corridor_main":
		return "Corridor"
	return room_id.capitalize()
