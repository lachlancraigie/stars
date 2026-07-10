class_name RelationshipGraph
extends RefCounted

# Crew social network. Pure data-manipulation utility (same shape as CrewStateMachine/
# NeedsModel/Checks: static funcs, no signal listening of its own) over
# GameState.crew_relationships, which is the authoritative store per Rule 3. The Node that
# actually listens to EventBus and decides WHEN to call into this (relationship_behavior.gd,
# added by Main) is kept separate on purpose, mirroring the CrewSystem/NeedsModel split.
#
# Data shape per pair (GameState.crew_relationships[pair_key(a,b)]):
#   {"affinity": float -1..1, "flags": Array[String],
#    "romance_stage": "none"|"hinted"|"advancing"|"accepted", "rejected_until": float}
#
# --- What moves affinity (the "small legible set" the overhaul spec asks for) ---
#   conversation completed together         +0.02  (on EventBus.conversation_ended)
#   praise / reassurance / offer_help said to them   +0.03
#   apology said to them                    +0.04
#   banter / gallows_humor said to them     +0.02
#   grief shared with them (comforting)     +0.02
#   insult said to them                     -0.06
#   complaint aimed at them                 -0.02
#   snapped at while panicking (bystanders in the same room when panic hits)  -0.04
#   shared crisis survived (ship-wide, on the "crisis_resolved" recent_event) +0.05
#   romance accepted                        +0.15
#   romance rejected                        -0.05
# Romance progression (romance_hint -> romance_advance -> romance_accept/reject) and the
# resulting affinity/stage/cooldown mutations are funnelled through on_line_spoken() below,
# called by DialogueSystem for every line with a resolvable specific addressee — this is
# the "romance intents gate through the relationship graph" contract from the overhaul spec.

const AAF_MIN: float = -1.0
const AAF_MAX: float = 1.0

const LINE_INTENT_AFFINITY: Dictionary = {
	"praise": 0.03, "reassurance": 0.03, "offer_help": 0.03, "apology": 0.04,
	"banter": 0.02, "gallows_humor": 0.02, "grief": 0.02,
	"insult": -0.06, "complaint": -0.02, "warning": -0.01,
}

const CONVERSATION_AFFINITY: float = 0.02
const PANIC_SNAP_AFFINITY: float = -0.04
const CRISIS_SURVIVED_AFFINITY: float = 0.05
const ROMANCE_ACCEPT_AFFINITY: float = 0.15
const ROMANCE_REJECT_AFFINITY: float = -0.05

# Romance gating thresholds. A speaker's own personality nudges these (see
# _personality_offset) — cheerful crew hint more readily, paranoid crew hold back more —
# derived from the archetype tag prefix (docs/dialogue_spec.md tag format), a light,
# optional touch: crew with no archetype_tag just get the base thresholds.
const ROMANCE_HINT_AFFINITY: float = 0.40
const ROMANCE_ACCEPT_THRESHOLD: float = 0.55
const REJECT_COOLDOWN_SECONDS: float = 240.0

const PERSONALITY_ROMANCE_OFFSET: Dictionary = {
	"CH": -0.05,  # cheerful — a little more forward
	"GR": 0.03,   # gruff — a little more guarded
	"EV": 0.0,    # even — neutral
	"PA": 0.08,   # paranoid — considerably more guarded
}


static func pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a <= b else "%s|%s" % [b, a]


static func _default_entry() -> Dictionary:
	return {"affinity": 0.0, "flags": [], "romance_stage": "none", "rejected_until": -1.0}


static func _entry(a: String, b: String) -> Dictionary:
	var key: String = pair_key(a, b)
	if not GameState.crew_relationships.has(key):
		GameState.crew_relationships[key] = _default_entry()
	return GameState.crew_relationships[key]


static func get_affinity(a: String, b: String) -> float:
	return float(_entry(a, b).get("affinity", 0.0))


static func adjust_affinity(a: String, b: String, delta: float, _reason: String = "") -> float:
	if delta == 0.0 or a == "" or b == "" or a == b:
		return get_affinity(a, b)
	var entry: Dictionary = _entry(a, b)
	var next: float = clampf(float(entry.get("affinity", 0.0)) + delta, AAF_MIN, AAF_MAX)
	entry["affinity"] = next
	EventBus.crew_relationship_changed.emit(a, b, delta)
	return next


static func get_flags(a: String, b: String) -> Array:
	return _entry(a, b).get("flags", [])


static func has_flag(a: String, b: String, flag: String) -> bool:
	return flag in get_flags(a, b)


static func add_flag(a: String, b: String, flag: String) -> void:
	var entry: Dictionary = _entry(a, b)
	var flags: Array = entry.get("flags", [])
	if flag not in flags:
		flags.append(flag)
	entry["flags"] = flags


static func get_romance_stage(a: String, b: String) -> String:
	return String(_entry(a, b).get("romance_stage", "none"))


static func set_romance_stage(a: String, b: String, stage: String) -> void:
	_entry(a, b)["romance_stage"] = stage


static func get_rejected_until(a: String, b: String) -> float:
	return float(_entry(a, b).get("rejected_until", -1.0))


static func are_couple(a: String, b: String) -> bool:
	return get_romance_stage(a, b) == "accepted"


# First accepted partner found for crew_id, "" if single. Romance is monogamous by
# construction (can_hint()/would_accept() below both refuse while already partnered).
static func partner_of(crew_id: String) -> String:
	for key: String in GameState.crew_relationships:
		var entry: Dictionary = GameState.crew_relationships[key]
		if String(entry.get("romance_stage", "")) != "accepted":
			continue
		var ids: PackedStringArray = key.split("|")
		if ids.size() != 2:
			continue
		if ids[0] == crew_id:
			return ids[1]
		if ids[1] == crew_id:
			return ids[0]
	return ""


static func _personality_of(crew: CrewMember) -> String:
	if crew.archetype_tag.length() >= 2:
		return crew.archetype_tag.substr(0, 2)
	return ""


static func _romance_threshold_offset(crew: CrewMember) -> float:
	return float(PERSONALITY_ROMANCE_OFFSET.get(_personality_of(crew), 0.0))


# Can `speaker` plausibly hint at romance toward `target` right now? Both unpartnered,
# affinity above the (personality-adjusted) threshold, no active romance track between
# them yet, and not on a post-rejection cooldown.
static func can_hint(speaker_id: String, target_id: String) -> bool:
	if speaker_id == "" or target_id == "" or speaker_id == target_id:
		return false
	if partner_of(speaker_id) != "" or partner_of(target_id) != "":
		return false
	if get_romance_stage(speaker_id, target_id) != "none":
		return false
	if TimeManager.elapsed < get_rejected_until(speaker_id, target_id):
		return false
	var speaker: CrewMember = GameState.crew.get(speaker_id) as CrewMember
	var threshold: float = ROMANCE_HINT_AFFINITY + (_romance_threshold_offset(speaker) if speaker else 0.0)
	return get_affinity(speaker_id, target_id) >= threshold


static func can_advance(speaker_id: String, target_id: String) -> bool:
	if partner_of(speaker_id) != "" or partner_of(target_id) != "":
		return false
	if get_romance_stage(speaker_id, target_id) != "hinted":
		return false
	var speaker: CrewMember = GameState.crew.get(speaker_id) as CrewMember
	var threshold: float = ROMANCE_HINT_AFFINITY + (_romance_threshold_offset(speaker) if speaker else 0.0)
	return get_affinity(speaker_id, target_id) >= threshold


# Would `target` accept a romance_accept/romance_reject reply toward `speaker` (the one
# who just hinted/advanced)? This is the hard gate that decides which of the two mutually-
# exclusive reply intents is even a valid candidate — see DialogueSystem's romance gate.
static func would_accept(target_id: String, speaker_id: String) -> bool:
	if partner_of(target_id) != "" or partner_of(speaker_id) != "":
		return false
	var target: CrewMember = GameState.crew.get(target_id) as CrewMember
	var threshold: float = ROMANCE_ACCEPT_THRESHOLD + (_romance_threshold_offset(target) if target else 0.0)
	return get_affinity(target_id, speaker_id) >= threshold


# Single funnel DialogueSystem calls for every spoken line that has a resolvable specific
# addressee (declarations/open-air lines have none and should not call this). Moves
# affinity per the table above and drives the romance_hint -> romance_advance ->
# romance_accept/reject stage machine.
static func on_line_spoken(speaker_id: String, target_id: String, intent: String) -> void:
	if speaker_id == "" or target_id == "" or speaker_id == target_id:
		return
	match intent:
		"romance_hint":
			set_romance_stage(speaker_id, target_id, "hinted")
			return
		"romance_advance":
			set_romance_stage(speaker_id, target_id, "advancing")
			return
		"romance_accept":
			set_romance_stage(speaker_id, target_id, "accepted")
			adjust_affinity(speaker_id, target_id, ROMANCE_ACCEPT_AFFINITY, "romance_accept")
			add_flag(speaker_id, target_id, "couple")
			EventBus.crew_romance_started.emit(speaker_id, target_id)
			return
		"romance_reject":
			set_romance_stage(speaker_id, target_id, "none")
			_entry(speaker_id, target_id)["rejected_until"] = TimeManager.elapsed + REJECT_COOLDOWN_SECONDS
			adjust_affinity(speaker_id, target_id, ROMANCE_REJECT_AFFINITY, "romance_reject")
			return
	if LINE_INTENT_AFFINITY.has(intent):
		adjust_affinity(speaker_id, target_id, float(LINE_INTENT_AFFINITY[intent]), intent)


static func on_conversation_ended(a: String, b: String) -> void:
	adjust_affinity(a, b, CONVERSATION_AFFINITY, "conversation")


# Bystanders in the same room as a crew member who just started panicking get snapped at.
static func on_crew_panicked(crew_id: String) -> void:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	if crew == null:
		return
	var room: RoomBase = GameState.rooms.get(crew.location) as RoomBase
	if room == null:
		return
	for other_id: String in room.occupants:
		if other_id == crew_id:
			continue
		adjust_affinity(crew_id, other_id, PANIC_SNAP_AFFINITY, "panic_snap")


# Ship-wide small bump across every pair of living crew — "shared crisis survived".
# Simplification: applied to every living pair rather than tracking exactly who was
# present for which crisis beat; documented as intentional (see CLAUDE.md session note).
static func on_crisis_resolved() -> void:
	var ids: Array = []
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew != null and crew.is_alive:
			ids.append(crew_id)
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			adjust_affinity(ids[i], ids[j], CRISIS_SURVIVED_AFFINITY, "crisis_resolved")


# Heavy grief/stress hit for the surviving partner of a crew member who just died.
static func on_crew_died(crew_id: String) -> void:
	var partner_id: String = partner_of(crew_id)
	if partner_id == "":
		return
	var partner: CrewMember = GameState.crew.get(partner_id) as CrewMember
	if partner == null or not partner.is_alive:
		return
	partner.add_stress(6, "death")  # source tag lets Hardened's stress_mult apply here too
	partner.pain = clampf(partner.pain + 0.4, 0.0, 1.0)
	partner.loneliness = clampf(partner.loneliness + 0.5, 0.0, 1.0)
	partner.fear = clampf(partner.fear + 0.3, 0.0, 1.0)
	add_flag(crew_id, partner_id, "lost_partner")
