class_name ScenarioEvent
extends Resource

# Tone weight: 0.0 = pure Trek, 1.0 = pure Alien.
# Events only fire when scenario_tone is within their tone range.
@export var event_id: String = ""
@export var title: String = ""
@export var description: String = ""        # shown to player in event log
@export var tone_min: float = 0.0
@export var tone_max: float = 1.0
@export var weight: float = 1.0             # relative draw probability within the pool
@export var min_elapsed: float = 0.0        # earliest this event can fire (seconds)
@export var cooldown: float = 300.0         # cannot re-fire within this window
@export var one_shot: bool = false          # if true, removed from pool after firing

# Conditions: all must be true for the event to be eligible.
# Each entry is {type: String, ...params}
# e.g. {type: "resource_below", resource: "battery_percent", value: 25.0}  (see GameState.get_metric)
#      {type: "crew_state", state: "panicking", min_count: 1}
#      {type: "ai_trust_below", crew_id: "any", value: 0.4}
@export var conditions: Array[Dictionary] = []

# Outcomes: applied in order when the event fires.
# e.g. {type: "resource_delta", resource: "battery_charge", amount: -15.0}  (see GameState.adjust_metric)
#      {type: "reactor_failure", source: "combat_damage"}
#      {type: "life_support_failure", source: "hull_breach"}
#      {type: "ai_core_damage", amount: 20.0, source: "sabotage"}
#      {type: "crew_fear_spike", amount: 0.2, all_crew: true}
#      {type: "set_flag", flag: "pathogen_detected"}
#      {type: "spawn_event", event_id: "quarantine_escalation"}
@export var outcomes: Array[Dictionary] = []

# Tracks runtime state — not exported (populated at scenario start)
var last_fired: float = -9999.0
var has_fired: bool = false
