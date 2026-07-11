extends Node

# Orchestrates running scenarios: loads config, checks win/lose conditions,
# applies end-of-scenario situational deltas, and hands off to the next scenario.
#
# Multi-instance (docs/director-spec.md §5/§8 step 3): `active_scenarios` holds every
# currently-running scenario keyed by a unique instance id, so the Overseer can later
# start a second one alongside the first (step 5's overlap scheduling) without this
# file changing shape again. Today exactly one scenario ever runs at a time (nothing
# calls start_scenario() twice yet) — the dictionary-of-one is deliberate scaffolding,
# not speculative complexity: every check below already iterates active_scenarios so
# step 5 only has to add a second start_scenario() call and a compatibility check.
#
# Win is per-scenario: each instance's own win_flags are checked independently, and
# only THAT instance ends (leg delta applied, scenario_instance_ended emitted). The
# run-level scenario_ended signal — every existing listener's (HUD/main.gd/monitors)
# expectation — fires once active_scenarios drains to empty, so single-scenario runs
# behave exactly as before.
#
# Lose conditions (all three permadeath paths from CLAUDE.md's design decision) are
# RUN-level, not per-scenario, and stay global on purpose — a death spiral in one
# concurrent scenario ends the whole voyage, not just its own instance:
#   - all crew dead
#   - ship destroyed (GameState.ship_destroyed — stub hook, no in-game content sets it yet)
#   - AI decommissioned, via either of two paths:
#       1. crew vote to shut it down outright (ai_decommission_attempted, low trust)
#       2. the AI core sits in blackout with no crew willing/able to repair it for too
#          long (AI_CORE_NEGLECT_TIMEOUT) — the overhaul spec's "if the AI is at 0 with no
#          crew willing to repair, that's the AI decommissioned game-over"

const AI_CORE_NEGLECT_TIMEOUT: float = 90.0
const AI_CORE_REPAIR_TRUST_THRESHOLD: float = 0.35

# Morph targets the bible names (docs/scenario-bible.md 1.3 "The Long Crack", 1.5
# "Close Quarters") that aren't built yet — redirected to the only other implemented
# Tier 1 scenario so a live morph has somewhere real to go. TODO(director): remove
# each entry once its real scenario exists.
const SCENARIO_STUB_FALLBACK: Dictionary = {
	"close_quarters": "the_narrow_passage",
	"the_long_crack": "the_quarantine",
}

# --- Overlap scheduling (docs/director-spec.md §4/§5/§8 step 5) ---
# "Past OVERLAP_THRESHOLD (heat >= ~0.75) AND active scenario older than its
# expected length: start a SECOND simultaneous scenario (cap: 2 concurrent; a
# second one must come from a different pressure axis ... never two of the same
# kind)". The full Tier-1 roster (id -> axis) lives here since it's the one place
# that already needs to reason about every scenario as data, not just the active
# one — extend both when a new Tier-1 scenario is built.
const OVERLAP_THRESHOLD: float = 0.75
const OVERLAP_CAP: int = 2
const RECENT_HISTORY_LEGS: int = 2   # "no repeats within 2 legs" — a soft de-prioritisation, not a hard ban (see _pick_overlap_candidate)

# The two hand-authored bespoke scenarios (ScenarioCatalog's builder overrides —
# see its class doc) plus whatever ScenarioCatalog has loaded from
# resources/scenarios/*.json. Kept as a small const + helper functions rather than
# a single const array/dict (the old shape) because the JSON-loaded ids aren't
# known until ScenarioCatalog lazily reads the filesystem at runtime — see
# _all_scenario_ids()/_scenario_axis() below, both read by _pick_overlap_candidate.
const BESPOKE_SCENARIO_IDS: Array[String] = ["the_quarantine", "the_narrow_passage"]
const BESPOKE_SCENARIO_AXIS: Dictionary = {"the_quarantine": "bio", "the_narrow_passage": "systems"}

# instance_id -> {id, scenario_id, config, started_at, morphed}. config is the same
# dictionary builders (QuarantineScenario.build(), etc) return — events/win_flags/
# leg_delta_*/morph_edges.
var active_scenarios: Dictionary = {}
var _next_instance_id: int = 0
var _run_active: bool = false   # guards against re-processing RUN-lose after it has already fired
var _ai_core_neglect_timer: float = 0.0
var _recent_scenario_ids: Array[String] = []   # last RECENT_HISTORY_LEGS legs' scenario ids, oldest first


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)
	EventBus.crew_died.connect(_on_crew_died)
	EventBus.ai_decommission_attempted.connect(_on_decommission_attempted)
	EventBus.scenario_flag_set.connect(_on_flag_set)


# Starts a new scenario instance and returns its unique instance id (callers that
# don't care — every existing call site — can simply ignore the return value).
func start_scenario(config: Dictionary) -> String:
	# True concurrent overlap (step 5) vs. a sequential morph handoff (step 4):
	# if another scenario is ALREADY active when this is called, the new one is
	# JOINING it (additive — see ScenarioDirector.start_scenario) rather than
	# replacing it. A morph's target never sees this true, since its source
	# instance is always ended first (_trigger_morph), leaving active_scenarios
	# empty at this point — same clean-slate reset single-scenario runs always had.
	var joining_existing: bool = not active_scenarios.is_empty()

	var instance_id: String = "%s#%d" % [config.get("id", "scenario"), _next_instance_id]
	_next_instance_id += 1
	active_scenarios[instance_id] = {
		"id": instance_id,
		"scenario_id": config.get("id", "unknown"),
		"config": config,
		"started_at": TimeManager.elapsed,
	}
	_run_active = true
	# GameState.scenario_id/scenario_tone stay single-valued (the HUD/dialogue-facing
	# "current scenario") — they track the most recently started instance. A true
	# multi-scenario-aware HUD is out of scope until overlap actually needs it.
	GameState.scenario_id = config.get("id", "unknown")
	if not joining_existing:
		GameState.scenario_tone = config.get("starting_tone", 0.2)
	ScenarioDirector.start_scenario(config.get("events", []), joining_existing)
	EventBus.scenario_event_triggered.emit("scenario_started")
	return instance_id


func _on_tick(_elapsed: float, delta: float) -> void:
	if active_scenarios.is_empty():
		return
	_check_run_lose_conditions(delta)
	if not _run_active:
		return
	_check_win_conditions()
	if not active_scenarios.is_empty():   # a win may have just drained it to empty
		_check_overlap_scheduling()


# --- RUN-level lose conditions (global — end every active scenario at once) ---

func _check_run_lose_conditions(delta: float) -> void:
	if GameState.ship_destroyed:
		_end_run("ship_destroyed", "hull_breach")
		return

	# AI neglect path: blackout, nobody repairing, and trust too low for anyone to want to.
	if GameState.ai_core_status == "blackout" and not GameState.is_being_repaired("ai_core") \
			and _average_trust() < AI_CORE_REPAIR_TRUST_THRESHOLD:
		_ai_core_neglect_timer += delta
		if _ai_core_neglect_timer >= AI_CORE_NEGLECT_TIMEOUT:
			_end_run("ai_decommissioned", "crew_refused_repair")
			return
	else:
		_ai_core_neglect_timer = 0.0

	# Lose if all crew are dead
	var any_alive: bool = false
	for crew_id in GameState.crew:
		if (GameState.crew[crew_id] as CrewMember).is_alive:
			any_alive = true
			break
	if not any_alive:
		_end_run("crew_dead", "all_crew_dead")


# --- Per-scenario win conditions ---

func _check_win_conditions() -> void:
	# Snapshot the keys — _end_scenario_instance mutates active_scenarios mid-loop.
	for instance_id: String in active_scenarios.keys():
		var instance: Dictionary = active_scenarios.get(instance_id, {})
		if instance.is_empty():
			continue
		var config: Dictionary = instance.get("config", {})
		var win_flags: Array = config.get("win_flags", [])
		if win_flags.is_empty():
			continue
		var all_met: bool = true
		for flag in win_flags:
			if not ScenarioDirector.get_flag(flag):
				all_met = false
				break
		if all_met:
			_end_scenario_instance(instance_id, "success", "all_win_conditions_met")


func _on_crew_died(_crew_id: String, _cause: String) -> void:
	# Win/lose re-check happens next tick — avoids checking mid-cascade
	pass


# --- Overlap scheduling (docs/director-spec.md §4/§5/§8 step 5) ---

func _check_overlap_scheduling() -> void:
	if active_scenarios.size() >= OVERLAP_CAP:
		return
	if ScenarioDirector.effective_heat() < OVERLAP_THRESHOLD:
		return
	if not _any_scenario_overdue():
		return
	var candidate_id: String = _pick_overlap_candidate()
	if candidate_id == "":
		return
	var config: Dictionary = _build_scenario_config(candidate_id)
	var new_id: String = start_scenario(config)
	_spawn_monitor(candidate_id, config)
	print("[OVERSEER] overlap start: %s (effective_heat=%.2f cap=%d/%d)" % [
		new_id, ScenarioDirector.effective_heat(), active_scenarios.size(), OVERLAP_CAP])


# "active scenario older than its expected length" — at least one currently active
# instance must have run past its own authored expected_length.
func _any_scenario_overdue() -> bool:
	var elapsed: float = TimeManager.elapsed
	for instance_id: String in active_scenarios:
		var instance: Dictionary = active_scenarios[instance_id]
		var config: Dictionary = instance.get("config", {})
		var expected_length: float = float(config.get("expected_length", 999999.0))
		if elapsed - float(instance.get("started_at", elapsed)) >= expected_length:
			return true
	return false


# Compatibility matrix (spec §5): must differ in pressure_axis from every already-
# active non-social scenario (a "social" axis scenario is exempt — "can run
# alongside anything"); can't be a scenario id already running. Among the
# survivors, weight by recent-history (soft de-prioritisation, not a hard ban —
# with only two Tier-1 scenarios today a hard ban could leave zero candidates) and
# by _weakness_fit (spec §4: "prefer morphs/overlaps that exploit current
# weaknesses").
func _pick_overlap_candidate() -> String:
	var active_ids: Array[String] = []
	var active_axes: Array[String] = []
	for instance_id: String in active_scenarios:
		var instance: Dictionary = active_scenarios[instance_id]
		var sid: String = instance.get("scenario_id", "")
		active_ids.append(sid)
		var axis: String = _scenario_axis(sid)
		if axis != "social" and axis != "":
			active_axes.append(axis)

	var candidates: Array[String] = []
	var weights: Array[float] = []
	for sid: String in _all_scenario_ids():
		if sid in active_ids:
			continue
		var axis: String = _scenario_axis(sid)
		if axis != "social" and axis in active_axes:
			continue
		var w: float = 1.0
		if sid in _recent_scenario_ids:
			w *= 0.3
		w *= _weakness_fit(sid)
		candidates.append(sid)
		weights.append(w)

	if candidates.is_empty():
		return ""
	return _weighted_pick_id(candidates, weights)


# Full candidate roster for overlap scheduling: the two bespoke ids plus
# everything ScenarioCatalog has loaded from resources/scenarios/*.json
# (derived, not hardcoded, so new JSON scenarios join the overlap pool for free
# the moment content lands — no engine change needed).
func _all_scenario_ids() -> Array[String]:
	var ids: Array[String] = BESPOKE_SCENARIO_IDS.duplicate()
	for id: String in ScenarioCatalog.all_ids():
		if id not in ids:
			ids.append(id)
	return ids


func _scenario_axis(scenario_id: String) -> String:
	if BESPOKE_SCENARIO_AXIS.has(scenario_id):
		return BESPOKE_SCENARIO_AXIS[scenario_id]
	return String(ScenarioCatalog.defs(scenario_id).get("pressure_axis", ""))


# Minimal today — only two Tier-1 scenarios exist, so there's only one weakness
# signal worth encoding (low battery -> the power-hungry scenario). Extend this
# table as more scenarios land (spec's other example: low trust -> crew-drama).
func _weakness_fit(scenario_id: String) -> float:
	if scenario_id == "the_narrow_passage" and GameState.get_metric("battery_percent") < 50.0:
		return 1.5
	return 1.0


func _weighted_pick_id(ids: Array[String], weights: Array[float]) -> String:
	var total: float = 0.0
	for w in weights:
		total += w
	var roll: float = randf() * total
	var cumulative: float = 0.0
	for i in ids.size():
		cumulative += weights[i]
		if roll <= cumulative:
			return ids[i]
	return ids.back()


# --- Morph edges (docs/director-spec.md §5) ---
#
# A scenario "stops being a one-shot island" by declaring morph_edges: {to,
# condition_flags, overlap_ok, weight}. Checked synchronously on every flag set
# (EventBus.scenario_flag_set, emitted from ScenarioDirector.set_flag) rather than
# polled per-tick, since a morph should fire the instant its condition becomes true,
# not up to one tick late. Step 4 scope note: every live morph today is a SEQUENTIAL
# handoff (the source instance ends, then the target starts) regardless of what
# overlap_ok says — overlap_ok is captured as real data for step 5, which will need
# to harden ScenarioDirector's single event-pool/flags/tension ownership for true
# concurrency first; acting on it here would corrupt the source scenario's in-flight
# state the moment start_scenario() re-inits ScenarioDirector for the target.
# TODO(director, step 5): honour overlap_ok for a true concurrent handoff.

func _on_flag_set(_flag: String, value: bool) -> void:
	if not value or not _run_active:
		return
	for instance_id: String in active_scenarios.keys():
		var instance: Dictionary = active_scenarios.get(instance_id, {})
		if instance.is_empty() or instance.get("morphed", false):
			continue
		var config: Dictionary = instance.get("config", {})
		var edge: Dictionary = _matching_morph_edge(config.get("morph_edges", []))
		if not edge.is_empty():
			_trigger_morph(instance_id, edge)


# First edge (in authoring order) whose condition_flags are ALL currently true.
# An edge with no condition_flags never matches — a morph always needs a reason.
func _matching_morph_edge(edges: Array) -> Dictionary:
	for edge_v in edges:
		var edge: Dictionary = edge_v
		var flags: Array = edge.get("condition_flags", [])
		if flags.is_empty():
			continue
		var all_met: bool = true
		for flag in flags:
			if not ScenarioDirector.get_flag(flag):
				all_met = false
				break
		if all_met:
			return edge
	return {}


func _trigger_morph(instance_id: String, edge: Dictionary) -> void:
	var instance: Dictionary = active_scenarios.get(instance_id, {})
	if instance.is_empty():
		return
	instance["morphed"] = true   # guard: this instance's edges never re-fire
	var target_id: String = String(edge.get("to", ""))
	# The stub redirect only applies while the real target doesn't exist yet in
	# the catalog (docs/mission-system-spec.md task-A note: "the_long_crack"/
	# "close_quarters" will exist as JSON soon) — once content lands, ScenarioCatalog.
	# has() flips true and this stops firing on its own, no engine change needed.
	var resolved_id: String = target_id
	if not ScenarioCatalog.has(target_id) and SCENARIO_STUB_FALLBACK.has(target_id):
		resolved_id = SCENARIO_STUB_FALLBACK[target_id]
		push_warning("ScenarioRunner: morph target '%s' not implemented yet — TODO(director), redirecting to '%s'" % [target_id, resolved_id])

	# Note: with today's sequential-only handoff, this scenario was the only active
	# instance, so _end_scenario_instance below WILL fire the run-level scenario_ended
	# (outcome "morphed") a moment before the new instance starts — an honest "this
	# chapter/leg closed, here's the next one" beat (spec §2's leg framing), not a bug;
	# it just means AUTODEMO-style auto-quit-on-scenario_ended harnesses shouldn't be
	# run across a forced morph (none of today's scripted AUTODEMO win paths ever
	# satisfy a morph condition, so this never fires during the acceptance-test runs).
	_end_scenario_instance(instance_id, "morphed", "morph_edge:%s" % target_id)
	var target_config: Dictionary = _build_scenario_config(resolved_id)
	var new_id: String = start_scenario(target_config)
	_spawn_monitor(resolved_id, target_config)
	print("[OVERSEER] morph fired: %s -> %s (edge to=%s) new_instance=%s" % [instance_id, resolved_id, target_id, new_id])


# Config lookup for any scenario id, needed wherever a morph/overlap start has no
# other code path that would supply one. Bespoke ids resolve through
# ScenarioCatalog's builder overrides; JSON ids resolve through its loaded catalog
# configs; a truly unknown id (not in the catalog at all) falls back to
# the_quarantine, matching main.gd's own "unknown SHIPAI_SCENARIO falls back to
# quarantine" convention.
func _build_scenario_config(scenario_id: String) -> Dictionary:
	if ScenarioCatalog.has(scenario_id):
		return ScenarioCatalog.build_config(scenario_id)
	return QuarantineScenario.build()


# Every scenario needs its companion Monitor node to actually be playable (the
# win-flag-setting logic lives there, not in the builder). Parented to this
# autoload rather than the main scene's deck — monitors only ever talk to
# GameState/EventBus/ScenarioDirector, never their own position in the tree.
# Bespoke ids keep their hand-written monitor classes; JSON-catalog ids don't have
# one yet (GenericScenarioMonitor is engine task D) — warn and spawn nothing rather
# than silently attaching the wrong monitor. A truly unknown id mirrors
# _build_scenario_config's quarantine fallback so config and monitor never disagree.
func _spawn_monitor(scenario_id: String, config: Dictionary) -> void:
	match scenario_id:
		"the_narrow_passage":
			var monitor := NarrowPassageMonitor.new()
			monitor.setup(config)
			add_child(monitor)
		"the_quarantine":
			add_child(QuarantineMonitor.new())
		_:
			if ScenarioCatalog.has(scenario_id):
				push_warning("ScenarioRunner: GenericScenarioMonitor pending (engine task D) — no monitor spawned for '%s'" % scenario_id)
			else:
				add_child(QuarantineMonitor.new())


func _on_decommission_attempted(_initiator: String) -> void:
	if not _run_active or active_scenarios.is_empty():
		return
	# Whether decommission succeeds depends on trust levels
	var avg_trust: float = _average_trust()
	if avg_trust < 0.3:
		_end_run("ai_decommissioned", "crew_voted_shutdown")


# Ends exactly one scenario instance (a win or a morph handoff). Other active
# scenarios (overlap) keep running untouched; scenario_ended (the run-level
# signal) and the leg-boundary hook only fire once this was the LAST active
# instance, so single-scenario runs behave exactly as before.
func _end_scenario_instance(instance_id: String, outcome: String, reason: String) -> void:
	var instance: Dictionary = active_scenarios.get(instance_id, {})
	if instance.is_empty():
		return
	active_scenarios.erase(instance_id)
	_apply_leg_delta(instance.get("config", {}), outcome)
	_remember_scenario(String(instance.get("scenario_id", "")))
	EventBus.scenario_instance_ended.emit(instance_id, outcome)
	push_warning("ScenarioRunner: scenario instance ended — id=%s outcome=%s reason=%s" % [instance_id, outcome, reason])
	if active_scenarios.is_empty():
		_advance_leg()   # every active scenario concluded on its own terms — a real leg boundary, not a death
		EventBus.scenario_ended.emit(outcome)
		# TODO(campaign): hand off to CampaignManager for next scenario/leg load
	# else: a differently-paced concurrent scenario is still running — the run isn't over.


func _remember_scenario(scenario_id: String) -> void:
	if scenario_id == "":
		return
	_recent_scenario_ids.append(scenario_id)
	while _recent_scenario_ids.size() > RECENT_HISTORY_LEGS:
		_recent_scenario_ids.pop_front()


# Leg boundary (spec §2/§3/§8 step 5): every active scenario has concluded via its
# own win/morph path — never called from _end_run, which ends the voyage
# permanently (permadeath; no next leg). Raises the escalation floor and calls the
# SaveManager checkpoint stub — unimplemented by design (CLAUDE.md: "SaveManager
# still stubbed by design"); the call site existing is the point here, not the
# save actually landing anywhere yet.
func _advance_leg() -> void:
	ScenarioDirector.advance_leg()
	SaveManager.save_checkpoint("leg_%d" % ScenarioDirector.current_leg)
	# Crew progression's leg-boundary resolution (Rest Saves, pending trait rolls, crit-tally
	# skill growth, service record — docs/crew-progression-spec.md §4) hooks in via EventBus
	# rather than a direct call, same arm's-length pattern as the SaveManager stub above.
	EventBus.leg_boundary_reached.emit(ScenarioDirector.current_leg)


# Ends the whole run (a RUN-lose condition fired) — every active scenario ends at
# once, each applying its own leg_delta_<outcome> if it defines one (concurrent
# scenarios both losing stacks their penalties, which is the intended read: an
# overlap gone bad costs more than a single scenario going bad).
func _end_run(outcome: String, reason: String) -> void:
	if not _run_active:
		return
	_run_active = false
	for instance_id: String in active_scenarios.keys():
		var instance: Dictionary = active_scenarios[instance_id]
		_apply_leg_delta(instance.get("config", {}), outcome)
		EventBus.scenario_instance_ended.emit(instance_id, outcome)
	active_scenarios.clear()
	EventBus.scenario_ended.emit(outcome)
	push_warning("ScenarioRunner: RUN ended — outcome=%s reason=%s" % [outcome, reason])


# End-of-leg situational delta (rewards/penalties carried into the next leg) — keys
# are GameState.adjust_metric names ("battery_charge", "ai_core_integrity").
func _apply_leg_delta(config: Dictionary, outcome: String) -> void:
	var delta: Dictionary = config.get("leg_delta_%s" % outcome, {})
	for metric_name in delta:
		GameState.adjust_metric(metric_name, delta[metric_name])


func _average_trust() -> float:
	if GameState.ai_trust_scores.is_empty():
		return 0.5
	var total: float = 0.0
	for crew_id in GameState.ai_trust_scores:
		total += GameState.ai_trust_scores[crew_id]
	return total / GameState.ai_trust_scores.size()
