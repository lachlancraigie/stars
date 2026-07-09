class_name CrewMemberNode
extends Node2D

# Visual representation of a CrewMember resource.
# Registers crew_data into GameState on _ready; renders a legacy-kit astronaut
# (8 facings, role tint), walks multi-hop routes along the ship graph, and
# z-sorts against deck props by y. Lives inside the ShipDeck node so its
# position shares the rooms' deck coordinate space.

const KIT_DIR: String = "res://assets/sprites/legacy/"
const MOVE_SPEED: float = 190.0          # deck px/sec (one grid cell ~130px)
const ARRIVE_EPSILON: float = 4.0        # px; movement is done when this close to target
const BOB_HEIGHT: float = 5.0            # px of walk bounce
const BOB_RATE: float = 9.0              # bounces per second while walking

# Role -> kit astronaut variant + tint. Tints multiply, so light suits take
# the colour while dark visors/boots stay dark. Labels match the tint.
const ROLE_VARIANT: Dictionary = {
	"captain": "astronautA", "engineer": "astronautA",
	"medic": "astronautB", "general": "astronautB",
}
const ROLE_TINT: Dictionary = {
	"captain":  Color(1.00, 0.86, 0.55),
	"engineer": Color(1.00, 1.00, 1.00),
	"medic":    Color(0.80, 1.00, 0.88),
	"general":  Color(0.72, 0.85, 1.00),
}
const FALLBACK_ROLE: String = "general"

const STATE_COLORS: Dictionary = {
	"idle":          Color(0.35, 0.78, 0.40),
	"working":       Color(0.25, 0.55, 0.95),
	"sleeping":      Color(0.60, 0.60, 0.65),
	"eating":        Color(0.95, 0.78, 0.20),
	"panicking":     Color(0.95, 0.25, 0.18),
	"incapacitated": Color(0.15, 0.12, 0.12),
}

# Registry so directive execution can find a crew's visual node by id.
static var nodes: Dictionary = {}  # crew_id -> CrewMemberNode

@export var crew_data: CrewMember

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel

var speed_mult: float = 1.0              # panic runs faster
var hold_room_until: float = 0.0         # TimeManager.elapsed until which idle wander is suppressed

var _facing: String = "S"
var _moving: bool = false
var _target_pos: Vector2 = Vector2.ZERO
var _route: Array = []                   # remaining room_ids to walk through
var _leg_points: Array = []              # remaining deck positions within the current hop
var _pending_room: String = ""           # room we are currently walking into
var _bob_t: float = 0.0
var _current_texture_key: String = ""
var _status_dot: ColorRect


func _ready() -> void:
	if crew_data == null:
		push_warning("CrewMemberNode has no crew_data assigned.")
		return
	GameState.crew[crew_data.crew_id] = crew_data
	nodes[crew_data.crew_id] = self

	name_label.text = crew_data.crew_name
	var tint: Color = ROLE_TINT.get(crew_data.role, Color.WHITE)
	name_label.add_theme_color_override("font_color", tint.lightened(0.35))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("outline_size", 6)
	sprite.offset = IsoKit.ANCHOR_OFFSET
	sprite.self_modulate = tint

	_status_dot = ColorRect.new()
	_status_dot.size = Vector2(9, 9)
	_status_dot.position = Vector2(-4.5, -86)
	add_child(_status_dot)

	position = DeckPlan.random_point(crew_data.location) if DeckPlan.has_room(crew_data.location) \
		else Vector2.ZERO
	z_index = IsoKit.z_for(position.y)
	_apply_sprite()
	_apply_status_dot()

	EventBus.crew_state_changed.connect(_on_state_changed)


func _exit_tree() -> void:
	if crew_data and nodes.get(crew_data.crew_id) == self:
		nodes.erase(crew_data.crew_id)


func _process(delta: float) -> void:
	if TimeManager.is_paused():
		return
	if crew_data.current_state == CrewStateMachine.INCAPACITATED:
		_moving = false
		_route.clear()
		_leg_points.clear()
		_apply_sprite()
		return
	if not _moving:
		_bob_t = 0.0
		sprite.position = Vector2.ZERO
		if crew_data.current_state == CrewStateMachine.PANICKING:
			sprite.position.x = sin(Time.get_ticks_msec() * 0.04) * 2.0
		return

	var to_target: Vector2 = _target_pos - position
	if to_target.length() <= ARRIVE_EPSILON:
		position = _target_pos
		_arrive()
		return

	_update_facing(to_target)
	position += to_target.normalized() * MOVE_SPEED * speed_mult * delta
	z_index = IsoKit.z_for(position.y)
	_bob_t += delta
	sprite.position.y = -absf(sin(_bob_t * BOB_RATE)) * BOB_HEIGHT
	_apply_sprite()


# Walk to another room following the ship graph (multi-hop). hold_seconds
# suppresses idle wandering after arrival — used for directives the crew
# agreed to, so they stay put long enough for it to matter.
func move_to_room(room_id: String, hold_seconds: float = 0.0) -> void:
	if room_id == crew_data.location and not _moving:
		return
	var path: Array = GameState.ship_graph.find_path(crew_data.location, room_id)
	if path.is_empty():
		push_warning("CrewMemberNode: no path %s -> %s" % [crew_data.location, room_id])
		return
	path.pop_front()  # first entry is the current room
	_route = path
	if hold_seconds > 0.0:
		hold_room_until = TimeManager.elapsed + hold_seconds
	_advance_route()


# Small repositioning inside the current room (idle flavour movement).
func wander_within_room() -> void:
	if _moving or not DeckPlan.has_room(crew_data.location):
		return
	_pending_room = ""
	_target_pos = DeckPlan.random_point(crew_data.location)
	_moving = true


func is_headed_to(room_id: String) -> bool:
	return _pending_room == room_id or room_id in _route


func is_busy() -> bool:
	return _moving or not _route.is_empty()


func _advance_route() -> void:
	if _route.is_empty():
		_moving = false
		return
	var next_room: String = _route.pop_front()
	var old_room: RoomBase = GameState.rooms.get(crew_data.location) as RoomBase
	if old_room:
		old_room.remove_occupant(crew_data.crew_id)
	_pending_room = next_room
	# Cross via the walkway/gate waypoints, then settle somewhere in the room.
	_leg_points = DeckPlan.hop_waypoints(crew_data.location, next_room)
	_leg_points.append(DeckPlan.random_point(next_room))
	_target_pos = _leg_points.pop_front()
	_moving = true


func _arrive() -> void:
	if not _leg_points.is_empty():
		_target_pos = _leg_points.pop_front()
		return
	_moving = false
	sprite.position = Vector2.ZERO
	if _pending_room != "":
		var from_room: String = crew_data.location
		crew_data.location = _pending_room
		_pending_room = ""
		EventBus.crew_moved.emit(crew_data.crew_id, from_room, crew_data.location)
		var room: RoomBase = GameState.rooms.get(crew_data.location) as RoomBase
		if room:
			room.add_occupant(crew_data.crew_id)
	if not _route.is_empty():
		_advance_route()
	else:
		_apply_sprite()


func _update_facing(to_target: Vector2) -> void:
	var angle: float = rad_to_deg(to_target.angle())  # y-down: 90 = screen south
	var bucket: int = wrapi(roundi(angle / 45.0), 0, 8)
	_facing = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"][bucket]


func _apply_sprite() -> void:
	var role: String = crew_data.role if ROLE_VARIANT.has(crew_data.role) else FALLBACK_ROLE
	var key: String = "%s_%s" % [ROLE_VARIANT[role], _facing]
	var collapsed: bool = crew_data.current_state == CrewStateMachine.INCAPACITATED

	if key != _current_texture_key:
		var texture: Texture2D = load(KIT_DIR + key + ".png")
		if texture == null:
			push_warning("CrewMemberNode '%s': missing kit sprite '%s'" % [crew_data.crew_id, key])
			return
		sprite.texture = texture
		_current_texture_key = key

	sprite.rotation_degrees = 90.0 if collapsed else 0.0
	var tint: Color = ROLE_TINT.get(role, Color.WHITE)
	if collapsed:
		tint = tint.darkened(0.55)
	elif crew_data.current_state == CrewStateMachine.PANICKING:
		tint = tint * Color(1.0, 0.62, 0.58)
	sprite.self_modulate = tint


func _apply_status_dot() -> void:
	if _status_dot:
		_status_dot.color = STATE_COLORS.get(crew_data.current_state, Color.WHITE)


func _on_state_changed(crew_id: String, _old_state: String, _new_state: String) -> void:
	if crew_id != crew_data.crew_id:
		return
	_apply_sprite()
	_apply_status_dot()
