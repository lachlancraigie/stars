class_name RoomBase
extends Node2D

# Base for all ship rooms. Rooms connect via a graph (not a grid).
# Pathfinding and crew routing traverse connected_room_ids.
#
# Visuals: each room composes its floor and props from the legacy isometric
# kit (IsoKit/DeckPlan) — floor diamonds per grid cell plus function-specific
# dressing. The node's position is the room centre in deck space; tiles are
# children positioned rect-relative.

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

@onready var room_label: Label = $RoomLabel


func _ready() -> void:
	GameState.rooms[room_id] = self
	_compose_visual()
	room_label.text = _display_name()


func _compose_visual() -> void:
	if not DeckPlan.has_room(room_id):
		push_warning("RoomBase '%s': no deck-plan rect; room will be invisible" % room_id)
		return
	var rect: Rect2 = DeckPlan.room_rect(room_id)
	var center: Vector2 = DeckPlan.room_center(room_id)
	var tint: Color = DeckPlan.FLOOR_TINTS.get(room_function, Color.WHITE)

	# Floor: one kit diamond per grid cell.
	for gx in range(int(rect.position.x), int(rect.position.x + rect.size.x)):
		for gy in range(int(rect.position.y), int(rect.position.y + rect.size.y)):
			var local: Vector2 = IsoKit.cell_to_deck(Vector2(gx, gy)) - center
			var tile: Sprite2D = IsoKit.make_sprite(DeckPlan.FLOOR_TILE, local, 0.0, true)
			tile.modulate = tint
			add_child(tile)

	# Props: function-specific dressing, z-sorted by absolute deck y.
	for prop in DeckPlan.PROPS.get(room_id, []):
		var cell: Vector2 = rect.position + prop[0]
		var local: Vector2 = IsoKit.cell_to_deck(cell) - center
		add_child(IsoKit.make_sprite(prop[1], local, center.y + local.y))

	# Label sits under the room's bottom corner.
	var bottom_cell: Vector2 = rect.position + rect.size - Vector2.ONE
	var bottom_y: float = IsoKit.cell_to_deck(bottom_cell).y - center.y
	room_label.position = Vector2(-70, bottom_y + IsoKit.TILE_HALF_H + 10.0)
	room_label.size = Vector2(140, 20)
	room_label.z_index = 4000
	room_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	room_label.add_theme_constant_override("outline_size", 5)


func _display_name() -> String:
	if room_id == "corridor_main":
		return "Corridor"
	return room_id.capitalize()


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
