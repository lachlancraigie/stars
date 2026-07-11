class_name MissionDeck
extends RefCounted

# Loads resources/missions/*.json into MissionDef instances and implements the
# eligibility filter + weighted draw (docs/mission-system-spec.md §3). One instance
# per campaign (MissionManager, task E, owns it) — RefCounted rather than a static
# registry (unlike ScenarioCatalog) because completed_ids is per-run state, not a
# process-wide cache.
#
# Deterministic-friendly: draw() takes an optional RandomNumberGenerator so tests/
# AUTODEMO-style harnesses can pin a seed instead of depending on the engine's global
# RNG stream.

var missions: Dictionary = {}          # id -> MissionDef
var completed_ids: Dictionary = {}     # id -> true; repeatable=false missions are excluded once here


func load_all(dir: String = "res://resources/missions") -> int:
	missions.clear()
	var da := DirAccess.open(dir)
	if da == null:
		push_warning("MissionDeck: could not open %s (err=%d)" % [dir, DirAccess.get_open_error()])
		return 0
	da.list_dir_begin()
	var file_name: String = da.get_next()
	while file_name != "":
		if not da.current_is_dir() and file_name.ends_with(".json"):
			var mission: MissionDef = MissionDef.from_file(dir.path_join(file_name))
			if mission != null and mission.id != "":
				if missions.has(mission.id):
					push_warning("MissionDeck: duplicate mission id '%s' (%s)" % [mission.id, file_name])
				missions[mission.id] = mission
		file_name = da.get_next()
	da.list_dir_end()
	return missions.size()


func mark_completed(mission_id: String) -> void:
	completed_ids[mission_id] = true


# Eligibility filter (spec §3's "eligibility" block) plus the repeatable/completed
# exclusion the spec's draw() prose calls out separately — folded in here since both
# are "is this mission even offerable right now" checks, and draw() needs exactly
# this same filtered pool before it does anything weight-related.
func eligible(campaign_flags: Dictionary, leg: int, hull: float) -> Array[MissionDef]:
	var result: Array[MissionDef] = []
	for mission_id: String in missions:
		var mission: MissionDef = missions[mission_id]
		if not mission.repeatable and completed_ids.has(mission_id):
			continue
		if _passes_eligibility(mission, campaign_flags, leg, hull):
			result.append(mission)
	return result


func _passes_eligibility(mission: MissionDef, campaign_flags: Dictionary, leg: int, hull: float) -> bool:
	var elig: Dictionary = mission.eligibility
	if leg < int(elig.get("min_leg", 1)):
		return false
	if hull < float(elig.get("min_hull", 0.0)) or hull > float(elig.get("max_hull", 100.0)):
		return false
	for flag in (elig.get("requires_flags_all", []) as Array):
		if not bool(campaign_flags.get(String(flag), false)):
			return false
	var requires_any: Array = elig.get("requires_flags_any", [])
	if not requires_any.is_empty():
		var any_met: bool = false
		for flag in requires_any:
			if bool(campaign_flags.get(String(flag), false)):
				any_met = true
				break
		if not any_met:
			return false
	for flag in (elig.get("excludes_flags", []) as Array):
		if bool(campaign_flags.get(String(flag), false)):
			return false
	return true


# Weighted draw (spec §3). Two-stage:
#  1. Priority preemption: among eligible missions with priority > 0, the highest
#     priority value wins outright (ties broken randomly) — used for forced
#     repair/emergency missions.
#  2. Otherwise a weighted draw over every eligible mission, where a mission's
#     `weight` is multiplied by any follow_on rule from the PREVIOUS mission that
#     names it (explicit id, or "tag:x" matching one of its tags) AND whose `when`
#     flags are all true in prev_outcome_flags ∪ campaign_flags.
#
# `prev_outcome_flags` and `prev_follow_ons` are passed as two separate params
# (rather than the single "prev_outcome_flags" the spec prose shorthand implies)
# because the follow_on RULES themselves live on the previous MissionDef, not in
# its outcome flags — the caller (MissionManager) has both close at hand from the
# mission that just resolved (prev_mission.follow_ons, and the flags its resolution
# set), so this keeps MissionDeck itself stateless about "what just happened".
func draw(campaign_flags: Dictionary, leg: int, hull: float,
		prev_outcome_flags: Dictionary = {}, prev_follow_ons: Array = [],
		rng: RandomNumberGenerator = null) -> MissionDef:
	var pool: Array[MissionDef] = eligible(campaign_flags, leg, hull)
	if pool.is_empty():
		return null

	var priority_pool: Array[MissionDef] = []
	var highest_priority: int = 0
	for mission: MissionDef in pool:
		if mission.priority > highest_priority:
			highest_priority = mission.priority
			priority_pool = [mission]
		elif mission.priority > 0 and mission.priority == highest_priority:
			priority_pool.append(mission)
	if not priority_pool.is_empty():
		return priority_pool[_rand_index(priority_pool.size(), rng)]

	var combined_flags: Dictionary = campaign_flags.duplicate()
	combined_flags.merge(prev_outcome_flags, true)

	var weights: Array[float] = []
	for mission: MissionDef in pool:
		weights.append(_weighted_weight(mission, combined_flags, prev_follow_ons))

	return pool[_weighted_index(weights, rng)]


func _weighted_weight(mission: MissionDef, combined_flags: Dictionary, follow_ons: Array) -> float:
	var weight: float = mission.weight
	for fo_v in follow_ons:
		var fo: Dictionary = fo_v
		if not _when_satisfied(fo.get("when", []), combined_flags):
			continue
		for next_v in (fo.get("next", []) as Array):
			var next_ref: String = String(next_v)
			var matches: bool = (next_ref.substr(4) in mission.tags) if next_ref.begins_with("tag:") \
				else (next_ref == mission.id)
			if matches:
				weight *= float(fo.get("weight", 1.0))
	return weight


func _when_satisfied(when_flags: Array, combined_flags: Dictionary) -> bool:
	for flag in when_flags:
		if not bool(combined_flags.get(String(flag), false)):
			return false
	return true


func _rand_index(count: int, rng: RandomNumberGenerator) -> int:
	if count <= 1:
		return 0
	return rng.randi_range(0, count - 1) if rng != null else randi_range(0, count - 1)


func _weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return _rand_index(weights.size(), rng)
	var roll: float = (rng.randf() if rng != null else randf()) * total
	var cumulative: float = 0.0
	for i in weights.size():
		cumulative += maxf(weights[i], 0.0)
		if roll <= cumulative:
			return i
	return weights.size() - 1
