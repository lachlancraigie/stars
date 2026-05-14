extends CanvasLayer

# Minimal resource readout. Built programmatically — replace with designed scene later.
# All resource bars update live via EventBus.resource_changed.

const PANEL_PADDING: float = 5.0
const ROW_HEIGHT: float = 28.0
const LABEL_WIDTH: float = 100.0
const BAR_WIDTH: float = 120.0

const CRITICAL_COLOUR: Color = Color(0.9, 0.2, 0.1)
const NORMAL_COLOUR: Color = Color(0.2, 0.7, 0.3)
const WARNING_COLOUR: Color = Color(0.9, 0.7, 0.1)

var _bars: Dictionary = {}  # resource_name -> ProgressBar


func _ready() -> void:
	_build_ui()
	EventBus.resource_changed.connect(_on_resource_changed)


func _build_ui() -> void:
	var resource_names: Array = GameState.resources.keys()
	var panel_height: float = resource_names.size() * ROW_HEIGHT + PANEL_PADDING * 2

	var panel := Panel.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(LABEL_WIDTH + BAR_WIDTH + PANEL_PADDING * 3, panel_height)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(PANEL_PADDING, PANEL_PADDING)
	vbox.size = Vector2(panel.size.x - PANEL_PADDING * 2, panel_height - PANEL_PADDING * 2)
	panel.add_child(vbox)

	for resource_name in resource_names:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, ROW_HEIGHT - 4)

		var label := Label.new()
		label.text = resource_name.capitalize().replace("_", " ")
		label.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = GameState.get_resource(resource_name)
		bar.custom_minimum_size = Vector2(BAR_WIDTH, 20)
		bar.show_percentage = false
		_set_bar_colour(bar, bar.value)

		row.add_child(label)
		row.add_child(bar)
		vbox.add_child(row)
		_bars[resource_name] = bar


func _on_resource_changed(resource_name: String, value: float, _delta: float) -> void:
	if resource_name not in _bars:
		return
	var bar: ProgressBar = _bars[resource_name]
	bar.value = value
	_set_bar_colour(bar, value)


func _set_bar_colour(bar: ProgressBar, value: float) -> void:
	var colour: Color = NORMAL_COLOUR if value > 0.5 else (WARNING_COLOUR if value > 0.2 else CRITICAL_COLOUR)
	bar.modulate = colour
