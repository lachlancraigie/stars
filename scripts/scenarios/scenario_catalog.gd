class_name ScenarioCatalog
extends RefCounted

# Static registry over resources/scenarios/*.json (docs/mission-system-spec.md §4),
# replacing the id->builder match statements previously duplicated in main.gd and
# ScenarioRunner. Not an autoload (spec §2 only lists MissionManager/IntruderSystem
# as new autoloads) — every public method is `static` and lazily loads the directory
# on first use, so ScenarioRunner (itself an autoload) can reach it as a plain
# class-level utility, the same shape as Checks/Traits/Items elsewhere in scripts/core.
#
# The two hand-authored, bespoke scenarios (QuarantineScenario/NarrowPassageScenario
# — spec §4's own carve-out: "those two stay as bespoke GDScript builders registered
# in ScenarioCatalog as overrides") are registered as BUILDER callables alongside the
# JSON-loaded ones so callers never need to know which kind of scenario an id
# resolves to — has()/build_config() treat both uniformly. defs()/pick() are
# JSON-only (the bespoke pair carry no §4 selection metadata — they're always forced
# via SHIPAI_SCENARIO or a morph edge, never offered by the Overseer's random pick).

static var _defs: Dictionary = {}          # id -> raw JSON dict (JSON-loaded scenarios only)
static var _configs: Dictionary = {}       # id -> ScenarioRunner-shaped config dict (JSON-loaded scenarios only)
static var _loaded: bool = false

# id -> Callable returning a ScenarioRunner-shaped config dict, same shape
# QuarantineScenario.build()/NarrowPassageScenario.build() already return.
static var _builtin_builders: Dictionary = {
	"the_quarantine": Callable(QuarantineScenario, "build"),
	"the_narrow_passage": Callable(NarrowPassageScenario, "build"),
}


static func load_all(dir: String = "res://resources/scenarios") -> int:
	_defs.clear()
	_configs.clear()
	_loaded = true
	var da := DirAccess.open(dir)
	if da == null:
		# Not an error — resources/scenarios/ may not exist yet (a parallel content
		# workstream populates it); the two bespoke builtins still register fine.
		return 0
	da.list_dir_begin()
	var file_name: String = da.get_next()
	var count: int = 0
	while file_name != "":
		if not da.current_is_dir() and file_name.ends_with(".json"):
			var path: String = dir.path_join(file_name)
			var parsed: Variant = _parse_json_file(path)
			if parsed is Dictionary:
				var sid: String = String(parsed.get("id", ""))
				if sid == "":
					push_warning("ScenarioCatalog: %s has no 'id' field" % path)
				elif _defs.has(sid) or _builtin_builders.has(sid):
					push_warning("ScenarioCatalog: duplicate scenario id '%s' (%s)" % [sid, path])
				else:
					_defs[sid] = parsed
					_configs[sid] = _to_config(parsed)
					count += 1
		file_name = da.get_next()
	da.list_dir_end()
	return count


static func _ensure_loaded() -> void:
	if not _loaded:
		load_all()


static func _parse_json_file(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("ScenarioCatalog: failed to open %s (err=%d)" % [path, FileAccess.get_open_error()])
		return null
	var text: String = f.get_as_text()
	f.close()
	var result: Variant = JSON.parse_string(text)
	if not (result is Dictionary):
		push_warning("ScenarioCatalog: %s did not parse to a JSON object" % path)
		return null
	return result


static func has(id: String) -> bool:
	_ensure_loaded()
	return _builtin_builders.has(id) or _defs.has(id)


static func all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for id: String in _builtin_builders.keys():
		ids.append(id)
	for id: String in _defs.keys():
		ids.append(id)
	return ids


# JSON-only raw metadata (contexts, intensity, axis, min_leg, once_per_run,
# trigger_status, weight, ...) — the fields §10 selection needs that live outside
# the ScenarioRunner config shape. Bespoke builtins return {} — see class doc.
static func defs(id: String) -> Dictionary:
	_ensure_loaded()
	return _defs.get(id, {})


# The ScenarioRunner-compatible config dict (events/win_flags/leg_delta_*/
# morph_edges/monitor) — exactly the shape QuarantineScenario.build() returns.
# Unknown ids return {} — callers (ScenarioRunner._build_scenario_config) are
# expected to check has() first and fall back themselves.
static func build_config(id: String) -> Dictionary:
	_ensure_loaded()
	if _builtin_builders.has(id):
		var callable: Callable = _builtin_builders[id]
		return callable.call()
	return _configs.get(id, {}).duplicate(true)


static func _to_config(def: Dictionary) -> Dictionary:
	return {
		"id": def.get("id", ""),
		"title": def.get("title", ""),
		"starting_tone": float(def.get("tone_start", 0.4)),
		"win_flags": (def.get("win_flags", []) as Array).duplicate(),
		"leg_delta_success": (def.get("leg_delta_success", {}) as Dictionary).duplicate(true),
		"leg_delta_crew_dead": (def.get("leg_delta_crew_dead", {}) as Dictionary).duplicate(true),
		"events": _build_events(def.get("events", [])),
		"pressure_axis": def.get("pressure_axis", "mystery"),
		"expected_length": float(def.get("expected_length", 240.0)),
		"morph_edges": (def.get("morph_edges", []) as Array).duplicate(true),
		# GenericScenarioMonitor's program (spec §4.3) — opaque to ScenarioRunner,
		# read only by the monitor itself (engine task D).
		"monitor": (def.get("monitor", {}) as Dictionary).duplicate(true),
	}


# JSON event dicts -> Array[ScenarioEvent] (spec §4.2: same fields as ScenarioEvent).
# Conditions/outcomes stay plain Dictionaries — ScenarioEvent's own @export typing
# (Array[Dictionary]) takes the JSON arrays as-is, same vocabulary EventPool/
# OutcomeApplier already read for the bespoke scenarios.
static func _build_events(events_in: Array) -> Array[ScenarioEvent]:
	var events: Array[ScenarioEvent] = []
	for event_v in events_in:
		var d: Dictionary = event_v
		var event := ScenarioEvent.new()
		event.event_id = String(d.get("event_id", ""))
		event.title = String(d.get("title", ""))
		event.description = String(d.get("description", ""))
		event.tone_min = float(d.get("tone_min", 0.0))
		event.tone_max = float(d.get("tone_max", 1.0))
		event.weight = float(d.get("weight", 1.0))
		event.min_elapsed = float(d.get("min_elapsed", 0.0))
		event.cooldown = float(d.get("cooldown", 300.0))
		event.one_shot = bool(d.get("one_shot", false))
		var conditions: Array[Dictionary] = []
		for c in (d.get("conditions", []) as Array):
			conditions.append(c as Dictionary)
		event.conditions = conditions
		var outcomes: Array[Dictionary] = []
		for o in (d.get("outcomes", []) as Array):
			outcomes.append(o as Dictionary)
		event.outcomes = outcomes
		events.append(event)
	return events


# --- Overseer selection (docs/mission-system-spec.md §10) ---
#
# Deliberately self-contained/stateless: the caller (MissionManager/ScenarioDirector,
# full wiring in task E) owns once_per_run bookkeeping, active-scenario axis tracking,
# and effective_heat's actual computation. This function only applies the closed
# selection rules to whatever it's handed:
#   - context filter: candidate must list `context` in its contexts, or list "any"
#   - min_leg gate
#   - once_per_run / already-recent exclusion: `recent_ids` is a hard exclusion set
#     the caller builds (used-once-per-run ids + however much recent history it wants
#     soft-avoided) — kept this simple on purpose so pick() stays trivially
#     unit-testable without a live GameState/ScenarioDirector.
#   - axis compatibility: candidate's pressure_axis must not be in `active_axes`,
#     UNLESS its axis is "social" (spec: "social axis scenario is exempt — can run
#     alongside anything").
#   - intensity gate: intensity 3 requires effective_heat >= 0.6 OR leg >= 4.
#   - mercy weighting: below heat 0.35, intensity-1 candidates get a 3x weight boost.
#   - weight = def.weight * tag_bias[axis] * weakness-fit (tag_bias is the mission
#     hook's own `tag_bias` dict, keyed by pressure_axis names, e.g. {"bio": 1.5}).
#   - weakness-fit (task E, spec §10): weight *= 1.5 when the candidate's axis is in
#     `weak_axes` — the caller's own computed list of currently-vulnerable axes
#     (ScenarioDirector.current_weak_axes(), which reads live GameState/crew so this
#     function itself stays free of that dependency — same spirit as active_axes/
#     tag_bias/recent_ids above, all caller-supplied rather than read in here).
#     "mystery" never appears in weak_axes by construction — spec: "mystery: flat".
# Returns "" if no candidate survives the filters.
static func pick(context: String, tag_bias: Dictionary, leg: int, active_axes: Array,
		recent_ids: Array, effective_heat: float, rng: RandomNumberGenerator = null,
		weak_axes: Array = []) -> String:
	_ensure_loaded()
	var candidates: Array[String] = []
	var weights: Array[float] = []

	for id: String in _defs.keys():   # builtins never participate in pick() — see class doc
		if id in recent_ids:
			continue
		var def: Dictionary = _defs[id]
		var contexts: Array = def.get("contexts", [])
		if not (context in contexts or "any" in contexts):
			continue
		if leg < int(def.get("min_leg", 0)):
			continue
		var axis: String = String(def.get("pressure_axis", ""))
		if axis != "social" and axis in active_axes:
			continue
		var intensity: int = int(def.get("intensity", 1))
		if intensity >= 3 and effective_heat < 0.6 and leg < 4:
			continue
		# trigger_status scenarios are the DELAYED PAYOFF for a hidden crew status
		# flag (spec §10) — their cast bindings (e.g. status:shaken) resolve to
		# nobody on a ship where no one carries the flag, leaving the scenario
		# hollow. Keep them out of ordinary hook draws until the status actually
		# exists aboard; the force-attach payoff path doesn't route through pick().
		var trigger: String = String(def.get("trigger_status", ""))
		if trigger != "" and not GameState.any_crew_status(trigger):
			continue

		var weight: float = float(def.get("weight", 1.0)) * float(tag_bias.get(axis, 1.0))
		if axis in weak_axes:
			weight *= 1.5
		if effective_heat < 0.35 and intensity == 1:
			weight *= 3.0

		candidates.append(id)
		weights.append(weight)

	if candidates.is_empty():
		return ""
	return candidates[_weighted_index(weights, rng)]


static func _weighted_index(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total: float = 0.0
	for w in weights:
		total += maxf(w, 0.0)
	if total <= 0.0:
		return (rng.randi_range(0, weights.size() - 1) if rng != null else randi_range(0, weights.size() - 1))
	var roll: float = (rng.randf() if rng != null else randf()) * total
	var cumulative: float = 0.0
	for i in weights.size():
		cumulative += maxf(weights[i], 0.0)
		if roll <= cumulative:
			return i
	return weights.size() - 1
