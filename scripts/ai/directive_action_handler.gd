class_name DirectiveActionHandler
extends Node

# Executes the world-effects of directives the crew have ACCEPTED.
#
# Architecture Rule 1 (no direct crew control) is respected: this handler only
# reacts to `directive_accepted`, which fires after the crew member has already
# evaluated the directive and chosen to comply. The AI never moves crew directly;
# it issues a directive, the crew decides, and — only on acceptance — we play out
# the movement the crew agreed to. A rejected directive produces no movement.


func _ready() -> void:
	EventBus.directive_accepted.connect(_on_directive_accepted)


func _on_directive_accepted(crew_id: String, directive: Resource) -> void:
	var d := directive as AIDirective
	if d == null or d.move_to_room == "":
		return
	var node: CrewMemberNode = CrewMemberNode.nodes.get(crew_id) as CrewMemberNode
	if node:
		# The crew agreed to go — they also stay a while rather than wandering
		# straight back out, so complying with the AI visibly means something.
		node.move_to_room(d.move_to_room, 60.0)
