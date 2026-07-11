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

# Task E (docs/mission-system-spec.md §10): the phase-order PLUS the away_return
# pseudo-phase, in the fixed evaluation order used to resolve which hook a delayed
# trigger_status payoff force-attaches at ("the first hook of that mission whose
# context matches" — see _resolve_payoff_hook_key).
const HOOK_ORDER: Array[String] = ["transit_out", "arrival", "on_station", "away_return", "transit_back"]

# Inter-scenario pacing gap (spec §10: "a 120s base inter-scenario gap"), stretched
# by ScenarioDirector.modifiers.cooldown_mult exactly like every other cooldown
# consumer (EventPool, etc.) — never a scattered special case (spec §4).
const SCENARIO_START_GAP_SECONDS: float = 120.0

var campaign_flags: Dictionary = {}
var current_mission: MissionDef = null
var mission_phase: String = ""     # "" | transit_out | arrival | on_station | transit_back | resolution
var mission_mode: bool = false
var mission_history: Array[Dictionary] = []   # [{id, outcome, leg}] — completed-mission log

var deck: MissionDeck = null
var rng: RandomNumberGenerator = null

# Away ops (docs/mission-system-spec.md §6/§7, engine task C). Created unconditionally
# below in _ready() — NOT gated on mission_mode — so RepairModel/EnvironmentMenu/etc. can
# always safely read MissionManager.shuttle_system regardless of whether a campaign is
# currently running (mirrors how AICoreSystem/every other always-on subsystem node works).
var shuttle_system: ShuttleSystem = null

var _objective_states: Dictionary = {}        # objective_id -> "active" | "complete" | "failed"
var _scenario_flags_seen: Dictionary = {}      # flag -> last value seen via EventBus.scenario_flag_set (this mission's lifetime)
var _once_per_run_scenario_ids: Array[String] = []   # once_per_run scenario ids already used this campaign

# Task E (spec §10 "Delayed payoffs" — THE interweave mechanic). One entry per
# scheduled trigger_status payoff: {crew_id, flag, scenario_id, due_leg, hook_key,
# fired}. hook_key is "" until a mission is running whose leg has reached due_leg
# (resolved once per mission by _resolve_pending_payoffs_for_mission, reset to ""
# whenever a mission resolves without firing it — see _resolve_mission — so the
# NEXT mission's hooks get a fresh chance to match). Persists for the campaign's
# lifetime (cleared in begin_campaign), same durability as campaign_flags.
var _pending_payoffs: Array[Dictionary] = []
var _payoff_scheduled_keys: Dictionary = {}    # "<crew_id>|<flag>" -> true — one payoff per (crew, flag), no stacking
var _last_scenario_start_elapsed: float = -999999.0   # TimeManager.elapsed of the last successful attach (any path)

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
	EventBus.docking_started.connect(_on_docking_started)
	EventBus.docking_completed.connect(_on_docking_completed)
	EventBus.undocked.connect(_on_undocked)
	EventBus.scenario_flag_set.connect(_on_scenario_flag_set)
	EventBus.crew_status_flag_changed.connect(_on_crew_status_flag_changed)

	shuttle_system = ShuttleSystem.new()
	shuttle_system.name = "ShuttleSystem"
	add_child(shuttle_system)


# --- Campaign start (spec §12) ---

func begin_campaign(seed_value: int = -1) -> void:
	campaign_flags = {}
	mission_history = []
	_once_per_run_scenario_ids = []
	_prev_outcome_flags = {}
	_prev_follow_ons = []
	_pending_payoffs = []
	_payoff_scheduled_keys = {}
	_last_scenario_start_elapsed = -999999.0

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

	_resolve_pending_payoffs_for_mission()

	print("[MISSION] started '%s' (%s) giver=%s leg=%d" % [
		mission.id, mission.title, mission.giver, ScenarioDirector.current_leg])
	EventBus.mission_started.emit(mission.id)
	EventBus.objective_changed.emit(_oneline_briefing(mission))
	_speak_bridge_intent(_briefing_ack_intent(mission))
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


func _on_docking_started(_contact_name: String) -> void:
	_speak_bridge_intent("docking_approach")


func _on_docking_completed(_contact_name: String) -> void:
	_speak_bridge_intent("docking_clamped")
	if current_mission == null or mission_phase == "resolution":
		return
	_complete_objectives_of_kind("dock_with_ship")


func _on_undocked(_contact_name: String) -> void:
	_speak_bridge_intent("docking_undock")


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

	# Delayed payoffs (task E): any entry resolved to a hook_key THIS mission that
	# never actually fired (blocked the whole mission by cap-2, or its hook simply
	# never got a matching context) gets its hook_key cleared so the NEXT mission's
	# _resolve_pending_payoffs_for_mission gives it a fresh resolution rather than
	# silently dying pinned to a hook that will never be entered again.
	for entry: Dictionary in _pending_payoffs:
		if not bool(entry.get("fired", false)):
			entry["hook_key"] = ""

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


# --- Scenario hooks (spec §3/§10, task E's Overseer refinement over task B's minimal
# flat-chance version) — deliberately kept as this one method so every phase entry and
# the away_return pseudo-phase can just call it with their hook key regardless of what
# selects/gates underneath. Three layers, checked in order:
#   1. A due delayed trigger_status payoff resolved to THIS hook — force-attaches,
#      bypassing the chance roll AND the inter-scenario gap entirely (still gated by
#      cap-2 + once_per_run — spec §10).
#   2. The inter-scenario gap: skip the roll outright if anything started within the
#      last 120s (modifiers.cooldown_mult-stretched).
#   3. The heat-scaled chance roll -> ScenarioCatalog.pick's full selection rules.

func _try_attach_scenario(hook_key: String) -> void:
	if current_mission == null:
		return
	var hook: Dictionary = current_mission.get_hook(hook_key)
	if hook.is_empty():
		return

	var due_payoff: Dictionary = _find_due_payoff_for_hook(hook_key)
	if not due_payoff.is_empty():
		_force_attach_payoff(due_payoff)
		return

	var chance: float = float(hook.get("chance", 0.0))
	if chance <= 0.0:
		return

	var gap: float = SCENARIO_START_GAP_SECONDS * float(ScenarioDirector.modifiers.get("cooldown_mult", 1.0))
	var since_last: float = TimeManager.elapsed - _last_scenario_start_elapsed
	if since_last < gap:
		if _debug:
			print("[MISSION] scenario hook '%s' skipped — inter-scenario gap (%.1fs < %.1fs)" % [
				hook_key, since_last, gap])
		return

	var effective_chance: float = chance * lerp(0.6, 1.4, ScenarioDirector.effective_heat())
	var roll: float = rng.randf() if rng != null else randf()
	if roll > effective_chance:
		if _debug:
			print("[MISSION] scenario hook '%s' rolled no attach (roll=%.2f > effective_chance=%.2f, base=%.2f heat=%.2f)" % [
				hook_key, roll, effective_chance, chance, ScenarioDirector.effective_heat()])
		return
	if ScenarioRunner.active_scenarios.size() >= ScenarioRunner.OVERLAP_CAP:
		return

	var context: String = String(hook.get("context", ""))
	var tag_bias: Dictionary = hook.get("tag_bias", {})
	var recent: Array = _once_per_run_scenario_ids.duplicate()
	var picked_id: String = ScenarioCatalog.pick(context, tag_bias, ScenarioDirector.current_leg,
		_active_scenario_axes(), recent, ScenarioDirector.effective_heat(), rng,
		ScenarioDirector.current_weak_axes())
	if picked_id == "":
		return
	var instance_id: String = _attach_scenario_now(picked_id)
	if instance_id == "":
		return

	if _debug:
		print("[MISSION] scenario hook '%s' fired -> %s (instance=%s roll=%.2f<=%.2f effective_chance=%.2f base=%.2f heat=%.2f)" % [
			hook_key, picked_id, instance_id, roll, effective_chance, effective_chance, chance, ScenarioDirector.effective_heat()])


# Shared tail for every attach path (normal roll + forced payoff): builds the config,
# starts the ScenarioRunner instance + its monitor, records once_per_run/gap bookkeeping.
# Returns "" (and does nothing else) on a bad/missing config — never partially attaches.
func _attach_scenario_now(scenario_id: String) -> String:
	var config: Dictionary = ScenarioCatalog.build_config(scenario_id)
	if config.is_empty():
		return ""
	var instance_id: String = ScenarioRunner.start_scenario(config)
	ScenarioRunner._spawn_monitor(scenario_id, config)
	if bool(ScenarioCatalog.defs(scenario_id).get("once_per_run", false)):
		_once_per_run_scenario_ids.append(scenario_id)
	_last_scenario_start_elapsed = TimeManager.elapsed
	return instance_id


# --- Delayed trigger_status payoffs (spec §10 "THE interweave mechanic") ---
# Flow: a hidden crew_status_flag lands (typically an AwayResolver exposure beat,
# but any crew_status_flag outcome qualifies) -> schedule a force-attach 1-2 legs
# later for the first matching scenario -> once a mission is running at/past that
# leg, resolve WHICH of its hooks the payoff will fire at -> the ordinary
# _try_attach_scenario call for that hook fires it instead of rolling.

func _on_crew_status_flag_changed(crew_id: String, flag: String, value: bool) -> void:
	if not value or not mission_mode:
		return
	var key: String = "%s|%s" % [crew_id, flag]
	if _payoff_scheduled_keys.has(key):
		return   # one scheduled payoff per (crew, flag) — no stacking duplicates
	var scenario_id: String = _pick_trigger_status_scenario(flag)
	if scenario_id == "":
		return
	_payoff_scheduled_keys[key] = true
	var delay: int = rng.randi_range(1, 2) if rng != null else (randi() % 2 + 1)
	var due_leg: int = ScenarioDirector.current_leg + delay
	_pending_payoffs.append({
		"crew_id": crew_id, "flag": flag, "scenario_id": scenario_id,
		"due_leg": due_leg, "hook_key": "", "fired": false,
	})
	if _debug:
		print("[MISSION] delayed payoff scheduled: %s <- '%s' -> scenario '%s' due leg %d (current leg %d, +%d)" % [
			crew_id, flag, scenario_id, due_leg, ScenarioDirector.current_leg, delay])


# Weighted pick among every catalog scenario whose trigger_status matches (rare for
# more than one to collide, but the catalog doesn't guarantee 1:1); once_per_run
# scenarios already consumed this campaign are excluded outright — scheduling a
# payoff that can never legally attach would just dead-end silently later.
func _pick_trigger_status_scenario(flag: String) -> String:
	var candidates: Array[String] = []
	var weights: Array[float] = []
	for id: String in ScenarioCatalog.all_ids():
		var def: Dictionary = ScenarioCatalog.defs(id)
		if def.is_empty():
			continue   # bespoke builtins carry no trigger_status metadata (ScenarioCatalog class doc)
		if String(def.get("trigger_status", "")) != flag:
			continue
		if bool(def.get("once_per_run", false)) and id in _once_per_run_scenario_ids:
			continue
		candidates.append(id)
		weights.append(maxf(float(def.get("weight", 1.0)), 0.01))
	if candidates.is_empty():
		return ""
	return candidates[_weighted_pick(weights)]


# Resolves hook_key for every due-but-unresolved payoff against the mission that just
# started (called from _start_mission). "Due" = due_leg has been reached; a payoff
# scheduled for a future leg is left alone until a mission actually reaches it.
func _resolve_pending_payoffs_for_mission() -> void:
	if current_mission == null:
		return
	for entry: Dictionary in _pending_payoffs:
		if bool(entry.get("fired", false)):
			continue
		if int(entry.get("due_leg", 0)) > ScenarioDirector.current_leg:
			continue
		if String(entry.get("hook_key", "")) != "":
			continue
		entry["hook_key"] = _resolve_payoff_hook_key(String(entry.get("scenario_id", "")))


# "The first hook of that mission whose context matches, or ANY hook if none match"
# (spec §10), evaluated in a fixed phase order (HOOK_ORDER) so the result is
# deterministic for a given mission/scenario pair.
func _resolve_payoff_hook_key(scenario_id: String) -> String:
	if current_mission == null:
		return ""
	var contexts: Array = ScenarioCatalog.defs(scenario_id).get("contexts", [])
	for hook_key: String in HOOK_ORDER:
		var hook: Dictionary = current_mission.get_hook(hook_key)
		if hook.is_empty():
			continue
		var hook_context: String = String(hook.get("context", ""))
		if hook_context in contexts or "any" in contexts:
			return hook_key
	for hook_key: String in HOOK_ORDER:   # fallback: ANY hook this mission actually has
		if not current_mission.get_hook(hook_key).is_empty():
			return hook_key
	return ""


func _find_due_payoff_for_hook(hook_key: String) -> Dictionary:
	for entry: Dictionary in _pending_payoffs:
		if not bool(entry.get("fired", false)) and String(entry.get("hook_key", "")) == hook_key:
			return entry
	return {}


# Bypasses the chance roll/gap entirely (spec §10) but still respects cap-2
# concurrent and once_per_run — exactly the two constraints the task brief calls
# out. A cap-2 block just defers (hook_key stays put, retried on the next call for
# the same hook — e.g. a second away_return within one mission); a once_per_run
# scenario already consumed elsewhere or a bad/missing config drops the payoff for
# good rather than retrying forever.
func _force_attach_payoff(payoff: Dictionary) -> void:
	var scenario_id: String = String(payoff.get("scenario_id", ""))
	var hook_key: String = String(payoff.get("hook_key", ""))
	var def: Dictionary = ScenarioCatalog.defs(scenario_id)
	if bool(def.get("once_per_run", false)) and scenario_id in _once_per_run_scenario_ids:
		payoff["fired"] = true
		if _debug:
			print("[MISSION] delayed payoff '%s' dropped — once_per_run already consumed elsewhere" % scenario_id)
		return
	if ScenarioRunner.active_scenarios.size() >= ScenarioRunner.OVERLAP_CAP:
		if _debug:
			print("[MISSION] delayed payoff '%s' deferred at hook '%s' — cap-2 concurrent full" % [scenario_id, hook_key])
		return
	var instance_id: String = _attach_scenario_now(scenario_id)
	if instance_id == "":
		payoff["fired"] = true   # bad/missing config — drop rather than retry forever
		return
	payoff["fired"] = true
	print("[MISSION] delayed payoff FIRED: %s (crew=%s flag=%s) at hook '%s' (bypassed roll, instance=%s)" % [
		scenario_id, payoff.get("crew_id", ""), payoff.get("flag", ""), hook_key, instance_id])


# --- Away-beat injection support (away_resolver.gd _apply_away_return_injection,
# task E deliverable 4) — small read-only surface AwayResolver queries so the
# "already active or scheduled" check lives in ONE place rather than AwayResolver
# reaching into ScenarioRunner/ScenarioCatalog/_pending_payoffs directly. ---

# First scenario id (already running, or scheduled as a not-yet-fired delayed
# payoff) whose contexts include "away_return" — the candidate whose away_injection
# data (or generic exposure-beat fallback) may flavor one beat of an in-flight away
# op. "" if nothing qualifies (the common case — AwayResolver degrades to its
# normal random beat table).
func find_away_injection_scenario_id() -> String:
	for instance_id: String in ScenarioRunner.active_scenarios:
		var sid: String = String(ScenarioRunner.active_scenarios[instance_id].get("scenario_id", ""))
		if "away_return" in ScenarioCatalog.defs(sid).get("contexts", []):
			return sid
	for entry: Dictionary in _pending_payoffs:
		if bool(entry.get("fired", false)):
			continue
		var sid: String = String(entry.get("scenario_id", ""))
		if "away_return" in ScenarioCatalog.defs(sid).get("contexts", []):
			return sid
	return ""


func _active_scenario_axes() -> Array[String]:
	var axes: Array[String] = []
	for instance_id: String in ScenarioRunner.active_scenarios:
		var instance: Dictionary = ScenarioRunner.active_scenarios[instance_id]
		var sid: String = String(instance.get("scenario_id", ""))
		var axis: String = ScenarioRunner._scenario_axis(sid)
		if axis != "" and axis not in axes:
			axes.append(axis)
	return axes


# --- Away ops (docs/mission-system-spec.md §6, engine task C) — small read-only surface
# ShuttleSystem/EnvironmentMenu query rather than reaching into private state directly. ---

# The current mission's incomplete away_team objective dict ({id, text, kind, params}), or
# {} if there isn't one (no mission running, or its away_team objective is already
# complete/failed — a mission is only ever authored with one at a time per the catalog).
func active_away_team_objective() -> Dictionary:
	if current_mission == null or mission_phase == "" or mission_phase == "resolution":
		return {}
	for obj: Dictionary in current_mission.objectives:
		if String(obj.get("kind", "")) != "away_team":
			continue
		var oid: String = String(obj.get("id", ""))
		if _objective_states.get(oid, "active") == "active":
			return obj
	return {}


func objective_state(oid: String) -> String:
	return String(_objective_states.get(oid, ""))


# True only once the on_station docking sequence has fully landed (docking_completed fired,
# not yet undocked) — the gate boarding-site away ops need (spec §7: "Boarding ops only
# while docked").
func is_docked() -> bool:
	return _docking_active and _docking_completed_flag


# --- Engine-triggered dialogue bridge (docs/dialogue_spec.md "Mission-system line
# categories") — briefing_ack_* (on mission_started) and docking_* (on the docking
# signals) both land on "whoever's on the bridge", so both funnel through this one helper.
# Silent no-op if there's no captain/bridge crew or the corpus has no matching line —
# same "degrades to silence" contract every other DialogueSystem call site relies on.

func _speak_bridge_intent(intent: String) -> void:
	if intent == "":
		return
	var crew_id: String = GameState.get_crew_of_role("captain")
	if crew_id == "":
		for cid: String in GameState.crew:
			var c: CrewMember = GameState.crew[cid] as CrewMember
			if c != null and c.is_alive and not c.off_ship:
				crew_id = cid
				break
	if crew_id == "":
		return
	DialogueSystem.speak_intent(crew_id, intent)


# Tier -> briefing_ack sub-key (dialogue_spec.md "briefing_ack_{routine|risky|grim}").
# Prefers the mission's own away_risk.tier when it has an away component; otherwise infers
# from type/tags exactly per the spec's mapping.
func _briefing_ack_intent(mission: MissionDef) -> String:
	var tier: String = String(mission.away_risk.get("tier", ""))
	match tier:
		"low", "moderate":
			return "briefing_ack_routine"
		"high":
			return "briefing_ack_risky"
		"extreme":
			return "briefing_ack_grim"
	if mission.mission_type in ["distress", "evacuation", "quarantine_run"] or "high_stakes" in mission.tags:
		return "briefing_ack_risky"
	if "opener" in mission.tags or mission.mission_type == "homecoming" or "low_stakes" in mission.tags:
		return "briefing_ack_routine"
	return "briefing_ack_routine"


# --- Objective force-complete/fail (spec §5 — OutcomeApplier's objective_complete/
# objective_fail outcomes; small addition, engine task D). No-ops safely if there's no
# current mission, the phase has already moved to resolution, or the objective id
# doesn't exist / isn't currently "active" — same "never hard-fail on bad content"
# posture as _set_objective_state's own callers.

func force_complete_objective(objective_id: String) -> void:
	if current_mission == null or mission_phase == "" or mission_phase == "resolution":
		return
	if _objective_states.get(objective_id, "") == "active":
		_set_objective_state(objective_id, "complete")


func force_fail_objective(objective_id: String) -> void:
	if current_mission == null or mission_phase == "" or mission_phase == "resolution":
		return
	if _objective_states.get(objective_id, "") == "active":
		_set_objective_state(objective_id, "failed")


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
