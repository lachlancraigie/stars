class_name ShipConfig
extends Resource

# Static ship class definition. Loaded from resources/ship_configs/*.tres at scenario start.
# Procedural generation mutates a duplicate of this at runtime — never the base resource.

@export var ship_class: int = 1
@export var ship_name: String = ""
@export var min_crew: int = 3
@export var max_crew: int = 6

@export var starting_resources: Dictionary = {
	"oxygen": 1.0,
	"power": 1.0,
	"food": 0.8,
	"water": 0.8,
	"fuel": 1.0,
	"spare_parts": 0.6,
	"medicine": 0.5,
}

@export var rooms: Array[RoomDefinition] = []
@export var connections: Array[ConnectionDefinition] = []
