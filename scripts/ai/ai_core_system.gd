class_name AICoreSystem
extends Node

# Owns the AI's own degraded-mode capability effects — this is the AI observing and
# limiting ITSELF as its core integrity drops, not the AI controlling crew (Rule 1 is
# unaffected: nothing here touches a CrewMember's position/state/action). Three cheap,
# legible degradations while ai_core_status == "degraded" (per the overhaul spec):
#   1. Door control lag — Door.ai_unlock() asks this system for the current lag and
#      defers the actual open() by that many seconds instead of acting instantly.
#   2. Sensor gaps — 1-2 random rooms the AI can't currently see occupants in
#      (GameState.ai_core_sensor_gap_rooms), rotated periodically.
#   3. Directive issue latency — AISystem asks this system for a delay before routing a
#      newly issued directive, instead of acting on it the instant it's issued.
# At "blackout", capability is withdrawn almost entirely — see GameState.ai_core_can_act(),
# which AISystem.issue_directive() and Door.ai_unlock() both check directly.

const SENSOR_GAP_ROOM_COUNT: int = 2
const SENSOR_GAP_ROTATE_SECS: float = 20.0
const DOOR_LAG_SECONDS: float = 4.0
const DIRECTIVE_LATENCY_SECONDS: float = 2.5

var _sensor_gap_timer: float = 0.0


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.ai_core_status_changed.connect(_on_status_changed)


func _on_tick(_elapsed: float, delta: float) -> void:
	if GameState.ai_core_status != "degraded":
		return
	_sensor_gap_timer -= delta
	if _sensor_gap_timer <= 0.0:
		_sensor_gap_timer = SENSOR_GAP_ROTATE_SECS
		_rotate_sensor_gaps()


func _on_status_changed(_old_status: String, new_status: String) -> void:
	if new_status != "degraded":
		GameState.ai_core_sensor_gap_rooms.clear()
	else:
		_rotate_sensor_gaps()


func _rotate_sensor_gaps() -> void:
	var room_ids: Array[String] = []
	room_ids.assign(GameState.rooms.keys())
	room_ids.shuffle()
	var gaps: Array[String] = []
	gaps.assign(room_ids.slice(0, mini(SENSOR_GAP_ROOM_COUNT, room_ids.size())))
	GameState.ai_core_sensor_gap_rooms = gaps



# Static so callers elsewhere (Door, AISystem) don't need a reference to this node's
# instance — only the sensor-gap rotation above needs to be a ticking Node.
static func door_lag_seconds() -> float:
	if GameState.ai_core_status == "degraded":
		return DOOR_LAG_SECONDS
	return 0.0


static func directive_latency_seconds() -> float:
	if GameState.ai_core_status == "degraded":
		return DIRECTIVE_LATENCY_SECONDS
	return 0.0
