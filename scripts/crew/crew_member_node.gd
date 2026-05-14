class_name CrewMemberNode
extends Node2D

# Visual representation of a CrewMember resource.
# Registers crew_data into GameState on _ready; handles display and movement.

@export var crew_data: CrewMember

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel


func _ready() -> void:
	if crew_data == null:
		push_warning("CrewMemberNode has no crew_data assigned.")
		return
	GameState.crew[crew_data.crew_id] = crew_data
	name_label.text = crew_data.crew_name
	EventBus.crew_state_changed.connect(_on_state_changed)


func move_to_room(room_id: String) -> void:
	var old_room: String = crew_data.location
	crew_data.location = room_id
	EventBus.crew_moved.emit(crew_data.crew_id, old_room, room_id)
	# TODO(crew): tween position to room's world-space coords once ship scene has layout


func _on_state_changed(crew_id: String, _old_state: String, new_state: String) -> void:
	if crew_id != crew_data.crew_id:
		return
	# Tint the sprite to make state legible during development
	match new_state:
		CrewStateMachine.PANICKING:
			modulate = Color(1.0, 0.3, 0.3)
		CrewStateMachine.SLEEPING:
			modulate = Color(0.5, 0.6, 1.0)
		CrewStateMachine.INCAPACITATED:
			modulate = Color(0.4, 0.4, 0.4)
		_:
			modulate = Color.WHITE
