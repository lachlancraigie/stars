class_name Door
extends Node2D

# Connects two rooms. Locked doors are excluded from ShipGraph pathfinding queries.
# AI override requires write-level access to the "doors" system.

@export var door_id: String = ""
@export var room_a_id: String = ""
@export var room_b_id: String = ""
@export var requires_access_level: int = 0
@export var is_locked: bool = false
@export var ai_override_enabled: bool = true


func _ready() -> void:
	GameState.doors[door_id] = self


func open() -> void:
	is_locked = false
	EventBus.door_state_changed.emit(door_id, true)


func lock() -> void:
	is_locked = true
	EventBus.door_state_changed.emit(door_id, false)


func request_crew_override(crew_id: String) -> void:
	EventBus.door_override_requested.emit(crew_id, door_id)


func ai_unlock() -> bool:
	if not ai_override_enabled or GameState.get_ai_access("doors") < 2:
		return false
	open()
	return true
