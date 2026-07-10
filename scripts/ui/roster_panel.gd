extends CanvasLayer

# Roster biography panel (docs/crew-progression-spec.md §5): "click a crew member -> service
# record: name, archetype blurb, legs served, traits with blurbs, skills, relationships
# (partner/friends via affinity), wounds. This panel is WHY death hurts — it's a biography,
# not a stat block." Toggled by its own corner button / the C key rather than a world click
# on the crew sprite — that click is already DirectiveMenu's "select crew, choose a
# destination" gesture (Rule 1: nothing here ever moves crew, so it stays a pure read-only
# side panel that can coexist with DirectiveMenu without fighting over the same click).
#
# A LOST tab reads GameState.fallen directly (CrewLifecycle.kill's memorial snapshot) since
# a dead crew member has no CrewMemberNode left in the world to click on at all — the tab is
# the only way to ever see their record again.
#
# Built programmatically like HUD/DirectiveMenu (no complex scene needed) — this file is
# the whole implementation; RosterPanel.tscn is just the CanvasLayer + script wrapper.

const PANEL_BG: Color = Color(0.09, 0.11, 0.15, 0.95)
const ACCENT: Color = Color(0.20, 0.80, 0.95)
const DIM_TEXT: Color = Color(0.55, 0.60, 0.68)
const BODY_TEXT: Color = Color(0.88, 0.90, 0.94)
const BUFF_COLOUR: Color = Color(0.45, 0.85, 0.55)
const DEBUFF_COLOUR: Color = Color(0.90, 0.45, 0.40)
const LOST_COLOUR: Color = Color(0.80, 0.45, 0.45)

const TOGGLE_BTN_SIZE: Vector2 = Vector2(120, 32)
const PANEL_SIZE: Vector2 = Vector2(760, 560)
const LIST_WIDTH: float = 210.0
const FRIEND_AFFINITY_MIN: float = 0.15   # only surface relationships that actually mean something
const FRIEND_LIST_MAX: int = 3

var _open: bool = false
var _tab: String = "crew"              # "crew" | "lost"
var _selected_crew_id: String = ""     # CREW tab selection
var _selected_fallen_index: int = -1   # LOST tab selection (index into GameState.fallen)

var _root_panel: PanelContainer
var _list_box: VBoxContainer
var _detail_box: VBoxContainer
var _tab_crew_btn: Button
var _tab_lost_btn: Button


func _ready() -> void:
	layer = 6  # above DirectiveMenu (5) — a modal-ish inspection panel sits on top
	_build_toggle_button()
	# Live refresh: a trait earned, a death, a tier-up, or a stress change while the panel
	# is open should be visible immediately, not just on next open — this is the panel
	# that's supposed to make progression feel real as it happens.
	EventBus.crew_trait_gained.connect(func(_cid, _tid): _refresh_if_open())
	EventBus.crew_trait_lost.connect(func(_cid, _tid): _refresh_if_open())
	EventBus.crew_died.connect(func(_cid, _cause): _refresh_if_open())
	EventBus.crew_skill_tier_up.connect(func(_cid, _s, _t): _refresh_if_open())
	EventBus.crew_stress_changed.connect(func(_cid, _o, _n): _refresh_if_open())
	EventBus.crew_injury.connect(func(_cid, _sev, _wt): _refresh_if_open())


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.is_echo() and key_event.keycode == KEY_C:
		_toggle()


func _build_toggle_button() -> void:
	var btn := Button.new()
	btn.text = "ROSTER (C)"
	btn.custom_minimum_size = TOGGLE_BTN_SIZE
	btn.position = Vector2(1920 - TOGGLE_BTN_SIZE.x - 10, 10)
	btn.pressed.connect(_toggle)
	add_child(btn)


func _toggle() -> void:
	if _open:
		_close()
	else:
		_open_panel()


func _open_panel() -> void:
	_open = true
	_build_panel()
	_refresh()


func _close() -> void:
	_open = false
	if _root_panel:
		_root_panel.queue_free()
		_root_panel = null
		_list_box = null
		_detail_box = null


func _refresh_if_open() -> void:
	if _open:
		_refresh()


# --- Panel construction ---

func _build_panel() -> void:
	_root_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.border_color = ACCENT
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	_root_panel.add_theme_stylebox_override("panel", style)
	_root_panel.custom_minimum_size = PANEL_SIZE
	_root_panel.position = Vector2((1920.0 - PANEL_SIZE.x) / 2.0, (1080.0 - PANEL_SIZE.y) / 2.0)
	add_child(_root_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 8)
	_root_panel.add_child(outer)
	outer.add_child(_build_header_row())

	var body_height: float = PANEL_SIZE.y - 70.0
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.custom_minimum_size = Vector2(PANEL_SIZE.x - 20.0, body_height)
	outer.add_child(body)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(LIST_WIDTH, body_height)
	body.add_child(list_scroll)
	_list_box = VBoxContainer.new()
	_list_box.custom_minimum_size = Vector2(LIST_WIDTH - 16.0, 0)
	_list_box.add_theme_constant_override("separation", 4)
	list_scroll.add_child(_list_box)

	body.add_child(VSeparator.new())

	var detail_width: float = PANEL_SIZE.x - 20.0 - LIST_WIDTH - 20.0
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(detail_width, body_height)
	body.add_child(detail_scroll)
	_detail_box = VBoxContainer.new()
	_detail_box.custom_minimum_size = Vector2(detail_width - 16.0, 0)
	_detail_box.add_theme_constant_override("separation", 6)
	detail_scroll.add_child(_detail_box)


func _build_header_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	_tab_crew_btn = Button.new()
	_tab_crew_btn.text = "CREW"
	_tab_crew_btn.toggle_mode = true
	_tab_crew_btn.pressed.connect(func(): _set_tab("crew"))
	row.add_child(_tab_crew_btn)

	_tab_lost_btn = Button.new()
	_tab_lost_btn.text = "LOST"
	_tab_lost_btn.toggle_mode = true
	_tab_lost_btn.pressed.connect(func(): _set_tab("lost"))
	row.add_child(_tab_lost_btn)

	var left_spacer := Control.new()
	left_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(left_spacer)

	var title := Label.new()
	title.text = GameState.ship_name if GameState.ship_name != "" else "SHIP ROSTER"
	title.add_theme_color_override("font_color", ACCENT)
	row.add_child(title)

	var right_spacer := Control.new()
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right_spacer)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(28, 28)
	close_btn.pressed.connect(_close)
	row.add_child(close_btn)
	return row


func _set_tab(tab: String) -> void:
	_tab = tab
	_refresh()


# --- Refresh: rebuild the list + detail from current GameState ---

func _refresh() -> void:
	if _list_box == null:
		return
	_tab_crew_btn.button_pressed = _tab == "crew"
	_tab_lost_btn.button_pressed = _tab == "lost"
	for child in _list_box.get_children():
		child.queue_free()
	if _tab == "crew":
		_refresh_crew_list()
	else:
		_refresh_lost_list()
	_refresh_detail()


func _refresh_crew_list() -> void:
	var ids: Array = []
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive:
			ids.append(crew_id)
	ids.sort()

	var selected_still_alive: bool = false
	if _selected_crew_id != "":
		var selected: CrewMember = GameState.crew.get(_selected_crew_id) as CrewMember
		selected_still_alive = selected != null and selected.is_alive
	if not selected_still_alive and not ids.is_empty():
		_selected_crew_id = String(ids[0])

	for crew_id: String in ids:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		var btn := Button.new()
		btn.text = crew.crew_name
		btn.toggle_mode = true
		btn.button_pressed = crew_id == _selected_crew_id
		btn.pressed.connect(_select_crew.bind(crew_id))
		_list_box.add_child(btn)

	if ids.is_empty():
		_add_to(_list_box, "No living crew.", DIM_TEXT)


func _refresh_lost_list() -> void:
	if _selected_fallen_index < 0 or _selected_fallen_index >= GameState.fallen.size():
		_selected_fallen_index = GameState.fallen.size() - 1
	for i in GameState.fallen.size():
		var entry: Dictionary = GameState.fallen[i]
		var btn := Button.new()
		btn.text = String(entry.get("name", "?"))
		btn.toggle_mode = true
		btn.button_pressed = i == _selected_fallen_index
		btn.add_theme_color_override("font_color", LOST_COLOUR)
		btn.pressed.connect(_select_fallen.bind(i))
		_list_box.add_child(btn)
	if GameState.fallen.is_empty():
		_add_to(_list_box, "No losses yet.", DIM_TEXT)


func _select_crew(crew_id: String) -> void:
	_selected_crew_id = crew_id
	_refresh()


func _select_fallen(index: int) -> void:
	_selected_fallen_index = index
	_refresh()


# --- Detail pane ---

func _refresh_detail() -> void:
	for child in _detail_box.get_children():
		child.queue_free()
	if _tab == "crew":
		_render_crew_detail()
	else:
		_render_fallen_detail()


func _render_crew_detail() -> void:
	if _selected_crew_id == "":
		_add_label("No living crew.", DIM_TEXT)
		return
	var crew: CrewMember = GameState.crew.get(_selected_crew_id) as CrewMember
	if crew == null:
		return

	_add_title(crew.crew_name)
	_add_label(_archetype_blurb(crew), DIM_TEXT)
	_add_label("Legs served: %d" % crew.legs_served)
	_add_label("Stress: %d (min %d)   Wounds: %d/%d" % [crew.stress, crew.min_stress, crew.wounds, crew.max_wounds])
	if not crew.conditions.is_empty():
		_add_label("Conditions: %s" % ", ".join(crew.conditions).replace("_", " "), DEBUFF_COLOUR)

	_add_section("TRAITS")
	if crew.traits.is_empty():
		_add_label("None yet — the voyage is young.", DIM_TEXT)
	else:
		for trait_id: String in crew.traits:
			_add_trait_row(trait_id)

	_add_section("SKILLS")
	if crew.skills.is_empty():
		_add_label("None trained.", DIM_TEXT)
	else:
		for skill_name: String in crew.skills:
			var progress: int = int(crew.skill_progress.get(skill_name, 0))
			var suffix: String = "  (+%d/%d toward next tier)" % [progress, CrewProgression.SKILL_PROGRESS_TIER_UP] if progress > 0 else ""
			_add_label("%s — %s%s" % [skill_name, crew.skills[skill_name], suffix])

	_add_section("RELATIONSHIPS")
	_render_relationships(crew.crew_id)


func _render_fallen_detail() -> void:
	if _selected_fallen_index < 0 or _selected_fallen_index >= GameState.fallen.size():
		_add_label("No losses yet. Every crew member currently aboard is alive.", DIM_TEXT)
		return
	var entry: Dictionary = GameState.fallen[_selected_fallen_index]
	_add_title(String(entry.get("name", "?")))
	_add_label("%s · %s" % [
		String(entry.get("role", "")).capitalize(),
		String(entry.get("archetype_tag", "")) if String(entry.get("archetype_tag", "")) != "" else "no archetype",
	], DIM_TEXT)
	_add_label("Legs served: %d" % int(entry.get("legs_served", 0)))
	_add_label("Cause of death: %s" % String(entry.get("cause", "unknown")).capitalize().replace("_", " "), LOST_COLOUR)
	var partner_id: String = String(entry.get("partner", ""))
	if partner_id != "":
		_add_label("Left behind: %s" % _crew_label(partner_id))

	_add_section("TRAITS AT TIME OF DEATH")
	var traits_at_death: Array = entry.get("traits", [])
	if traits_at_death.is_empty():
		_add_label("None earned — lost too soon.", DIM_TEXT)
	else:
		for trait_id: Variant in traits_at_death:
			_add_trait_row(String(trait_id))


func _archetype_blurb(crew: CrewMember) -> String:
	return "%s · %s · %s" % [crew.mship_class, crew.role.capitalize(), crew.rank.capitalize().replace("_", " ")]


func _add_trait_row(trait_id: String) -> void:
	var colour: Color = BODY_TEXT
	match Traits.polarity(trait_id):
		"buff": colour = BUFF_COLOUR
		"debuff": colour = DEBUFF_COLOUR
	_add_label(Traits.display_name(trait_id), colour)
	var blurb: String = Traits.blurb(trait_id)
	if blurb != "":
		var blurb_lbl := Label.new()
		blurb_lbl.text = blurb
		blurb_lbl.add_theme_font_size_override("font_size", 12)
		blurb_lbl.add_theme_color_override("font_color", DIM_TEXT)
		blurb_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		_detail_box.add_child(blurb_lbl)


func _render_relationships(crew_id: String) -> void:
	var partner_id: String = RelationshipGraph.partner_of(crew_id)
	if partner_id != "":
		_add_label("Partner: %s" % _crew_label(partner_id), BUFF_COLOUR)
	var friends: Array = _top_affinities(crew_id, partner_id)
	if friends.is_empty() and partner_id == "":
		_add_label("No close bonds yet.", DIM_TEXT)
	for pair: Array in friends:
		_add_label("Close with %s (affinity %.2f)" % [_crew_label(String(pair[0])), float(pair[1])])


# Every other living crew member this one has a meaningfully positive bond with, sorted
# strongest-first, excluding the partner (already shown on its own line above).
func _top_affinities(crew_id: String, exclude_id: String) -> Array:
	var scored: Array = []
	for key: String in GameState.crew_relationships:
		var ids: PackedStringArray = key.split("|")
		if ids.size() != 2 or crew_id not in ids:
			continue
		var other_id: String = ids[1] if ids[0] == crew_id else ids[0]
		if other_id == exclude_id or other_id == crew_id:
			continue
		var affinity: float = float((GameState.crew_relationships[key] as Dictionary).get("affinity", 0.0))
		if affinity >= FRIEND_AFFINITY_MIN:
			scored.append([other_id, affinity])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return scored.slice(0, FRIEND_LIST_MAX)


func _crew_label(crew_id: String) -> String:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	return crew.crew_name if crew != null else crew_id


# --- Small label builders ---

func _add_title(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", ACCENT)
	_detail_box.add_child(lbl)


func _add_section(text: String) -> void:
	_detail_box.add_child(HSeparator.new())
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", ACCENT)
	_detail_box.add_child(lbl)


func _add_label(text: String, colour: Color = BODY_TEXT) -> void:
	_add_to(_detail_box, text, colour)


func _add_to(container: VBoxContainer, text: String, colour: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	lbl.add_theme_color_override("font_color", colour)
	container.add_child(lbl)
