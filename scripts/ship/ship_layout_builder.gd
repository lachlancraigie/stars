class_name ShipLayoutBuilder
extends RefCounted

# Instantiates a live ship from a ShipConfig resource.
# Call build() once at scenario start to populate GameState with rooms, doors, and the graph.

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
		room.position = room_def.layout_position
		parent.add_child(room)

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
			parent.add_child(door)

	# Back-fill connected_room_ids on each room so rooms know their neighbours
	for room_id in GameState.rooms:
		var room: RoomBase = GameState.rooms[room_id]
		room.connected_room_ids = GameState.ship_graph.get_neighbours(room_id)

	for resource_name in config.starting_resources:
		GameState.set_resource(resource_name, config.starting_resources[resource_name])
