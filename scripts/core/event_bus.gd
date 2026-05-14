extends Node

# Time
signal game_paused
signal game_unpaused
signal time_ticked(elapsed: float, delta: float)

# Ship systems
signal system_damaged(system_name: String, severity: float)
signal system_repaired(system_name: String)
signal system_critical(system_name: String, severity: float)
signal system_power_changed(system_name: String, draw: float)

# Rooms and doors
signal door_override_requested(crew_id: String, door_id: String)
signal door_state_changed(door_id: String, is_open: bool)
signal room_entered(crew_id: String, room_id: String)
signal room_exited(crew_id: String, room_id: String)

# Resources
signal resource_changed(resource_name: String, value: float, delta: float)
signal resource_critical(resource_name: String, value: float)

# Crew
signal crew_moved(crew_id: String, from_room: String, to_room: String)
signal crew_state_changed(crew_id: String, old_state: String, new_state: String)
signal crew_need_changed(crew_id: String, need_name: String, value: float)
signal crew_need_critical(crew_id: String, need_name: String, value: float)
signal crew_relationship_changed(crew_id_a: String, crew_id_b: String, delta: float)
signal crew_died(crew_id: String, cause: String)

# AI directives
signal directive_issued(directive: Resource)
signal directive_accepted(crew_id: String, directive: Resource)
signal directive_rejected(crew_id: String, directive: Resource, reason: String)
signal directive_completed(crew_id: String, directive: Resource)

# AI trust and access
signal ai_trust_changed(crew_id: String, old_trust: float, new_trust: float)
signal ai_access_changed(system_name: String, old_level: int, new_level: int)
signal ai_decommission_attempted(initiator_crew_id: String)

# Scenario events
signal scenario_event_triggered(event_id: String)
signal scenario_event_resolved(event_id: String, outcome: String)
signal scenario_ended(outcome: String)  # "crew_dead" | "ship_destroyed" | "ai_decommissioned" | "success"
