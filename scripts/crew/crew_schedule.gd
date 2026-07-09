class_name CrewSchedule
extends RefCounted

# Ship-wide shift-cycle schedule layered on top of TimeManager.elapsed. This is a
# LEGIBILITY device (per CLAUDE.md's "Dwarf Fortress" framing) — at any moment the
# player can tell what the crew SHOULD be doing: on shift, eating, socialising, or
# turned in. It extends CrewBehavior's existing per-crew decision loop (crew_behavior.gd)
# rather than replacing CrewStateMachine: needs-driven states (SLEEPING/EATING/PANICKING/
# WORKING-via-boredom) are evaluated first and unconditionally override the schedule —
# this module only decides what an otherwise-IDLE crew member does with their time.
#
# A full "day" cycles through four phases. Real-world length is deliberately short
# (DAY_LENGTH seconds at 1x speed) so a player sees multiple full cycles within a single
# scenario session, matching the existing needs-model pacing (NeedsModel's own comment:
# "~10 min to starvation, ~14 min to exhaustion" at 1x with 4 crew).
const DAY_LENGTH: float = 360.0  # 6 minutes at 1x

# Cumulative end-fraction of each phase within one day, in order. "work" runs first
# (slightly under half the day), then a meal window, then recreation/downtime, then
# sleep fills the remainder.
const PHASE_ORDER: Array[String] = ["work", "meal", "recreation", "sleep"]
const PHASE_END_FRACTION: Dictionary = {
	"work": 0.45,
	"meal": 0.55,
	"recreation": 0.75,
	"sleep": 1.0,
}

# Per-crew phase boundaries are jittered by a stable per-crew offset so the whole crew
# doesn't snap between phases in lockstep (reads as more organic; also spreads
# mess-room/quarters arrivals out a little instead of everyone teleporting-by-decision-
# tick on the exact same frame). The GLOBAL (unjittered) phase — see phase_at() — is what
# drives the ship-wide shift_start/shift_end/meal_time/quiet_shift events.
const JITTER_FRACTION: float = 0.06  # +/- 6% of DAY_LENGTH

# Recreation-phase behaviour mix for an otherwise-idle crew member: mostly head to a
# social/hobby spot, but keep a slice of the old unscheduled wander/shuffle texture so
# downtime doesn't look perfectly regimented either.
const RECREATION_WANDER_CHANCE: float = 0.15
const RECREATION_SIDE_PROJECT_CHANCE: float = 0.35
const RECREATION_PARTNER_JOIN_CHANCE: float = 0.7  # couples preferentially spend downtime together

# target_id (GameState.repair_jobs key) -> room TYPE the repairing crew member must stay
# in. Mirrors RepairBehavior's own room resolution (kept here too, not exported there, to
# avoid coupling scripts/ship/repair_model.gd-adjacent code to crew-schedule concerns).
const REPAIR_ROOM_TYPE: Dictionary = {
	"reactor": "engine_room",
	"life_support": "life_support",
	"ai_core": "ai_core",
}

# Edge-trigger guard for the global (ship-wide) phase, so the shift_start/shift_end/
# meal_time/quiet_shift recent_events fire once per transition, not once per tick.
static var _last_global_phase: String = ""


static func phase_at(t: float) -> String:
	var frac: float = fposmod(t, DAY_LENGTH) / DAY_LENGTH
	for phase: String in PHASE_ORDER:
		if frac < float(PHASE_END_FRACTION[phase]):
			return phase
	return PHASE_ORDER[PHASE_ORDER.size() - 1]


# Stable per-crew time offset (seconds), deterministic from crew_id so it doesn't
# reshuffle between calls/sessions with the same roster.
static func _crew_jitter(crew_id: String) -> float:
	var unit: float = float(abs(hash(crew_id)) % 1000) / 1000.0  # 0..1
	return (unit - 0.5) * 2.0 * JITTER_FRACTION * DAY_LENGTH


static func phase_for(crew: CrewMember) -> String:
	return phase_at(TimeManager.elapsed + _crew_jitter(crew.crew_id))


# Call once per tick (see CrewBehavior._on_tick). Detects the ship-wide (unjittered)
# phase transition and emits the matching docs/dialogue_spec.md recent_events. Meal and
# shift-end are both true the moment work ends, so both fire on that one transition.
static func check_phase_transition() -> void:
	var current: String = phase_at(TimeManager.elapsed)
	if current == _last_global_phase:
		return
	_last_global_phase = current
	match current:
		"work":
			EventBus.recent_event.emit("shift_start", {})
		"meal":
			EventBus.recent_event.emit("shift_end", {})
			EventBus.recent_event.emit("meal_time", {})
		"sleep":
			EventBus.recent_event.emit("quiet_shift", {})


# Room-id (not type) a crew member with an in-progress repair assignment must hold —
# "" if they have none. RepairBehavior only ever starts a job with a crew member already
# on-scene; this is what makes that stick (schedule/recreation can't pull them away
# mid-repair — "RepairBehavior duties outrank recreation" per the overhaul spec).
static func repair_duty_room(crew: CrewMember) -> String:
	for target_id: String in GameState.repair_jobs:
		var job: Dictionary = GameState.repair_jobs[target_id]
		if String(job.get("crew_id", "")) == crew.crew_id:
			return GameState.get_room_of_type(String(REPAIR_ROOM_TYPE.get(target_id, "")))
	return ""


# Where an idle, schedule-driven crew member should spend a recreation window: with
# their partner if they have one (and the partner's currently somewhere sane to join),
# else sometimes their personal side project, else the default social hub (mess).
static func recreation_room_for(crew: CrewMember) -> String:
	var partner_id: String = RelationshipGraph.partner_of(crew.crew_id)
	if partner_id != "" and randf() < RECREATION_PARTNER_JOIN_CHANCE:
		var partner: CrewMember = GameState.crew.get(partner_id) as CrewMember
		if partner != null and partner.is_alive \
				and partner.current_state not in [CrewStateMachine.INCAPACITATED, CrewStateMachine.FROZEN, CrewStateMachine.PANICKING] \
				and partner.location != "":
			return partner.location
	if randf() < RECREATION_SIDE_PROJECT_CHANCE:
		var room_id: String = GameState.get_room_of_type(SideProjects.location_for(crew))
		if room_id != "":
			return room_id
	return GameState.get_room_of_type("mess")
