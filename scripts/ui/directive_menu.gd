extends CanvasLayer

# Click-on-crew contextual directive interface (see GDD: no free-text input).
# Left-click a crew member to select them: a selection ring, a top-level action menu, and a
# compact info card (top-right) all appear together. The top-level menu is deliberately
# shallow — "Inspect" (opens the full RosterPanel bio page) and "Move to ▸" (a SUBmenu
# holding the actual destination list, which used to be dumped flat at top level) — plus
# room for future directive entries alongside them. Every destination choice still issues a
# real AIDirective through AISystem; the crew then decides whether to comply (Architecture
# Rule 1: nothing here ever sets crew state directly). Click empty space or Esc dismisses
# everything.
#
# Crew live in world space under DeckCamera (scripts/ship/deck_camera.gd); this node is a
# CanvasLayer, so its own children (ring, menu, submenu, card) render in screen space and
# are untouched by the camera's pan/zoom. Hit-testing therefore compares in WORLD space
# (_world_mouse_pos() against crew global_position via CrewMemberNode.crew_at_world_point —
# the same shared hit-test EnvironmentMenu uses for doors/equipment, so crew always wins a
# click over environment targets), while anything positioned FOR DISPLAY on this layer
# converts a crew node's world position to screen space via
# get_global_transform_with_canvas().origin, which accounts for whatever camera transform
# is currently active.

const RING_RADIUS: float = 40.0
const RING_SEGMENTS: int = 28
const ACCENT: Color = Color(0.20, 0.80, 0.95)
const PANEL_BG: Color = Color(0.09, 0.11, 0.15, 0.95)
const MENU_OFFSET: Vector2 = Vector2(52, -40)
const SUBMENU_GAP: float = 8.0             # screen px between the top menu and the Move-to submenu
const SUBMENU_MAX_HEIGHT: float = 320.0    # scrollable past this — ships can have many rooms

# Info card (top-right) sizing/layout.
const CARD_SIZE: Vector2 = Vector2(240, 108)
const CARD_MARGIN: Vector2 = Vector2(16, 16)
const PORTRAIT_SRC_PATH: String = "res://assets/sprites/gen2/crew/portraits/head_s.png"
const PORTRAIT_DISPLAY_SIZE: Vector2 = Vector2(84, 84)  # upscaled nearest-neighbor from a ~25x21 source

var _selected_id: String = ""
var _ring: Line2D
var _menu: PanelContainer
var _submenu: PanelContainer
var _submenu_open: bool = false
var _card: PanelContainer

static var _portrait_texture: Texture2D = null
static var _portrait_load_attempted: bool = false


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
	# Keep the selection ring on the crew if they move (or the camera pans/
	# zooms) while selected.
	if _selected_id != "":
		var node: CrewMemberNode = CrewMemberNode.nodes.get(_selected_id) as CrewMemberNode
		if node:
			_ring.position = _screen_pos(node)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed):
		return

	# World-space hit test — deliberately NOT gated on whether DeckCamera
	# turns this same press into a drag; the crew-select/menu-open decision
	# is made here at press time regardless (see deck_camera.gd's comment on
	# why it never marks button events as handled).
	var hit: CrewMemberNode = CrewMemberNode.crew_at_world_point(_world_mouse_pos())
	if hit:
		_select(hit)
	else:
		_deselect()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var ke := event as InputEventKey
	if ke.pressed and not ke.is_echo() and ke.keycode == KEY_ESCAPE:
		_deselect()


# World position of a crew node, converted to this CanvasLayer's screen space
# (accounts for DeckCamera's current pan/zoom).
func _screen_pos(node: CrewMemberNode) -> Vector2:
	return node.get_global_transform_with_canvas().origin


# CanvasLayer isn't a CanvasItem (no get_global_mouse_position() of its own,
# unlike the crew Node2Ds), so invert the viewport's canvas transform by hand
# — identical to what Node2D.get_global_mouse_position() does internally.
func _world_mouse_pos() -> Vector2:
	var vp: Viewport = get_viewport()
	return vp.get_canvas_transform().affine_inverse() * vp.get_mouse_position()


func _select(node: CrewMemberNode) -> void:
	_selected_id = node.crew_data.crew_id
	_ring.position = _screen_pos(node)
	_ring.visible = true
	_submenu_open = false
	_open_menu(node)
	_open_card(node)


func _deselect() -> void:
	_selected_id = ""
	_ring.visible = false
	_close_menu()
	_close_submenu()
	_close_card()


# --- Top-level menu: Inspect / Move to ▸ ---

func _open_menu(node: CrewMemberNode) -> void:
	_close_menu()
	_close_submenu()
	_menu = _make_panel()

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_menu.add_child(vbox)

	var header := Label.new()
	header.text = node.crew_data.crew_name
	header.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(header)

	var inspect_btn := Button.new()
	inspect_btn.text = "Inspect"
	inspect_btn.pressed.connect(_on_inspect_pressed.bind(node.crew_data.crew_id))
	vbox.add_child(inspect_btn)

	var move_btn := Button.new()
	move_btn.text = "Move to ▸"
	move_btn.pressed.connect(_on_move_to_pressed.bind(node))
	vbox.add_child(move_btn)

	# Room for future directive entries here, alongside Inspect/Move to — none exist yet
	# beyond destinations, which the submenu above already covers.

	add_child(_menu)
	_position_panel(_menu, _screen_pos(node) + MENU_OFFSET)


func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


func _on_inspect_pressed(crew_id: String) -> void:
	if RosterPanel.instance:
		RosterPanel.instance.open_for_crew(crew_id)


# --- Move-to submenu: the old flat destination list, now nested one level down ---

func _on_move_to_pressed(node: CrewMemberNode) -> void:
	if _submenu_open:
		_close_submenu()
		return
	_open_submenu(node)


func _open_submenu(node: CrewMemberNode) -> void:
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

	# One "go to" option per room except the crew's current location and bare
	# transit corridors (generated ships can have several corridor segments;
	# they're pass-through, not meaningful directive destinations).
	var room_ids: Array[String] = []
	for room_id: String in GameState.rooms:
		if room_id == node.crew_data.location:
			continue
		var room: RoomBase = GameState.rooms[room_id]
		if room and room.room_function == "corridor":
			continue
		room_ids.append(room_id)
	room_ids.sort()

	for room_id: String in room_ids:
		var button := Button.new()
		button.text = "Go to %s" % _room_display_name(room_id)
		button.pressed.connect(_on_destination_chosen.bind(node.crew_data.crew_id, room_id))
		vbox.add_child(button)

	if room_ids.is_empty():
		var lbl := Label.new()
		lbl.text = "No destinations."
		vbox.add_child(lbl)

	add_child(_submenu)
	_submenu.reset_size()
	scroll.custom_minimum_size.y = minf(SUBMENU_MAX_HEIGHT, _submenu.size.y)

	# Anchor to the right of the top-level menu, falling back below it if that would run
	# off-screen (same clamp idiom _position_panel already applies for the final position).
	_menu.reset_size()
	var anchor: Vector2 = _menu.position + Vector2(_menu.size.x + SUBMENU_GAP, 0)
	_position_panel(_submenu, anchor)


func _close_submenu() -> void:
	_submenu_open = false
	if _submenu:
		_submenu.queue_free()
		_submenu = null


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


# --- Info card (top-right): portrait, name, age, role, rank ---

func _open_card(node: CrewMemberNode) -> void:
	_close_card()
	var crew: CrewMember = node.crew_data
	_card = _make_panel()
	_card.custom_minimum_size = CARD_SIZE

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	_card.add_child(hbox)

	var portrait := TextureRect.new()
	portrait.texture = _get_portrait_texture()
	portrait.custom_minimum_size = PORTRAIT_DISPLAY_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	# Crisp pixel-art upscale — no smoothing filter (task spec: "crisp pixels, no filtering").
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Same role tint the in-world sprite wears (CrewMemberNode.ROLE_TINT) so the card reads
	# as "this crew member" rather than a generic silhouette, even though every crew member
	# currently shares one canonical head asset (gen2 art is a single character design).
	portrait.self_modulate = CrewMemberNode.ROLE_TINT.get(crew.role, Color.WHITE)
	hbox.add_child(portrait)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = crew.crew_name
	name_lbl.add_theme_color_override("font_color", ACCENT)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_lbl)

	_add_card_line(vbox, "Age %d · %s" % [crew.age, crew.role.capitalize()])
	_add_card_line(vbox, "%s · %s" % [crew.rank.capitalize().replace("_", " "), crew.mship_class])

	add_child(_card)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_card.reset_size()
	_card.position = Vector2(vp.x - _card.size.x - CARD_MARGIN.x, CARD_MARGIN.y)


func _add_card_line(container: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.80, 0.84, 0.90))
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	container.add_child(lbl)


func _close_card() -> void:
	if _card:
		_card.queue_free()
		_card = null


# Loaded once for the whole process (every card shares the same canonical head texture —
# assets/sprites/gen2/crew/portraits/head_s.png, copied from the head-swap compositing
# work's _test/canonical_heads/ output; see tools/image_gen/crew_head_swap.py). Missing
# file degrades to no portrait rather than an error, matching the gen2 sprite fallback
# idiom elsewhere in this codebase (CrewMemberNode._ensure_gen2_manifest).
func _get_portrait_texture() -> Texture2D:
	if not _portrait_load_attempted:
		_portrait_load_attempted = true
		if ResourceLoader.exists(PORTRAIT_SRC_PATH):
			_portrait_texture = load(PORTRAIT_SRC_PATH)
	return _portrait_texture


# --- Shared panel styling/positioning ---

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


# Positions `panel` at `anchor` (screen px), clamped to stay fully on-screen.
func _position_panel(panel: PanelContainer, anchor: Vector2) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	panel.reset_size()
	var pos: Vector2 = anchor
	pos.x = clampf(pos.x, 0.0, vp.x - panel.size.x)
	pos.y = clampf(pos.y, 0.0, vp.y - panel.size.y)
	panel.position = pos


func _room_display_name(room_id: String) -> String:
	if room_id == "corridor_main":
		return "Corridor"
	return room_id.capitalize()  # "life_support" -> "Life Support"
