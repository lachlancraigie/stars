class_name DeckPlan
extends RefCounted

# Hand-authored visual deck plan for the Class 1 Scout, expressed on the
# isometric grid of the legacy sprite kit (see IsoKit). Logic (ShipGraph,
# rooms, doors) stays in ShipConfig; this file only decides how the deck
# LOOKS: which cells each room's floor covers, walkway tiles between rooms,
# maintenance tubes, door gates, and per-room prop dressing.

# room_id -> floor rect in grid cells (x, y, w, h)
const ROOM_RECTS: Dictionary = {
	"bridge":        Rect2(7, 0, 5, 4),
	"corridor_main": Rect2(8, 4, 3, 7),
	"medbay":        Rect2(2, 5, 4, 4),
	"quarters":      Rect2(13, 5, 4, 4),
	"engineering":   Rect2(2, 10, 5, 4),
	"life_support":  Rect2(8, 11, 3, 3),
	"cargo":         Rect2(12, 10, 5, 4),
}

# Subtle per-function floor tinting so zones read at a glance without
# breaking the kit's unified palette.
const FLOOR_TINTS: Dictionary = {
	"bridge":       Color(0.85, 0.90, 1.00),
	"corridor":     Color(1.00, 1.00, 1.00),
	"medbay":       Color(0.88, 1.00, 0.94),
	"quarters":     Color(0.95, 0.90, 1.00),
	"reactor":      Color(1.00, 0.90, 0.82),
	"life_support": Color(0.86, 0.98, 0.92),
	"cargo":        Color(1.00, 0.96, 0.84),
}

# Open floor tile used everywhere; walkways use the same tile so crew read
# as walking on connected decking. Maintenance tubes render as pipes.
const FLOOR_TILE: String = "platform_center_SE"
const WALKWAY_TILE: String = "platform_center_SE"
const TUBE_TILE: String = "pipe_straight_SE"

# Walkway cells connecting room islands (absolute grid cells).
const WALKWAYS: Array = [
	Vector2(6, 6), Vector2(7, 6),      # medbay <-> corridor
	Vector2(11, 6), Vector2(12, 6),    # quarters <-> corridor
	Vector2(7, 10),                    # engineering <-> corridor
	Vector2(11, 10),                   # cargo <-> corridor
]

# Maintenance tube cells (crew with access crawl these; drawn as pipes).
const TUBES: Array = [
	Vector2(7, 12),                    # engineering <-> life_support
	Vector2(11, 12),                   # life_support <-> cargo
]

# door_id -> grid cell for its gate sprite (fractional = on a cell boundary).
const DOOR_CELLS: Dictionary = {
	"door_bridge":      Vector2(9, 3.5),
	"door_engineering": Vector2(7, 10),
	"door_cargo":       Vector2(11, 10),
}
const DOOR_SPRITE: String = "gate_simple_SE"

# room_id -> array of [rect-relative cell, kit sprite name].
const PROPS: Dictionary = {
	"bridge": [
		[Vector2(1, 0), "desk_computer_SE"],
		[Vector2(2, 0), "desk_computerScreen_SE"],
		[Vector2(3, 0), "desk_computer_SE"],
		[Vector2(0, 1), "desk_computerCorner_SE"],
		[Vector2(4, 1), "desk_computerCorner_SW"],
		[Vector2(2, 1.6), "desk_chairArms_NW"],
	],
	"medbay": [
		[Vector2(0, 0), "desk_computerScreen_SE"],
		[Vector2(3, 0), "machine_wireless_SW"],
		[Vector2(1, 1), "desk_chair_SE"],
		[Vector2(0, 3), "barrels_NE"],
		[Vector2(3, 3), "machine_barrel_NW"],
	],
	"quarters": [
		[Vector2(0, 0), "desk_computerCorner_SE"],
		[Vector2(3, 0), "barrel_SW"],
		[Vector2(1, 1), "desk_chairArms_SE"],
		[Vector2(2, 2), "desk_chairArms_SW"],
		[Vector2(3, 3), "desk_chairStool_NW"],
	],
	"engineering": [
		[Vector2(0, 0), "machine_generator_SE"],
		[Vector2(4, 0), "machine_generator_SW"],
		[Vector2(2, 1.5), "machine_generatorLarge_SE"],
		[Vector2(0, 3), "pipe_straight_SE"],
		[Vector2(4, 3), "machine_barrelLarge_NW"],
	],
	"life_support": [
		[Vector2(1, 0), "machine_wirelessCable_SE"],
		[Vector2(0, 2), "machine_barrel_NE"],
		[Vector2(2, 2), "pipe_ring_NW"],
	],
	"cargo": [
		[Vector2(0, 0), "barrels_SE"],
		[Vector2(1, 0), "barrel_SE"],
		[Vector2(4, 0), "machine_barrelLarge_SW"],
		[Vector2(2, 1.5), "barrels_rail_SE"],
		[Vector2(0, 3), "barrels_NE"],
		[Vector2(4, 3), "barrels_NW"],
		[Vector2(3, 2), "barrel_SE"],
	],
	"corridor_main": [],
}


# Waypoint cells crew pass through when hopping between two connected rooms,
# so they visibly cross the walkway/gate instead of cutting over open space.
# Listed in from|to order of the key; reversed automatically for the return trip.
const HOP_WAYPOINTS: Dictionary = {
	"bridge|corridor_main":       [Vector2(9, 3), Vector2(9, 4.5)],
	"medbay|corridor_main":       [Vector2(5.5, 6), Vector2(8.5, 6)],
	"quarters|corridor_main":     [Vector2(13, 6), Vector2(10.5, 6)],
	"engineering|corridor_main":  [Vector2(6, 10), Vector2(8, 10)],
	"cargo|corridor_main":        [Vector2(12, 10), Vector2(10, 10)],
	"life_support|corridor_main": [Vector2(9, 11.5), Vector2(9, 10)],
	"engineering|life_support":   [Vector2(6, 12), Vector2(8, 12)],
	"life_support|cargo":         [Vector2(10, 12), Vector2(12, 12)],
}


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
	var cell := Vector2(
		randf_range(rect.position.x + inset, rect.position.x + rect.size.x - 1.0 - inset),
		randf_range(rect.position.y + inset, rect.position.y + rect.size.y - 1.0 - inset)
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
	# Pad for tile half-extents plus prop/label headroom above.
	min_p += Vector2(-IsoKit.TILE_HALF_W, -IsoKit.TILE_HALF_H - 110.0)
	max_p += Vector2(IsoKit.TILE_HALF_W, IsoKit.TILE_HALF_H + 40.0)
	return Rect2(min_p, max_p - min_p)
