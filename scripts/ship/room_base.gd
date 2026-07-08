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

# room_function -> sprite file under res://assets/sprites/rooms/. Note reactor uses the
# "engineering" sprite (asset naming predates the RoomFunction.REACTOR rename).
const ROOM_SPRITE_DIR: String = "res://assets/sprites/rooms/"
const ROOM_SPRITES: Dictionary = {
	"bridge": "room_bridge.png",
	"reactor": "room_engineering.png",
	"life_support": "room_life_support.png",
	"medbay": "room_medbay.png",
	"quarters": "room_quarters.png",
	"cargo": "room_cargo.png",
	"corridor": "room_corridor.png",
}
const TARGET_ROOM_WIDTH := 360.0  # rooms are generated large (~1152px); downscale to this on-screen width

var occupants: Array[String] = []          # crew_ids currently here
var connected_room_ids: Array[String] = [] # directly reachable rooms

@onready var floor_sprite: Sprite2D = $Floor
@onready var room_label: Label = $RoomLabel


func _ready() -> void:
	GameState.rooms[room_id] = self
	_apply_floor_sprite()
	room_label.text = room_id


func _apply_floor_sprite() -> void:
	var file_name: String = ROOM_SPRITES.get(room_function, "")
	if file_name == "":
		push_warning("RoomBase '%s': no sprite mapped for room_function '%s'" % [room_id, room_function])
		return
	var texture: Texture2D = load(ROOM_SPRITE_DIR + file_name)
	if texture == null:
		push_warning("RoomBase '%s': failed to load sprite '%s'" % [room_id, file_name])
		return
	floor_sprite.texture = texture
	var scale_factor: float = TARGET_ROOM_WIDTH / texture.get_width()
	floor_sprite.scale = Vector2(scale_factor, scale_factor)


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
