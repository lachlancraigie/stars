class_name RoomBase
extends Node2D

# Base for all ship rooms. Rooms connect via a graph (not a grid).
# Pathfinding and crew routing traverse connected_room_ids.

const RoomFunction: Dictionary = {
	BRIDGE = "bridge",
	MEDBAY = "medbay",
	REACTOR = "reactor",
	LIFE_SUPPORT = "life_support",
	PROPULSION = "propulsion",
	WEAPONS = "weapons",
	SENSORS = "sensors",
	COMMS = "comms",
	CARGO = "cargo",
	QUARTERS = "quarters",
	CORRIDOR = "corridor",
	MAINTENANCE = "maintenance",
}

@export var room_id: String = ""
@export var room_function: String = RoomFunction.CORRIDOR
@export var integrity: float = 1.0       # 0.0 = destroyed, 1.0 = pristine
@export var access_level: int = 0        # 0 = unrestricted; higher = more restricted

var occupants: Array[String] = []          # crew_ids currently here
var connected_room_ids: Array[String] = [] # directly reachable rooms


func _ready() -> void:
	GameState.rooms[room_id] = self


func add_occupant(crew_id: String) -> void:
	if crew_id not in occupants:
		occupants.append(crew_id)
		EventBus.room_entered.emit(crew_id, room_id)


func remove_occupant(crew_id: String) -> void:
	if crew_id in occupants:
		occupants.erase(crew_id)
		EventBus.room_exited.emit(crew_id, room_id)


func apply_damage(amount: float) -> void:
	integrity = maxf(0.0, integrity - amount)
	if integrity <= 0.2:
		EventBus.system_critical.emit(room_id, integrity)
