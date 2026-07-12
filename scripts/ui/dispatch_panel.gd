extends CanvasLayer

# Dispatch offer cards (docs/loop-direction.md §6.1). Appears when MissionManager posts
# contract offers; each card carries the overt risk/reward facts (pay, away-risk tier,
# giver, destination, briefing) and a RECOMMEND button. Pure render + one call surface:
# every press routes to MissionManager.recommend_offer() — the captain-mediation roll
# and all state live there, never here (Architecture Rules 3/5). The window countdown
# is MissionManager's too; this just displays it.

const CARD_WIDTH: float = 380.0
const CARD_HEIGHT: float = 330.0
const CARD_GAP: float = 30.0
const RESULT_LINGER_SECONDS: float = 5.0

const ACCENT: Color = Color(0.20, 0.80, 0.95)
const TEXT: Color = Color(0.85, 0.87, 0.92)
const DIM_TEXT: Color = Color(0.55, 0.60, 0.68)
const PAY_COLOUR: Color = Color(0.35, 0.95, 0.55)
const OVERRIDE_COLOUR: Color = Color(0.95, 0.55, 0.25)
const RISK_COLOURS: Dictionary = {
	"low": Color(0.2, 0.7, 0.3), "moderate": Color(0.9, 0.7, 0.1),
	"high": Color(0.95, 0.45, 0.15), "extreme": Color(0.9, 0.2, 0.1),
}

var _root: Control = null
var _cards_box: HBoxContainer = null
var _header_label: Label = null
var _countdown_label: Label = null
var _result_label: Label = null
var _result_shown_at: float = -1.0


func _ready() -> void:
	layer = 8
	_build()
	visible = false
	EventBus.mission_offers_posted.connect(_on_offers_posted)
	EventBus.mission_selected.connect(_on_mission_selected)


func _process(_delta: float) -> void:
	if not visible:
		return
	if _result_shown_at >= 0.0:
		if Time.get_ticks_msec() / 1000.0 - _result_shown_at >= RESULT_LINGER_SECONDS:
			_close()
		return
	var remaining: float = MissionManager.dispatch_seconds_remaining()
	_countdown_label.text = "Dispatch window closes in %ds — captain will choose unaided." % int(ceil(remaining))


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_header_label = Label.new()
	_header_label.text = "INCOMING DISPATCH — CONTRACTS ON OFFER"
	_header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header_label.add_theme_font_size_override("font_size", 26)
	_header_label.add_theme_color_override("font_color", ACCENT)
	_header_label.position = Vector2(0, 150)
	_header_label.size = Vector2(1920, 40)
	_root.add_child(_header_label)

	_countdown_label = Label.new()
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 14)
	_countdown_label.add_theme_color_override("font_color", DIM_TEXT)
	_countdown_label.position = Vector2(0, 192)
	_countdown_label.size = Vector2(1920, 24)
	_root.add_child(_countdown_label)

	_cards_box = HBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", int(CARD_GAP))
	_cards_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_box.position = Vector2(0, 240)
	_cards_box.size = Vector2(1920, CARD_HEIGHT)
	_root.add_child(_cards_box)

	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_label.add_theme_font_size_override("font_size", 20)
	_result_label.position = Vector2(360, 600)
	_result_label.size = Vector2(1200, 80)
	_root.add_child(_result_label)


func _on_offers_posted(_offer_ids: Array) -> void:
	for child in _cards_box.get_children():
		child.queue_free()
	_result_label.text = ""
	_result_shown_at = -1.0
	for offer: MissionDef in MissionManager.dispatch_offers:
		_cards_box.add_child(_make_card(offer))
	visible = true


func _make_card(offer: MissionDef) -> Panel:
	var card := Panel.new()
	card.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(12, 10)
	vbox.custom_minimum_size = Vector2(CARD_WIDTH - 24, CARD_HEIGHT - 20)
	vbox.add_theme_constant_override("separation", 5)
	card.add_child(vbox)

	vbox.add_child(_line(offer.title, 18, ACCENT))
	vbox.add_child(_line("%s — %s" % [offer.giver, offer.mission_type.capitalize().replace("_", " ")], 13, DIM_TEXT))
	var dest_name: String = String(offer.destination.get("name", "?"))
	var dest_desc: String = String(offer.destination.get("descriptor", ""))
	var dest_text: String = ("%s (%s)" % [dest_name, dest_desc]) if dest_desc != "" else dest_name
	vbox.add_child(_line("Destination: %s" % dest_text, 13, TEXT))

	var pay: float = float(offer.rewards.get("credits", 0.0))
	vbox.add_child(_line("Pay: %d cr" % int(pay), 15, PAY_COLOUR))

	var tier: String = String(offer.away_risk.get("tier", ""))
	if tier != "":
		vbox.add_child(_line("Away risk: %s" % tier.to_upper(), 14,
			RISK_COLOURS.get(tier, DIM_TEXT)))
	else:
		vbox.add_child(_line("No away operation filed.", 13, DIM_TEXT))

	vbox.add_child(HSeparator.new())

	var briefing := Label.new()
	briefing.text = offer.briefing
	briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	briefing.custom_minimum_size = Vector2(CARD_WIDTH - 24, 0)
	briefing.size_flags_vertical = Control.SIZE_EXPAND_FILL
	briefing.add_theme_font_size_override("font_size", 12)
	briefing.add_theme_color_override("font_color", TEXT)
	vbox.add_child(briefing)

	var button := Button.new()
	button.text = "RECOMMEND"
	button.custom_minimum_size = Vector2(CARD_WIDTH - 24, 34)
	button.pressed.connect(func(): MissionManager.recommend_offer(offer.id))
	vbox.add_child(button)
	return card


# The dispatch verdict (§6.1's legibility valve): when the captain overrides, say so
# and say why, in place, before the panel yields to the mission briefing.
func _on_mission_selected(mission_id: String, followed: bool, reason: String) -> void:
	if not visible:
		return
	for child in _cards_box.get_children():
		child.queue_free()
	# mission_selected fires before _start_mission, so look the title up in the deck.
	var title: String = mission_id
	var mission: MissionDef = null
	if MissionManager.deck != null:
		mission = MissionManager.deck.missions.get(mission_id) as MissionDef
	if mission != null:
		title = mission.title
	if followed:
		_result_label.text = "Captain: \"Agreed. Setting course.\" — %s" % title
		_result_label.add_theme_color_override("font_color", PAY_COLOUR)
	else:
		_result_label.text = "Captain overrides the recommendation (%s) — taking \"%s\" instead." % [
			_reason_text(reason), title]
		_result_label.add_theme_color_override("font_color", OVERRIDE_COLOUR)
	_countdown_label.text = ""
	_header_label.text = "DISPATCH RESOLVED"
	_result_shown_at = Time.get_ticks_msec() / 1000.0


func _reason_text(reason: String) -> String:
	match reason:
		"low_trust": return "doesn't trust the AI's judgement"
		"captain_prerogative": return "captain's prerogative"
		"window_expired": return "no recommendation given in time"
		_: return reason


func _close() -> void:
	visible = false
	_result_shown_at = -1.0
	_header_label.text = "INCOMING DISPATCH — CONTRACTS ON OFFER"
