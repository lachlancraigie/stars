class_name DirectiveEvaluator
extends RefCounted

# Per-type multiplier on the base compliance probability.
# Indexed by AIDirective.Type enum value.
const TYPE_MODIFIERS: Array[float] = [
	1.10,  # SUGGESTION
	1.00,  # RECOMMENDATION
	0.85,  # INSTRUCTION
	1.05,  # ALERT — urgency provides a small compliance boost
	0.40,  # OVERRIDE_ATTEMPT — heavy scrutiny
]

const CONFLICT_PENALTY_FEAR:   float = 0.30
const CONFLICT_PENALTY_VALUES: float = 0.25
const MIN_COMPLIANCE: float          = 0.05
const MAX_COMPLIANCE: float          = 0.95

# Content tag → values it conflicts with.
# Scenario authors tag directives; crew values are matched here.
const VALUE_CONFLICTS: Dictionary = {
	"sacrifice":   ["survival", "crew_welfare"],
	"abandon":     ["loyalty", "crew_welfare"],
	"deceive":     ["integrity"],
	"risk_ship":   ["mission_completion"],
	"lethal":      ["crew_welfare", "survival"],
}


static func evaluate(crew: CrewMember, directive: AIDirective) -> Dictionary:
	# Returns {will_comply: bool, probability: float, rejection_reason: String}

	if crew.current_state == CrewStateMachine.INCAPACITATED:
		return {will_comply = false, probability = 0.0, rejection_reason = "incapacitated"}

	# Panicking crew only respond to ALERT directives
	if crew.current_state == CrewStateMachine.PANICKING:
		if directive.type != AIDirective.Type.ALERT:
			return {will_comply = false, probability = 0.0, rejection_reason = "panicking"}

	var probability: float = GameState.get_ai_trust(crew.crew_id)
	probability *= TYPE_MODIFIERS[int(directive.type)]

	# Morale and willpower adjust compliance up or down
	probability += (crew.morale - 0.5) * 0.30
	probability += (crew.willpower - 0.5) * 0.15

	# Conflict checks against crew fears and values
	var conflict_reason: String = ""
	for tag: String in directive.content_tags:
		if tag in crew.fears:
			probability -= CONFLICT_PENALTY_FEAR
			if conflict_reason == "":
				conflict_reason = "triggers_fear_%s" % tag
		if _conflicts_with_values(tag, crew.values):
			probability -= CONFLICT_PENALTY_VALUES
			if conflict_reason == "":
				conflict_reason = "conflicts_with_values"

	probability = clampf(probability, MIN_COMPLIANCE, MAX_COMPLIANCE)

	var will_comply: bool = randf() < probability
	return {
		will_comply = will_comply,
		probability = probability,
		rejection_reason = "" if will_comply else (conflict_reason if conflict_reason != "" else "low_trust_or_morale"),
	}


static func _conflicts_with_values(tag: String, values: Array[String]) -> bool:
	if tag not in VALUE_CONFLICTS:
		return false
	for conflicting_value: String in VALUE_CONFLICTS[tag]:
		if conflicting_value in values:
			return true
	return false
