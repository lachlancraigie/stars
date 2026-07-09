class_name Door
extends Node2D

# Connects two rooms. Locked doors are excluded from ShipGraph pathfinding queries.
# AI override requires write-level access to the "doors" system.

# Gate sprite tint per lock state — both semi-transparent so the doorway stays
# readable either way; ShipLayoutBuilder assigns gate_sprite when it places the
# gate at the door's deck cell.
const LOCKED_TINT: Color = Color(0.95, 0.30, 0.25, 0.80)
const UNLOCKED_TINT: Color = Color(0.55, 0.90, 0.70, 0.55)

@export var door_id: String = ""
@export var room_a_id: String = ""
@export var room_b_id: String = ""
@export var requires_access_level: int = 0
@export var is_locked: bool = false
@export var ai_override_enabled: bool = true

var gate_sprite: Sprite2D = null


func _ready() -> void:
	GameState.doors[door_id] = self
	refresh_gate_visual()


func open() -> void:
	is_locked = false
	EventBus.door_state_changed.emit(door_id, true)
	refresh_gate_visual()


func lock() -> void:
	is_locked = true
	EventBus.door_state_changed.emit(door_id, false)
	refresh_gate_visual()


# Recolours the gate sprite to reflect is_locked. Safe to call before the gate
# sprite exists (ShipLayoutBuilder may set it after _ready()) or if a door has
# no deck-plan cell at all (some connections are undoored/borderless).
func refresh_gate_visual() -> void:
	if gate_sprite == null:
		return
	gate_sprite.modulate = LOCKED_TINT if is_locked else UNLOCKED_TINT


func request_crew_override(crew_id: String) -> void:
	EventBus.door_override_requested.emit(crew_id, door_id)


func ai_unlock() -> bool:
	if not ai_override_enabled or GameState.get_ai_access("doors") < 2:
		return false
	open()
	return true
