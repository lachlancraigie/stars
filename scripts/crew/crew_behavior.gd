class_name CrewBehavior
extends Node

# Autonomous crew movement. Crew act on their own needs and state — this is
# the crew's self-determination layer (Architecture Rule 1: the AI never moves
# crew; this module is the crew moving themselves).
#
# Every few seconds each crew member re-evaluates where they should be:
#   sleeping/eating -> quarters, working -> their duty station,
#   panicking -> flee to a random neighbouring room,
#   idle -> occasionally wander or shuffle around the room.

const DECISION_MIN: float = 2.5   # seconds between decisions (randomised per crew)
const DECISION_MAX: float = 5.0
const PANIC_SPEED_MULT: float = 1.8
const WANDER_CHANCE: float = 0.30       # idle: chance to visit a neighbouring room
const SHUFFLE_CHANCE: float = 0.45      # idle: chance to reposition inside the room

# Room TYPE (not room_id — generated ships have ids like "cargo_2") each role
# reports to; resolved to an actual room_id via GameState.get_room_of_type().
const DUTY_STATION: Dictionary = {
	"captain": "bridge",
	"engineer": "engine_room",
	"medic": "medbay",
	"general": "cargo",
}

var _timers: Dictionary = {}  # crew_id -> seconds until next decision


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)


func _on_tick(_elapsed: float, delta: float) -> void:
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew == null or not crew.is_alive:
			continue
		_timers[crew_id] = _timers.get(crew_id, randf_range(0.2, DECISION_MAX)) - delta
		if _timers[crew_id] > 0.0:
			continue
		_timers[crew_id] = randf_range(DECISION_MIN, DECISION_MAX)
		_decide(crew)


func _decide(crew: CrewMember) -> void:
	var node: CrewMemberNode = CrewMemberNode.nodes.get(crew.crew_id) as CrewMemberNode
	if node == null:
		return

	match crew.current_state:
		CrewStateMachine.INCAPACITATED:
			return

		CrewStateMachine.PANICKING:
			node.speed_mult = PANIC_SPEED_MULT
			var neighbours: Array[String] = GameState.ship_graph.get_neighbours(crew.location)
			if not neighbours.is_empty():
				node.move_to_room(neighbours.pick_random())

		CrewStateMachine.SLEEPING, CrewStateMachine.EATING:
			node.speed_mult = 1.0
			if _honouring_directive(node):
				return
			_ensure_room_of_type(node, crew, "quarters")

		CrewStateMachine.WORKING:
			node.speed_mult = 1.0
			if _honouring_directive(node):
				return
			_ensure_room_of_type(node, crew, DUTY_STATION.get(crew.role, "cargo"))

		CrewStateMachine.IDLE:
			node.speed_mult = 1.0
			# Don't undercut a directive the crew just agreed to, and don't
			# interrupt a walk already in progress.
			if node.is_busy() or TimeManager.elapsed < node.hold_room_until:
				return
			var roll: float = randf()
			if roll < WANDER_CHANCE:
				var neighbours: Array[String] = GameState.ship_graph.get_neighbours(crew.location)
				if not neighbours.is_empty():
					node.move_to_room(neighbours.pick_random())
			elif roll < WANDER_CHANCE + SHUFFLE_CHANCE:
				node.wander_within_room()


func _ensure_room_of_type(node: CrewMemberNode, crew: CrewMember, room_type: String) -> void:
	var room_id: String = GameState.get_room_of_type(room_type)
	if room_id == "" or crew.location == room_id or node.is_headed_to(room_id):
		return
	node.move_to_room(room_id)


# A crew member who agreed to an AI directive honours it for its hold window
# instead of drifting back to their duty station mid-task. Panic still
# overrides — fear beats compliance.
func _honouring_directive(node: CrewMemberNode) -> bool:
	return node.is_busy() or TimeManager.elapsed < node.hold_room_until
