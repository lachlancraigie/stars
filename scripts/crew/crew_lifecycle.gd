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
	# Memorial snapshot (docs/crew-progression-spec.md §5) — recorded before the signal
	# fires so any crew_died listener (HUD feed, the roster panel's Lost tab) can already
	# read GameState.fallen for this death.
	GameState.record_fallen({
		"crew_id": crew.crew_id,
		"name": crew.crew_name,
		"role": crew.role,
		"archetype_tag": crew.archetype_tag,
		"traits": crew.traits.duplicate(),
		"legs_served": crew.legs_served,
		"cause": cause,
		"partner": RelationshipGraph.partner_of(crew.crew_id),
		"died_at": TimeManager.elapsed,
	})
	EventBus.crew_died.emit(crew.crew_id, cause)
