class_name CrewBehavior
extends Node

# Autonomous crew movement. Crew act on their own needs and state — this is
# the crew's self-determination layer (Architecture Rule 1: the AI never moves
# crew; this module is the crew moving themselves).
#
# Every few seconds each crew member re-evaluates where they should be:
#   sleeping -> quarters, eating -> mess, working -> their duty station,
#   panicking -> flee to a random neighbouring room.
# An IDLE crew member (none of the above needs are pressing) defers to
# CrewSchedule's shift-cycle: report to a duty station on shift, gather for meals,
# turn in at bedtime, or socialise/pursue a side project during recreation — see
# _decide_idle_schedule(). Priority (highest first): incapacitated/frozen > panic >
# needs (sleep/eat/work-via-boredom) > an in-progress repair assignment > an accepted
# directive's hold_room_until > the schedule.

const DECISION_MIN: float = 2.5   # seconds between decisions (randomised per crew)
const DECISION_MAX: float = 5.0
const PANIC_SPEED_MULT: float = 1.8

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
	CrewSchedule.check_phase_transition()
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew == null or not crew.is_alive:
			continue
		# Away teams (docs/mission-system-spec.md §6) don't self-direct on the ship's deck
		# while off_ship — ShuttleSystem/AwayResolver own their movement (or lack thereof)
		# for the duration of the op.
		if crew.off_ship:
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
		CrewStateMachine.INCAPACITATED, CrewStateMachine.FROZEN:
			return

		CrewStateMachine.PANICKING:
			node.speed_mult = PANIC_SPEED_MULT
			var neighbours: Array[String] = GameState.ship_graph.get_neighbours(crew.location)
			if not neighbours.is_empty():
				node.move_to_room(neighbours.pick_random())

		CrewStateMachine.SLEEPING:
			node.speed_mult = 1.0
			if _honouring_directive(node):
				return
			_ensure_room_of_type(node, crew, "quarters")

		CrewStateMachine.EATING:
			node.speed_mult = 1.0
			if _honouring_directive(node):
				return
			_ensure_room_of_type(node, crew, "mess")

		CrewStateMachine.WORKING:
			node.speed_mult = 1.0
			if _honouring_directive(node):
				return
			_ensure_room_of_type(node, crew, DUTY_STATION.get(crew.role, "cargo"))

		CrewStateMachine.IDLE:
			node.speed_mult = 1.0
			# Don't undercut a directive the crew just agreed to, and don't
			# interrupt a walk already in progress. Directives/an in-flight route
			# outrank the schedule exactly like they outrank plain wandering.
			if node.is_busy() or TimeManager.elapsed < node.hold_room_until:
				return
			# An in-progress repair assignment (RepairBehavior) outranks recreation —
			# the crew member stays put/returns to the system room instead of drifting
			# off to socialise mid-job.
			var repair_room: String = CrewSchedule.repair_duty_room(crew)
			if repair_room != "":
				if crew.location != repair_room and not node.is_headed_to(repair_room):
					node.move_to_room(repair_room)
				return
			_decide_idle_schedule(node, crew)


# Shift-cycle schedule (CrewSchedule) for an otherwise-idle crew member: report to duty
# stations on shift, gather for meals, head to quarters at bedtime, and socialise/pursue a
# side project during recreation. This only ever fires from the IDLE branch above — every
# needs-driven state (SLEEPING/EATING/WORKING/PANICKING) was already handled first and
# takes priority, satisfying "needs and crises override schedule".
func _decide_idle_schedule(node: CrewMemberNode, crew: CrewMember) -> void:
	match CrewSchedule.phase_for(crew):
		"work":
			_ensure_room_of_type(node, crew, DUTY_STATION.get(crew.role, "cargo"))
		"meal":
			_ensure_room_of_type(node, crew, "mess")
		"sleep":
			_ensure_room_of_type(node, crew, "quarters")
		"recreation":
			var roll: float = randf()
			if roll < CrewSchedule.RECREATION_WANDER_CHANCE:
				# Keep a slice of the old unscheduled texture so downtime doesn't look
				# perfectly regimented either.
				if randf() < 0.5:
					var neighbours: Array[String] = GameState.ship_graph.get_neighbours(crew.location)
					if not neighbours.is_empty():
						node.move_to_room(neighbours.pick_random())
				else:
					node.wander_within_room()
			else:
				var room_id: String = CrewSchedule.recreation_room_for(crew)
				if room_id != "" and room_id != crew.location and not node.is_headed_to(room_id):
					node.move_to_room(room_id)


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
