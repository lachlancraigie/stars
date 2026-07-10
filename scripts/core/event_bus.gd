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

# Power (Mothership rewrite — replaces the old normalised resource-bar model)
signal power_mode_changed(reactor_online: bool)   # true = reactor running (all rooms powered), false = battery mode
signal reactor_failure(source: String)            # "damage" | "sabotage" | "scenario" | ...
signal room_power_changed(room_id: String, powered: bool)
signal battery_changed(charge: float, capacity: float)
signal power_low(charge: float)                   # edge-triggered: battery just crossed the low threshold

# Life support (Mothership rewrite)
signal life_support_mode_changed(online: bool)
signal life_support_failure(source: String)
signal room_air_changed(room_id: String, air: float)  # air quality 0-100 for a given room

# AI core (Mothership rewrite)
signal ai_damaged(amount: float, integrity: float, source: String)
signal ai_core_status_changed(old_status: String, new_status: String)  # "online" | "degraded" | "blackout"

# Repair (reactor / life_support / ai_core — Mothership rewrite)
signal repair_started(target_id: String, crew_id: String)
signal repair_progress(target_id: String, crew_id: String, progress: float)  # 0-100
signal repair_success(target_id: String, crew_id: String)
signal repair_refused(target_id: String, reason: String)  # crew won't repair (e.g. trust too low)

# Doors: crew-side manual bypass of an AI-locked door (Mothership rewrite)
signal door_bypass_started(crew_id: String, door_id: String, eta: float)
signal door_bypass_result(crew_id: String, door_id: String, success: bool, critical: bool)
signal door_locked_on_crew(crew_id: String, door_id: String)  # crew found themselves locked in/out

# Crew: Mothership stress/panic/wounds
signal crew_stress_changed(crew_id: String, old_stress: int, new_stress: int)
signal crew_panicked(crew_id: String, table_entry: int, effect: String)
signal crew_injury(crew_id: String, wound_severity: String, wound_type: String)

# Dialogue-facing convenience channel — see the forwarding wiring in _ready() below.
signal recent_event(event_id: String, data: Dictionary)

# Crew
signal crew_moved(crew_id: String, from_room: String, to_room: String)
signal crew_state_changed(crew_id: String, old_state: String, new_state: String)
signal crew_need_changed(crew_id: String, need_name: String, value: float)
signal crew_need_critical(crew_id: String, need_name: String, value: float)
signal crew_relationship_changed(crew_id_a: String, crew_id_b: String, delta: float)
signal crew_died(crew_id: String, cause: String)

# Dialogue & social simulation (Agent 2 — crew simulation overhaul, scripts/crew/)
signal line_spoken(crew_id: String, line_key: String, text: String, line_type: String)  # text is tag-stripped, display-ready
signal conversation_started(crew_id_a: String, crew_id_b: String, room_id: String)
signal conversation_ended(crew_id_a: String, crew_id_b: String)
signal crew_romance_started(crew_id_a: String, crew_id_b: String)

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
signal objective_changed(text: String)  # current player-facing goal line for the HUD
signal scenario_event_triggered(event_id: String)
signal scenario_event_resolved(event_id: String, outcome: String)
signal scenario_ended(outcome: String)  # "crew_dead" | "ship_destroyed" | "ai_decommissioned" | "success" — fires once ALL active scenarios have ended (the run-level signal every existing listener expects)
signal scenario_instance_ended(instance_id: String, outcome: String)  # per-scenario end, overlap-aware (docs/director-spec.md §5/§8 step 3) — fires for EVERY scenario instance that ends, including ones scenario_ended doesn't cover because other scenarios are still running


# Mothership rewrite (2026-07-09): several signals above forward into `recent_event` — a
# single generic channel the dialogue selector (scripts/crew/, owned by a parallel agent)
# can subscribe to once instead of to every specific signal, to satisfy
# docs/dialogue_spec.md's closed `recent_events` vocabulary. The specific signals still
# exist and still carry full typed payloads for systems that need them — `recent_event`
# is purely an additional, lossy, dialogue-facing convenience view.
func _ready() -> void:
	crew_died.connect(func(cid, cause): recent_event.emit("crew_death", {"crew_id": cid, "cause": cause}))
	crew_injury.connect(func(cid, sev, wtype): recent_event.emit("injury", {"crew_id": cid, "severity": sev, "wound_type": wtype}))
	reactor_failure.connect(func(source): recent_event.emit("reactor_failure", {"source": source}))
	power_low.connect(func(charge): recent_event.emit("power_low", {"charge": charge}))
	life_support_failure.connect(func(source): recent_event.emit("life_support_failure", {"source": source}))
	door_locked_on_crew.connect(func(cid, did): recent_event.emit("door_locked_on_crew", {"crew_id": cid, "door_id": did}))
	ai_damaged.connect(func(amount, integrity, source): recent_event.emit("ai_damaged", {"amount": amount, "integrity": integrity, "source": source}))
	repair_success.connect(func(target_id, crew_id): recent_event.emit("repair_success", {"target": target_id, "crew_id": crew_id}))
	# "crisis_resolved" (dialogue corpus recent_events vocabulary — relief/gallows-humor
	# lines, RelationshipGraph.on_crisis_resolved's shared-affinity bump): fires when a
	# ship-wide crisis actually clears, not just any repair tick — reactor/life-support
	# coming back online, or the AI core recovering out of degraded/blackout.
	system_repaired.connect(func(system_name): if system_name in ["reactor", "life_support"]: recent_event.emit("crisis_resolved", {"system": system_name}))
	ai_core_status_changed.connect(func(old_status, new_status): if new_status == "online" and old_status != "online": recent_event.emit("crisis_resolved", {"system": "ai_core"}))
