class_name ShuttleSystem
extends Node

# Away-op orchestrator (docs/mission-system-spec.md §6/§7). Node child MissionManager
# creates/owns in its own _ready() (unconditionally — see mission_manager.gd), so it's
# always safe to reach via MissionManager.shuttle_system regardless of mission_mode.
#
# Owns two things:
#  1. The shuttle ENTITY: state bayed|outbound|on_site|inbound|lost, shuttle_hull 0-100
#     (damage from AwayResolver's shuttle_strain beats; repairable via RepairModel target
#     "shuttle" — see repair_model.gd). Only meaningful for site=="surface" ops; boarding
#     ops (derelict/station/other_ship, via the airlock) never move the physical shuttle,
#     they just send crew off_ship the same way.
#  2. The away-op FLOW: quorum (issue an away_op AIDirective — spec §6 step 1 — to a
#     capped candidate pool, let ObedienceEngine/DirectiveEvaluator decide per crew member
#     exactly like any other directive, tally accept/reject), muster (reuses the EXISTING
#     move_to_room directive-acceptance path — DirectiveActionHandler already walks a crew
#     member to d.move_to_room the moment they accept, so no new movement code is needed
#     here, just d.move_to_room = the bay/airlock and a room_entered tally), departure
#     choreography (barks, then hide/off_ship), the AwayResolver op itself, and return
#     choreography (barks, then un-hide/clear off_ship) before EventBus.shuttle_returned.
#
# Architecture Rule 1 is respected throughout: crew are never moved or hidden until THEY
# accept the away_op directive (quorum) and THEN physically arrive at the muster room
# (their own CrewMemberNode walking there, same as any other accepted directive).

const STATE_BAYED: String = "bayed"
const STATE_OUTBOUND: String = "outbound"
const STATE_ON_SITE: String = "on_site"
const STATE_INBOUND: String = "inbound"
const STATE_LOST: String = "lost"

const MUSTER_TIMEOUT: float = 90.0        # safety cap waiting for the team to reach the bay/airlock
const PREP_SECONDS: float = 6.0           # shuttle_ops_prep -> launch beat gap (surface only)
const DEPART_BARK_STAGGER: float = 1.6    # seconds between each departing crew member's away_depart bark
const DEPART_HIDE_GRACE: float = 0.8      # extra beat after the last away_depart bark before nodes hide
const RETURN_PREP_SECONDS: float = 4.0    # shuttle_ops_land lead-in (surface only)
const RETURN_BARK_STAGGER: float = 1.6

var state: String = STATE_BAYED
var shuttle_hull: float = 100.0

var _rng: RandomNumberGenerator = null

# --- Quorum request (spec §6 step 1) ---
var _request_active: bool = false
var _request_id: String = ""
var _request_site: String = ""
var _request_min_crew: int = 0
var _request_candidates: Array[String] = []
var _request_responses: Dictionary = {}   # crew_id -> bool accepted

# --- Muster (walking to the bay/airlock) ---
var _mustering: bool = false
var _muster_room: String = ""
var _muster_team: Array[String] = []      # the full accepted team for the current muster
var _muster_pending: Array[String] = []   # subset of _muster_team not yet arrived
var _muster_elapsed: float = 0.0

# --- Departure choreography ---
var _departing: bool = false

# --- Active op ---
var _resolver: AwayResolver = null
var _op_team: Array[String] = []
var _op_site: String = ""
var _op_min_crew: int = 0

# --- Return choreography ---
var _returning: bool = false


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.directive_accepted.connect(_on_directive_accepted)
	EventBus.directive_rejected.connect(_on_directive_rejected)
	EventBus.room_entered.connect(_on_room_entered)


static func away_fast() -> bool:
	return OS.get_environment("SHIPAI_AWAY_FAST") == "1"


func scale_duration(seconds: float) -> float:
	return seconds / 10.0 if away_fast() else seconds


func is_busy() -> bool:
	return _request_active or _mustering or _departing or _resolver != null or _returning


# --- Eligibility (read by EnvironmentMenu to gate the "Send Away Team" entry) ---
# Returns {ok, reason, objective, site, muster_room}.
func can_launch_info() -> Dictionary:
	if is_busy():
		return {"ok": false, "reason": "An away op is already underway.", "objective": {}}
	var objective: Dictionary = MissionManager.active_away_team_objective()
	if objective.is_empty():
		return {"ok": false, "reason": "No open away-team objective.", "objective": {}}
	var params: Dictionary = objective.get("params", {})
	var site: String = String(params.get("site", "surface"))
	var muster_room: String = _muster_room_for(site)
	if muster_room == "":
		return {"ok": false,
			"reason": "No %s aboard this ship." % ("shuttlebay" if site == "surface" else "airlock"),
			"objective": objective}
	if site == "surface" and state != STATE_BAYED:
		return {"ok": false, "reason": "The shuttle isn't bayed.", "objective": objective}
	if site != "surface" and not MissionManager.is_docked():
		return {"ok": false, "reason": "Not docked — cannot board.", "objective": objective}
	return {"ok": true, "reason": "", "objective": objective, "site": site, "muster_room": muster_room}


func _muster_room_for(site: String) -> String:
	var room_type: String = "shuttlebay" if site == "surface" else "airlock"
	return GameState.get_room_of_type(room_type)


# --- Request (spec §6 step 1) — called by EnvironmentMenu's "Send Away Team" button ---

func request_away_op() -> Dictionary:
	var info: Dictionary = can_launch_info()
	if not bool(info.get("ok", false)):
		return info

	var objective: Dictionary = info["objective"]
	var params: Dictionary = objective.get("params", {})
	var site: String = String(info["site"])
	var min_crew: int = int(params.get("min_crew", 1))
	var suggested: Array = params.get("suggested_skills", [])
	var muster_room: String = String(info["muster_room"])

	var candidates: Array[String] = _pick_candidates(min_crew, suggested)
	if candidates.size() < min_crew:
		return {"ok": false, "reason": "Not enough available crew (%d needed)." % min_crew}

	_request_active = true
	_request_id = "away_%d" % Time.get_ticks_msec()
	_request_site = site
	_request_min_crew = min_crew
	_request_candidates = candidates
	_request_responses = {}
	_muster_room = muster_room

	var site_label: String = _site_label(site)
	for crew_id: String in candidates:
		var d := AIDirective.new()
		d.type = AIDirective.Type.RECOMMENDATION
		d.target_type = AIDirective.TargetType.CREW
		d.target_id = crew_id
		d.content = "Away team requested — %s. Report to the %s." % [site_label, _room_display(muster_room)]
		d.confidence = 0.8
		d.priority = 3
		d.move_to_room = muster_room
		d.away_op_site = site
		d.away_op_request_id = _request_id
		if not AISystem.issue_directive(d):
			_request_responses[crew_id] = false   # blocked (AI core down / access denied) — counts as a no

	print("[AWAY] muster requested — site=%s min_crew=%d candidates=%s" % [site, min_crew, candidates])
	_check_quorum_complete()   # in case every candidate above got blocked synchronously
	return {"ok": true, "reason": ""}


# Best-fit candidate pool: living, aboard, not incapacitated/frozen, ranked by
# suggested_skills bonus (best first), capped at min_crew+1 (spec: "up to min_crew+1").
func _pick_candidates(min_crew: int, suggested_skills: Array) -> Array[String]:
	var eligible: Array[String] = []
	for crew_id: String in GameState.crew:
		var c: CrewMember = GameState.crew[crew_id] as CrewMember
		if c == null or not c.is_alive or c.off_ship:
			continue
		if c.current_state in [CrewStateMachine.INCAPACITATED, CrewStateMachine.FROZEN]:
			continue
		eligible.append(crew_id)
	eligible.sort_custom(func(a: String, b: String) -> bool:
		var ca: CrewMember = GameState.crew[a] as CrewMember
		var cb: CrewMember = GameState.crew[b] as CrewMember
		var ba: int = ca.best_skill_bonus(suggested_skills)
		var bb: int = cb.best_skill_bonus(suggested_skills)
		if ba != bb:
			return ba > bb
		return a < b)
	var cap: int = min_crew + 1
	return eligible.slice(0, mini(cap, eligible.size()))


func _on_directive_accepted(crew_id: String, directive: Resource) -> void:
	var d := directive as AIDirective
	if d == null or d.away_op_request_id == "" or d.away_op_request_id != _request_id:
		return
	_request_responses[crew_id] = true
	_check_quorum_complete()


func _on_directive_rejected(crew_id: String, directive: Resource, _reason: String) -> void:
	var d := directive as AIDirective
	if d == null or d.away_op_request_id == "" or d.away_op_request_id != _request_id:
		return
	_request_responses[crew_id] = false
	_check_quorum_complete()


func _check_quorum_complete() -> void:
	if not _request_active or _request_responses.size() < _request_candidates.size():
		return
	var accepted: Array[String] = []
	for crew_id: String in _request_candidates:
		if bool(_request_responses.get(crew_id, false)):
			accepted.append(crew_id)
	_request_active = false

	if accepted.size() < _request_min_crew:
		print("[AWAY] quorum FAILED — %d/%d volunteered" % [accepted.size(), _request_min_crew])
		EventBus.objective_changed.emit("Away team could not be crewed — not enough volunteers.")
		return

	print("[AWAY] quorum met — team=%s" % [accepted])
	_op_site = _request_site
	_op_min_crew = _request_min_crew
	_begin_muster(accepted)


# --- Muster (spec §6 step 1: "willing crew walk to shuttlebay/airlock") ---
# Movement itself is free — DirectiveActionHandler already started every accepted crew
# member walking to d.move_to_room the instant they accepted (see _on_directive_accepted
# above firing before this). This just waits for them to physically arrive.

func _begin_muster(team: Array[String]) -> void:
	_mustering = true
	_muster_team = team.duplicate()
	_muster_pending = team.duplicate()
	_muster_elapsed = 0.0
	for crew_id: String in team:
		var c: CrewMember = GameState.crew.get(crew_id) as CrewMember
		if c != null and c.location == _muster_room:
			_muster_pending.erase(crew_id)   # already there — no room_entered will fire for them
	_try_finish_muster()


func _on_room_entered(crew_id: String, room_id: String) -> void:
	if not _mustering or room_id != _muster_room:
		return
	_muster_pending.erase(crew_id)
	_try_finish_muster()


func _try_finish_muster() -> void:
	if not _mustering or not _muster_pending.is_empty():
		return
	_mustering = false
	_begin_departure(_muster_team)


# --- Departure choreography ---

func _begin_departure(team: Array[String]) -> void:
	_departing = true
	_op_team = team.duplicate()
	if _op_site == "surface":
		DialogueSystem.speak_intent(_pick_speaker(team), "shuttle_ops_prep")
	get_tree().create_timer(scale_duration(PREP_SECONDS)).timeout.connect(_execute_departure)


func _execute_departure() -> void:
	var team: Array[String] = _op_team
	var site: String = _op_site
	var target_name: String = _site_target_name()

	if site == "surface":
		state = STATE_OUTBOUND
		DialogueSystem.speak_intent(_pick_speaker(team), "shuttle_ops_launch")
		EventBus.shuttle_departed.emit(team, site)
	else:
		EventBus.boarding_started.emit(team, target_name)

	var stagger: float = 0.0
	for crew_id: String in team:
		var cid: String = crew_id   # fresh local per iteration — safe lambda capture
		get_tree().create_timer(scale_duration(stagger)).timeout.connect(func():
			DialogueSystem.speak_intent(cid, "away_depart_%s" % site))
		stagger += DEPART_BARK_STAGGER

	get_tree().create_timer(scale_duration(stagger + DEPART_HIDE_GRACE)).timeout.connect(func():
		for crew_id2: String in team:
			var c: CrewMember = GameState.crew.get(crew_id2) as CrewMember
			if c == null:
				continue
			c.off_ship = true
			var node: CrewMemberNode = CrewMemberNode.nodes.get(crew_id2) as CrewMemberNode
			if node:
				node.set_off_ship(true)
		if site == "surface":
			state = STATE_ON_SITE
		_departing = false
		_start_resolver(team, site))


func _start_resolver(team: Array[String], site: String) -> void:
	if _rng == null:
		_rng = RandomNumberGenerator.new()
		_rng.seed = MissionManager.rng.randi() if MissionManager.rng != null else randi()
	var mission: MissionDef = MissionManager.current_mission
	_resolver = AwayResolver.new(team, site, mission, self, _rng, away_fast())
	print("[AWAY] op begins — site=%s team=%s tier=%s duration=%.1fs beats=%d" % [
		site, team, _resolver.tier, _resolver.duration, _resolver.beat_times.size()])


# --- Shuttle hull (spec §7 — RepairModel target "shuttle") ---

func apply_hull_strain(amount: float) -> void:
	if amount <= 0.0:
		return
	shuttle_hull = clampf(shuttle_hull - amount, 0.0, 100.0)


func repair_hull(amount: float) -> void:
	if amount <= 0.0:
		return
	shuttle_hull = clampf(shuttle_hull + amount, 0.0, 100.0)
	if state == STATE_LOST and shuttle_hull > 0.0:
		state = STATE_BAYED


# --- Tick: advance the active resolver + muster timeout safety net ---

func _on_tick(_elapsed: float, delta: float) -> void:
	if _mustering:
		_muster_elapsed += delta
		# Deliberately NOT scale_duration()'d — SHIPAI_AWAY_FAST compresses the AWAY-OP
		# ITSELF (spec: "all op durations /10"), not how long it takes a crew member to
		# physically walk to the bay/airlock, which is governed by CrewMemberNode.MOVE_SPEED
		# and ship layout regardless of the fast flag.
		if _muster_elapsed >= MUSTER_TIMEOUT:
			_muster_timeout()
			return
	if _resolver != null:
		_resolver.tick(delta)
		if _resolver.is_complete():
			_finish_op()


func _muster_timeout() -> void:
	_mustering = false
	var arrived: Array[String] = []
	for crew_id: String in _muster_team:
		if crew_id not in _muster_pending:
			arrived.append(crew_id)
	if arrived.size() < _op_min_crew:
		print("[AWAY] muster TIMED OUT — only %d/%d reached the muster point, scrubbing" % [arrived.size(), _op_min_crew])
		EventBus.objective_changed.emit("Away team scrubbed — the team didn't reach the muster point in time.")
		return
	print("[AWAY] muster timed out with %d/%d present — departing anyway" % [arrived.size(), _muster_team.size()])
	_begin_departure(arrived)


# --- Return choreography (spec §6 step 3) ---

var _return_report: Dictionary = {}

func _finish_op() -> void:
	var report: Dictionary = _resolver.build_report()
	_resolver = null
	_return_report = report
	_returning = true

	if bool(report.get("lost", false)):
		var site: String = _op_site
		MissionManager.campaign_flags["crew_stranded_%s" % site] = true
		if site == "surface":
			state = STATE_LOST
		print("[AWAY] OUTCOME: LOST — %s stranded at %s" % [report.get("team_ids", []), site])
		_returning = false
		_op_team = []
		_op_site = ""
		EventBus.shuttle_returned.emit(report)
		return

	if _op_site == "surface":
		state = STATE_INBOUND
	get_tree().create_timer(scale_duration(RETURN_PREP_SECONDS)).timeout.connect(_execute_return)


func _execute_return() -> void:
	var report: Dictionary = _return_report
	var team: Array = report.get("returning_crew_ids", [])

	if _op_site == "surface":
		DialogueSystem.speak_intent(_pick_speaker(team), "shuttle_ops_land")

	# Survivor (spec §6/step 4's crew-gain mechanic): board them into the roster + spawn a
	# visual node BEFORE unhiding the returning team, so they appear together.
	var survivor: CrewMember = report.get("survivor_crew", null)
	if survivor != null and not GameState.crew.has(survivor.crew_id):
		_board_survivor(survivor)

	for crew_id: String in team:
		var c: CrewMember = GameState.crew.get(crew_id) as CrewMember
		if c == null:
			continue
		c.off_ship = false
		var node: CrewMemberNode = CrewMemberNode.nodes.get(crew_id) as CrewMemberNode
		if node:
			node.set_off_ship(false)

	if _op_site == "surface":
		state = STATE_BAYED

	var outcomes: Dictionary = report.get("crew_outcomes", {})
	var stagger: float = 0.0
	for crew_id: String in team:
		var cid: String = crew_id
		var outcome: String = String(outcomes.get(cid, "fine"))
		get_tree().create_timer(scale_duration(stagger)).timeout.connect(func():
			DialogueSystem.speak_intent(cid, "away_return_%s" % outcome))
		stagger += RETURN_BARK_STAGGER

	print("[AWAY] shuttle_returned — returning=%s hull=%.0f items=%s credits=%.0f survivor=%s" % [
		team, shuttle_hull, report.get("items_found", []), report.get("credits_found", 0.0),
		report.get("survivor_id", "")])

	_returning = false
	_op_team = []
	_op_site = ""
	EventBus.shuttle_returned.emit(report)


const CREW_SCENE: String = "res://scenes/crew/CrewMember.tscn"

func _board_survivor(survivor: CrewMember) -> void:
	survivor.location = _muster_room
	GameState.crew[survivor.crew_id] = survivor
	GameState.set_ai_trust(survivor.crew_id, 0.35)   # a stranger just brought aboard — trust starts low, not default
	var room: RoomBase = GameState.rooms.get(_muster_room) as RoomBase
	if room:
		room.occupants.append(survivor.crew_id)
	var crew_scene: PackedScene = load(CREW_SCENE)
	if crew_scene == null:
		return
	var node: CrewMemberNode = crew_scene.instantiate()
	node.crew_data = survivor
	get_tree().current_scene.get_node("ShipDeck").add_child(node)


# --- Small text helpers ---

func _pick_speaker(team: Array) -> String:
	if team.is_empty():
		return ""
	return String(team[randi() % team.size()])


func _site_label(site: String) -> String:
	match site:
		"surface": return "surface op"
		"derelict": return "derelict boarding"
		"station": return "station boarding"
		"other_ship": return "boarding op"
		_: return site.capitalize()


func _site_target_name() -> String:
	if MissionManager.current_mission != null:
		var dest_name: String = String(MissionManager.current_mission.destination.get("name", ""))
		if dest_name != "":
			return dest_name
	return _op_site.capitalize()


func _room_display(room_id: String) -> String:
	if room_id == "corridor_main":
		return "Corridor"
	return room_id.capitalize()
