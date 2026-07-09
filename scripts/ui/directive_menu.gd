extends CanvasLayer

# Click-on-crew contextual directive interface (see GDD: no free-text input).
# Left-click a crew member to select them and open a menu of destinations; each
# choice issues a real AIDirective through AISystem — the crew then decides
# whether to comply. Click empty space to dismiss.
#
# World and canvas share one coordinate space here (no Camera2D, canvas_items
# stretch), so crew Node2D positions compare directly against input positions.

const CLICK_RADIUS: float = 60.0
const RING_RADIUS: float = 40.0
const RING_SEGMENTS: int = 28
const ACCENT: Color = Color(0.20, 0.80, 0.95)
const PANEL_BG: Color = Color(0.09, 0.11, 0.15, 0.95)
const MENU_OFFSET: Vector2 = Vector2(52, -40)

var _selected_id: String = ""
var _ring: Line2D
var _menu: PanelContainer


func _ready() -> void:
	layer = 5  # above the world and the HUD
	_ring = Line2D.new()
	_ring.width = 3.0
	_ring.default_color = ACCENT
	_ring.closed = true
	_ring.visible = false
	for i in RING_SEGMENTS:
		var a: float = TAU * float(i) / float(RING_SEGMENTS)
		_ring.add_point(Vector2(cos(a), sin(a)) * RING_RADIUS)
	add_child(_ring)


func _process(_delta: float) -> void:
	# Keep the selection ring on the crew if they move while selected.
	if _selected_id != "":
		var node: CrewMemberNode = CrewMemberNode.nodes.get(_selected_id) as CrewMemberNode
		if node:
			_ring.position = node.global_position


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed):
		return

	var hit: CrewMemberNode = _crew_at(mb.position)
	if hit:
		_select(hit)
	else:
		_deselect()


func _crew_at(point: Vector2) -> CrewMemberNode:
	var best: CrewMemberNode = null
	var best_dist: float = CLICK_RADIUS
	for crew_id: String in CrewMemberNode.nodes:
		var node: CrewMemberNode = CrewMemberNode.nodes[crew_id] as CrewMemberNode
		if node == null:
			continue
		# Crew live inside the scaled ShipDeck — compare in canvas space.
		var d: float = node.global_position.distance_to(point)
		if d <= best_dist:
			best = node
			best_dist = d
	return best


func _select(node: CrewMemberNode) -> void:
	_selected_id = node.crew_data.crew_id
	_ring.position = node.global_position
	_ring.visible = true
	_open_menu(node)


func _deselect() -> void:
	_selected_id = ""
	_ring.visible = false
	_close_menu()


func _open_menu(node: CrewMemberNode) -> void:
	_close_menu()
	_menu = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	_menu.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_menu.add_child(vbox)

	var header := Label.new()
	header.text = node.crew_data.crew_name
	header.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(header)

	# One "go to" option per room except the crew's current location.
	for room_id: String in GameState.rooms:
		if room_id == node.crew_data.location:
			continue
		var button := Button.new()
		button.text = "Go to %s" % _room_display_name(room_id)
		button.pressed.connect(_on_destination_chosen.bind(node.crew_data.crew_id, room_id))
		vbox.add_child(button)

	add_child(_menu)
	# Position beside the crew, kept on-screen.
	var pos: Vector2 = node.global_position + MENU_OFFSET
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_menu.reset_size()
	pos.x = clampf(pos.x, 0.0, vp.x - _menu.size.x)
	pos.y = clampf(pos.y, 0.0, vp.y - _menu.size.y)
	_menu.position = pos


func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


func _on_destination_chosen(crew_id: String, room_id: String) -> void:
	var d := AIDirective.new()
	d.type = AIDirective.Type.RECOMMENDATION
	d.target_type = AIDirective.TargetType.CREW
	d.target_id = crew_id
	d.content = "Proceed to %s." % _room_display_name(room_id)
	d.move_to_room = room_id
	d.confidence = 0.85
	d.priority = 2
	AISystem.issue_directive(d)
	_deselect()


func _room_display_name(room_id: String) -> String:
	if room_id == "corridor_main":
		return "Corridor"
	return room_id.capitalize()  # "life_support" -> "Life Support"
