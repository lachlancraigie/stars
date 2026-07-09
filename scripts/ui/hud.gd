extends CanvasLayer

# Resource readout (left), objective line (top centre), event feed (bottom
# left), and a win/lose banner. Built programmatically — replace with a
# designed scene later. Updates live via EventBus.

const PANEL_PADDING: float = 5.0
const ROW_HEIGHT: float = 28.0
const LABEL_WIDTH: float = 100.0
const BAR_WIDTH: float = 120.0
const FEED_LINES: int = 7

const CRITICAL_COLOUR: Color = Color(0.9, 0.2, 0.1)
const NORMAL_COLOUR: Color = Color(0.2, 0.7, 0.3)
const WARNING_COLOUR: Color = Color(0.9, 0.7, 0.1)
const ACCENT: Color = Color(0.20, 0.80, 0.95)
const FEED_COLOUR: Color = Color(0.65, 0.72, 0.80)

# Player-readable text for scenario event ids (fallback: prettified id).
const EVENT_TEXT: Dictionary = {
	"scenario_started": "Scenario started: The Quarantine",
	"pathogen_detected": "⚠ Biosensors flag an anomalous pathogen in Vasquez's bloodwork.",
	"pathogen_spreads": "⚠ Secondary exposure — Okafor's bioscan shows the same signature.",
	"symptoms_appear": "Vasquez reports feeling feverish.",
	"containment_possible": "Dr. Chen requests the full biosensor log.",
	"life_support_contaminated": "☣ Pathogen detected in the air recyclers.",
	"vasquez_isolated": "Vasquez is isolated in the Medbay.",
	"pathogen_contained": "✔ Containment protocol complete.",
}

var _bars: Dictionary = {}  # resource_name -> ProgressBar
var _objective_label: Label
var _feed_box: VBoxContainer


func _ready() -> void:
	_build_resource_panel()
	_build_objective_label()
	_build_feed()
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.objective_changed.connect(_on_objective_changed)
	EventBus.scenario_event_triggered.connect(_on_scenario_event)
	EventBus.directive_accepted.connect(
		func(cid, d): _push_feed("%s: complying — %s" % [_crew_name(cid), d.content]))
	EventBus.directive_rejected.connect(
		func(cid, d, _r): _push_feed("%s: refuses — %s" % [_crew_name(cid), d.content]))
	EventBus.crew_died.connect(
		func(cid, _cause): _push_feed("☠ %s has died." % _crew_name(cid)))
	EventBus.scenario_ended.connect(_on_scenario_ended)


func _build_resource_panel() -> void:
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
	_push_feed(EVENT_TEXT.get(event_id, event_id.capitalize()))


func _on_scenario_ended(outcome: String) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.size = Vector2(1920, 1080)
	add_child(dim)

	var banner := Label.new()
	var won: bool = outcome == "success"
	banner.text = "MISSION COMPLETE\nPathogen contained. The voyage continues." if won \
		else "MISSION FAILED\n%s" % outcome.capitalize().replace("_", " ")
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 44)
	banner.add_theme_color_override("font_color",
		Color(0.35, 0.95, 0.55) if won else Color(0.95, 0.30, 0.25))
	banner.position = Vector2(0, 460)
	banner.size = Vector2(1920, 160)
	add_child(banner)


func _on_resource_changed(resource_name: String, value: float, _delta: float) -> void:
	if resource_name not in _bars:
		return
	var bar: ProgressBar = _bars[resource_name]
	bar.value = value
	_set_bar_colour(bar, value)


func _set_bar_colour(bar: ProgressBar, value: float) -> void:
	var colour: Color = NORMAL_COLOUR if value > 0.5 else (WARNING_COLOUR if value > 0.2 else CRITICAL_COLOUR)
	bar.modulate = colour
