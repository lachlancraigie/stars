extends CanvasLayer

# Voyage epilogue (docs/loop-direction.md §6.2). Fires on EventBus.voyage_completed —
# the charter finale resolved with the ship alive. Shows the run's shape: outcome, legs,
# credits, mission record, the survivors with the histories they accumulated (the
# veterancy payoff), and the memorial roll. MissionManager pauses time before emitting;
# this is a terminal screen — restart-in-place is a separate backlog task (autoload
# state reset), so v1 ends the run here.

const ACCENT: Color = Color(0.20, 0.80, 0.95)
const TEXT: Color = Color(0.85, 0.87, 0.92)
const DIM_TEXT: Color = Color(0.55, 0.60, 0.68)
const GOOD: Color = Color(0.35, 0.95, 0.55)
const PARTIAL: Color = Color(0.9, 0.7, 0.1)
const BAD: Color = Color(0.95, 0.30, 0.25)
const FALLEN_COLOUR: Color = Color(0.75, 0.55, 0.55)


func _ready() -> void:
	layer = 15
	visible = false
	EventBus.voyage_completed.connect(_on_voyage_completed)


func _on_voyage_completed(summary: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.85)
	dim.size = Vector2(1920, 1080)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var vbox := VBoxContainer.new()
	vbox.position = Vector2(460, 90)
	vbox.custom_minimum_size = Vector2(1000, 900)
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	var outcome: String = String(summary.get("final_outcome", "mission_partial"))
	var title := _line("VOYAGE COMPLETE — %s" % String(summary.get("destination", "")).to_upper(), 38, _outcome_colour(outcome))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var subtitle := _line(_outcome_line(outcome), 18, TEXT)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	vbox.add_child(HSeparator.new())

	var missions: Array = summary.get("missions", [])
	var success_count: int = 0
	for entry in missions:
		if String((entry as Dictionary).get("outcome", "")) == "mission_success":
			success_count += 1
	vbox.add_child(_line("%d legs — %d contracts flown, %d succeeded — %d credits banked" % [
		int(summary.get("legs", 0)), missions.size(), success_count,
		int(summary.get("credits", 0.0))], 16, TEXT))
	vbox.add_child(HSeparator.new())

	var survivors: Array = summary.get("survivors", [])
	vbox.add_child(_line("CAME HOME (%d)" % survivors.size(), 16, ACCENT))
	for s in survivors:
		var sd: Dictionary = s
		var trait_names: Array = []
		for tid in (sd.get("traits", []) as Array):
			trait_names.append(Traits.display_name(String(tid)))
		var trait_text: String = " — " + ", ".join(trait_names) if not trait_names.is_empty() else ""
		vbox.add_child(_line("  %s (%s, %d legs)%s" % [
			String(sd.get("name", "?")), String(sd.get("role", "")).capitalize(),
			int(sd.get("legs_served", 0)), trait_text], 14, TEXT))

	var fallen: Array = summary.get("fallen", [])
	if not fallen.is_empty():
		vbox.add_child(HSeparator.new())
		vbox.add_child(_line("DID NOT (%d)" % fallen.size(), 16, FALLEN_COLOUR))
		for f in fallen:
			var fd: Dictionary = f
			vbox.add_child(_line("  %s — %s" % [
				String(fd.get("name", fd.get("crew_name", "?"))),
				String(fd.get("cause", "unknown")).capitalize().replace("_", " ")], 14, FALLEN_COLOUR))

	vbox.add_child(HSeparator.new())
	var footer := _line("The charter is closed. End of voyage.", 13, DIM_TEXT)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(footer)

	visible = true


func _line(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.custom_minimum_size = Vector2(1000, 0)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _outcome_colour(outcome: String) -> Color:
	match outcome:
		"mission_success": return GOOD
		"mission_partial": return PARTIAL
		_: return BAD


func _outcome_line(outcome: String) -> String:
	match outcome:
		"mission_success":
			return "The final approach was clean. The company logs the charter as fulfilled."
		"mission_partial":
			return "The ship made it in. The paperwork will be less kind."
		_:
			return "The ship made it in — barely. The inquiry starts tomorrow."
