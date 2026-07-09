class_name ShipLayoutBuilder
extends RefCounted

# Instantiates a live ship from a ShipConfig resource.
# Call build() once at scenario start to populate GameState with rooms, doors,
# and the graph. `parent` should be the ShipDeck container node — rooms, deck
# furniture (walkways, tubes, door gates), and later crew all live in that one
# coordinate space so painter's-order z-sorting works across the whole deck.

const ROOM_BASE_SCENE: String = "res://scenes/rooms/RoomBase.tscn"
const DOOR_SCENE: String = "res://scenes/rooms/Door.tscn"


static func build(config: ShipConfig, parent: Node) -> void:
	GameState.ship_graph = ShipGraph.new()

	_build_hull(parent)

	# room_id -> access_level, so doors can inherit the stricter side's clearance.
	var access_by_room: Dictionary = {}
	for rd in config.rooms:
		access_by_room[rd.room_id] = rd.access_level

	var room_scene: PackedScene = load(ROOM_BASE_SCENE)
	for room_def in config.rooms:
		var room: RoomBase = room_scene.instantiate()
		room.room_id = room_def.room_id
		room.room_function = room_def.room_function
		room.integrity = room_def.integrity
		room.access_level = room_def.access_level
		# The deck plan is authoritative for visual placement; layout_position
		# is only a fallback for rooms the plan doesn't know.
		if DeckPlan.has_room(room_def.room_id):
			room.position = DeckPlan.room_center(room_def.room_id)
		else:
			room.position = room_def.layout_position
		parent.add_child(room)

	_build_deck_furniture(parent)

	var door_scene: PackedScene = load(DOOR_SCENE)
	for conn_def in config.connections:
		GameState.ship_graph.connect_rooms(
			conn_def.room_a_id,
			conn_def.room_b_id,
			conn_def.weight,
			conn_def.door_id,
			conn_def.maintenance_only
		)
		if conn_def.door_id != "":
			var door: Door = door_scene.instantiate()
			door.door_id = conn_def.door_id
			door.room_a_id = conn_def.room_a_id
			door.room_b_id = conn_def.room_b_id
			door.requires_access_level = maxi(
				access_by_room.get(conn_def.room_a_id, 0),
				access_by_room.get(conn_def.room_b_id, 0)
			)
			var cell: Vector2 = DeckPlan.DOOR_CELLS.get(conn_def.door_id, Vector2.ZERO)
			if cell != Vector2.ZERO:
				door.position = IsoKit.cell_to_deck(cell)
				var gate: Sprite2D = IsoKit.make_sprite(DeckPlan.DOOR_SPRITE, Vector2.ZERO, door.position.y)
				door.add_child(gate)
				door.gate_sprite = gate
			parent.add_child(door)
			door.refresh_gate_visual()

	# Back-fill connected_room_ids on each room so rooms know their neighbours
	for room_id in GameState.rooms:
		var room: RoomBase = GameState.rooms[room_id]
		room.connected_room_ids = GameState.ship_graph.get_neighbours(room_id)

	for resource_name in config.starting_resources:
		GameState.set_resource(resource_name, config.starting_resources[resource_name])


# Walkway decking between room islands, maintenance tube pipes, and the
# semi-transparent wall segments the generator placed along room boundaries.
static func _build_deck_furniture(parent: Node) -> void:
	for cell: Vector2 in DeckPlan.WALKWAYS:
		var pos: Vector2 = IsoKit.cell_to_deck(cell)
		parent.add_child(IsoKit.make_sprite(DeckPlan.WALKWAY_TILE, pos, 0.0, true))
	for cell: Vector2 in DeckPlan.TUBES:
		var pos: Vector2 = IsoKit.cell_to_deck(cell)
		parent.add_child(IsoKit.make_sprite(DeckPlan.TUBE_TILE, pos, pos.y))
	for seg: Dictionary in DeckPlan.WALL_SEGMENTS:
		var pos: Vector2 = IsoKit.cell_to_deck(seg["cell"])
		var wall: Sprite2D = IsoKit.make_sprite(seg["sprite"], pos, pos.y)
		wall.modulate.a = seg["alpha"]
		parent.add_child(wall)


# Ship hull silhouette: sits behind the floor/props (Z_FLOOR is 0) but in front
# of the starfield (Starfield renders at z_index -1000), so rooms read as being
# inside a single vessel with open space visible outside its outline.
static func _build_hull(parent: Node) -> void:
	if DeckPlan.HULL_POLYGON.size() < 3:
		return
	var fill := Polygon2D.new()
	fill.polygon = DeckPlan.HULL_POLYGON
	fill.color = Color(0.13, 0.15, 0.19, 0.92)
	fill.z_index = -10
	parent.add_child(fill)

	var outline := Line2D.new()
	for p: Vector2 in DeckPlan.HULL_POLYGON:
		outline.add_point(p)
	outline.add_point(DeckPlan.HULL_POLYGON[0])
	outline.width = 5.0
	outline.default_color = Color(0.42, 0.48, 0.58, 0.85)
	outline.z_index = -9
	parent.add_child(outline)
