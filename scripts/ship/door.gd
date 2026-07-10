class_name Door
extends Node2D

# Connects two rooms. Locked doors block ShipGraph pathfinding queries that pass this
# door's id in `blocked_doors` (see CrewMemberNode.move_to_room, which now respects locks
# instead of ignoring them). AI override requires write-level access to the "doors" system,
# is withdrawn during an AI core blackout, is delayed during "degraded" mode (door control
# lag), and requires both connected rooms to be powered.
#
# Crew-side manual bypass (Mothership rewrite): a crew member blocked by a locked door can
# attempt to force it — an Intellect check with a tech/engineering skill bonus through
# Checks, the game's one roll-resolution utility. Success opens it quickly; (non-critical)
# failure still opens it, just slowly, and costs Stress (via Checks.perform_check); a
# Critical Failure jams the door outright (no entry, extra Stress, a Panic Check) until a
# later attempt succeeds. Equipment (crowbar/cutting torch/engineer's toolkit) shortens the
# time and/or adds a flat bonus to the check via item tags (see scripts/core/items.gd).

# Gate sprite tint per lock state — both semi-transparent so the doorway stays
# readable either way; ShipLayoutBuilder assigns gate_sprite when it places the
# gate at the door's deck cell.
const LOCKED_TINT: Color = Color(0.95, 0.30, 0.25, 0.80)
const UNLOCKED_TINT: Color = Color(0.55, 0.90, 0.70, 0.55)
const JAMMED_TINT: Color = Color(0.55, 0.20, 0.75, 0.85)

const BYPASS_SKILLS: Array[String] = ["Hacking", "Computers", "Engineering", "Mechanical Repair"]
const FAST_BYPASS_SECONDS: float = 6.0     # success
const INSTANT_BYPASS_SECONDS: float = 1.5  # critical success
const SLOW_BYPASS_SECONDS: float = 45.0    # (non-critical) failure — still gets through, just slow
const LOCKOUT_TRUST_EVERY: int = 3          # every Nth lockout on the same door dents trust

@export var door_id: String = ""
@export var room_a_id: String = ""
@export var room_b_id: String = ""
@export var requires_access_level: int = 0
@export var is_locked: bool = false
@export var ai_override_enabled: bool = true
@export var jammed: bool = false

var gate_sprite: Sprite2D = null
var _bypassing_crew_ids: Dictionary = {}   # crew_id -> true, guards against double-attempts


func _ready() -> void:
	GameState.doors[door_id] = self
	refresh_gate_visual()


func open() -> void:
	is_locked = false
	jammed = false
	EventBus.door_state_changed.emit(door_id, true)
	refresh_gate_visual()


func lock() -> void:
	is_locked = true
	EventBus.door_state_changed.emit(door_id, false)
	refresh_gate_visual()


# Recolours the gate sprite to reflect is_locked/jammed. Safe to call before the gate
# sprite exists (ShipLayoutBuilder may set it after _ready()) or if a door has
# no deck-plan cell at all (some connections are undoored/borderless).
func refresh_gate_visual() -> void:
	if gate_sprite == null:
		return
	if jammed:
		gate_sprite.modulate = JAMMED_TINT
	else:
		gate_sprite.modulate = LOCKED_TINT if is_locked else UNLOCKED_TINT


func request_crew_override(crew_id: String) -> void:
	EventBus.door_override_requested.emit(crew_id, door_id)


func ai_unlock() -> bool:
	if jammed or not ai_override_enabled or GameState.get_ai_access("doors") < 2:
		return false
	if not GameState.ai_core_can_act():
		return false
	if not (GameState.get_room_powered(room_a_id) and GameState.get_room_powered(room_b_id)):
		return false
	var lag: float = AICoreSystem.door_lag_seconds()
	if lag <= 0.0:
		open()
	else:
		get_tree().create_timer(lag).timeout.connect(open)
	return true


# Entry point for a crew member blocked by this locked door (see
# CrewMemberNode.move_to_room). Rolls an Intellect+tech-skill check through Checks and
# resolves the door after a duration that depends on the result.
func attempt_crew_bypass(crew: CrewMember) -> void:
	if not is_locked or crew.crew_id in _bypassing_crew_ids:
		return
	_bypassing_crew_ids[crew.crew_id] = true
	_record_lockout(crew)
	EventBus.door_locked_on_crew.emit(crew.crew_id, door_id)

	var skill_bonus: int = crew.best_skill_bonus(BYPASS_SKILLS)
	var item_bonus: int = int(crew.item_bonus("door_bypass_bonus"))
	# Overseer mercy knob (docs/director-spec.md §4): +5 max, hard-capped by
	# ScenarioDirector itself — never visible to the player, never announced.
	var mercy_bonus: int = int(ScenarioDirector.modifiers.get("check_bonus", 0))
	var result: Checks.CheckResult = Checks.perform_check(crew, "intellect", "", false, false, skill_bonus + item_bonus + mercy_bonus)
	var time_mult: float = crew.item_time_multiplier("door_bypass_time_mult")

	var eta: float
	if result.critical_success():
		eta = INSTANT_BYPASS_SECONDS
	elif result.success:
		eta = FAST_BYPASS_SECONDS
	elif result.critical_failure():
		eta = 0.0  # resolved immediately as a jam below
	else:
		eta = SLOW_BYPASS_SECONDS
	eta *= time_mult

	EventBus.door_bypass_started.emit(crew.crew_id, door_id, eta)
	if result.critical_failure():
		_resolve_bypass(crew, result)
	else:
		get_tree().create_timer(eta).timeout.connect(_resolve_bypass.bind(crew, result))


func _resolve_bypass(crew: CrewMember, result: Checks.CheckResult) -> void:
	_bypassing_crew_ids.erase(crew.crew_id)
	if result.critical_failure():
		jammed = true
		crew.add_stress(1)  # perform_check already applied +1 for the failure itself
		refresh_gate_visual()
	else:
		# Both success and a plain (non-critical) failure eventually force the door —
		# failure is just slow and costly in Stress, not a hard block.
		open()
	EventBus.door_bypass_result.emit(crew.crew_id, door_id, result.success, result.critical)


func _record_lockout(crew: CrewMember) -> void:
	var count: int = int(crew.door_lockout_counts.get(door_id, 0)) + 1
	crew.door_lockout_counts[door_id] = count
	if count % LOCKOUT_TRUST_EVERY == 0:
		TrustModel.modify(crew.crew_id, TrustModel.DISOBEDIENCE_MINOR)
