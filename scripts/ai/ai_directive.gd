class_name AIDirective
extends Resource

enum Type {
	SUGGESTION       = 0,  # easiest to comply with; lowest scrutiny
	RECOMMENDATION   = 1,  # standard; default for most player actions
	INSTRUCTION      = 2,  # authoritative; moderate scrutiny
	ALERT            = 3,  # urgent; urgency slightly boosts compliance
	OVERRIDE_ATTEMPT = 4,  # maximum scrutiny; requires high trust
}

enum TargetType {
	CREW   = 0,
	ROOM   = 1,
	SYSTEM = 2,
}

@export var directive_id: String = ""
@export var type: Type = Type.RECOMMENDATION
@export var target_type: TargetType = TargetType.CREW
@export var target_id: String = ""           # crew_id, room_id, or system_name
@export var content: String = ""             # text shown to crew and written to logs
@export var confidence: float = 0.8          # how certain the AI presents itself (0–1)
@export var priority: int = 1                # 1–5
@export var timestamp: float = 0.0

# Destination room a crew directive asks the crew to move to. Empty = no movement.
# Executed by DirectiveActionHandler only when the crew *accepts* the directive.
@export var move_to_room: String = ""

# Repair target this directive asks the crew to work on ("reactor" | "life_support" |
# "ai_core", matching GameState.repair_jobs keys / RepairModel.REPAIR_SKILLS). Empty = no
# repair action. Executed by DirectiveActionHandler only on acceptance, same pattern as
# move_to_room — the UI never calls GameState.start_repair_job directly (Architecture
# Rule 1: no direct crew control from UI, directives only).
@export var repair_target: String = ""

# Tags for conflict detection in DirectiveEvaluator.
# e.g. "danger", "sacrifice", "abandon", "deceive" — matched against crew fears/values.
@export var content_tags: Array[String] = []

# Internal fields — crew cannot observe these directly.
var actual_intent: String = ""   # what the AI is really trying to achieve
var is_deceptive: bool = false   # AI is misrepresenting its intent
