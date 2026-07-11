class_name AwayResolver
extends RefCounted

# Off-screen away-op resolver (docs/mission-system-spec.md §6). One instance per op,
# owned/ticked by ShuttleSystem (RefCounted, not a Node — ShuttleSystem is already a
# ticking Node and this needs no scene-tree presence of its own, same shape as
# Checks/WoundTable/RepairModel elsewhere in this codebase).
#
# The player NEVER sees this run directly — it plays 2-4 beats across a 90-180s window of
# TimeManager time (ShuttleSystem.tick(delta) drives us forward every EventBus.time_ticked,
# so pause/SHIPAI_AWAY_FAST both apply for free, same as every other mission timer), and the
# only live signal that escapes is a `radio_bark` per beat. Everything else — wounds, hidden
# exposure flags, found items, a possible new crew member — lands in the final report
# (build_report()) that ShuttleSystem hands to EventBus.shuttle_returned. Report contains
# ONLY observable facts; `crew_status_flag`-style exposure never appears in it (spec §6
# step 3: "the AI never learns about hidden exposure").
#
# Deterministic: every roll goes through the RNG passed in at construction (seeded from
# MissionManager.rng by ShuttleSystem), so a pinned SHIPAI_SEED reproduces an op exactly.

const BEAT_KINDS: Array[String] = [
	"nothing", "find", "hazard", "exposure", "shuttle_strain", "contact", "survivor",
]

# Base per-beat-kind weights by away_risk.tier (spec §6 step 2). Not published numbers in
# the spec itself — authored here to read as "low tier = mostly fine, extreme tier = mostly
# not" while keeping every kind reachable at every tier (a `nothing`/`find` floor even at
# extreme, so a bad run still occasionally breathes).
const BASE_WEIGHTS_BY_TIER: Dictionary = {
	"low":      {"nothing": 40.0, "find": 25.0, "hazard": 10.0, "exposure": 5.0,  "shuttle_strain": 5.0,  "contact": 12.0, "survivor": 3.0},
	"moderate": {"nothing": 28.0, "find": 22.0, "hazard": 18.0, "exposure": 10.0, "shuttle_strain": 8.0,  "contact": 11.0, "survivor": 3.0},
	"high":     {"nothing": 16.0, "find": 18.0, "hazard": 26.0, "exposure": 16.0, "shuttle_strain": 12.0, "contact": 9.0,  "survivor": 3.0},
	"extreme":  {"nothing": 8.0,  "find": 12.0, "hazard": 34.0, "exposure": 22.0, "shuttle_strain": 16.0, "contact": 6.0,  "survivor": 2.0},
}

# away_risk.outcome_bias keys that DON'T scale the beat-kind table above — they scale which
# hidden status flag an `exposure` beat plants instead (spec: "weight by mission bias").
# Recognised so they don't trip the "unknown bias key" warning meant for genuinely unknown
# keys (a content-author typo, or a bias vocabulary this resolver doesn't know about yet).
const EXPOSURE_BIAS_KEYS: Dictionary = {
	"crew_infected": "infected", "crew_changed": "changed",
	"crew_shaken": "shaken", "crew_marked": "marked",
}
const EXPOSURE_FLAGS: Array[String] = ["infected", "changed", "shaken", "marked"]

const WOUND_TYPES_BY_SITE: Dictionary = {
	"surface":    ["bleeding", "blunt_force", "gore_massive"],
	"derelict":   ["blunt_force", "gore_massive", "fire_explosives"],
	"station":    ["blunt_force", "gunshot", "fire_explosives"],
	"other_ship": ["gunshot", "blunt_force", "fire_explosives"],
}

const FLAVOR_NOTHING: Array[String] = [
	"Nothing to report. Proceeding on schedule.",
	"Quiet out here. Still working the site.",
]
const FLAVOR_CONTACT: Array[String] = [
	"Thought we heard something. Standing by.",
	"Movement at the edge of the light. Holding position.",
]

const LOST_CHANCE_EXTREME: float = 0.12   # spec: "rare"

var team_ids: Array[String] = []
var site: String = ""
var mission_id: String = ""
var shuttle: ShuttleSystem = null
var rng: RandomNumberGenerator = null
var fast: bool = false

var tier: String = "moderate"
var outcome_bias: Dictionary = {}
var skill_mitigators: Array = []
var item_mitigators: Array = []
var weight_table: Dictionary = {}

var duration: float = 120.0
var beat_times: Array[float] = []
var elapsed: float = 0.0
var beat_index: int = 0

var _complete: bool = false
var _lost: bool = false

var pre_stress: Dictionary = {}   # crew_id -> int, snapshot at op start
var pre_wounds: Dictionary = {}   # crew_id -> int, snapshot at op start

# --- Report accumulators (only what makes it into build_report() is player-observable) ---
var bark_log: Array[Dictionary] = []
var wound_events: Array[Dictionary] = []   # [{crew_id, severity}] — visible
var items_found: Array[String] = []
var credits_found: float = 0.0
var survivor_id: String = ""
var survivor_crew: CrewMember = null


func _init(p_team: Array[String], p_site: String, p_mission: MissionDef, p_shuttle: ShuttleSystem,
		p_rng: RandomNumberGenerator, p_fast: bool) -> void:
	team_ids = p_team.duplicate()
	site = p_site
	shuttle = p_shuttle
	rng = p_rng
	fast = p_fast

	var away_risk: Dictionary = p_mission.away_risk if p_mission != null else {}
	mission_id = p_mission.id if p_mission != null else ""
	tier = String(away_risk.get("tier", "moderate"))
	if tier not in BASE_WEIGHTS_BY_TIER:
		tier = "moderate"
	outcome_bias = away_risk.get("outcome_bias", {})
	skill_mitigators = away_risk.get("skill_mitigators", [])
	item_mitigators = away_risk.get("item_mitigators", [])
	weight_table = _build_weight_table()

	# Spec §6 step 2: "op duration 90-180s ... plays 2-4 beats at intervals."
	# SHIPAI_AWAY_FAST=1 compresses every op duration 10x (spec §12/task brief), which this
	# resolver — not ShuttleSystem's choreography timers — owns since it's the one place
	# that actually needs to know the op's total length up front.
	var base_duration: float = rng.randf_range(90.0, 180.0)
	duration = base_duration / 10.0 if fast else base_duration

	var beat_count: int = rng.randi_range(2, 4)
	var slice: float = duration / float(beat_count + 1)
	for i in beat_count:
		var t: float = slice * float(i + 1) + rng.randf_range(-slice * 0.25, slice * 0.25)
		beat_times.append(clampf(t, 0.5, duration - 0.5))
	beat_times.sort()

	for crew_id: String in team_ids:
		var c: CrewMember = GameState.crew.get(crew_id) as CrewMember
		if c != null:
			pre_stress[crew_id] = c.stress
			pre_wounds[crew_id] = c.wounds


func _build_weight_table() -> Dictionary:
	var base: Dictionary = (BASE_WEIGHTS_BY_TIER.get(tier, BASE_WEIGHTS_BY_TIER["moderate"]) as Dictionary).duplicate()
	var unknown: Array[String] = []
	for key: String in outcome_bias.keys():
		if key in base:
			base[key] = float(base[key]) * float(outcome_bias[key])
		elif key in EXPOSURE_BIAS_KEYS:
			pass   # consumed by _pick_exposure_flag() instead — not a beat-kind weight
		else:
			unknown.append(key)
	if not unknown.is_empty():
		push_warning("AwayResolver: unknown away_risk.outcome_bias key(s) %s ignored (mission=%s, closed beat-kind vocabulary: %s)" % [
			unknown, mission_id, BEAT_KINDS])
	return base


# --- Task E injection point (spec §6 step 2: "a scenario may REPLACE the table for one
# beat"). Currently a no-op passthrough — task E (away_return-context scenarios) wires
# ScenarioDirector/OutcomeApplier state into this to override specific beat indices. Keep
# this method's name/signature stable; it's the documented hand-off point. ---
func _apply_away_return_injection(_beat_index: int, base_weights: Dictionary) -> Dictionary:
	return base_weights


# --- Tick loop (driven by ShuttleSystem's own EventBus.time_ticked handler) ---

func tick(delta: float) -> void:
	if _complete:
		return
	elapsed += delta
	while beat_index < beat_times.size() and elapsed >= beat_times[beat_index]:
		_resolve_beat(beat_index)
		beat_index += 1
		if _complete:
			return   # hull failure mid-op ends things early (see _abort_from_hull_failure)
	if elapsed >= duration:
		if tier == "extreme" and rng.randf() < LOST_CHANCE_EXTREME:
			_lost = true
		_complete = true


func is_complete() -> bool:
	return _complete


# --- Beat resolution ---

func _resolve_beat(index: int) -> void:
	var weights: Dictionary = _apply_away_return_injection(index, weight_table)
	match _weighted_pick_kind(weights):
		"nothing":
			_bark_calm(_flavor_nothing())
		"find":
			_do_find()
		"hazard":
			_do_hazard()
		"exposure":
			_do_exposure()
		"shuttle_strain":
			_do_shuttle_strain()
		"contact":
			_do_contact()
		"survivor":
			_do_survivor()


func _weighted_pick_kind(weights: Dictionary) -> String:
	var total: float = 0.0
	for k: String in BEAT_KINDS:
		total += maxf(float(weights.get(k, 0.0)), 0.0)
	if total <= 0.0:
		return "nothing"
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for k: String in BEAT_KINDS:
		acc += maxf(float(weights.get(k, 0.0)), 0.0)
		if roll <= acc:
			return k
	return "nothing"


func _living_team() -> Array[CrewMember]:
	var out: Array[CrewMember] = []
	for crew_id: String in team_ids:
		var c: CrewMember = GameState.crew.get(crew_id) as CrewMember
		if c != null and c.is_alive:
			out.append(c)
	return out


# --- find: item/cargo/data per a lightweight rewards-ish table ---

func _do_find() -> void:
	if rng.randf() < 0.45:
		var credit_amt: float = rng.randf_range(50.0, 300.0)
		credits_found += credit_amt
		GameState.adjust_metric("credits", credit_amt)
		_bark_calm("Found something worth logging — salvage, call it %d credits." % int(credit_amt))
		return
	var pool: Array[String] = ["med_kit", "medscanner", "jury_rig_kit", "engineers_toolkit", "stimpak"]
	var item_id: String = pool[rng.randi_range(0, pool.size() - 1)]
	var living: Array[CrewMember] = _living_team()
	if not living.is_empty():
		living[rng.randi_range(0, living.size() - 1)].inventory.append(item_id)
	items_found.append(item_id)
	_bark_calm("Picked up a %s." % String(Items.get_item(item_id).get("name", item_id)))


# --- hazard: a REAL Checks.perform_check against the best-suited team member ---

func _do_hazard() -> void:
	var living: Array[CrewMember] = _living_team()
	if living.is_empty():
		return
	var responder: CrewMember = _best_hazard_responder(living)
	var mitigated: bool = _has_mitigation(responder)
	var advantage: bool = mitigated
	var disadvantage: bool = tier == "extreme" and not mitigated
	var skill_name: String = responder.best_skill_name(skill_mitigators) if not skill_mitigators.is_empty() else ""
	var result: Checks.CheckResult = Checks.perform_check(responder, "body", skill_name, advantage, disadvantage)

	if result.success:
		_bark_tense("Rough moment out there — %s kept it together." % responder.crew_name)
		return

	var crit: bool = result.critical_failure()
	# Crit-fail always draws real blood; a plain fail only does on high/extreme tiers —
	# lower tiers let a plain fail cost stress instead (spec: "crit-fail/fail consequences
	# per tier").
	if crit or tier in ["high", "extreme"]:
		var cell: Dictionary = WoundTable.roll_and_apply(responder, _hazard_wound_type())
		if responder.is_alive:
			wound_events.append({"crew_id": responder.crew_id, "severity": String(cell.get("severity", ""))})
			_bark_bad("%s took a wound out there." % responder.crew_name)
		else:
			_bark_bad("%s didn't make it." % responder.crew_name)
			return
		# "death only on extreme+crit-fail or failed Body save after grave wound" — the
		# extreme+crit-fail case gets an EXTRA save on top of whatever WoundTable's own
		# Death Save chain just resolved (grave wounds already roll their own via
		# WoundTable.death_save when applicable).
		if tier == "extreme" and crit and responder.is_alive:
			var save: Checks.CheckResult = Checks.save_check(responder.get_stat_or_save("body"))
			if not save.success:
				CrewLifecycle.kill(responder, "away_op_hazard")
				wound_events.append({"crew_id": responder.crew_id, "severity": "fatal_injury"})
				_bark_bad("%s didn't make it." % responder.crew_name)
	else:
		responder.add_stress(2)
		_bark_bad("%s took a bad scare out there." % responder.crew_name)


func _best_hazard_responder(living: Array[CrewMember]) -> CrewMember:
	if skill_mitigators.is_empty():
		return living[rng.randi_range(0, living.size() - 1)]
	var best: CrewMember = living[0]
	var best_bonus: int = best.best_skill_bonus(skill_mitigators)
	for c: CrewMember in living:
		var b: int = c.best_skill_bonus(skill_mitigators)
		if b > best_bonus:
			best_bonus = b
			best = c
	return best


func _has_mitigation(c: CrewMember) -> bool:
	if not skill_mitigators.is_empty() and c.best_skill_bonus(skill_mitigators) > 0:
		return true
	for item_id in item_mitigators:
		if String(item_id) in c.inventory:
			return true
	return false


func _hazard_wound_type() -> String:
	var pool: Array = WOUND_TYPES_BY_SITE.get(site, WoundTable.WOUND_TYPES)
	return String(pool[rng.randi_range(0, pool.size() - 1)])


# Hull failure mid-op (spec §7: "at 0 during an op -> op aborts with casualties roll") —
# a disadvantaged Body save per living team member; failure draws a real wound. The op ends
# here (report still reflects whoever's left standing), distinct from the rare "lost"
# ending, which only ever happens on a clean run-to-completion roll (see tick()).
func _abort_from_hull_failure() -> void:
	for c: CrewMember in _living_team():
		var result: Checks.CheckResult = Checks.save_check(c.get_stat_or_save("body"), 0, false, true)
		if not result.success:
			var cell: Dictionary = WoundTable.roll_and_apply(c, _hazard_wound_type())
			if c.is_alive:
				wound_events.append({"crew_id": c.crew_id, "severity": String(cell.get("severity", ""))})
	_bark_bad("Hull failure — the op is aborting.")
	_complete = true


# --- exposure: HIDDEN crew_status_flag, weighted by mission bias, no HUD tell ---

func _do_exposure() -> void:
	var living: Array[CrewMember] = _living_team()
	if living.is_empty():
		return
	var target: CrewMember = living[rng.randi_range(0, living.size() - 1)]
	var flag: String = _pick_exposure_flag()
	target.set_status_flag(flag, true)
	# Deliberately generic/vague bark text — the exposure itself must never leak through
	# the ONLY live signal the player gets (spec §6 step 3: "the AI never learns about
	# hidden exposure"). A corpus away_radio_bad line (picked with no knowledge of the
	# hidden flag) reads the same as any other bad beat.
	_bark_bad("Something's off, but everyone's still on their feet.")
	# Debug-only visibility (task brief: "report whether an exposure flag got set, print via
	# debug env only") — NEVER surfaced through any player-facing signal; this print exists
	# purely so a dev soak test can confirm the hidden mechanic actually fired.
	if OS.get_environment("SHIPAI_MISSION_DEBUG") == "1":
		print("[AWAY-DEBUG] hidden exposure: %s <- '%s' (never sent to the AI/HUD)" % [target.crew_id, flag])


func _pick_exposure_flag() -> String:
	var weights: Dictionary = {"infected": 1.0, "changed": 1.0, "shaken": 1.0, "marked": 1.0}
	for bias_key: String in EXPOSURE_BIAS_KEYS:
		if outcome_bias.has(bias_key):
			var flag: String = String(EXPOSURE_BIAS_KEYS[bias_key])
			weights[flag] = float(weights[flag]) * float(outcome_bias[bias_key])
	var total: float = 0.0
	for k: String in EXPOSURE_FLAGS:
		total += float(weights[k])
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for k: String in EXPOSURE_FLAGS:
		acc += float(weights[k])
		if roll <= acc:
			return k
	return "shaken"


# --- shuttle_strain: return damage ---

func _do_shuttle_strain() -> void:
	var amount: float = rng.randf_range(4.0, 14.0) * _tier_strain_mult()
	if shuttle != null:
		shuttle.apply_hull_strain(amount)
	_bark_tense("The %s took a knock — minor damage." % ("shuttle" if site == "surface" else "hull seal"))
	if shuttle != null and shuttle.shuttle_hull <= 0.0:
		_abort_from_hull_failure()


func _tier_strain_mult() -> float:
	match tier:
		"low": return 0.6
		"high": return 1.3
		"extreme": return 1.8
		_: return 1.0


# --- contact: radio_line colour + fear ---

func _do_contact() -> void:
	var living: Array[CrewMember] = _living_team()
	if not living.is_empty():
		var c: CrewMember = living[rng.randi_range(0, living.size() - 1)]
		c.fear = minf(1.0, c.fear + 0.08)
	_bark_tense(_flavor_contact())


# --- survivor: crew_join candidate queued to board on return ---

func _do_survivor() -> void:
	if survivor_id != "":
		return   # one per op — a second roll just reads as more of the same beat
	var gen_seed: int = rng.randi()
	# required_roles=[] leaves slot 0's ROLE randomised (CrewGen._random_role()), but
	# generate_roster's own captain_slot default is still index 0 whenever required_roles is
	# empty — it would hand this rescued survivor the "captain" RANK, which would collide
	# with the ship's own captain (CrewGen's "exactly one captain per ship" rule only holds
	# WITHIN a single generate_roster call, not across two separate ones). Force a sane
	# rescued-stranger rank afterward rather than fighting CrewGen's API for a one-off.
	var roster: Array[CrewMember] = CrewGen.generate_roster(gen_seed, 1, [])
	if roster.is_empty():
		return
	var new_crew: CrewMember = roster[0]
	new_crew.crew_id = "survivor_%d" % gen_seed
	new_crew.rank = "crew_mate"
	survivor_id = new_crew.crew_id
	survivor_crew = new_crew
	_bark_tense("Picked up a signal — someone's still alive out there.")


# --- Barks: real corpus line when the away team has one, generic flavour otherwise.
# Either way it's the ONLY live window the player gets (spec §6 step 2) — routed through
# EventBus.radio_bark since the away team is off-ship (no CrewMemberNode to bubble over). ---

func _bark(tone: String, fallback_text: String) -> void:
	var speaker_id: String = _pick_speaker()
	var text: String = ""
	if speaker_id != "":
		text = DialogueSystem.speak_intent(speaker_id, "away_radio_%s" % tone)
	if text == "":
		text = fallback_text
	bark_log.append({"text": text, "tone": tone, "at": elapsed})
	EventBus.radio_bark.emit(text, tone)


func _bark_calm(text: String) -> void:
	_bark("calm", text)


func _bark_tense(text: String) -> void:
	_bark("tense", text)


func _bark_bad(text: String) -> void:
	_bark("bad", text)


func _pick_speaker() -> String:
	var living: Array[CrewMember] = _living_team()
	if living.is_empty():
		return ""
	return living[rng.randi_range(0, living.size() - 1)].crew_id


func _flavor_nothing() -> String:
	return FLAVOR_NOTHING[rng.randi_range(0, FLAVOR_NOTHING.size() - 1)]


func _flavor_contact() -> String:
	return FLAVOR_CONTACT[rng.randi_range(0, FLAVOR_CONTACT.size() - 1)]


# --- Report (spec §6 step 3: ONLY observable facts — no hidden flags) ---

func build_report() -> Dictionary:
	var returning: Array[String] = []
	var outcomes: Dictionary = {}
	for crew_id: String in team_ids:
		var c: CrewMember = GameState.crew.get(crew_id) as CrewMember
		if c == null or not c.is_alive or _lost:
			continue
		returning.append(crew_id)
		outcomes[crew_id] = _classify_outcome(c)

	var wound_severities: Dictionary = {}
	for w: Dictionary in wound_events:
		wound_severities[String(w["crew_id"])] = String(w["severity"])

	return {
		"mission_id": mission_id,
		"site": site,
		"team_ids": team_ids.duplicate(),
		"returning_crew_ids": returning,
		"crew_outcomes": outcomes,
		"wound_severities": wound_severities,
		"shuttle_hull": shuttle.shuttle_hull if shuttle != null else 100.0,
		"items_found": items_found.duplicate(),
		"credits_found": credits_found,
		"survivor_id": survivor_id,
		"survivor_crew": survivor_crew,
		"bark_log": bark_log.duplicate(true),
		"lost": _lost,
	}


# Per-crew observable outcome (spec dialogue bridge: "keyed off THAT crew member's own
# observable outcome ... not the mission's overall outcome") — wound state / stress delta
# from THIS op only, never the hidden exposure flag.
func _classify_outcome(c: CrewMember) -> String:
	if int(c.wounds) > int(pre_wounds.get(c.crew_id, 0)):
		return "injured"
	if c.stress - int(pre_stress.get(c.crew_id, c.stress)) >= 3:
		return "shaken"
	return "fine"
