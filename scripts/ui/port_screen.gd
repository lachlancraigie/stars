extends CanvasLayer

# Port services screen (docs/loop-direction.md §6.3). Opens on EventBus.port_docked,
# closes on port_departed (or its own DEPART button). Pure render + call surface: every
# purchase routes through MissionManager.port_* methods, which own affordability checks
# and all state mutation (Architecture Rules 3/5) — buttons just call and refresh.

const PANEL_WIDTH: float = 560.0
const PANEL_HEIGHT: float = 620.0
const ROW_FONT: int = 14

const ACCENT: Color = Color(0.20, 0.80, 0.95)
const TEXT: Color = Color(0.85, 0.87, 0.92)
const DIM_TEXT: Color = Color(0.55, 0.60, 0.68)
const CREDIT_COLOUR: Color = Color(0.35, 0.95, 0.55)
const WARNING_COLOUR: Color = Color(0.9, 0.7, 0.1)

var _panel: Panel = null
var _title_label: Label = null
var _credits_label: Label = null
var _fee_label: Label = null
var _hull_label: Label = null
var _shuttle_label: Label = null
var _countdown_label: Label = null
var _hull_25_btn: Button = null
var _hull_full_btn: Button = null
var _shuttle_btn: Button = null
var _hire_btn: Button = null
var _hire_result_label: Label = null
var _item_buttons: Dictionary = {}   # item_id -> Button


func _ready() -> void:
	layer = 8
	_build()
	visible = false
	EventBus.port_docked.connect(_on_port_docked)
	EventBus.port_departed.connect(func(_name): visible = false)
	EventBus.port_service_purchased.connect(func(_service, _cost): _refresh())


func _process(_delta: float) -> void:
	if visible:
		_countdown_label.text = "Departure in %ds" % int(ceil(MissionManager.port_seconds_remaining()))


func _build() -> void:
	_panel = Panel.new()
	_panel.position = Vector2((1920.0 - PANEL_WIDTH) / 2.0, (1080.0 - PANEL_HEIGHT) / 2.0)
	_panel.size = Vector2(PANEL_WIDTH, PANEL_HEIGHT)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(16, 12)
	vbox.custom_minimum_size = Vector2(PANEL_WIDTH - 32, PANEL_HEIGHT - 24)
	vbox.add_theme_constant_override("separation", 7)
	_panel.add_child(vbox)

	_title_label = _line_label(20, ACCENT)
	vbox.add_child(_title_label)
	_fee_label = _line_label(12, DIM_TEXT)
	vbox.add_child(_fee_label)
	_credits_label = _line_label(16, CREDIT_COLOUR)
	vbox.add_child(_credits_label)
	vbox.add_child(HSeparator.new())

	# Repairs
	_hull_label = _line_label(ROW_FONT, TEXT)
	vbox.add_child(_hull_label)
	var repair_row := HBoxContainer.new()
	repair_row.add_theme_constant_override("separation", 10)
	_hull_25_btn = _service_button("Repair +25", func(): MissionManager.port_repair_hull(25.0))
	_hull_full_btn = _service_button("Repair full", func(): MissionManager.port_repair_hull(100.0))
	repair_row.add_child(_hull_25_btn)
	repair_row.add_child(_hull_full_btn)
	vbox.add_child(repair_row)

	_shuttle_label = _line_label(ROW_FONT, TEXT)
	vbox.add_child(_shuttle_label)
	_shuttle_btn = _service_button("Repair shuttle (%d cr)" % int(MissionManager.PORT_SHUTTLE_REPAIR_COST),
		func(): MissionManager.port_repair_shuttle())
	vbox.add_child(_shuttle_btn)
	vbox.add_child(HSeparator.new())

	# Chandlery
	var stock_header := _line_label(ROW_FONT, DIM_TEXT)
	stock_header.text = "Chandlery — issued to the captain's kit:"
	vbox.add_child(stock_header)
	var stock_grid := GridContainer.new()
	stock_grid.columns = 2
	stock_grid.add_theme_constant_override("h_separation", 10)
	stock_grid.add_theme_constant_override("v_separation", 5)
	for item_id: String in MissionManager.PORT_STOCK:
		var item: Dictionary = Items.get_item(item_id)
		if item.is_empty():
			continue
		var btn := _service_button("%s (%d cr)" % [String(item.get("name", item_id)), int(item.get("cost", 0))],
			func(): MissionManager.port_buy_item(item_id))
		stock_grid.add_child(btn)
		_item_buttons[item_id] = btn
	vbox.add_child(stock_grid)
	vbox.add_child(HSeparator.new())

	# Hiring hall
	_hire_btn = _service_button("Hire crew (%d cr)" % int(MissionManager.PORT_HIRE_COST), _on_hire_pressed)
	vbox.add_child(_hire_btn)
	_hire_result_label = _line_label(12, DIM_TEXT)
	vbox.add_child(_hire_result_label)
	vbox.add_child(HSeparator.new())

	var depart_btn := Button.new()
	depart_btn.text = "DEPART"
	depart_btn.custom_minimum_size = Vector2(PANEL_WIDTH - 32, 40)
	depart_btn.pressed.connect(func(): MissionManager.depart_port())
	vbox.add_child(depart_btn)

	_countdown_label = _line_label(12, DIM_TEXT)
	vbox.add_child(_countdown_label)


func _line_label(font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.custom_minimum_size = Vector2(PANEL_WIDTH - 32, 0)
	return label


func _service_button(text: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2((PANEL_WIDTH - 42) / 2.0, 30)
	btn.pressed.connect(on_press)
	return btn


func _on_port_docked(port_name: String, fee_charged: float, wages_frozen: bool) -> void:
	_title_label.text = "DOCKED — %s" % port_name
	if wages_frozen:
		_fee_label.text = "Docking fee %d cr — COULD NOT COVER WAGES. The crew know." % int(fee_charged)
		_fee_label.add_theme_color_override("font_color", WARNING_COLOUR)
	else:
		_fee_label.text = "Docking fee + wages paid: %d cr" % int(fee_charged)
		_fee_label.add_theme_color_override("font_color", DIM_TEXT)
	_hire_result_label.text = ""
	_refresh()
	visible = true


func _on_hire_pressed() -> void:
	var recruit: CrewMember = MissionManager.port_hire_crew()
	if recruit != null:
		_hire_result_label.text = "%s signed on. Green, but breathing." % recruit.crew_name


func _refresh() -> void:
	var credits: int = int(GameState.credits)
	_credits_label.text = "Credits: %d" % credits

	var hull: float = GameState.hull_integrity
	var missing: float = 100.0 - hull
	_hull_label.text = "Hull integrity: %d%%  (%d cr per point)" % [
		int(hull), int(MissionManager.PORT_HULL_REPAIR_PER_POINT)]
	var cost_25: float = minf(25.0, missing) * MissionManager.PORT_HULL_REPAIR_PER_POINT
	var cost_full: float = missing * MissionManager.PORT_HULL_REPAIR_PER_POINT
	_hull_25_btn.text = "Repair +%d (%d cr)" % [int(minf(25.0, missing)), int(cost_25)]
	_hull_full_btn.text = "Repair full (%d cr)" % int(cost_full)
	_hull_25_btn.disabled = missing <= 0.0 or GameState.credits < cost_25
	_hull_full_btn.disabled = missing <= 0.0 or GameState.credits < cost_full

	var shuttle_hull: float = 100.0
	if MissionManager.shuttle_system != null:
		shuttle_hull = MissionManager.shuttle_system.shuttle_hull
	_shuttle_label.text = "Shuttle hull: %d%%" % int(shuttle_hull)
	_shuttle_btn.disabled = shuttle_hull >= 100.0 or GameState.credits < MissionManager.PORT_SHUTTLE_REPAIR_COST

	for item_id: String in _item_buttons:
		var cost: float = float(Items.get_item(item_id).get("cost", 0))
		(_item_buttons[item_id] as Button).disabled = GameState.credits < cost

	_hire_btn.disabled = GameState.credits < MissionManager.PORT_HIRE_COST
