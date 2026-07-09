extends Node

# Emergent dialogue runtime (docs/dialogue_spec.md "Runtime selection" is the implementation
# spec for everything below). Autoload (appended last in project.godot — the corpus/other
# crew-facing autoloads it reads from, CrewSystem/GameState/EventBus/TimeManager, are all
# already up by then). Loads the READ-ONLY corpus under resources/dialogue/ at startup with
# defensive parsing (skip invalid entries, log, keep whatever loaded — a missing or partially
# broken corpus degrades to silence, never a crash), then drives two things every tick:
#   - DECLARATIONS: a per-crew idle-timer-fired open-air line (target: open_air), scaled by
#     stress. Per the spec's Display section these are always rendered as THOUGHT bubbles
#     (no sound, italic/dimmed) — see CrewMemberNode's handling of EventBus.line_spoken with
#     line_type == "declaration".
#   - CONVERSATIONS: two free crew sharing a room may start one (a periodic scan, chance
#     weighted by CrewSchedule phase — recreation-phase crew chat far more readily than
#     crew mid-shift). A matching conversation template is preferred; otherwise an emergent
#     opener->reply->...->closer chain (3-6 parts) is built turn by turn. Every line — thought
#     or speech — routes through the same scoring/hard-filter net (_score below).
#
# Nothing here sets crew position/state (Rule 1) — it only reads CrewMember/GameState and
# emits EventBus signals; CrewMemberNode/other systems react to those independently.

const HARD_FAIL: float = -999999.0
const TOP_SCORE_MARGIN: float = 1.0  # weighted-random pick among candidates within this of the best score

const REPETITION_WINDOW_SECONDS: float = 600.0   # "said in last 10 min by anyone" — exact spec figure
const RECENT_EVENT_WINDOW_SECONDS: float = 180.0  # "occurred in last N minutes" — spec leaves N open; 3 min chosen to match the pace of ship crises

const DECLARATION_BASE_INTERVAL: float = 45.0   # calm (min stress) average gap between mutters
const DECLARATION_MIN_INTERVAL: float = 12.0    # floor even at max stress — stressed crew mutter more
const DECLARATION_STRESS_SPAN: float = 18.0     # crew.stress ranges ~2..20 (CLAUDE.md)

const CONVO_SCAN_INTERVAL: float = 4.0
const CONVO_CHANCE_WORK: float = 0.12        # either party mid-shift: rare, brief
const CONVO_CHANCE_MIXED: float = 0.35
const CONVO_CHANCE_RECREATION: float = 0.65  # both off duty and socialising: frequent
const CONVO_LINE_GAP_BASE: float = 2.5
const CONVO_LINE_GAP_PER_CHAR: float = 0.045
const CONVO_LINE_GAP_MAX: float = 7.0
const EMERGENT_LEN_MIN: int = 3
const EMERGENT_LEN_MAX: int = 6

const ROMANCE_INTENTS: Array[String] = ["romance_hint", "romance_advance", "romance_accept", "romance_reject"]

# Dialogue-spec dimension codes <-> CrewMember's own authoritative fields, so a line's
# "target"/participant spec (an archetype tag OR a 2-3 letter career/rank code OR "any")
# can be checked against any live or referenced crew member.
const CAREER_TO_CODE: Dictionary = {
	"scientist_medic": "SCI", "android": "AND", "teamster_engineer": "ENG", "marine": "MAR",
}
const RANK_TO_CODE: Dictionary = {"captain": "CA", "officer": "OF", "crew_mate": "CM"}
const CLASS_TO_CAREER_CODE: Dictionary = {
	"Scientist": "SCI", "Android": "AND", "Teamster": "ENG", "Marine": "MAR",
}

# --- Loaded corpus (read-only resources/dialogue/**; see _load_corpus) ---
var _archetype_dims: Dictionary = {}       # tag -> {"career_code": String, "rank_code": String}
var _lines_by_tag: Dictionary = {}         # archetype tag -> Array[Dictionary]
var _line_by_key: Dictionary = {}          # "TAG#00042" -> Dictionary
var _lines_by_career_code: Dictionary = {} # "SCI"/"AND"/"ENG"/"MAR" -> Array[Dictionary] (fallback pool)
var _convo_templates: Array = []           # Array[Dictionary]
var _tag_regex: RegEx

# --- Runtime state ---
var _recent_events: Array = []       # [{"id": String, "at": float}], oldest first
var _recently_said: Dictionary = {}  # line key -> TimeManager.elapsed when last spoken
var _declaration_timer: Dictionary = {}       # crew_id -> seconds remaining
var _crew_in_conversation: Dictionary = {}    # crew_id -> active conversation key
var _active_conversations: Dictionary = {}    # key -> {room, queue, index, timer}
var _convo_scan_timer: float = 0.0
var _convo_seq: int = 0


func _ready() -> void:
	_tag_regex = RegEx.new()
	if _tag_regex.compile("\\[[A-Z ]+\\]\\s?") != OK:
		push_warning("DialogueSystem: emotive-tag regex failed to compile — display text will keep [TAGS].")
		_tag_regex = null
	_load_corpus()
	EventBus.recent_event.connect(_on_recent_event)
	EventBus.time_ticked.connect(_on_tick)


# --- Corpus loading (defensive: skip invalid, log, keep whatever loaded) ---

func _load_corpus() -> void:
	_load_archetypes()
	_load_lines()
	_load_conversations()
	print("[DIALOGUE] loaded %d archetypes, %d lines (%d archetype pools), %d conversation templates" % [
		_archetype_dims.size(), _line_by_key.size(), _lines_by_tag.size(), _convo_templates.size()])


func _load_archetypes() -> void:
	var dir_path: String = "res://resources/dialogue/archetypes/"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("DialogueSystem: no archetypes/ directory — dialogue will be inert (no lines can be pooled by tag).")
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			_load_one_archetype(dir_path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()


func _load_one_archetype(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		push_warning("DialogueSystem: could not read archetype file %s — skipped." % path)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("DialogueSystem: archetype file %s is not a JSON object — skipped." % path)
		return
	var dict: Dictionary = parsed
	var tag: String = String(dict.get("tag", ""))
	if tag == "":
		push_warning("DialogueSystem: archetype file %s has no tag — skipped." % path)
		return
	var dims: Dictionary = dict.get("dimensions", {})
	_archetype_dims[tag] = {
		"career_code": String(CAREER_TO_CODE.get(String(dims.get("career", "")), "")),
		"rank_code": String(RANK_TO_CODE.get(String(dims.get("rank", "")), "")),
	}


const VALID_LINE_TYPES: Array[String] = ["declaration", "opener", "reply", "closer"]


func _load_lines() -> void:
	var dir_path: String = "res://resources/dialogue/lines/"
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("DialogueSystem: no lines/ directory — dialogue will be inert.")
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json"):
			_load_one_line_file(dir_path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	# Build the career-fallback pools once all archetype pools are known — "crew with no
	# archetype lines fall back to any same-career pool" (spec).
	for tag: String in _lines_by_tag:
		var cc: String = String(_archetype_dims.get(tag, {}).get("career_code", ""))
		if cc == "":
			continue
		if not _lines_by_career_code.has(cc):
			_lines_by_career_code[cc] = []
		(_lines_by_career_code[cc] as Array).append_array(_lines_by_tag[tag])


func _load_one_line_file(path: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		push_warning("DialogueSystem: could not read line file %s — skipped." % path)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		push_warning("DialogueSystem: line file %s is not a JSON array — skipped." % path)
		return
	for entry: Variant in (parsed as Array):
		_load_one_line(entry, path)


func _load_one_line(entry: Variant, source_path: String) -> void:
	if not (entry is Dictionary):
		push_warning("DialogueSystem: non-object line entry in %s — skipped." % source_path)
		return
	var line: Dictionary = entry
	var key: String = String(line.get("key", ""))
	var text: String = String(line.get("text", ""))
	var line_type: String = String(line.get("type", ""))
	var intent: String = String(line.get("intent", ""))
	if key == "" or text == "" or line_type not in VALID_LINE_TYPES or intent == "":
		push_warning("DialogueSystem: malformed line (key='%s') in %s — skipped." % [key, source_path])
		return
	# Normalize optional fields defensively rather than trusting the corpus shape exactly.
	if not (line.get("conditions") is Dictionary):
		line["conditions"] = {}
	if not (line.get("reply_to_intents") is Array):
		line["reply_to_intents"] = []
	if not (line.get("weight") is float) and not (line.get("weight") is int):
		line["weight"] = 1.0
	var tag: String = _tag_from_key(key)
	if not _lines_by_tag.has(tag):
		_lines_by_tag[tag] = []
	(_lines_by_tag[tag] as Array).append(line)
	_line_by_key[key] = line


func _load_conversations() -> void:
	var path: String = "res://resources/dialogue/conversations/convos_core.json"
	var text: String = FileAccess.get_file_as_string(path)
	if text == "":
		push_warning("DialogueSystem: could not read %s — template conversations disabled, emergent chaining still works." % path)
		return
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Array):
		push_warning("DialogueSystem: %s is not a JSON array — template conversations disabled." % path)
		return
	for entry: Variant in (parsed as Array):
		if not (entry is Dictionary):
			continue
		var tmpl: Dictionary = entry
		var participants: Array = tmpl.get("participants", [])
		var lines: Array = tmpl.get("lines", [])
		if participants.size() != 2 or lines.is_empty():
			push_warning("DialogueSystem: malformed conversation template '%s' — skipped." % String(tmpl.get("convo_id", "?")))
			continue
		if not (tmpl.get("conditions") is Dictionary):
			tmpl["conditions"] = {}
		_convo_templates.append(tmpl)


func _tag_from_key(key: String) -> String:
	return key.get_slice("#", 0) if "#" in key else key


# --- Recent-events window (feeds the "recent_event_match" scoring term) ---

func _on_recent_event(event_id: String, _data: Dictionary) -> void:
	_recent_events.append({"id": event_id, "at": TimeManager.elapsed})


func _prune_recent_events() -> void:
	var cutoff: float = TimeManager.elapsed - RECENT_EVENT_WINDOW_SECONDS
	while not _recent_events.is_empty() and float(_recent_events[0]["at"]) < cutoff:
		_recent_events.pop_front()


func _any_recent_event(names: Array) -> bool:
	for e: Dictionary in _recent_events:
		if String(e["id"]) in names:
			return true
	return false


# --- Repetition tracking ---

func _mark_said(key: String) -> void:
	if key != "":
		_recently_said[key] = TimeManager.elapsed


func _said_recently(key: String) -> bool:
	if not _recently_said.has(key):
		return false
	return TimeManager.elapsed - float(_recently_said[key]) < REPETITION_WINDOW_SECONDS


# --- Identity helpers (archetype tag / career code / rank code) ---

func _career_code_for(crew: CrewMember) -> String:
	return String(CLASS_TO_CAREER_CODE.get(crew.mship_class, ""))


func _rank_code_for(crew: CrewMember) -> String:
	return String(RANK_TO_CODE.get(crew.rank, ""))


func _mood_for(crew: CrewMember) -> String:
	if crew.morale >= 0.75:
		return "high"
	if crew.morale >= 0.45:
		return "ok"
	if crew.morale >= 0.2:
		return "low"
	return "grim"


func _room_type_of(room_id: String) -> String:
	var room: RoomBase = GameState.rooms.get(room_id) as RoomBase
	return room.room_function if room != null else ""


# spec == "any" always matches; otherwise matches an exact archetype tag, career code, or
# rank code. Used both for line "target" conditions and conversation-template participants.
func _spec_matches(spec: String, tag: String, career_code: String, rank_code: String) -> bool:
	if spec == "any":
		return true
	if spec == tag and tag != "":
		return true
	if spec == career_code and career_code != "":
		return true
	if spec == rank_code and rank_code != "":
		return true
	return false


func _pool_for(crew: CrewMember, type_filter: String) -> Array:
	var pool: Array = []
	if crew.archetype_tag != "" and _lines_by_tag.has(crew.archetype_tag) and not (_lines_by_tag[crew.archetype_tag] as Array).is_empty():
		pool = _lines_by_tag[crew.archetype_tag]
	else:
		pool = _lines_by_career_code.get(_career_code_for(crew), [])
	if pool.is_empty():
		return []
	var filtered: Array = []
	for line: Dictionary in pool:
		if String(line.get("type", "")) == type_filter:
			filtered.append(line)
	return filtered


# --- Romance gate (spec: "Romance intents gate through the relationship graph") ---

func _romance_gate_ok(intent: String, speaker_id: String, addressee_id: String) -> bool:
	if addressee_id == "" or intent not in ROMANCE_INTENTS:
		return true
	match intent:
		"romance_hint":
			return RelationshipGraph.can_hint(speaker_id, addressee_id)
		"romance_advance":
			return RelationshipGraph.can_advance(speaker_id, addressee_id)
		"romance_accept":
			return RelationshipGraph.would_accept(speaker_id, addressee_id)
		"romance_reject":
			return not RelationshipGraph.would_accept(speaker_id, addressee_id)
	return true


# --- Scoring (docs/dialogue_spec.md "Runtime selection") ---
#
# score = weight + 2.0*recent_event + 1.0*location + 1.0*target + 1.0*mood
#         + 0.5*stress_band_closeness - 5.0 if said in the last 10 min
# Hard filters (never scored, return HARD_FAIL instead): panic flag, stress bounds,
# wounded, reply_to_intents when answering, and the romance gate.
func _score(crew: CrewMember, line: Dictionary, ctx: Dictionary) -> float:
	var cond: Dictionary = line.get("conditions", {})

	if cond.has("panic"):
		var want_panic: bool = bool(cond["panic"])
		if want_panic != (crew.current_state == CrewStateMachine.PANICKING):
			return HARD_FAIL
	if cond.has("stress_min") and crew.stress < int(cond["stress_min"]):
		return HARD_FAIL
	if cond.has("stress_max") and crew.stress > int(cond["stress_max"]):
		return HARD_FAIL
	if cond.has("wounded") and cond["wounded"] != null:
		if bool(cond["wounded"]) != (crew.wounds > 0):
			return HARD_FAIL

	var line_type: String = String(line.get("type", ""))
	var reply_to: Array = line.get("reply_to_intents", [])
	var prior_intent: String = String(ctx.get("prior_intent", ""))
	if line_type == "reply":
		if reply_to.is_empty() or prior_intent not in reply_to:
			return HARD_FAIL
	elif line_type == "closer":
		if not reply_to.is_empty() and prior_intent not in reply_to:
			return HARD_FAIL

	if bool(ctx.get("has_addressee", false)):
		if not _romance_gate_ok(String(line.get("intent", "")), crew.crew_id, String(ctx.get("addressee_id", ""))):
			return HARD_FAIL

	var score: float = float(line.get("weight", 1.0))

	var events: Array = cond.get("recent_events", [])
	if not events.is_empty() and _any_recent_event(events):
		score += 2.0

	var locs: Array = cond.get("location", [])
	if not locs.is_empty() and ("any" in locs or String(ctx.get("room_type", "")) in locs):
		score += 1.0

	if _target_specific_match(cond.get("target", []), ctx):
		score += 1.0

	var moods: Array = cond.get("mood", [])
	if not moods.is_empty() and String(ctx.get("mood", "")) in moods:
		score += 1.0

	if cond.has("stress_min") or cond.has("stress_max"):
		score += 0.5 * _stress_band_closeness(cond, crew.stress)

	if _said_recently(String(line.get("key", ""))):
		score -= 5.0

	return score


func _target_specific_match(targets: Array, ctx: Dictionary) -> bool:
	if targets.is_empty() or not bool(ctx.get("has_addressee", false)):
		return false
	for t: Variant in targets:
		var spec: String = String(t)
		if spec == "any" or spec == "open_air":
			continue
		if spec == String(ctx.get("addressee_tag", "")) \
				or spec == String(ctx.get("addressee_career", "")) \
				or spec == String(ctx.get("addressee_rank", "")):
			return true
	return false


func _stress_band_closeness(cond: Dictionary, stress: int) -> float:
	var lo: float = float(cond.get("stress_min", stress))
	var hi: float = float(cond.get("stress_max", stress))
	if hi < lo:
		var tmp: float = lo
		lo = hi
		hi = tmp
	var center: float = (lo + hi) / 2.0
	var half: float = maxf((hi - lo) / 2.0, 1.0)
	var dist: float = clampf(absf(float(stress) - center) / half, 0.0, 1.0)
	return 1.0 - dist


# Weighted-random pick among the top-scoring candidates (within TOP_SCORE_MARGIN of the
# best). Returns the picked line, or {} if every candidate hard-failed.
func _pick_line(crew: CrewMember, pool: Array, ctx: Dictionary) -> Dictionary:
	if pool.is_empty():
		return {}
	var scores: Array = []
	var max_score: float = HARD_FAIL
	for line: Dictionary in pool:
		var s: float = _score(crew, line, ctx)
		scores.append(s)
		if s > max_score:
			max_score = s
	if max_score <= HARD_FAIL / 2.0:
		return {}  # nothing passed the hard filters
	var tier_indices: Array = []
	var tier_weights: Array = []
	var total_w: float = 0.0
	for i in pool.size():
		if scores[i] >= max_score - TOP_SCORE_MARGIN:
			tier_indices.append(i)
			var w: float = maxf(float((pool[i] as Dictionary).get("weight", 1.0)), 0.01)
			tier_weights.append(w)
			total_w += w
	if tier_indices.is_empty():
		return {}
	var roll: float = randf() * total_w
	var acc: float = 0.0
	for k in tier_indices.size():
		acc += float(tier_weights[k])
		if roll <= acc:
			return pool[tier_indices[k]]
	return pool[tier_indices[tier_indices.size() - 1]]


func _addressee_ctx(base_ctx: Dictionary, addressee: CrewMember) -> Dictionary:
	var ctx: Dictionary = base_ctx.duplicate()
	ctx["has_addressee"] = true
	ctx["addressee_id"] = addressee.crew_id
	ctx["addressee_tag"] = addressee.archetype_tag
	ctx["addressee_career"] = _career_code_for(addressee)
	ctx["addressee_rank"] = _rank_code_for(addressee)
	return ctx


func _pick_declaration(crew: CrewMember) -> Dictionary:
	var pool: Array = _pool_for(crew, "declaration")
	if pool.is_empty():
		return {}
	var ctx: Dictionary = {
		"room_type": _room_type_of(crew.location), "mood": _mood_for(crew),
		"has_addressee": false, "prior_intent": "",
	}
	return _pick_line(crew, pool, ctx)


func _pick_opener(speaker: CrewMember, listener: CrewMember, room_id: String) -> Dictionary:
	var pool: Array = _pool_for(speaker, "opener")
	if pool.is_empty():
		return {}
	var ctx: Dictionary = _addressee_ctx(
		{"room_type": _room_type_of(room_id), "mood": _mood_for(speaker), "prior_intent": ""}, listener)
	return _pick_line(speaker, pool, ctx)


func _pick_reply(speaker: CrewMember, listener: CrewMember, room_id: String, prior_intent: String, prefer_closer: bool) -> Dictionary:
	var type_order: Array[String] = ["reply", "closer"]
	if prefer_closer:
		type_order = ["closer", "reply"]
	for t: String in type_order:
		var pool: Array = _pool_for(speaker, t)
		if pool.is_empty():
			continue
		var ctx: Dictionary = _addressee_ctx(
			{"room_type": _room_type_of(room_id), "mood": _mood_for(speaker), "prior_intent": prior_intent}, listener)
		var line: Dictionary = _pick_line(speaker, pool, ctx)
		if not line.is_empty():
			return line
	return {}


# Same-intent same-type substitute from `speaker`'s own pool — used to resolve a
# conversation-template line-slot whose referenced archetype isn't the one actually present
# ("the runtime substitutes lines of matching intent from whichever archetype is actually
# present" — spec).
func _find_matching_intent_line(speaker: CrewMember, type_filter: String, intent_filter: String,
		listener: CrewMember, room_id: String, prior_intent: String) -> Dictionary:
	var pool: Array = _pool_for(speaker, type_filter)
	if pool.is_empty():
		return {}
	var matches: Array = []
	for line: Dictionary in pool:
		if String(line.get("intent", "")) == intent_filter:
			matches.append(line)
	if matches.is_empty():
		return {}
	var ctx: Dictionary = _addressee_ctx(
		{"room_type": _room_type_of(room_id), "mood": _mood_for(speaker), "prior_intent": prior_intent}, listener)
	return _pick_line(speaker, matches, ctx)


func _strip_tags(text: String) -> String:
	if _tag_regex == null:
		return text
	return _tag_regex.sub(text, "", true)


# --- Speaking a line: display + relationship hooks + repetition/declaration-timer upkeep ---

func _speak(speaker: CrewMember, line: Dictionary, addressee_id: String) -> void:
	var key: String = String(line.get("key", ""))
	_mark_said(key)
	var display_text: String = _strip_tags(String(line.get("text", "")))
	var line_type: String = String(line.get("type", "declaration"))
	EventBus.line_spoken.emit(speaker.crew_id, key, display_text, line_type)
	if addressee_id != "":
		RelationshipGraph.on_line_spoken(speaker.crew_id, addressee_id, String(line.get("intent", "")))
	# Having just spoken, don't also immediately fire an unrelated declaration.
	_declaration_timer[speaker.crew_id] = _next_declaration_interval(speaker)


# --- Tick loop ---

func _on_tick(_elapsed: float, delta: float) -> void:
	_prune_recent_events()
	_tick_conversations(delta)
	_tick_declarations(delta)
	_convo_scan_timer -= delta
	if _convo_scan_timer <= 0.0:
		_convo_scan_timer = CONVO_SCAN_INTERVAL
		_scan_for_conversations()


func _next_declaration_interval(crew: CrewMember) -> float:
	var stress_ratio: float = clampf(float(crew.stress - 2) / DECLARATION_STRESS_SPAN, 0.0, 1.0)
	var base: float = lerpf(DECLARATION_BASE_INTERVAL, DECLARATION_MIN_INTERVAL, stress_ratio)
	return base * randf_range(0.7, 1.3)


func _tick_declarations(delta: float) -> void:
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if crew == null or not crew.is_alive:
			continue
		if crew_id in _crew_in_conversation:
			continue
		if crew.current_state in [CrewStateMachine.INCAPACITATED, CrewStateMachine.FROZEN]:
			continue
		if not _declaration_timer.has(crew_id):
			_declaration_timer[crew_id] = randf_range(4.0, DECLARATION_BASE_INTERVAL)
		_declaration_timer[crew_id] = float(_declaration_timer[crew_id]) - delta
		if _declaration_timer[crew_id] > 0.0:
			continue
		_declaration_timer[crew_id] = _next_declaration_interval(crew)
		var line: Dictionary = _pick_declaration(crew)
		if not line.is_empty():
			_speak(crew, line, "")


# --- Conversation triggering ---

func _eligible_for_conversation(crew: CrewMember) -> bool:
	if crew == null or not crew.is_alive:
		return false
	if crew.crew_id in _crew_in_conversation:
		return false
	# IDLE/EATING (mess, downtime) are the obvious cases; WORKING is included too — the
	# corpus's own "work_talk" intent implies on-shift banter, and with one crew member per
	# duty station (see CrewBehavior.DUTY_STATION), excluding WORKING would make the two
	# crew who share a room while working a repair or a scenario-directed task (e.g. the
	# quarantine's medic + patient in medbay) unable to ever talk to each other.
	if crew.current_state not in [CrewStateMachine.IDLE, CrewStateMachine.EATING, CrewStateMachine.WORKING]:
		return false
	# is_busy() (mid-route, or mid a door-bypass attempt) genuinely can't hold a stationary
	# conversation. hold_room_until is deliberately NOT checked here, unlike CrewBehavior's
	# own honouring-directive gate: a crew member holding position for an accepted directive
	# (e.g. the quarantine's "proceed to medbay") can still talk to whoever's standing next
	# to them — hold_room_until only suppresses onward wandering, not speech.
	var node: CrewMemberNode = CrewMemberNode.nodes.get(crew.crew_id) as CrewMemberNode
	return node != null and not node.is_busy()


func _conversation_chance(a: CrewMember, b: CrewMember) -> float:
	var pa: String = CrewSchedule.phase_for(a)
	var pb: String = CrewSchedule.phase_for(b)
	if pa == "work" or pb == "work":
		return CONVO_CHANCE_WORK
	if pa == "recreation" and pb == "recreation":
		return CONVO_CHANCE_RECREATION
	return CONVO_CHANCE_MIXED


func _scan_for_conversations() -> void:
	var by_room: Dictionary = {}
	for crew_id: String in GameState.crew:
		var crew: CrewMember = GameState.crew[crew_id] as CrewMember
		if not _eligible_for_conversation(crew):
			continue
		if not by_room.has(crew.location):
			by_room[crew.location] = []
		(by_room[crew.location] as Array).append(crew_id)
	for room_id: String in by_room:
		var ids: Array = by_room[room_id]
		if ids.size() < 2:
			continue
		ids.shuffle()
		var a: CrewMember = GameState.crew[ids[0]] as CrewMember
		var b: CrewMember = GameState.crew[ids[1]] as CrewMember
		if randf() < _conversation_chance(a, b):
			_start_conversation(a, b, room_id)


func _start_conversation(a: CrewMember, b: CrewMember, room_id: String) -> void:
	var queue: Array = _try_template(a, b, room_id)
	if queue.is_empty():
		queue = _try_emergent(a, b, room_id)
	if queue.is_empty():
		return  # nobody had anything to say this round — try again on a later scan
	var key: String = "convo_%d" % _convo_seq
	_convo_seq += 1
	_active_conversations[key] = {"room": room_id, "queue": queue, "index": 0, "timer": 0.4}
	_crew_in_conversation[a.crew_id] = key
	_crew_in_conversation[b.crew_id] = key
	EventBus.conversation_started.emit(a.crew_id, b.crew_id, room_id)


# --- Conversation templates (participants matched by tag or career/rank code) ---

func _match_participants(participants: Array, a: CrewMember, b: CrewMember) -> Array:
	var a_tag: String = a.archetype_tag
	var a_car: String = _career_code_for(a)
	var a_rank: String = _rank_code_for(a)
	var b_tag: String = b.archetype_tag
	var b_car: String = _career_code_for(b)
	var b_rank: String = _rank_code_for(b)
	var p0: String = String(participants[0])
	var p1: String = String(participants[1])
	if _spec_matches(p0, a_tag, a_car, a_rank) and _spec_matches(p1, b_tag, b_car, b_rank):
		return [a, b]
	if _spec_matches(p0, b_tag, b_car, b_rank) and _spec_matches(p1, a_tag, a_car, a_rank):
		return [b, a]
	return []


func _template_conditions_ok(tmpl: Dictionary, a: CrewMember, b: CrewMember) -> bool:
	var cond: Dictionary = tmpl.get("conditions", {})
	var events: Array = cond.get("recent_events", [])
	if not events.is_empty() and not _any_recent_event(events):
		return false
	if cond.has("stress_min") and maxi(a.stress, b.stress) < int(cond["stress_min"]):
		return false
	if cond.has("stress_max") and mini(a.stress, b.stress) > int(cond["stress_max"]):
		return false
	return true


func _try_template(a: CrewMember, b: CrewMember, room_id: String) -> Array:
	var candidates: Array = []
	for tmpl: Dictionary in _convo_templates:
		var order: Array = _match_participants(tmpl.get("participants", []), a, b)
		if order.is_empty():
			continue
		if not _template_conditions_ok(tmpl, a, b):
			continue
		candidates.append({"tmpl": tmpl, "order": order})
	candidates.shuffle()
	for cand: Dictionary in candidates:
		var order: Array = cand["order"]
		var resolved: Array = _resolve_template_queue(cand["tmpl"], order[0], order[1], room_id)
		if not resolved.is_empty():
			return resolved
	return []


func _resolve_template_queue(tmpl: Dictionary, first: CrewMember, second: CrewMember, room_id: String) -> Array:
	var keys: Array = tmpl.get("lines", [])
	var queue: Array = []
	var prior_intent: String = ""
	for i in keys.size():
		var speaker: CrewMember = first if i % 2 == 0 else second
		var listener: CrewMember = second if i % 2 == 0 else first
		var key: String = String(keys[i])
		var ref_line: Dictionary = _line_by_key.get(key, {})
		if ref_line.is_empty():
			if queue.is_empty():
				return []
			break
		var resolved_line: Dictionary
		if speaker.archetype_tag == _tag_from_key(key):
			resolved_line = ref_line
		else:
			resolved_line = _find_matching_intent_line(
				speaker, String(ref_line.get("type", "")), String(ref_line.get("intent", "")), listener, room_id, prior_intent)
		if resolved_line.is_empty():
			if queue.is_empty():
				return []
			break
		var ctx: Dictionary = _addressee_ctx(
			{"room_type": _room_type_of(room_id), "mood": _mood_for(speaker), "prior_intent": prior_intent}, listener)
		if _score(speaker, resolved_line, ctx) <= HARD_FAIL / 2.0:
			if queue.is_empty():
				return []
			break
		queue.append({"speaker_id": speaker.crew_id, "listener_id": listener.crew_id, "line": resolved_line})
		prior_intent = String(resolved_line.get("intent", ""))
	return queue


# --- Emergent chaining (no matching template): opener -> reply(matches prior intent) ->
# ... -> closer, 3-6 parts, alternating speaker. A panicking or departing participant
# breaks the chain — enforced every turn in _tick_conversations, not just at start.

func _try_emergent(a: CrewMember, b: CrewMember, room_id: String) -> Array:
	var pair_orders: Array = [[a, b], [b, a]]
	pair_orders.shuffle()
	for pair: Array in pair_orders:
		var speaker: CrewMember = pair[0]
		var listener: CrewMember = pair[1]
		var opener: Dictionary = _pick_opener(speaker, listener, room_id)
		if opener.is_empty():
			continue
		var target_len: int = randi_range(EMERGENT_LEN_MIN, EMERGENT_LEN_MAX)
		var queue: Array = [{"speaker_id": speaker.crew_id, "listener_id": listener.crew_id, "line": opener}]
		var cur_speaker: CrewMember = listener
		var cur_listener: CrewMember = speaker
		var prior_intent: String = String(opener.get("intent", ""))
		for turn in range(1, target_len):
			var prefer_closer: bool = turn == target_len - 1
			var reply: Dictionary = _pick_reply(cur_speaker, cur_listener, room_id, prior_intent, prefer_closer)
			if reply.is_empty():
				break
			queue.append({"speaker_id": cur_speaker.crew_id, "listener_id": cur_listener.crew_id, "line": reply})
			prior_intent = String(reply.get("intent", ""))
			if String(reply.get("type", "")) == "closer":
				break
			var tmp: CrewMember = cur_speaker
			cur_speaker = cur_listener
			cur_listener = tmp
		return queue
	return []


# --- Conversation playback ---

func _still_eligible_for_turn(speaker: CrewMember, listener: CrewMember, room_id: String) -> bool:
	if speaker == null or listener == null or not speaker.is_alive or not listener.is_alive:
		return false
	var broken_states: Array[String] = [CrewStateMachine.PANICKING, CrewStateMachine.INCAPACITATED, CrewStateMachine.FROZEN]
	if speaker.current_state in broken_states or listener.current_state in broken_states:
		return false
	return speaker.location == room_id and listener.location == room_id


func _line_gap(text: String) -> float:
	return clampf(CONVO_LINE_GAP_BASE + text.length() * CONVO_LINE_GAP_PER_CHAR, CONVO_LINE_GAP_BASE, CONVO_LINE_GAP_MAX)


func _tick_conversations(delta: float) -> void:
	var to_end: Array = []
	for key: String in _active_conversations.keys():
		var conv: Dictionary = _active_conversations[key]
		conv["timer"] = float(conv["timer"]) - delta
		if conv["timer"] > 0.0:
			continue
		var idx: int = int(conv["index"])
		var queue: Array = conv["queue"]
		if idx >= queue.size():
			to_end.append(key)
			continue
		var entry: Dictionary = queue[idx]
		var speaker: CrewMember = GameState.crew.get(entry["speaker_id"]) as CrewMember
		var listener: CrewMember = GameState.crew.get(entry["listener_id"]) as CrewMember
		if not _still_eligible_for_turn(speaker, listener, String(conv["room"])):
			to_end.append(key)
			continue
		_speak(speaker, entry["line"], listener.crew_id)
		idx += 1
		conv["index"] = idx
		conv["timer"] = _line_gap(String((entry["line"] as Dictionary).get("text", "")))
		_active_conversations[key] = conv
		if idx >= queue.size():
			to_end.append(key)
	for key: String in to_end:
		_end_conversation(key)


func _end_conversation(key: String) -> void:
	var conv: Dictionary = _active_conversations.get(key, {})
	if conv.is_empty():
		return
	_active_conversations.erase(key)
	var queue: Array = conv.get("queue", [])
	if queue.is_empty():
		return
	var a_id: String = String((queue[0] as Dictionary)["speaker_id"])
	var b_id: String = String((queue[0] as Dictionary)["listener_id"])
	_crew_in_conversation.erase(a_id)
	_crew_in_conversation.erase(b_id)
	EventBus.conversation_ended.emit(a_id, b_id)
	RelationshipGraph.on_conversation_ended(a_id, b_id)
