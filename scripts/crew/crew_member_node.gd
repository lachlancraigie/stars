class_name CrewMemberNode
extends Node2D

# Visual representation of a CrewMember resource.
# Registers crew_data into GameState on _ready; renders the role/state/facing
# sprite and walks between rooms along the deck plan when told to move.

const CREW_SPRITE_DIR: String = "res://assets/sprites/crew/"
const TARGET_CREW_HEIGHT: float = 96.0   # crew sprites are generated ~576px tall; downscale to this
const MOVE_SPEED: float = 150.0          # px/sec along the deck plan
const ARRIVE_EPSILON: float = 3.0        # px; movement is done when this close to target
const Z_CREW: int = 10                   # crew render above room floor-plates

# Roles without a dedicated sprite set fall back to the general crew sprites.
const KNOWN_ROLES: Array[String] = ["captain", "engineer", "medic", "general"]
const FALLBACK_ROLE: String = "general"

# Registry so directive execution can find a crew's visual node by id.
static var nodes: Dictionary = {}  # crew_id -> CrewMemberNode

@export var crew_data: CrewMember

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel

var _facing: String = "s"
var _moving: bool = false
var _target_pos: Vector2 = Vector2.ZERO
var _current_pose: String = ""    # cached to avoid reloading the texture every frame


func _ready() -> void:
	if crew_data == null:
		push_warning("CrewMemberNode has no crew_data assigned.")
		return
	GameState.crew[crew_data.crew_id] = crew_data
	nodes[crew_data.crew_id] = self
	name_label.text = crew_data.crew_name
	z_index = Z_CREW

	# Place at the starting room, spread so co-located crew do not fully overlap.
	var room: RoomBase = GameState.rooms.get(crew_data.location) as RoomBase
	if room:
		position = room.position + _occupant_offset()
	_apply_sprite()

	EventBus.crew_state_changed.connect(_on_state_changed)


func _exit_tree() -> void:
	if crew_data and nodes.get(crew_data.crew_id) == self:
		nodes.erase(crew_data.crew_id)


func _process(delta: float) -> void:
	if not _moving:
		return
	var to_target: Vector2 = _target_pos - position
	if to_target.length() <= ARRIVE_EPSILON:
		position = _target_pos
		_moving = false
		var room: RoomBase = GameState.rooms.get(crew_data.location) as RoomBase
		if room:
			room.add_occupant(crew_data.crew_id)
		_apply_sprite()
		return
	_update_facing(to_target)
	position += to_target.normalized() * MOVE_SPEED * delta
	_apply_sprite()


# Crew begins walking to another room. Occupant bookkeeping: leave the old room
# immediately, join the new room on arrival.
func move_to_room(room_id: String) -> void:
	if room_id == crew_data.location and not _moving:
		return
	var old_room_id: String = crew_data.location
	var old_room: RoomBase = GameState.rooms.get(old_room_id) as RoomBase
	if old_room:
		old_room.remove_occupant(crew_data.crew_id)

	crew_data.location = room_id
	EventBus.crew_moved.emit(crew_data.crew_id, old_room_id, room_id)

	var dest: RoomBase = GameState.rooms.get(room_id) as RoomBase
	if dest == null:
		push_warning("CrewMemberNode: move target room '%s' not found" % room_id)
		return
	_target_pos = dest.position + _occupant_offset()
	_moving = true


func _update_facing(to_target: Vector2) -> void:
	# Screen space is y-down: moving up is north, down is south.
	if absf(to_target.x) > absf(to_target.y):
		_facing = "e" if to_target.x > 0.0 else "w"
	else:
		_facing = "s" if to_target.y > 0.0 else "n"


func _pose_for_state() -> String:
	match crew_data.current_state:
		CrewStateMachine.INCAPACITATED:
			return "collapsed"
		CrewStateMachine.PANICKING:
			return "panic"
		_:
			return ("walk_" if _moving else "idle_") + _facing


func _apply_sprite() -> void:
	var pose: String = _pose_for_state()
	if pose == _current_pose:
		return
	_current_pose = pose

	var role: String = crew_data.role if crew_data.role in KNOWN_ROLES else FALLBACK_ROLE
	var path: String = CREW_SPRITE_DIR + "crew_%s_%s.png" % [role, pose]
	var texture: Texture2D = load(path)
	if texture == null:
		push_warning("CrewMemberNode '%s': failed to load sprite '%s'" % [crew_data.crew_id, path])
		return
	sprite.texture = texture
	var scale_factor: float = TARGET_CREW_HEIGHT / texture.get_height()
	sprite.scale = Vector2(scale_factor, scale_factor)


# Stable per-crew screen offset so crew sharing a room don't stack exactly.
func _occupant_offset() -> Vector2:
	var i: int = GameState.crew.keys().find(crew_data.crew_id)
	if i < 0:
		i = 0
	return Vector2((i % 3 - 1) * 44, (i / 3) * 40)


func _on_state_changed(crew_id: String, _old_state: String, _new_state: String) -> void:
	if crew_id != crew_data.crew_id:
		return
	_apply_sprite()
