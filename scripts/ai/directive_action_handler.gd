class_name DirectiveActionHandler
extends Node

# Executes the world-effects of directives the crew have ACCEPTED.
#
# Architecture Rule 1 (no direct crew control) is respected: this handler only
# reacts to `directive_accepted`, which fires after the crew member has already
# evaluated the directive and chosen to comply. The AI never moves crew directly;
# it issues a directive, the crew decides, and — only on acceptance — we play out
# the movement the crew agreed to. A rejected directive produces no movement.

const HUNT_HOLD_SECONDS: float = 45.0


func _ready() -> void:
	EventBus.directive_accepted.connect(_on_directive_accepted)


func _on_directive_accepted(crew_id: String, directive: Resource) -> void:
	var d := directive as AIDirective
	if d == null:
		return
	if d.move_to_room != "":
		var node: CrewMemberNode = CrewMemberNode.nodes.get(crew_id) as CrewMemberNode
		if node:
			# The crew agreed to go — they also stay a while rather than wandering
			# straight back out, so complying with the AI visibly means something.
			node.move_to_room(d.move_to_room, 60.0)
	if d.repair_target != "":
		# Same shape as move_to_room above: the world-effect only plays out once the crew
		# has agreed. GameState.start_repair_job is the same funnel RepairBehavior's own
		# autonomous consideration uses (scripts/crew/repair_behavior.gd) — it no-ops if a
		# job is already running (e.g. RepairBehavior beat the directive to it).
		GameState.start_repair_job(d.repair_target, crew_id)
	if d.hunt_intruder_id != "":
		# Same move_to_room-on-accept pattern as everything above (docs/mission-system-spec.md
		# §9) — resolved fresh here rather than at issue time since a mobile intruder may
		# have moved on by the time the crew member actually agrees.
		var target_room: String = IntruderSystem.room_of(d.hunt_intruder_id)
		if target_room != "":
			var hunter: CrewMemberNode = CrewMemberNode.nodes.get(crew_id) as CrewMemberNode
			if hunter:
				hunter.move_to_room(target_room, HUNT_HOLD_SECONDS)
