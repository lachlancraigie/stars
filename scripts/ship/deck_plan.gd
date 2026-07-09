class_name DeckPlan
extends RefCounted

# Visual deck plan for the current ship, expressed on the isometric grid of the
# legacy sprite kit (see IsoKit). Logic (ShipGraph, rooms, doors) stays in
# ShipConfig; this file only decides how the deck LOOKS: which cells each room's
# floor covers, walkway tiles between rooms, maintenance tubes, door gates,
# per-room prop dressing, wall segments, and the hull silhouette.
#
# Historically this was hand-authored const data for the Class-1 Scout. It is now
# a data CONTAINER filled by scripts/procedural/ship_layout_gen.gd at scenario
# start via load_plan() — every other system (RoomBase, ShipLayoutBuilder,
# CrewMemberNode) keeps calling the same static accessors below unchanged, so the
# generator is a drop-in data source rather than a rewrite of every consumer.

# room_id -> floor rect in grid cells (x, y, w, h)
static var ROOM_RECTS: Dictionary = {}

# room TYPE (room_function) -> floor tint / floor tile choice.
static var FLOOR_TINTS: Dictionary = {}
static var FLOOR_TILE_BY_TYPE: Dictionary = {}

# Fallback tile for anything load_plan() didn't populate (walkways, tubes, or a
# room type with no per-type entry yet).
const FLOOR_TILE: String = "platform_center_SE"
const WALKWAY_TILE: String = "platform_center_SE"
const TUBE_TILE: String = "pipe_straight_SE"

# Walkway cells connecting room islands / maintenance tube cells (absolute grid cells).
static var WALKWAYS: Array = []
static var TUBES: Array = []

# door_id -> grid cell for its gate sprite (fractional = on a cell boundary).
static var DOOR_CELLS: Dictionary = {}
const DOOR_SPRITE: String = "gate_simple_SE"

# room_id -> array of [rect-relative cell, kit sprite name].
static var PROPS: Dictionary = {}

# "from_room|to_room" -> array of deck-space waypoint cells crossed while hopping
# between two connected rooms (reversed automatically for the return trip).
static var HOP_WAYPOINTS: Dictionary = {}

# Wall segments for the whole deck: [{cell:Vector2, sprite:String, alpha:float}].
static var WALL_SEGMENTS: Array = []

# Hull silhouette polygon in deck-pixel space (already projected via IsoKit).
static var HULL_POLYGON: PackedVector2Array = PackedVector2Array()


# Replaces the whole deck plan with a freshly generated one. Called once by
# ShipLayoutGen.generate() before ShipLayoutBuilder.build() runs.
static func load_plan(plan: Dictionary) -> void:
	ROOM_RECTS = plan.get("room_rects", {})
	FLOOR_TINTS = plan.get("floor_tints", {})
	FLOOR_TILE_BY_TYPE = plan.get("floor_tile_by_type", {})
	WALKWAYS = plan.get("walkways", [])
	TUBES = plan.get("tubes", [])
	DOOR_CELLS = plan.get("door_cells", {})
	PROPS = plan.get("props", {})
	HOP_WAYPOINTS = plan.get("hop_waypoints", {})
	WALL_SEGMENTS = plan.get("wall_segments", [])
	HULL_POLYGON = plan.get("hull_polygon", PackedVector2Array())


static func floor_tile_for(room_type: String) -> String:
	return FLOOR_TILE_BY_TYPE.get(room_type, FLOOR_TILE)


# Deck-pixel waypoints for walking from one room to an adjacent one.
static func hop_waypoints(from_room: String, to_room: String) -> Array:
	var cells: Array = []
	if HOP_WAYPOINTS.has(from_room + "|" + to_room):
		cells = HOP_WAYPOINTS[from_room + "|" + to_room]
	elif HOP_WAYPOINTS.has(to_room + "|" + from_room):
		cells = HOP_WAYPOINTS[to_room + "|" + from_room].duplicate()
		cells.reverse()
	var points: Array = []
	for cell: Vector2 in cells:
		points.append(IsoKit.cell_to_deck(cell))
	return points


static func room_rect(room_id: String) -> Rect2:
	return ROOM_RECTS.get(room_id, Rect2())


static func has_room(room_id: String) -> bool:
	return ROOM_RECTS.has(room_id)


# Room centre in deck pixels (position for the RoomBase node).
static func room_center(room_id: String) -> Vector2:
	var rect: Rect2 = room_rect(room_id)
	var center_cell: Vector2 = rect.position + (rect.size - Vector2.ONE) * 0.5
	return IsoKit.cell_to_deck(center_cell)


# Random standing spot inside a room, inset from the floor edge, in deck px.
static func random_point(room_id: String) -> Vector2:
	var rect: Rect2 = room_rect(room_id)
	if rect.size == Vector2.ZERO:
		return Vector2.ZERO
	var inset: float = 0.65
	var w: float = maxf(rect.size.x - 1.0 - 2.0 * inset, 0.0)
	var h: float = maxf(rect.size.y - 1.0 - 2.0 * inset, 0.0)
	var cell := Vector2(
		rect.position.x + inset + randf() * w,
		rect.position.y + inset + randf() * h
	)
	return IsoKit.cell_to_deck(cell)


# Bounding box of the whole deck in deck pixels (for fitting to the viewport).
static func deck_bounds() -> Rect2:
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for room_id: String in ROOM_RECTS:
		var rect: Rect2 = ROOM_RECTS[room_id]
		for corner: Vector2 in [
			rect.position,
			rect.position + Vector2(rect.size.x - 1, 0),
			rect.position + Vector2(0, rect.size.y - 1),
			rect.position + rect.size - Vector2.ONE,
		]:
			var p: Vector2 = IsoKit.cell_to_deck(corner)
			min_p = min_p.min(p)
			max_p = max_p.max(p)
	if min_p.x == INF:
		return Rect2()
	# Pad for tile half-extents plus prop/label headroom above.
	min_p += Vector2(-IsoKit.TILE_HALF_W, -IsoKit.TILE_HALF_H - 110.0)
	max_p += Vector2(IsoKit.TILE_HALF_W, IsoKit.TILE_HALF_H + 40.0)
	return Rect2(min_p, max_p - min_p)
