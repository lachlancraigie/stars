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
			var cell: Vector2 = DeckPlan.DOOR_CELLS.get(conn_def.door_id, Vector2.ZERO)
			if cell != Vector2.ZERO:
				door.position = IsoKit.cell_to_deck(cell)
				door.add_child(IsoKit.make_sprite(DeckPlan.DOOR_SPRITE, Vector2.ZERO, door.position.y))
			parent.add_child(door)

	# Back-fill connected_room_ids on each room so rooms know their neighbours
	for room_id in GameState.rooms:
		var room: RoomBase = GameState.rooms[room_id]
		room.connected_room_ids = GameState.ship_graph.get_neighbours(room_id)

	for resource_name in config.starting_resources:
		GameState.set_resource(resource_name, config.starting_resources[resource_name])


# Walkway decking between room islands and maintenance tube pipes.
static func _build_deck_furniture(parent: Node) -> void:
	for cell: Vector2 in DeckPlan.WALKWAYS:
		var pos: Vector2 = IsoKit.cell_to_deck(cell)
		parent.add_child(IsoKit.make_sprite(DeckPlan.WALKWAY_TILE, pos, 0.0, true))
	for cell: Vector2 in DeckPlan.TUBES:
		var pos: Vector2 = IsoKit.cell_to_deck(cell)
		parent.add_child(IsoKit.make_sprite(DeckPlan.TUBE_TILE, pos, pos.y))
