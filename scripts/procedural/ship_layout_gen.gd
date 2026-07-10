class_name ShipLayoutGen
extends RefCounted

# Procedural ship layout generator. Given a seed + ship-class id, produces BOTH:
#   1. a ShipConfig (rooms + connections) for ShipGraph/pathfinding/Door logic, and
#   2. the full visual deck-plan dataset (room rects, floor styling, props, walkways,
#      tubes, door cells, hop waypoints, wall segments, hull silhouette) — loaded
#      straight into DeckPlan (see scripts/ship/deck_plan.gd) so RoomBase,
#      ShipLayoutBuilder and CrewMemberNode keep working unchanged.
#
# See CLAUDE.md session note (2026-07-09) for the human-readable ruleset writeup.
# Only one class is implemented: "freighter" (classic long-haul cargo/exploration
# vessel). CLASS_RULESETS is a Dictionary keyed by class id so more classes can be
# added later without touching the algorithm below (data-driven room counts/sizes).
#
# THE RULESET (freighter)
# ------------------------
# - Fore-to-aft spine: a chain of corridor-type room segments (corridor_1, corridor_2, …)
#   running the length of the ship. Bridge caps the fore end, engine_room caps the aft
#   end, both directly abutting the spine (no gap) through a locking door.
# - Every "flank row" along the spine offers a west slot and an east slot for a room
#   that flanks the corridor (gap of 2 cells, bridged by walkway decking). Rooms are
#   handed out to slots in a fixed thematic order so the layout always reads sensibly:
#     ai_core (first row, right off the bridge) -> mess -> quarters (clustered next to
#     mess) -> cargo/medbay (medbay lands at the structural middle of the flank
#     sequence; "reasonably central") -> more cargo -> airlock(s) (outermost rows).
# - life_support gets its own inline segment directly ahead of engine_room ("near
#   engineering"), abutting both with no gap.
# - Doors (lockable, AI-overridable) exist on: bridge, engine_room, every cargo hold,
#   ai_core, every airlock — the ship's sealable/hazardous spaces. medbay, mess,
#   quarters, life_support and corridor-corridor seams stay open (matches the existing
#   Quarantine scenario's assumption that medbay containment is behavioural, not a
#   physical lock).
# - Maintenance tubes (secondary, maintenance-only graph edges, weight-penalised but
#   door-independent): life_support<->engine_room, ai_core<->life_support, and a
#   crawlway chaining consecutive cargo holds. These let a directive-driven maintenance
#   route bypass a locked door later (ShipGraph.find_path(..., allow_maintenance=true));
#   normal crew wandering never uses them (CrewMemberNode calls find_path with the
#   default allow_maintenance=false, same as the original hand-authored layout).
# - Room counts randomised per seed within: quarters 1-2, cargo 1-3, airlock 1-2.
#   Room sizes randomised per seed within per-type cell ranges (ROOM_SIZE_RANGES).
# - Exactly one ai_core, bridge, engine_room, medbay, mess, life_support; at least one
#   quarters, cargo, airlock — satisfying the shared room-type contract with
#   docs/dialogue_spec.md's location list.


# --- Grid layout constants (cells) ---

const CORRIDOR_X0: int = 8
const CORRIDOR_WIDTH: int = 3
const FLANK_GAP: int = 2          # cells between a flank room's inner edge and the corridor
const CORRIDOR_MID_X: float = CORRIDOR_X0 + CORRIDOR_WIDTH / 2.0

const NOSE_LEN: float = 2.6       # cells the hull tapers forward past the bridge
const AFT_BLOCK_LEN: float = 2.2  # cells the hull extends aft past the engine room
const HULL_MARGIN: float = 1.3    # cells the hull is inflated past each room row
const HULL_AFT_MARGIN: float = 2.4

const DOORED_TYPES: Array[String] = ["bridge", "engine_room", "cargo", "ai_core", "airlock"]

const ROOM_SIZE_RANGES: Dictionary = {
	"bridge":       {"w": [4, 6], "h": [3, 4]},
	"engine_room":  {"w": [5, 6], "h": [4, 4]},
	"ai_core":      {"w": [3, 4], "h": [3, 4]},
	"medbay":       {"w": [3, 4], "h": [3, 4]},
	"mess":         {"w": [4, 5], "h": [3, 4]},
	"quarters":     {"w": [3, 4], "h": [3, 4]},
	"cargo":        {"w": [4, 5], "h": [3, 4]},
	"life_support": {"w": [3, 4], "h": [3, 3]},
	"airlock":      {"w": [2, 3], "h": [2, 3]},
}

const FLOOR_TINTS_BY_TYPE: Dictionary = {
	"bridge":       Color(0.85, 0.90, 1.00),
	"corridor":     Color(1.00, 1.00, 1.00),
	"medbay":       Color(0.88, 1.00, 0.94),
	"quarters":     Color(0.95, 0.90, 1.00),
	"engine_room":  Color(1.00, 0.90, 0.82),
	"life_support": Color(0.86, 0.98, 0.92),
	"cargo":        Color(1.00, 0.96, 0.84),
	"mess":         Color(1.00, 0.94, 0.80),
	"ai_core":      Color(0.80, 0.92, 1.00),
	"airlock":      Color(0.75, 0.80, 0.85),
}

const FLOOR_TILE_BY_TYPE: Dictionary = {
	"bridge":       "tile_bridge",
	"corridor":     "tile_corridor",
	"medbay":       "tile_medbay",
	"mess":         "tile_mess",
	"quarters":     "tile_quarters",
	"cargo":        "tile_cargo",
	"life_support": "tile_life_support",
	"ai_core":      "tile_ai_core",
	"engine_room":  "tile_engine_room",
	"airlock":      "tile_airlock",
}

# Per-type prop pools (Kenney Space Kit isometric has no literal "table" or "bunk"
# sprite; mess/quarters substitute chairs + barrels/desks the same way the original
# hand-authored deck plan did).
const PROP_POOLS: Dictionary = {
	"bridge":       ["desk_computer_SE", "desk_computerScreen_SE", "desk_computerCorner_SE",
		"desk_computerCorner_SW", "desk_chairArms_NW", "desk_chair_SE"],
	"medbay":       ["desk_computerScreen_SE", "machine_wireless_SW", "desk_chair_SE",
		"barrels_NE", "machine_barrel_NW"],
	"mess":         ["barrels_SE", "desk_chairArms_SE", "desk_chairStool_NW",
		"desk_chairArms_SW", "barrel_SE"],
	"quarters":     ["desk_computerCorner_SE", "barrel_SW", "desk_chairArms_SE",
		"desk_chairArms_SW", "desk_chairStool_NW"],
	"cargo":        ["barrels_SE", "barrel_SE", "machine_barrelLarge_SW", "barrels_rail_SE",
		"barrels_NE", "barrels_NW", "barrel_SW"],
	"engine_room":  ["machine_generator_SE", "machine_generator_SW", "machine_generatorLarge_SE",
		"pipe_straight_SE", "machine_barrelLarge_NW", "pipe_ring_NW", "pipe_cross_SE"],
	"life_support": ["machine_wirelessCable_SE", "machine_barrel_NE", "pipe_ring_NW",
		"pipe_ringHigh_SE", "pipe_supportHigh_SE"],
	"ai_core":      ["machine_wireless_SE", "desk_computerScreen_SE", "desk_computerScreen_SW",
		"machine_wirelessCable_SE", "pipe_ring_SE"],
	"airlock":      ["pipe_entrance_SE", "structure_closed_SE"],
	"corridor":     [],
}
# "Most computer-looking" prop per type — placed first, at a prominent back-wall cell.
const CENTERPIECE_BY_TYPE: Dictionary = {
	"ai_core": "machine_wireless_SE",
	"bridge":  "desk_computerScreen_SE",
}

# room-type -> [wall_sprite_directions] indexed by grid edge (N/S/E/W); see the
# comment on _emit_wall_edges for the screen-facing rationale (SE/SW = front/near
# camera = more transparent; NE/NW = back = less transparent).
const WALL_SPRITE_FOR_EDGE: Dictionary = {
	"N": "corridor_wall_NE", "S": "corridor_wall_SW",
	"E": "corridor_wall_SE", "W": "corridor_wall_NW",
}
const WALL_ALPHA_FOR_EDGE: Dictionary = {
	"N": 0.62, "S": 0.32, "E": 0.32, "W": 0.62,
}

const FREIGHTER_RULESET: Dictionary = {
	"ship_name": "Long-Haul Freighter",
	"min_crew": 3,
	"max_crew": 6,
	"starting_resources": {
		"oxygen": 1.0, "power": 1.0, "food": 0.9, "water": 0.9,
		"fuel": 0.85, "spare_parts": 0.7, "medicine": 0.5,
	},
}
const CLASS_RULESETS: Dictionary = {
	"freighter": FREIGHTER_RULESET,
}


# --- Public entry point ---

# Generates a full ship: builds the ShipConfig, loads DeckPlan with the matching
# visual dataset, and returns the ShipConfig for ShipLayoutBuilder.build().
static func generate(seed_value: int, ship_class_id: String = "freighter") -> ShipConfig:
	var ruleset: Dictionary = CLASS_RULESETS.get(ship_class_id, FREIGHTER_RULESET)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var build: Dictionary = _layout_rooms(rng)
	# build: {"rooms": {id -> {"type","rect"}}, "connections": [...], "row_meta": [...],
	#         "connect_edges": {id -> [edges]}, "gap_midpoints": {id -> {"row_y","mid_y"}}}

	_add_maintenance_tubes(build)

	var plan: Dictionary = _build_deck_plan(rng, build)
	DeckPlan.load_plan(plan)

	return _build_ship_config(ship_class_id, ruleset, build)


# --- Room + connection layout ---

static func _fill_order(rng: RandomNumberGenerator, type_totals: Dictionary) -> Array:
	var n_quarters: int = rng.randi_range(1, 2)
	var n_cargo: int = rng.randi_range(1, 3)
	var n_airlock: int = rng.randi_range(1, 2)
	type_totals["quarters"] = n_quarters
	type_totals["cargo"] = n_cargo
	type_totals["airlock"] = n_airlock

	var order: Array = ["ai_core", "mess"]
	for i in n_quarters:
		order.append("quarters")

	var cargo_first: int = int(ceil(n_cargo / 2.0))
	for i in cargo_first:
		order.append("cargo")
	order.append("medbay")
	for i in n_cargo - cargo_first:
		order.append("cargo")

	for i in n_airlock:
		order.append("airlock")
	return order


static func _layout_rooms(rng: RandomNumberGenerator) -> Dictionary:
	var rooms: Dictionary = {}          # room_id -> {"type": String, "rect": Rect2}
	var connections: Array = []         # [{"a","b","weight","door","maint"}]
	var row_meta: Array = []            # [{"min_x","max_x","y0","y1"}] fore -> aft
	var connect_edges: Dictionary = {}  # room_id -> Array[String] edges to skip for props/walls
	var gap_info: Dictionary = {}       # room_id -> {"mid_y": int} for flank rooms (walkway/hop calc)

	var type_totals: Dictionary = {}
	var fill_order: Array = _fill_order(rng, type_totals)
	var type_counters: Dictionary = {}

	var y_cursor: int = 0

	# --- Bridge (fore cap) ---
	var bw: int = rng.randi_range(ROOM_SIZE_RANGES["bridge"]["w"][0], ROOM_SIZE_RANGES["bridge"]["w"][1])
	var bh: int = rng.randi_range(ROOM_SIZE_RANGES["bridge"]["h"][0], ROOM_SIZE_RANGES["bridge"]["h"][1])
	var bx0: int = int(round(CORRIDOR_MID_X - bw / 2.0))
	var bridge_rect := Rect2(bx0, y_cursor, bw, bh)
	rooms["bridge"] = {"type": "bridge", "rect": bridge_rect}
	connect_edges["bridge"] = ["S"]
	row_meta.append({"min_x": bx0, "max_x": bx0 + bw, "y0": y_cursor, "y1": y_cursor + bh})
	y_cursor += bh

	var prev_corridor_id: String = ""
	var corridor_index: int = 0

	var i: int = 0
	while i < fill_order.size():
		var west_type: String = fill_order[i]
		var east_type: String = fill_order[i + 1] if i + 1 < fill_order.size() else ""
		i += 2
		corridor_index += 1
		var corridor_id: String = "corridor_%d" % corridor_index

		var west_id: String = ""
		var west_rect := Rect2()
		var west_h: int = 0
		if west_type != "":
			west_id = _next_id(type_counters, west_type, type_totals.get(west_type, 1))
			var rw: int = rng.randi_range(ROOM_SIZE_RANGES[west_type]["w"][0], ROOM_SIZE_RANGES[west_type]["w"][1])
			var rh: int = rng.randi_range(ROOM_SIZE_RANGES[west_type]["h"][0], ROOM_SIZE_RANGES[west_type]["h"][1])
			west_rect = Rect2(CORRIDOR_X0 - FLANK_GAP - rw, y_cursor, rw, rh)
			rooms[west_id] = {"type": west_type, "rect": west_rect}
			connect_edges[west_id] = ["E"]
			west_h = rh

		var east_id: String = ""
		var east_rect := Rect2()
		var east_h: int = 0
		if east_type != "":
			east_id = _next_id(type_counters, east_type, type_totals.get(east_type, 1))
			var rw2: int = rng.randi_range(ROOM_SIZE_RANGES[east_type]["w"][0], ROOM_SIZE_RANGES[east_type]["w"][1])
			var rh2: int = rng.randi_range(ROOM_SIZE_RANGES[east_type]["h"][0], ROOM_SIZE_RANGES[east_type]["h"][1])
			east_rect = Rect2(CORRIDOR_X0 + CORRIDOR_WIDTH + FLANK_GAP, y_cursor, rw2, rh2)
			rooms[east_id] = {"type": east_type, "rect": east_rect}
			connect_edges[east_id] = ["W"]
			east_h = rh2

		var row_h: int = max(max(west_h, east_h), 3)
		var corridor_rect := Rect2(CORRIDOR_X0, y_cursor, CORRIDOR_WIDTH, row_h)
		rooms[corridor_id] = {"type": "corridor", "rect": corridor_rect}

		var row_min_x: float = corridor_rect.position.x if west_id == "" else west_rect.position.x
		var row_max_x: float = (corridor_rect.position.x + corridor_rect.size.x) if east_id == "" \
			else (east_rect.position.x + east_rect.size.x)
		row_meta.append({"min_x": row_min_x, "max_x": row_max_x, "y0": y_cursor, "y1": y_cursor + row_h})

		# Spine connection (open, no door).
		if prev_corridor_id == "":
			connections.append({"a": "bridge", "b": corridor_id, "weight": 1.0, "door": "door_bridge", "maint": false})
		else:
			connections.append({"a": prev_corridor_id, "b": corridor_id, "weight": 1.0, "door": "", "maint": false})

		if west_id != "":
			var mid_y_w: int = y_cursor + int(min(west_h, row_h) / 2.0)
			gap_info[west_id] = {"mid_y": mid_y_w}
			var doored_w: bool = west_type in DOORED_TYPES
			connections.append({"a": corridor_id, "b": west_id, "weight": 1.0,
				"door": ("door_%s" % west_id) if doored_w else "", "maint": false})
		if east_id != "":
			var mid_y_e: int = y_cursor + int(min(east_h, row_h) / 2.0)
			gap_info[east_id] = {"mid_y": mid_y_e}
			var doored_e: bool = east_type in DOORED_TYPES
			connections.append({"a": corridor_id, "b": east_id, "weight": 1.0,
				"door": ("door_%s" % east_id) if doored_e else "", "maint": false})

		prev_corridor_id = corridor_id
		y_cursor += row_h

	# --- life_support (inline, ahead of engine_room) ---
	var lsw: int = rng.randi_range(ROOM_SIZE_RANGES["life_support"]["w"][0], ROOM_SIZE_RANGES["life_support"]["w"][1])
	var lsh: int = rng.randi_range(ROOM_SIZE_RANGES["life_support"]["h"][0], ROOM_SIZE_RANGES["life_support"]["h"][1])
	var lsx0: int = int(round(CORRIDOR_MID_X - lsw / 2.0))
	var ls_rect := Rect2(lsx0, y_cursor, lsw, lsh)
	rooms["life_support"] = {"type": "life_support", "rect": ls_rect}
	connect_edges["life_support"] = ["N", "S"]
	row_meta.append({"min_x": lsx0, "max_x": lsx0 + lsw, "y0": y_cursor, "y1": y_cursor + lsh})
	connections.append({"a": prev_corridor_id, "b": "life_support", "weight": 1.0, "door": "", "maint": false})
	y_cursor += lsh

	# --- engine_room (aft cap) ---
	var ew: int = rng.randi_range(ROOM_SIZE_RANGES["engine_room"]["w"][0], ROOM_SIZE_RANGES["engine_room"]["w"][1])
	var eh: int = rng.randi_range(ROOM_SIZE_RANGES["engine_room"]["h"][0], ROOM_SIZE_RANGES["engine_room"]["h"][1])
	var ex0: int = int(round(CORRIDOR_MID_X - ew / 2.0))
	var engine_rect := Rect2(ex0, y_cursor, ew, eh)
	rooms["engine_room"] = {"type": "engine_room", "rect": engine_rect}
	connect_edges["engine_room"] = ["N"]
	row_meta.append({"min_x": ex0, "max_x": ex0 + ew, "y0": y_cursor, "y1": y_cursor + eh})
	connections.append({"a": "life_support", "b": "engine_room", "weight": 1.0, "door": "door_engine_room", "maint": false})

	return {
		"rooms": rooms,
		"connections": connections,
		"row_meta": row_meta,
		"connect_edges": connect_edges,
		"gap_info": gap_info,
	}


static func _next_id(counters: Dictionary, type: String, total: int) -> String:
	if total <= 1:
		return type
	counters[type] = counters.get(type, 0) + 1
	return "%s_%d" % [type, counters[type]]


static func _add_maintenance_tubes(build: Dictionary) -> void:
	var rooms: Dictionary = build["rooms"]
	var connections: Array = build["connections"]

	connections.append({"a": "life_support", "b": "engine_room", "weight": 0.6, "door": "", "maint": true})
	if rooms.has("ai_core"):
		connections.append({"a": "ai_core", "b": "life_support", "weight": 1.2, "door": "", "maint": true})

	var cargo_ids: Array = []
	for room_id in rooms:
		if rooms[room_id]["type"] == "cargo":
			cargo_ids.append(room_id)
	cargo_ids.sort()
	for i in range(cargo_ids.size() - 1):
		connections.append({"a": cargo_ids[i], "b": cargo_ids[i + 1], "weight": 0.8, "door": "", "maint": true})


# --- ShipConfig assembly ---

static func _build_ship_config(ship_class_id: String, ruleset: Dictionary, build: Dictionary) -> ShipConfig:
	var config := ShipConfig.new()
	config.ship_class = 1
	config.ship_name = ruleset.get("ship_name", "Freighter")
	config.min_crew = ruleset.get("min_crew", 3)
	config.max_crew = ruleset.get("max_crew", 6)
	config.starting_resources = (ruleset.get("starting_resources", {}) as Dictionary).duplicate()

	var rooms: Dictionary = build["rooms"]
	for room_id in rooms:
		var rd := RoomDefinition.new()
		rd.room_id = room_id
		rd.room_function = rooms[room_id]["type"]
		rd.access_level = 1 if rooms[room_id]["type"] in ["bridge", "ai_core"] else 0
		rd.integrity = 1.0
		rd.layout_position = Vector2.ZERO  # DeckPlan.room_center() is authoritative for placement
		config.rooms.append(rd)

	for c in build["connections"]:
		var cd := ConnectionDefinition.new()
		cd.room_a_id = c["a"]
		cd.room_b_id = c["b"]
		cd.weight = c["weight"]
		cd.door_id = c["door"]
		cd.maintenance_only = c["maint"]
		config.connections.append(cd)

	return config


# --- Deck plan (visual) assembly ---

static func _build_deck_plan(rng: RandomNumberGenerator, build: Dictionary) -> Dictionary:
	var rooms: Dictionary = build["rooms"]
	var connect_edges: Dictionary = build["connect_edges"]
	var gap_info: Dictionary = build["gap_info"]

	var room_rects: Dictionary = {}
	var props: Dictionary = {}
	var walkways: Array = []
	var tubes: Array = []
	var door_cells: Dictionary = {}
	var hop_waypoints: Dictionary = {}
	var wall_segments: Array = []

	for room_id in rooms:
		var type: String = rooms[room_id]["type"]
		var rect: Rect2 = rooms[room_id]["rect"]
		room_rects[room_id] = rect
		if type == "corridor":
			props[room_id] = []
			continue
		var skip_edges: Array = connect_edges.get(room_id, [])
		props[room_id] = _generate_props(rng, type, rect, skip_edges)
		wall_segments.append_array(_emit_wall_edges(rect, skip_edges))

	# Connections -> walkways / door cells / tube cells / hop waypoints.
	for c in build["connections"]:
		var a_id: String = c["a"]
		var b_id: String = c["b"]
		var door_id: String = c["door"]
		var maint: bool = c["maint"]
		if not (rooms.has(a_id) and rooms.has(b_id)):
			continue
		var a_rect: Rect2 = rooms[a_id]["rect"]
		var b_rect: Rect2 = rooms[b_id]["rect"]
		var vertical: bool = _shares_vertical_boundary(a_rect, b_rect)

		if maint:
			# Maintenance tubes get a couple of pipe tiles between the two rooms'
			# facing edges for visual flavour; not used by default crew pathing.
			tubes.append_array(_tube_cells(a_rect, b_rect))
			continue

		if vertical:
			var boundary_y: float = b_rect.position.y  # a sits above b (fore -> aft)
			if door_id != "":
				door_cells[door_id] = Vector2(CORRIDOR_MID_X, boundary_y - 0.5)
			hop_waypoints["%s|%s" % [a_id, b_id]] = [
				Vector2(CORRIDOR_MID_X, boundary_y - 1.0),
				Vector2(CORRIDOR_MID_X, boundary_y + 0.5),
			]
		else:
			# Flank (horizontal) connection: a is the corridor, b is the flank room,
			# OR vice versa depending on generation order — figure out which side.
			var corridor_rect: Rect2 = a_rect if rooms[a_id]["type"] == "corridor" else b_rect
			var room_rect: Rect2 = b_rect if rooms[a_id]["type"] == "corridor" else a_rect
			var room_id_for_gap: String = b_id if rooms[a_id]["type"] == "corridor" else a_id
			var gap_entry: Dictionary = gap_info.get(room_id_for_gap, {})
			var mid_y: int = gap_entry.get("mid_y", int(room_rect.position.y))
			var room_is_west: bool = room_rect.position.x < corridor_rect.position.x

			# Gap cells run [near-room, near-corridor]; the door (when present)
			# sits on the cell adjacent to the corridor side, matching the
			# original hand-authored layout's door_engineering/door_cargo cells.
			var gap_cells: Array = []
			var wp_room: Vector2
			var wp_corridor: Vector2
			if room_is_west:
				var x0: int = int(room_rect.position.x + room_rect.size.x)
				gap_cells = [Vector2(x0, mid_y), Vector2(x0 + 1, mid_y)]
				wp_room = Vector2(room_rect.position.x + room_rect.size.x - 0.5, mid_y)
				wp_corridor = Vector2(corridor_rect.position.x + 0.5, mid_y)
				if door_id != "":
					door_cells[door_id] = Vector2(x0 + 1, mid_y)
			else:
				var x0e: int = int(corridor_rect.position.x + corridor_rect.size.x)
				gap_cells = [Vector2(x0e, mid_y), Vector2(x0e + 1, mid_y)]
				wp_room = Vector2(room_rect.position.x + 0.5, mid_y)
				wp_corridor = Vector2(corridor_rect.position.x + corridor_rect.size.x - 0.5, mid_y)
				if door_id != "":
					door_cells[door_id] = Vector2(x0e, mid_y)
			walkways.append_array(gap_cells)
			var corridor_id_actual: String = a_id if rooms[a_id]["type"] == "corridor" else b_id
			hop_waypoints["%s|%s" % [room_id_for_gap, corridor_id_actual]] = [wp_room, wp_corridor]

	var hull_polygon: PackedVector2Array = _build_hull_polygon(build["row_meta"])

	return {
		"room_rects": room_rects,
		"floor_tints": FLOOR_TINTS_BY_TYPE,
		"floor_tile_by_type": FLOOR_TILE_BY_TYPE,
		"props": props,
		"walkways": walkways,
		"tubes": tubes,
		"door_cells": door_cells,
		"hop_waypoints": hop_waypoints,
		"wall_segments": wall_segments,
		"hull_polygon": hull_polygon,
	}


static func _shares_vertical_boundary(a: Rect2, b: Rect2) -> bool:
	# Fore/aft (spine) connections directly abut in Y with matching X ranges;
	# flank connections sit side by side with a gap in X instead.
	var a_bottom: float = a.position.y + a.size.y
	var b_bottom: float = b.position.y + b.size.y
	return is_equal_approx(a_bottom, b.position.y) or is_equal_approx(b_bottom, a.position.y)


static func _tube_cells(a: Rect2, b: Rect2) -> Array:
	var a_center: Vector2 = a.position + a.size / 2.0
	var b_center: Vector2 = b.position + b.size / 2.0
	var mid: Vector2 = ((a_center + b_center) / 2.0).round()
	return [mid]


# --- Props ---

static func _generate_props(rng: RandomNumberGenerator, type: String, rect: Rect2, skip_edges: Array) -> Array:
	var w: int = int(rect.size.x)
	var h: int = int(rect.size.y)
	var pool: Array = PROP_POOLS.get(type, [])
	if pool.is_empty():
		return []

	var candidates: Array = []
	for x in range(w):
		for y in range(h):
			var on_perimeter: bool = x == 0 or x == w - 1 or y == 0 or y == h - 1
			if not on_perimeter:
				continue
			if "N" in skip_edges and y == 0:
				continue
			if "S" in skip_edges and y == h - 1:
				continue
			if "W" in skip_edges and x == 0:
				continue
			if "E" in skip_edges and x == w - 1:
				continue
			candidates.append(Vector2(x, y))

	if candidates.is_empty():
		return []

	var result: Array = []
	var area: int = w * h
	var max_count: int = 1 if area <= 6 else clampi(rng.randi_range(2, 4), 1, pool.size())

	var centerpiece: String = CENTERPIECE_BY_TYPE.get(type, "")
	if centerpiece != "" and not candidates.is_empty():
		# Prefer a back-facing edge (N then W) for the centerpiece so it reads
		# prominently without sitting in the doorway gap.
		var back_candidates: Array = []
		for cell in candidates:
			if ("N" not in skip_edges and cell.y == 0) or ("W" not in skip_edges and cell.x == 0):
				back_candidates.append(cell)
		var pick_from: Array = back_candidates if not back_candidates.is_empty() else candidates
		var idx: int = rng.randi_range(0, pick_from.size() - 1)
		var cell: Vector2 = pick_from[idx]
		result.append([cell, centerpiece])
		candidates.erase(cell)
		max_count = max(max_count - 1, 0)

	var shuffled: Array = _shuffled(rng, candidates)
	var take: int = min(max_count, shuffled.size())
	for k in range(take):
		var sprite: String = pool[rng.randi_range(0, pool.size() - 1)]
		result.append([shuffled[k], sprite])

	return result


static func _shuffled(rng: RandomNumberGenerator, arr: Array) -> Array:
	var out: Array = arr.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = out[i]
		out[i] = out[j]
		out[j] = tmp
	return out


# --- Walls ---

# Emits wall tiles along every edge of `rect` NOT listed in skip_edges (those face
# an open connection). Edge -> screen-facing sprite/alpha: the far/back edges (N, W
# in grid space) render as the NE/NW-facing wall pieces and stay more opaque; the
# near/front edges (S, E) render as SW/SE-facing pieces and stay more transparent,
# since painter's-order z-sort draws them over the room's interior (see IsoKit).
static func _emit_wall_edges(rect: Rect2, skip_edges: Array) -> Array:
	var segments: Array = []
	var x0: int = int(rect.position.x)
	var y0: int = int(rect.position.y)
	var w: int = int(rect.size.x)
	var h: int = int(rect.size.y)

	if "N" not in skip_edges:
		for x in range(x0, x0 + w):
			segments.append({"cell": Vector2(x, y0), "sprite": WALL_SPRITE_FOR_EDGE["N"], "alpha": WALL_ALPHA_FOR_EDGE["N"]})
	if "S" not in skip_edges:
		for x in range(x0, x0 + w):
			segments.append({"cell": Vector2(x, y0 + h - 1), "sprite": WALL_SPRITE_FOR_EDGE["S"], "alpha": WALL_ALPHA_FOR_EDGE["S"]})
	if "W" not in skip_edges:
		for y in range(y0, y0 + h):
			segments.append({"cell": Vector2(x0, y), "sprite": WALL_SPRITE_FOR_EDGE["W"], "alpha": WALL_ALPHA_FOR_EDGE["W"]})
	if "E" not in skip_edges:
		for y in range(y0, y0 + h):
			segments.append({"cell": Vector2(x0 + w - 1, y), "sprite": WALL_SPRITE_FOR_EDGE["E"], "alpha": WALL_ALPHA_FOR_EDGE["E"]})
	return segments


# --- Hull silhouette ---

# Builds a simple, guaranteed non-self-intersecting hull polygon (grid-cell space,
# caller converts via IsoKit.cell_to_deck) from the fore-to-aft row extents: a nose
# taper ahead of the bridge, the flanks inflated per row, and a flared aft block
# behind the engine room.
static func _build_hull_polygon(row_meta: Array) -> PackedVector2Array:
	if row_meta.is_empty():
		return PackedVector2Array()

	var first_row: Dictionary = row_meta[0]
	var last_row: Dictionary = row_meta[row_meta.size() - 1]
	var apex := Vector2(CORRIDOR_MID_X, first_row["y0"] - NOSE_LEN)
	var aft_half_w: float = (last_row["max_x"] - last_row["min_x"]) / 2.0 + HULL_AFT_MARGIN
	var aft_cap_y: float = last_row["y1"] + AFT_BLOCK_LEN

	var points: Array = [apex]
	for row in row_meta:
		points.append(Vector2(row["min_x"] - HULL_MARGIN, row["y0"]))
	points.append(Vector2(last_row["min_x"] - HULL_AFT_MARGIN, last_row["y1"]))
	points.append(Vector2(CORRIDOR_MID_X - aft_half_w, aft_cap_y))
	points.append(Vector2(CORRIDOR_MID_X + aft_half_w, aft_cap_y))
	points.append(Vector2(last_row["max_x"] + HULL_AFT_MARGIN, last_row["y1"]))
	for k in range(row_meta.size() - 1, -1, -1):
		var row2: Dictionary = row_meta[k]
		points.append(Vector2(row2["max_x"] + HULL_MARGIN, row2["y0"]))

	var deck_points := PackedVector2Array()
	for p in points:
		deck_points.append(IsoKit.cell_to_deck(p))
	return deck_points
