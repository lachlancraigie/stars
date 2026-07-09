class_name RelationshipBehavior
extends Node

# Thin EventBus-listening layer over RelationshipGraph (added by Main, mirrors the
# CrewSystem/NeedsModel split: this Node decides WHEN, RelationshipGraph decides HOW).
# DialogueSystem calls RelationshipGraph directly for the per-line affinity/romance hooks
# (on_line_spoken, on_conversation_ended) since it already has speaker/target/intent in
# hand there; this file covers the social events that originate OUTSIDE the dialogue
# system: panic snapping, shared-crisis bonding, and partner grief on death.


func _ready() -> void:
	EventBus.crew_state_changed.connect(_on_crew_state_changed)
	EventBus.crew_died.connect(_on_crew_died)
	EventBus.recent_event.connect(_on_recent_event)


func _on_crew_state_changed(crew_id: String, old_state: String, new_state: String) -> void:
	if new_state == CrewStateMachine.PANICKING and old_state != CrewStateMachine.PANICKING:
		RelationshipGraph.on_crew_panicked(crew_id)


func _on_crew_died(crew_id: String, _cause: String) -> void:
	RelationshipGraph.on_crew_died(crew_id)


func _on_recent_event(event_id: String, _data: Dictionary) -> void:
	if event_id == "crisis_resolved":
		RelationshipGraph.on_crisis_resolved()
