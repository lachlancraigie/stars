class_name CrewLifecycle
extends RefCounted

# Single funnel for "a crew member has died", whatever the cause (starvation-style
# needs collapse, Mothership Death Save, suffocation, sabotage). Keeps the
# is_alive flip + EventBus emission consistent no matter which system triggers it.


static func kill(crew: CrewMember, cause: String) -> void:
	if not crew.is_alive:
		return
	crew.is_alive = false
	crew.current_state = CrewStateMachine.INCAPACITATED
	EventBus.crew_died.emit(crew.crew_id, cause)
