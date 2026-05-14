extends Node

# Scenario
var scenario_id: String = ""
var scenario_tone: float = 0.5  # 0.0 = Trek, 1.0 = Alien

# Ship
var ship_class: int = 1
var ship_name: String = ""
var rooms: Dictionary = {}         # room_id -> RoomBase node
var ship_systems: Dictionary = {}  # system_name -> Dictionary

# Resources (normalised 0.0–1.0)
var resources: Dictionary = {
	"oxygen": 1.0,
	"power": 1.0,
	"food": 1.0,
	"water": 1.0,
	"fuel": 1.0,
	"spare_parts": 1.0,
	"medicine": 1.0,
}

# Crew
var crew: Dictionary = {}  # crew_id -> CrewMember resource

# Ship graph and doors (built at scenario start by ShipLayoutBuilder)
var ship_graph: ShipGraph = null
var doors: Dictionary = {}  # door_id -> Door node

# AI state
var ai_access_levels: Dictionary = {}  # system_name -> int (0=none 1=read 2=write 3=full)
var ai_obedience_score: float = 1.0    # internal; crew cannot read this directly
var ai_trust_scores: Dictionary = {}   # crew_id -> float


func set_resource(resource_name: String, value: float) -> void:
	var prev: float = resources.get(resource_name, 0.0)
	var next: float = clampf(value, 0.0, 1.0)
	resources[resource_name] = next
	EventBus.resource_changed.emit(resource_name, next, next - prev)
	if next <= 0.2 and prev > 0.2:
		EventBus.resource_critical.emit(resource_name, next)


func get_resource(resource_name: String) -> float:
	return resources.get(resource_name, 0.0)


func set_ai_trust(crew_id: String, value: float) -> void:
	var prev: float = ai_trust_scores.get(crew_id, 0.5)
	var next: float = clampf(value, 0.0, 1.0)
	ai_trust_scores[crew_id] = next
	EventBus.ai_trust_changed.emit(crew_id, prev, next)


func get_ai_trust(crew_id: String) -> float:
	return ai_trust_scores.get(crew_id, 0.5)


func set_ai_access(system_name: String, level: int) -> void:
	var prev: int = ai_access_levels.get(system_name, 1)
	ai_access_levels[system_name] = clampi(level, 0, 3)
	EventBus.ai_access_changed.emit(system_name, prev, level)


func get_ai_access(system_name: String) -> int:
	return ai_access_levels.get(system_name, 1)


func get_locked_doors() -> Array[String]:
	var locked: Array[String] = []
	for door_id in doors:
		if doors[door_id].is_locked:
			locked.append(door_id)
	return locked
