class_name LifeSupportModel
extends RefCounted

# Ship life support (Mothership rewrite). While the life_support room is functioning,
# every room has full air. On failure, per-room air quality (0-100) degrades toward 0 over
# minutes; the AI diverts remaining life-support capacity to a capped set of rooms, which
# instead recover toward 100. Thresholds below feed docs/rules.md "Survival Conditions >
# Oxygen": below AIR_DISADVANTAGE_THRESHOLD checks made in that room take Disadvantage
# (Checks.perform_check reads this via CrewMember.has_environmental_disadvantage); below
# AIR_CRITICAL_THRESHOLD, crew present start accruing suffocation (see SuffocationModel).

const MAX_LIFE_SUPPORT_ROOMS: int = 3
const DEGRADE_SECONDS_FULL: float = 240.0   # 100 -> 0 over ~4 minutes when unsupported
const RECOVER_SECONDS_FULL: float = 90.0    # 0 -> 100 over ~1.5 minutes when (re)supported
const AIR_DISADVANTAGE_THRESHOLD: float = 40.0
const AIR_CRITICAL_THRESHOLD: float = 15.0


static func tick(delta: float) -> void:
	_check_auto_failure()
	for room_id: String in GameState.rooms.keys():
		var supported: bool = _room_is_supported(room_id)
		var air: float = GameState.get_room_air(room_id)
		if supported:
			air = minf(100.0, air + (100.0 / RECOVER_SECONDS_FULL) * delta)
		else:
			air = maxf(0.0, air - (100.0 / DEGRADE_SECONDS_FULL) * delta)
		GameState.set_room_air(room_id, air)


# Life support automatically fails if its own room loses power (nothing to run the
# scrubbers/recyclers on) — a cheap, legible cascade from the power model into this one.
static func _check_auto_failure() -> void:
	if not GameState.life_support_online:
		return
	var ls_room: String = GameState.get_room_of_type("life_support")
	if ls_room != "" and not GameState.get_room_powered(ls_room):
		GameState.set_life_support_online(false, "unpowered")


static func _room_is_supported(room_id: String) -> bool:
	if GameState.life_support_online:
		return true
	return room_id in GameState.life_supported_rooms
