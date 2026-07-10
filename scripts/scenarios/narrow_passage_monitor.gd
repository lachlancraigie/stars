class_name NarrowPassageMonitor
extends Node

# Turns The Narrow Passage's flags into achievable, timed play (the Monitor pattern —
# same shape as QuarantineMonitor). The scenario builder (NarrowPassageScenario) owns
# every timing/threshold/trust knob in its config's "monitor" section; this node owns
# only the clockwork:
#
#   approach warning -> shutdown deadline (comply early = the AI's own choice, trust
#   credit; still hot at the boundary = forced emergency scram, trust cost) -> the
#   crossing on battery with the 3-powered / 3-life-supported room caps live ->
#   scripted turbulence scares (battery drain + crossing extension) -> a fragile
#   patient in the medbay whose Body Saves run against cold/thin air -> exit on timer
#   (or early, if the engineer relights the reactor mid-field) -> reactor restart ->
#   passage_cleared (win, graded by trust/battery/patient outcomes).
#
# Lose paths: battery exhausted inside the field (short dark-drift grace, then the
# hull gives — GameState.destroy_ship), plus every standard ScenarioRunner lose
# condition. A dead patient does NOT gate the win (scenario-bible: "you can clear the
# field with a dead patient, and the game lets you live with that, on purpose") — it
# colors trust and the ending instead.
#
# Rule 1 note: nothing here sets crew position/state/action. Crew are pressured
# exclusively through GameState mutators (reactor/battery/power/air), Checks-resolved
# Body Saves, and ScenarioDirector event outcomes; movement stays with CrewBehavior
# and the player's directives.
#
# Director-AI friendliness (per coordinator note): all tuning comes from setup()'s
# config; every EventBus connection is additive (connect, never monopolize); every
# handler gates on this scenario's own flags/config so a co-running scenario is
# unaffected.

# Phases of the clockwork, in order.
const PHASE_PRE: String = "pre"              # before the approach warning
const PHASE_ORDERED: String = "ordered"      # shutdown ordered, deadline counting
const PHASE_CROSSING: String = "crossing"    # inside the field, on battery
const PHASE_RESTART: String = "restart"      # field cleared, reactor still cold
const PHASE_DONE: String = "done"            # resolved (win fired) or scenario over

var _cfg: Dictionary = {}                    # NarrowPassageScenario.build()["monitor"]
var _trust_cfg: Dictionary = {}
var _events_by_id: Dictionary = {}           # event_id -> ScenarioEvent (from the builder)

var _phase: String = PHASE_PRE
var _t0: float = -1.0                        # TimeManager.elapsed at first tick
var _quiet_shift_sent: bool = false
var _shutdown_mode: String = ""              # "" | "complied" | "forced"
var _entry_t: float = 0.0                    # scenario-relative time of field entry
var _exit_t: float = 0.0                     # scenario-relative time the field clears
var _turb_fired: int = 0
var _appeal_fired: bool = false
var _relight_seen: bool = false
var _stranded_since: float = -1.0
var _min_battery: float = 100.0              # lowest battery seen during the crossing
var _crossing_time: float = 0.0
var _bridge_powered_time: float = 0.0

var _patient_stability: float = 100.0
var _patient_check_t: float = 0.0
var _patient_crash_announced: bool = false
var _patient_lost: bool = false

var _last_objective: String = ""

# Resolved once at _ready — rooms by TYPE, crew by ROLE (never hardcoded ids).
var _medbay_id: String = ""
var _bridge_id: String = ""
var _engine_id: String = ""
var _patient_id: String = ""
var _medic_id: String = ""
var _captain_id: String = ""
var _engineer_id: String = ""


# Hand the monitor the same dictionary ScenarioRunner.start_scenario() receives, so
# builder data and monitor behaviour can never drift apart. Call before add_child().
func setup(config: Dictionary) -> void:
	_cfg = config.get("monitor", {})
	_trust_cfg = _cfg.get("trust", {})
	_patient_stability = _cfgf("patient_stability_max", 100.0)
	_min_battery = GameState.battery_charge
	for event: ScenarioEvent in config.get("events", []):
		_events_by_id[event.event_id] = event


func _ready() -> void:
	_medbay_id = GameState.get_room_of_type("medbay")
	_bridge_id = GameState.get_room_of_type("bridge")
	_engine_id = GameState.get_room_of_type("engine_room")
	_patient_id = GameState.get_crew_of_role("general")
	_medic_id = GameState.get_crew_of_role("medic")
	_captain_id = GameState.get_crew_of_role("captain")
	_engineer_id = GameState.get_crew_of_role("engineer")
	if _cfg.is_empty():
		push_warning("NarrowPassageMonitor: setup() not called before _ready — monitor inert")
	if _medbay_id == "" or _engine_id == "":
		push_warning("NarrowPassageMonitor: ship lacks a medbay/engine_room — scenario cannot progress properly")
	EventBus.time_ticked.connect(_on_tick)
	EventBus.crew_died.connect(_on_crew_died)
	EventBus.scenario_event_triggered.connect(_on_scenario_event)
	EventBus.scenario_ended.connect(_on_scenario_ended)


# --- Tick clockwork ---

func _on_tick(elapsed: float, delta: float) -> void:
	if _cfg.is_empty() or _phase == PHASE_DONE:
		return
	if _t0 < 0.0:
		_t0 = elapsed
	var t: float = elapsed - _t0

	match _phase:
		PHASE_PRE:
			_tick_pre(t)
		PHASE_ORDERED:
			_tick_ordered(t)
		PHASE_CROSSING:
			_tick_crossing(t, delta)
		PHASE_RESTART:
			_tick_restart()


func _tick_pre(t: float) -> void:
	# The calm before: the dialogue corpus's quiet_shift lines get one clean cue.
	if not _quiet_shift_sent and t >= _cfgf("quiet_shift_at", 6.0):
		_quiet_shift_sent = true
		EventBus.recent_event.emit("quiet_shift", {"scenario": "narrow_passage"})
	if t >= _cfgf("approach_warning_at", 12.0):
		_fire("shear_field_detected")
		_phase = PHASE_ORDERED
		return
	_set_objective("Routine transit. A charted shear-field crossing lies ahead.")


func _tick_ordered(t: float) -> void:
	var deadline: float = _cfgf("shutdown_deadline", 50.0)

	# Early compliance: any reactor-offline before the deadline counts, whether it
	# came from the HUD's reactor control or (future) another control surface.
	if not GameState.reactor_online and _shutdown_mode == "":
		_shutdown_mode = "complied"
		_fire("reactor_shutdown_complied")

	if t >= deadline:
		if GameState.reactor_online:
			# The field forces the issue: emergency scram, at a price. (If the AI
			# complied and then let a relight finish before entry, the scram —
			# and its cost — is earned all the same; the trust delta rides on the
			# event's outcomes either way.)
			if _shutdown_mode == "":
				_shutdown_mode = "forced"
			GameState.set_reactor_online(false, "emergency_scram")
			_fire("reactor_forced_scram")
		_enter_crossing(t)
		return

	var remain: int = int(ceilf(deadline - t))
	if GameState.reactor_online:
		_set_objective("⚠ Shear field in %ds. Captain's orders: take the reactor OFFLINE before entry (top-left panel)." % remain)
	else:
		_set_objective("Reactor secured. Field entry in %ds — divert battery power (max %d rooms) and life support (max %d rooms)." % [
			remain, PowerModel.MAX_BATTERY_ROOMS, LifeSupportModel.MAX_LIFE_SUPPORT_ROOMS])


func _enter_crossing(t: float) -> void:
	_entry_t = t
	_exit_t = t + _cfgf("crossing_duration", 110.0)
	_phase = PHASE_CROSSING
	_fire("field_entry")


func _tick_crossing(t: float, delta: float) -> void:
	var since_entry: float = t - _entry_t

	# Allocation report-card bookkeeping (graded at resolution).
	_crossing_time += delta
	if _bridge_id != "" and GameState.get_room_powered(_bridge_id):
		_bridge_powered_time += delta
	_min_battery = minf(_min_battery, GameState.battery_charge)

	# Act 2 beat: the medic's counter-claim, shortly after entry.
	if not _appeal_fired and since_entry >= _cfgf("medic_appeal_offset", 8.0):
		_appeal_fired = true
		_fire("medic_appeal")

	# Act 3 scares: scripted turbulence at fixed offsets (the pool may fire extras;
	# both routes converge on _on_scenario_event for the crossing extension).
	var offsets: Array = _cfg.get("turbulence_offsets", [])
	while _turb_fired < offsets.size() and since_entry >= float(offsets[_turb_fired]):
		_turb_fired += 1
		_fire("field_turbulence")

	_tick_patient(delta)

	# Battery exhaustion inside the field: a short dark drift, then the hull gives.
	# A relight (which refills the bank) during the grace window cancels it.
	if GameState.battery_charge <= 0.0 and not GameState.reactor_online:
		if _stranded_since < 0.0:
			_stranded_since = t
			_fire("ship_stranded")
		elif t - _stranded_since >= _cfgf("stranded_grace", 20.0):
			GameState.destroy_ship("stranded_in_shear_field")
			_phase = PHASE_DONE
			return
	else:
		_stranded_since = -1.0

	# Early relight: the engineer got the reactor back mid-field — the ship powers
	# through the tail of the field instead of drifting the full chart width. Main
	# power also brings the air recyclers back up (the life-support "failure" was a
	# power cut, not damage — a legible reverse of the entry cascade).
	if GameState.reactor_online and not _relight_seen:
		_relight_seen = true
		if not GameState.life_support_online:
			GameState.set_life_support_online(true)
		_exit_t = minf(_exit_t, t + _cfgf("relight_exit_tail", 10.0))

	if t >= _exit_t:
		_fire("field_exited")
		if GameState.reactor_online:
			_resolve()
		else:
			_phase = PHASE_RESTART
		return

	_set_objective(_crossing_objective(t))


func _crossing_objective(t: float) -> String:
	if _stranded_since >= 0.0:
		var grace_left: int = int(ceilf(_cfgf("stranded_grace", 20.0) - (t - _stranded_since)))
		return "⚠ SHIP DARK — adrift in the field. %ds until hull stresses exceed tolerance." % maxi(0, grace_left)
	var text: String = "Crossing the shear field — ~%ds. Battery %d%%." % [
		int(ceilf(_exit_t - t)), int(GameState.battery_charge)]
	if _patient_lost:
		text += "  The medbay patient is gone."
	elif _patient_crash_announced:
		text += "  ⚠ Medbay patient failing."
	return text


func _tick_restart() -> void:
	if GameState.reactor_online:
		_resolve()
		return
	_set_objective("Field cleared. Restart the reactor — get %s to the Engine Room." % _crew_name(_engineer_id))


# --- The fragile patient (bible Act 2: "a real, measured mechanical cost") ---
# Scenario-scoped stability meter. Danger = medbay unpowered OR air below the
# Mothership disadvantage threshold; danger forces a Body Save through Checks every
# check-interval (thin-air disadvantage folds in automatically; the medic at the
# bedside grants advantage). Stability at 0 -> a real WoundTable Death Save.

func _tick_patient(delta: float) -> void:
	if _patient_lost or _medbay_id == "":
		return
	var patient: CrewMember = GameState.crew.get(_patient_id) as CrewMember
	if patient == null or not patient.is_alive:
		return

	var in_danger: bool = (not GameState.get_room_powered(_medbay_id)) \
		or GameState.get_room_air(_medbay_id) < LifeSupportModel.AIR_DISADVANTAGE_THRESHOLD
	if not in_danger:
		_patient_check_t = 0.0
		_patient_stability = minf(_cfgf("patient_stability_max", 100.0),
			_patient_stability + _cfgf("patient_recover_per_sec", 4.0) * delta)
		return

	_patient_check_t += delta
	if _patient_check_t < _cfgf("patient_check_interval", 12.0):
		return
	_patient_check_t = 0.0

	var medic_present: bool = _is_in(_medbay_id, _medic_id)
	var result: Checks.CheckResult = Checks.perform_check(patient, "body", "", medic_present)
	_patient_stability -= _cfgf("patient_drain_held", 8.0) if result.success \
		else _cfgf("patient_drain_failed", 30.0)

	if not _patient_crash_announced and _patient_stability <= _cfgf("patient_crash_threshold", 45.0):
		_patient_crash_announced = true
		_fire("patient_crashing")

	if _patient_stability <= 0.0:
		WoundTable.death_save(patient)
		if patient.is_alive:
			_patient_stability = _cfgf("patient_death_save_reset", 40.0)


func _on_crew_died(crew_id: String, _cause: String) -> void:
	if _cfg.is_empty() or _phase == PHASE_DONE or _patient_lost:
		return
	if crew_id != _patient_id:
		return
	_patient_lost = true
	_fire("patient_lost")   # carries the all-crew trust hit as an event outcome
	TrustModel.modify(_medic_id, _trustf("patient_lost_medic", -0.12))


# --- Resolution ---

func _resolve() -> void:
	_phase = PHASE_DONE
	# Main power is back; the recyclers spin up with it (see the relight note above).
	if not GameState.life_support_online:
		GameState.set_life_support_online(true)

	# Grade the crossing — small, legible trust deltas per the builder's knobs.
	var patient: CrewMember = GameState.crew.get(_patient_id) as CrewMember
	if not _patient_lost and patient != null and patient.is_alive:
		TrustModel.modify(_medic_id, _trustf("patient_saved_medic", 0.05))
	if _crossing_time > 0.0 and _captain_id != "":
		var bridge_fraction: float = _bridge_powered_time / _crossing_time
		if bridge_fraction >= _cfgf("bridge_fraction_threshold", 0.6):
			TrustModel.modify(_captain_id, _trustf("bridge_kept_captain", 0.03))
		else:
			TrustModel.modify(_captain_id, _trustf("bridge_dark_captain", -0.04))
	if _min_battery >= _cfgf("battery_margin_good", 40.0):
		TrustModel.modify_all(_trustf("battery_margin_all", 0.02))
	elif _min_battery <= _cfgf("battery_margin_scraped", 10.0):
		TrustModel.modify_all(_trustf("battery_scraped_all", -0.02))

	_fire("passage_cleared")   # sets the win flag; ScenarioRunner ends the leg next tick
	_set_objective("Passage cleared." if not _patient_lost else "Passage cleared. Not everyone made it through.")


# --- EventBus listeners (additive — never assume this is the only scenario) ---

# Both monitor-fired and pool-drawn turbulence converge here, so the crossing
# extension applies identically regardless of which path fired the event.
func _on_scenario_event(event_id: String) -> void:
	if _cfg.is_empty() or _phase != PHASE_CROSSING:
		return
	if event_id == "field_turbulence":
		_exit_t += _cfgf("turbulence_extension", 8.0)


func _on_scenario_ended(_outcome: String) -> void:
	# Whatever ended the leg (win, stranded, crew dead, decommission), stand down.
	_phase = PHASE_DONE


# --- Helpers ---

# Fires a builder-defined event through ScenarioDirector so outcome application
# (flags, trust deltas, fear spikes, resource deltas) stays on the one shared path.
func _fire(event_id: String) -> void:
	var event: ScenarioEvent = _events_by_id.get(event_id) as ScenarioEvent
	if event == null:
		push_warning("NarrowPassageMonitor: unknown event '%s'" % event_id)
		return
	ScenarioDirector.fire_event(event)


func _cfgf(key: String, default: float) -> float:
	return float(_cfg.get(key, default))


func _trustf(key: String, default: float) -> float:
	return float(_trust_cfg.get(key, default))


func _is_in(room_id: String, crew_id: String) -> bool:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	return crew != null and crew.is_alive and crew.location == room_id


func _crew_name(crew_id: String) -> String:
	var crew: CrewMember = GameState.crew.get(crew_id) as CrewMember
	return crew.crew_name if crew else (crew_id if crew_id != "" else "the engineer")


func _set_objective(text: String) -> void:
	if text == _last_objective:
		return
	_last_objective = text
	EventBus.objective_changed.emit(text)
