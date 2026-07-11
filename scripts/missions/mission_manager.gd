extends Node

# Autoload MissionManager (docs/mission-system-spec.md — the whole doc, this is the
# core loop's owner). Owns the campaign: which mission is running, its phase clock,
# objective tracking/grading, resolution/rewards, leg-boundary hand-off, and the
# scenario hooks that let the Overseer's covert layer interweave with the overt
# mission layer. Built on task A's foundations (MissionDef/MissionDeck/ScenarioCatalog,
# f982386) — this file adds no new data model, only the runtime state machine that
# drives them.
#
# Registered in project.godot AFTER ScenarioRunner (spec §2) — it reads
# ScenarioDirector.current_leg/effective_heat() and ScenarioRunner.active_scenarios
# reactively (never during its own _ready(), only once begin_campaign() is called
# from main.gd well after every autoload has initialized), so declaration order only
# needs to satisfy "exists as a global name", which Godot guarantees regardless —
# the AFTER ordering here is about reading intent, not a hard dependency.
#
# campaign_flags vs the deck's prev_outcome_flags/prev_follow_ons params (see
# mission_deck.gd's own doc comment on draw()): campaign_flags is the durable,
# cross-leg campaign record (extra_outcome_flags + the derived crew/hull flags below)
# — the stuff future missions' `eligibility` blocks gate on. The three grade flags
# (mission_success/partial/failed) are deliberately kept OUT of campaign_flags and
# passed only as the deck's `prev_outcome_flags` for the very next draw — they're
# generic across every mission (unlike, say, "crew_stranded_surface"), so leaving one
# permanently true in campaign_flags the moment any mission ever succeeds would let
# it silently satisfy `requires_flags_all: ["mission_success"]` forever after,
# regardless of what happened since. Follow_on `"when"` rules that want "the mission
# that just resolved succeeded" get exactly that from prev_outcome_flags each draw;
# nothing in the shipped catalog needs the sticky, forever-true version.

const DOCKING_SECONDS: float = 20.0
const INTERMISSION_SECONDS: float = 10.0
const PHASE_ORDER: Array[String] = ["transit_out", "arrival", "on_station", "transit_back"]

var campaign_flags: Dictionary = {}
var current_mission: MissionDef = null
var mission_phase: String = ""     # "" | transit_out | arrival | on_station | transit_back | resolution
var mission_mode: bool = false
var mission_history: Array[Dictionary] = []   # [{id, outcome, leg}] — completed-mission log

var deck: MissionDeck = null
var rng: RandomNumberGenerator = null

var _objective_states: Dictionary = {}        # objective_id -> "active" | "complete" | "failed"
var _scenario_flags_seen: Dictionary = {}      # flag -> last value seen via EventBus.scenario_flag_set (this mission's lifetime)
var _once_per_run_scenario_ids: Array[String] = []   # once_per_run scenario ids already used this campaign

var _phase_elapsed: float = 0.0
var _aborted: bool = false

var _docking_active: bool = false
var _docking_completed_flag: bool = false
var _docking_elapsed: float = 0.0
var _docking_name: String = ""

var _intermission_active: bool = false
var _intermission_elapsed: float = 0.0
var _prev_outcome_flags: Dictionary = {}       # this-resolution-only grade flag, fed to the NEXT draw() call
var _prev_follow_ons: Array = []               # the just-resolved mission's follow_ons rules, likewise

var _debug: bool = false


func _ready() -> void:
	_debug = OS.get_environment("SHIPAI_MISSION_DEBUG") == "1"
	EventBus.time_ticked.connect(_on_time_ticked)
	EventBus.shuttle_returned.connect(_on_shuttle_returned)
	EventBus.docking_completed.connect(_on_docking_completed)
	EventBus.scenario_flag_set.connect(_on_scenario_flag_set)


# --- Campaign start (spec §12) ---

func begin_campaign(seed_value: int = -1) -> void:
	campaign_flags = {}
	mission_history = []
	_once_per_run_scenario_ids = []
	_prev_outcome_flags = {}
	_prev_follow_ons = []

	var seed_env: String = OS.get_environment("SHIPAI_SEED")
	var use_seed: int = seed_value
	if seed_env != "":
		use_seed = int(seed_env)
	elif use_seed == -1:
		use_seed = randi()
	rng = RandomNumberGenerator.new()
	rng.seed = use_seed

	deck = MissionDeck.new()
	var loaded: int = deck.load_all()
	if loaded == 0:
		push_warning("MissionManager: no missions found in resources/missions — campaign cannot start")
		return
	mission_mode = true

	var forced_id: String = OS.get_environment("SHIPAI_MISSION").strip_edges()
	var opener: MissionDef = null
	if forced_id != "":
		opener = deck.missions.get(forced_id) as MissionDef
		if opener == null:
			push_warning("MissionManager: SHIPAI_MISSION='%s' not found in deck — falling back to opener draw" % forced_id)
	if opener == null:
		opener = _draw_opener()
	if opener == null:
		push_warning("MissionManager: no eligible mission found to open campaign")
		mission_mode = false
		return

	print("[MISSION] campaign begin — seed=%d missions_loaded=%d" % [use_seed, loaded])
	_start_mission(opener)


# Prefers a tag "opener" mission at leg 1 (spec §12); falls back to a normal
# weighted draw if none qualify (e.g. a trimmed-down test deck with no opener tag).
func _draw_opener() -> MissionDef:
	var leg: int = ScenarioDirector.current_leg
	var hull: float = GameState.hull_integrity
	var pool: Array[MissionDef] = deck.eligible(campaign_flags, leg, hull)
	var openers: Array[MissionDef] = []
	for m: MissionDef in pool:
		if "opener" in m.tags:
			openers.append(m)
	if not openers.is_empty():
		var weights: Array[float] = []
		for m: MissionDef in openers:
			weights.append(maxf(m.weight, 0.01))
		return openers[_weighted_pick(weights)]
	return deck.draw(campaign_flags, leg, hull, {}, [], rng)


# --- Mission start / phase clock ---

func _start_mission(mission: MissionDef) -> void:
	current_mission = mission
	_aborted = false
	_objective_states = {}
	_scenario_flags_seen = {}
	_docking_active = false
	_docking_completed_flag = false
	_docking_elapsed = 0.0
	_docking_name = ""

	for obj: Dictionary in mission.objectives:
		_set_objective_state(String(obj.get("id", "")), "active")

	print("[MISSION] started '%s' (%s) giver=%s leg=%d" % [
		mission.id, mission.title, mission.giver, ScenarioDirector.current_leg])
	EventBus.mission_started.emit(mission.id)
	EventBus.objective_changed.emit(_oneline_briefing(mission))
	_enter_phase("transit_out", true)


func _on_time_ticked(_elapsed: float, delta: float) -> void:
	if not mission_mode:
		return

	if _intermission_active:
		_intermission_elapsed += delta
		if _intermission_elapsed >= INTERMISSION_SECONDS:
			_intermission_active = false
			_draw_next_mission()
		return

	if current_mission == null or mission_phase == "" or mission_phase == "resolution":
		return

	_phase_elapsed += delta
	_check_repair_objectives()

	if _docking_active and not _docking_completed_flag:
		_docking_elapsed += delta
		if _docking_elapsed >= DOCKING_SECONDS:
			_docking_completed_flag = true
			EventBus.docking_completed.emit(_docking_name)

	if _phase_elapsed >= _phase_duration(mission_phase):
		_advance_phase()


func _phase_duration(phase: String) -> float:
	if current_mission == null:
		return 180.0
	return float(current_mission.phases.get(phase, 180.0))


# `is_initial`: true only for the transit_out entered straight out of _start_mission
# — skips the phase-text objective_changed overwrite so the briefing one-liner just
# emitted in _start_mission gets a moment on screen instead of being clobbered in the
# same frame. Every side effect (phase-changed signal, hook roll, survive_until
# checks, docking setup) still fires normally regardless of is_initial.
func _enter_phase(phase: String, is_initial: bool = false) -> void:
	mission_phase = phase
	_phase_elapsed = 0.0
	if _debug:
		print("[MISSION] phase -> %s" % phase)
	EventBus.mission_phase_changed.emit(current_mission.id, phase)

	if not is_initial:
		var line: String = _phase_objective_text(phase)
		if line != "":
			EventBus.objective_changed.emit(line)

	_complete_survive_until_objectives(phase)

	match phase:
		"transit_out":
			_try_attach_scenario("transit_out")
		"arrival":
			EventBus.destination_sighted.emit(
				String(current_mission.destination.get("kind", "")),
				String(current_mission.destination.get("name", "")))
			_try_attach_scenario("arrival")
		"on_station":
			var dest_kind: String = String(current_mission.destination.get("kind", ""))
			if dest_kind == "ship" or dest_kind == "station":
				_docking_active = true
				_docking_elapsed = 0.0
				_docking_completed_flag = false
				_docking_name = String(current_mission.destination.get("name", ""))
				EventBus.docking_started.emit(_docking_name)
			_try_attach_scenario("on_station")
		"transit_back":
			_try_attach_scenario("transit_back")
		"resolution":
			_resolve_mission()


func _advance_phase() -> void:
	var leaving: String = mission_phase
	_on_phase_end(leaving)
	var idx: int = PHASE_ORDER.find(leaving)
	var next_phase: String = "resolution"
	if idx != -1 and idx + 1 < PHASE_ORDER.size():
		next_phase = PHASE_ORDER[idx + 1]
	_enter_phase(next_phase)


func _on_phase_end(phase: String) -> void:
	match phase:
		"arrival":
			_complete_objectives_of_kind("reach_destination")
		"on_station":
			_complete_deliver_cargo_objectives()
			if _docking_active:
				EventBus.undocked.emit(_docking_name)
				_docking_active = false


func _phase_objective_text(phase: String) -> String:
	if current_mission == null:
		return ""
	var dest_name: String = String(current_mission.destination.get("name", "the destination"))
	match phase:
		"transit_out":
			return "En route to %s." % dest_name
		"arrival":
			return "Approaching %s." % dest_name
		"on_station":
			return "On station at %s." % dest_name
		"transit_back":
			return "Returning to the shipping lane."
		_:
			return ""


func _oneline_briefing(mission: MissionDef) -> String:
	var brief: String = mission.briefing.strip_edges()
	var cut: int = brief.find(". ")
	var first: String = brief.substr(0, cut + 1) if cut != -1 else brief
	if first.length() > 140:
		first = first.substr(0, 137) + "..."
	return "%s — %s" % [mission.title, first]


# --- Objective tracking (spec §3.2) ---

func _obj_params(obj: Dictionary) -> Dictionary:
	return (obj.get("params", {}) as Dictionary)


func _objective_text(oid: String) -> String:
	if current_mission == null:
		return oid
	for obj: Dictionary in current_mission.objectives:
		if String(obj.get("id", "")) == oid:
			return String(obj.get("text", oid))
	return oid


func _set_objective_state(oid: String, state: String) -> void:
	if oid == "" or current_mission == null:
		return
	if _objective_states.get(oid, "") == state:
		return
	_objective_states[oid] = state
	EventBus.mission_objective_updated.emit(current_mission.id, oid, state)
	if state == "complete":
		print("[MISSION] objective complete: %s" % _objective_text(oid))
		EventBus.objective_changed.emit("✓ %s" % _objective_text(oid))
	elif state == "failed":
		print("[MISSION] objective failed: %s" % _objective_text(oid))
		EventBus.objective_changed.emit("✗ %s" % _objective_text(oid))


func _complete_objectives_of_kind(kind: String) -> void:
	if current_mission == null:
		return
	for obj: Dictionary in current_mission.objectives:
		if String(obj.get("kind", "")) != kind:
			continue
		var oid: String = String(obj.get("id", ""))
		if _objective_states.get(oid, "") == "active":
			_set_objective_state(oid, "complete")


func _complete_survive_until_objectives(phase: String) -> void:
	if current_mission == null or GameState.ship_destroyed:
		return
	for obj: Dictionary in current_mission.objectives:
		if String(obj.get("kind", "")) != "survive_until":
			continue
		if String(_obj_params(obj).get("phase", "")) != phase:
			continue
		var oid: String = String(obj.get("id", ""))
		if _objective_states.get(oid, "") == "active":
			_set_objective_state(oid, "complete")


# deliver_cargo (spec §3.2): "on_station ends with cargo_flag NOT set false" — the
# cargo_flag param names a ScenarioDirector-style flag a sabotage outcome can set to
# false via the generic `set_flag` outcome; we don't own that flag's storage (that's
# ScenarioDirector.scenario_flags via OutcomeApplier, task D), we just watch every
# EventBus.scenario_flag_set broadcast and remember the latest value we saw for each
# name. Never explicitly set false -> default true -> objective completes; explicitly
# set false -> sabotage happened -> objective fails instead.
func _complete_deliver_cargo_objectives() -> void:
	if current_mission == null:
		return
	for obj: Dictionary in current_mission.objectives:
		if String(obj.get("kind", "")) != "deliver_cargo":
			continue
		var oid: String = String(obj.get("id", ""))
		if _objective_states.get(oid, "") != "active":
			continue
		var cargo_flag: String = String(_obj_params(obj).get("cargo_flag", ""))
		var sabotaged: bool = cargo_flag != "" and _scenario_flags_seen.get(cargo_flag, true) == false
		_set_objective_state(oid, "failed" if sabotaged else "complete")


func _check_repair_objectives() -> void:
	if current_mission == null:
		return
	for obj: Dictionary in current_mission.objectives:
		if String(obj.get("kind", "")) != "repair_to":
			continue
		var oid: String = String(obj.get("id", ""))
		if _objective_states.get(oid, "") != "active":
			continue
		var value: float = float(_obj_params(obj).get("value", 0.0))
		if GameState.hull_integrity >= value:
			_set_objective_state(oid, "complete")


func _keep_alive_ok(role: String) -> bool:
	if role == "" or role == "all":
		for cid: String in GameState.crew:
			var c: CrewMember = GameState.crew[cid] as CrewMember
			if c != null and not c.is_alive:
				return false
		return true
	var cid: String = GameState.get_crew_of_role(role)
	if cid == "":
		return true   # no crew of that role aboard — nothing to have lost
	var c: CrewMember = GameState.crew.get(cid) as CrewMember
	return c != null and c.is_alive


# --- Event-driven objective hooks (away_team / dock_with_ship / scenario_flag) ---
# Both away_team and dock_with_ship stay "active" (incomplete) until task C actually
# emits shuttle_returned / this mission's own docking sequence fires
# docking_completed — an honest partial grade until then, per the task brief.

func _on_shuttle_returned(_report: Dictionary) -> void:
	if current_mission == null or mission_phase == "resolution":
		return
	_complete_objectives_of_kind("away_team")
	_try_attach_scenario("away_return")


func _on_docking_completed(_contact_name: String) -> void:
	if current_mission == null or mission_phase == "resolution":
		return
	_complete_objectives_of_kind("dock_with_ship")


func _on_scenario_flag_set(flag: String, value: bool) -> void:
	_scenario_flags_seen[flag] = value
	if current_mission == null or mission_phase == "resolution" or not value:
		return
	for obj: Dictionary in current_mission.objectives:
		if String(obj.get("kind", "")) != "scenario_flag":
			continue
		if String(_obj_params(obj).get("flag", "")) != flag:
			continue
		var oid: String = String(obj.get("id", ""))
		if _objective_states.get(oid, "") == "active":
			_set_objective_state(oid, "complete")


# --- Resolution & grading (spec §3.2/§5) ---

func _resolve_mission() -> void:
	if current_mission == null:
		return
	var mission: MissionDef = current_mission
	var ship_alive: bool = not GameState.ship_destroyed

	# Finalize the resolution-only objective kinds before grading.
	for obj: Dictionary in mission.objectives:
		var oid: String = String(obj.get("id", ""))
		if _objective_states.get(oid, "active") != "active":
			continue
		match String(obj.get("kind", "")):
			"return_home":
				_set_objective_state(oid, "complete" if ship_alive else "failed")
			"keep_alive":
				var role: String = String(_obj_params(obj).get("role", "all"))
				_set_objective_state(oid, "complete" if _keep_alive_ok(role) else "failed")
			"repair_to":
				var value: float = float(_obj_params(obj).get("value", 0.0))
				_set_objective_state(oid, "complete" if GameState.hull_integrity >= value else "failed")
			# away_team / dock_with_ship / scenario_flag / deliver_cargo / reach_destination /
			# survive_until: whatever they resolved to already stands; still "active" here
			# just means "never completed" — that's the honest incomplete-objective case.

	var outcome: String
	if _aborted or not ship_alive:
		outcome = "mission_failed"
	else:
		var required_hard_failed: bool = false
		var required_complete: bool = true
		var optional_complete_count: int = 0
		for obj: Dictionary in mission.objectives:
			var oid: String = String(obj.get("id", ""))
			var state: String = _objective_states.get(oid, "active")
			var optional: bool = bool(obj.get("optional", false))
			if optional:
				if state == "complete":
					optional_complete_count += 1
			else:
				if state == "failed":
					required_hard_failed = true
				elif state != "complete":
					required_complete = false
		if required_hard_failed:
			outcome = "mission_failed"
		elif required_complete:
			outcome = "mission_success"
		else:
			outcome = "mission_partial"
			if optional_complete_count >= 1:
				outcome = "mission_success"   # optional-objective upgrade rule (spec §3.2)

	if outcome != "mission_failed":
		_apply_rewards(mission)

	# extra_outcome_flags: campaign_flag -> objective id that must be COMPLETE
	# (including optional ones — faction-grudge chains depend on this per spec §13).
	for flag_name: String in mission.extra_outcome_flags.keys():
		var target_oid: String = String(mission.extra_outcome_flags[flag_name])
		campaign_flags[flag_name] = _objective_states.get(target_oid, "") == "complete"

	# Derived flags from live ship/crew state (spec §5's hidden status_flags + hull).
	campaign_flags["crew_infected_aboard"] = GameState.any_crew_status("infected")
	campaign_flags["crew_changed_aboard"] = GameState.any_crew_status("changed")
	campaign_flags["crew_shaken_aboard"] = GameState.any_crew_status("shaken")
	campaign_flags["crew_marked_aboard"] = GameState.any_crew_status("marked")
	campaign_flags["hull_mauled"] = GameState.hull_integrity < 50.0

	_prev_outcome_flags = {outcome: true}
	_prev_follow_ons = mission.follow_ons.duplicate(true)

	deck.mark_completed(mission.id)
	mission_history.append({"id": mission.id, "outcome": outcome, "leg": ScenarioDirector.current_leg})

	print("[MISSION] resolved '%s' -> %s (aborted=%s ship_alive=%s)" % [
		mission.id, outcome, _aborted, ship_alive])
	EventBus.objective_changed.emit("%s — %s" % [mission.title, _outcome_label(outcome)])
	EventBus.mission_completed.emit(mission.id, outcome)

	# Leg boundary ownership (spec §10): mission mode drives this from resolution,
	# NOT ScenarioRunner's scenario-drain path (guarded off in scenario_runner.gd
	# via MissionManager.mission_mode — see _end_scenario_instance there).
	ScenarioDirector.advance_leg()
	SaveManager.save_checkpoint("leg_%d" % ScenarioDirector.current_leg)
	EventBus.leg_boundary_reached.emit(ScenarioDirector.current_leg)

	_aborted = false
	_intermission_active = true
	_intermission_elapsed = 0.0


func _outcome_label(outcome: String) -> String:
	match outcome:
		"mission_success": return "SUCCESS"
		"mission_partial": return "PARTIAL"
		"mission_failed": return "FAILED"
		_: return outcome.to_upper()


func _apply_rewards(mission: MissionDef) -> void:
	var credits_amt: float = float(mission.rewards.get("credits", 0.0))
	if credits_amt != 0.0:
		GameState.adjust_metric("credits", credits_amt)
	var metrics: Dictionary = mission.rewards.get("metrics", {})
	for metric_name: String in metrics.keys():
		GameState.adjust_metric(metric_name, float(metrics[metric_name]))
	var items: Array = mission.rewards.get("items", [])
	if not items.is_empty():
		var recipient: CrewMember = _reward_recipient()
		if recipient != null:
			for item_id in items:
				recipient.inventory.append(String(item_id))   # best-effort — no capacity checks


func _reward_recipient() -> CrewMember:
	var cid: String = GameState.get_crew_of_role("captain")
	if cid != "":
		return GameState.crew.get(cid) as CrewMember
	for c_id: String in GameState.crew:
		var c: CrewMember = GameState.crew[c_id] as CrewMember
		if c != null and c.is_alive:
			return c
	return null


# --- Next mission draw ---

func _draw_next_mission() -> void:
	var leg: int = ScenarioDirector.current_leg
	var hull: float = GameState.hull_integrity
	var mission: MissionDef = deck.draw(campaign_flags, leg, hull, _prev_outcome_flags, _prev_follow_ons, rng)
	if mission == null:
		mission = _fallback_draw()
	if mission == null:
		push_warning("MissionManager: deck exhausted — no mission available, campaign idle")
		mission_phase = ""
		return
	_start_mission(mission)


# Empty-deck graceful fallback (spec deliverable): relax eligibility entirely and
# prefer repeatable missions; if even that pool is empty, take literally anything in
# the deck rather than leaving the campaign stuck forever.
func _fallback_draw() -> MissionDef:
	var pool: Array[MissionDef] = []
	for mid: String in deck.missions.keys():
		var m: MissionDef = deck.missions[mid]
		if m.repeatable:
			pool.append(m)
	if pool.is_empty():
		for mid: String in deck.missions.keys():
			pool.append(deck.missions[mid])
	if pool.is_empty():
		return null
	var weights: Array[float] = []
	for m: MissionDef in pool:
		weights.append(maxf(m.weight, 0.01))
	return pool[_weighted_pick(weights)]


func _weighted_pick(weights: Array[float]) -> int:
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return rng.randi_range(0, weights.size() - 1) if rng != null else 0
	var roll: float = (rng.randf() if rng != null else randf()) * total
	var cumulative: float = 0.0
	for i in weights.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return i
	return weights.size() - 1


# --- Scenario hooks (spec §3/§10 — MINIMAL version; task E does Overseer refinement) ---
# Deliberately factored into this one method so a later pass can swap the selection
# internals (heat-scaled chance, cooldowns, delayed trigger_status payoffs) without
# touching any call site — every phase entry and the away_return pseudo-phase both
# just call this with their hook key.

func _try_attach_scenario(hook_key: String) -> void:
	if current_mission == null:
		return
	var hook: Dictionary = current_mission.get_hook(hook_key)
	if hook.is_empty():
		return
	var chance: float = float(hook.get("chance", 0.0))
	if chance <= 0.0:
		return
	var roll: float = rng.randf() if rng != null else randf()
	if roll > chance:
		return
	if ScenarioRunner.active_scenarios.size() >= 2:
		return

	var context: String = String(hook.get("context", ""))
	var tag_bias: Dictionary = hook.get("tag_bias", {})
	var recent: Array = _once_per_run_scenario_ids.duplicate()
	var picked_id: String = ScenarioCatalog.pick(context, tag_bias, ScenarioDirector.current_leg,
		_active_scenario_axes(), recent, ScenarioDirector.effective_heat(), rng)
	if picked_id == "":
		return
	var config: Dictionary = ScenarioCatalog.build_config(picked_id)
	if config.is_empty():
		return

	var instance_id: String = ScenarioRunner.start_scenario(config)
	ScenarioRunner._spawn_monitor(picked_id, config)
	if bool(ScenarioCatalog.defs(picked_id).get("once_per_run", false)):
		_once_per_run_scenario_ids.append(picked_id)

	if _debug:
		print("[MISSION] scenario hook '%s' fired -> %s (instance=%s roll=%.2f<=%.2f)" % [
			hook_key, picked_id, instance_id, roll, chance])


func _active_scenario_axes() -> Array[String]:
	var axes: Array[String] = []
	for instance_id: String in ScenarioRunner.active_scenarios:
		var instance: Dictionary = ScenarioRunner.active_scenarios[instance_id]
		var sid: String = String(instance.get("scenario_id", ""))
		var axis: String = ScenarioRunner._scenario_axis(sid)
		if axis != "" and axis not in axes:
			axes.append(axis)
	return axes


# --- Abort (spec §5 — OutcomeApplier lands in task D; this is the hook it'll call) ---

func mission_abort(reason: String) -> void:
	if current_mission == null or mission_phase == "" or mission_phase == "resolution":
		return
	_aborted = true
	print("[MISSION] ABORT: %s (%s)" % [current_mission.id, reason])
	if mission_phase != "transit_back":
		_enter_phase("transit_back")
	# else: already inbound — let it run out naturally; resolution grades it failed
	# because _aborted is true, regardless of what objectives happen to complete.
