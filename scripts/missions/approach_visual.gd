class_name ApproachVisual
extends Node2D

# Placeholder destination art (docs/mission-system-spec.md §8) — planets render as
# tinted concentric circles + an atmosphere ring, ships/stations as a dark angular
# silhouette. Sits in its own CanvasLayer alongside Starfield (see main.gd's
# _setup_approach_visual — same "fixed to the viewport, not the deck" trick as
# Starfield, layered between it and the ship deck's implicit layer 0) so mission
# destination art reads as background, behind rooms/hull, in front of the stars.
#
# Driven entirely by EventBus.time_ticked deltas (never raw _process deltas) so the
# grow-in/recede timing respects TimeManager's pause exactly like everything else in
# the sim — no ticks are emitted while paused, so there's nothing to drive here either.
# _draw() only runs once per destination_sighted (when the palette/silhouette
# changes); every tick after that is a cheap scale/modulate property write, no
# redraw, no per-tick allocation.

const ANCHOR_POS: Vector2 = Vector2(1600.0, 260.0)
const MAX_RADIUS: float = 130.0
const RECEDE_SECONDS: float = 60.0

# descriptor keyword -> palette id (spec §8: "jungle greens, ice blue-whites, desert
# rusts, ocean blues, barren greys, volcanic ember, gas bands, ruined ash"). Checked
# in order against the mission's free-text `destination.descriptor`; first match wins.
const KEYWORD_PALETTE: Array = [
	["jungle", "jungle"], ["ice", "ice"], ["frozen", "ice"], ["snow", "ice"],
	["desert", "desert"], ["dune", "desert"], ["sand", "desert"],
	["ocean", "ocean"], ["water", "ocean"], ["sea", "ocean"],
	["volcan", "volcanic"], ["lava", "volcanic"], ["ember", "volcanic"],
	["gas", "gas"], ["cloud", "gas"],
	["ash", "ash"], ["ruin", "ash"], ["scorch", "ash"], ["burnt", "ash"],
	["barren", "barren"], ["moon", "barren"], ["grey", "barren"], ["gray", "barren"], ["rock", "barren"],
]

const PALETTES: Dictionary = {
	"jungle":   {"core": Color(0.16, 0.42, 0.20), "shade": Color(0.05, 0.16, 0.07, 0.55), "atmo": Color(0.35, 0.80, 0.45, 0.30)},
	"ice":      {"core": Color(0.72, 0.82, 0.90), "shade": Color(0.35, 0.46, 0.58, 0.55), "atmo": Color(0.70, 0.85, 1.00, 0.30)},
	"desert":   {"core": Color(0.62, 0.42, 0.26), "shade": Color(0.32, 0.19, 0.10, 0.55), "atmo": Color(0.85, 0.60, 0.35, 0.25)},
	"ocean":    {"core": Color(0.14, 0.35, 0.62), "shade": Color(0.04, 0.12, 0.28, 0.55), "atmo": Color(0.35, 0.60, 0.95, 0.30)},
	"barren":   {"core": Color(0.48, 0.48, 0.50), "shade": Color(0.20, 0.20, 0.22, 0.55), "atmo": Color(0.60, 0.62, 0.66, 0.18)},
	"volcanic": {"core": Color(0.35, 0.14, 0.08), "shade": Color(0.65, 0.24, 0.06, 0.55), "atmo": Color(0.95, 0.45, 0.15, 0.30)},
	"gas":      {"core": Color(0.55, 0.45, 0.30), "shade": Color(0.40, 0.32, 0.20, 0.55), "atmo": Color(0.80, 0.70, 0.50, 0.28)},
	"ash":      {"core": Color(0.30, 0.28, 0.27), "shade": Color(0.10, 0.09, 0.08, 0.55), "atmo": Color(0.45, 0.40, 0.38, 0.22)},
}

const SHIP_SILHOUETTE: PackedVector2Array = [
	Vector2(-1.0, -0.15), Vector2(-0.55, -0.45), Vector2(0.35, -0.4), Vector2(1.0, -0.05),
	Vector2(0.85, 0.1), Vector2(1.0, 0.25), Vector2(0.3, 0.42), Vector2(-0.6, 0.35),
	Vector2(-0.95, 0.1),
]
const SILHOUETTE_COLOR: Color = Color(0.05, 0.06, 0.08, 1.0)
const SILHOUETTE_EDGE: Color = Color(0.30, 0.34, 0.40, 1.0)

var _kind: String = ""            # "" (hidden) | "planet"-style | "ship" | "station"
var _palette: Dictionary = {}
var _state: String = "hidden"     # hidden | growing | holding | receding
var _state_elapsed: float = 0.0
var _state_duration: float = 300.0
var _silhouette: Polygon2D = null
var _silhouette_edge: Line2D = null


func _ready() -> void:
	position = ANCHOR_POS
	z_index = -500
	scale = Vector2.ZERO
	modulate.a = 0.0
	EventBus.destination_sighted.connect(_on_destination_sighted)
	EventBus.mission_phase_changed.connect(_on_phase_changed)
	EventBus.time_ticked.connect(_on_tick)


func _on_destination_sighted(kind: String, _dest_name: String) -> void:
	var descriptor: String = ""
	var arrival_secs: float = 300.0
	if MissionManager.current_mission != null:
		descriptor = String(MissionManager.current_mission.destination.get("descriptor", ""))
		arrival_secs = float(MissionManager.current_mission.phases.get("arrival", 300.0))

	_kind = kind if kind in ["ship", "station"] else "planet"
	_palette = _resolve_palette(descriptor)
	_build_silhouette()

	_state = "growing"
	_state_elapsed = 0.0
	_state_duration = maxf(arrival_secs, 1.0)
	queue_redraw()


func _on_phase_changed(_mission_id: String, phase: String) -> void:
	if _kind == "":
		return
	match phase:
		"on_station":
			_state = "holding"
			_state_elapsed = 0.0
			scale = Vector2.ONE
			modulate.a = 1.0
		"transit_back":
			_state = "receding"
			_state_elapsed = 0.0
			_state_duration = RECEDE_SECONDS
		"resolution", "transit_out":
			_state = "hidden"
			_kind = ""
			scale = Vector2.ZERO
			modulate.a = 0.0
			_clear_silhouette()
			queue_redraw()


func _on_tick(_elapsed: float, delta: float) -> void:
	if _state == "growing":
		_state_elapsed += delta
		_apply_progress(clampf(_state_elapsed / _state_duration, 0.0, 1.0))
	elif _state == "receding":
		_state_elapsed += delta
		_apply_progress(clampf(1.0 - _state_elapsed / _state_duration, 0.0, 1.0))
		if _state_elapsed >= _state_duration:
			_state = "hidden"
			_kind = ""
			_clear_silhouette()
			queue_redraw()


func _apply_progress(p: float) -> void:
	scale = Vector2.ONE * p
	modulate.a = p


func _resolve_palette(descriptor: String) -> Dictionary:
	var lower: String = descriptor.to_lower()
	for pair in KEYWORD_PALETTE:
		if lower.find(String(pair[0])) != -1:
			return PALETTES[String(pair[1])]
	return PALETTES["barren"]


func _build_silhouette() -> void:
	_clear_silhouette()
	if _kind != "ship" and _kind != "station":
		return
	_silhouette = Polygon2D.new()
	var pts: PackedVector2Array = PackedVector2Array()
	for p in SHIP_SILHOUETTE:
		pts.append(p * MAX_RADIUS)
	_silhouette.polygon = pts
	_silhouette.color = SILHOUETTE_COLOR
	add_child(_silhouette)

	_silhouette_edge = Line2D.new()
	var edge_pts: PackedVector2Array = pts.duplicate()
	edge_pts.append(pts[0])
	_silhouette_edge.points = edge_pts
	_silhouette_edge.width = 2.0
	_silhouette_edge.default_color = SILHOUETTE_EDGE
	add_child(_silhouette_edge)


func _clear_silhouette() -> void:
	if _silhouette != null and is_instance_valid(_silhouette):
		_silhouette.queue_free()
	_silhouette = null
	if _silhouette_edge != null and is_instance_valid(_silhouette_edge):
		_silhouette_edge.queue_free()
	_silhouette_edge = null


func _draw() -> void:
	if _kind != "planet" or _palette.is_empty():
		return
	draw_circle(Vector2.ZERO, MAX_RADIUS * 1.15, _palette.get("atmo", Color(1, 1, 1, 0.2)))
	draw_circle(Vector2.ZERO, MAX_RADIUS, _palette.get("core", Color(0.5, 0.5, 0.5)))
	# Cheap terminator-shading disc, offset toward one edge — no shader needed for a placeholder.
	draw_circle(Vector2(MAX_RADIUS * 0.35, MAX_RADIUS * 0.1), MAX_RADIUS * 0.75, _palette.get("shade", Color(0.3, 0.3, 0.3)))
