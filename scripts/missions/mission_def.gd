class_name MissionDef
extends RefCounted

# Parsed wrapper around one resources/missions/<id>.json file (docs/mission-system-spec.md
# §3). Pure data + light defaulting — no gameplay logic, no mutation after load.
# MissionDeck/MissionManager read these fields; nothing here talks to GameState/EventBus
# (Architecture Rule 3: GameState is the one mutable source of truth, not this).
#
# Field-level schema validation (closed-set enums, cross-reference checks) lives in
# tools/missions/validate_content.py, run at content-authoring time — this loader stays
# permissive (fills sane defaults for anything missing) so a slightly incomplete JSON
# still loads for iteration rather than hard-failing the whole deck.

const DEFAULT_PHASES: Dictionary = {
	"transit_out": 180.0, "arrival": 300.0, "on_station": 240.0, "transit_back": 180.0,
}
const DEFAULT_ELIGIBILITY: Dictionary = {
	"min_leg": 1, "requires_flags_all": [], "requires_flags_any": [],
	"excludes_flags": [], "min_hull": 0.0, "max_hull": 100.0,
}
const DEFAULT_REWARDS: Dictionary = {"credits": 0.0, "items": [], "metrics": {}}

var id: String = ""
var title: String = ""
var mission_type: String = ""
var giver: String = ""
var briefing: String = ""
var flavor: String = ""
var destination: Dictionary = {}                # kind, name, descriptor, art
var phases: Dictionary = DEFAULT_PHASES.duplicate()   # phase name -> seconds (float)
var objectives: Array[Dictionary] = []           # {id, text, kind, params, optional}
var away_risk: Dictionary = {}                   # tier, skill_mitigators, item_mitigators, outcome_bias
var eligibility: Dictionary = DEFAULT_ELIGIBILITY.duplicate(true)
var weight: float = 1.0
var priority: int = 0
var repeatable: bool = false
var scenario_hooks: Dictionary = {}              # phase (or "away_return") -> {chance, context, tag_bias}
var rewards: Dictionary = DEFAULT_REWARDS.duplicate(true)
var extra_outcome_flags: Dictionary = {}         # campaign_flag -> objective id
var follow_ons: Array[Dictionary] = []           # [{when, next, weight}]
var tags: Array[String] = []
var source_path: String = ""                     # "" for a dict built directly via from_dict()


static func from_dict(d: Dictionary) -> MissionDef:
	var m := MissionDef.new()
	m.id = String(d.get("id", ""))
	m.title = String(d.get("title", ""))
	m.mission_type = String(d.get("mission_type", ""))
	m.giver = String(d.get("giver", ""))
	m.briefing = String(d.get("briefing", ""))
	m.flavor = String(d.get("flavor", ""))
	m.destination = (d.get("destination", {}) as Dictionary).duplicate(true)

	var phases_in: Dictionary = d.get("phases", {})
	var phases_out: Dictionary = DEFAULT_PHASES.duplicate()
	for phase_key: String in phases_out.keys():
		phases_out[phase_key] = float(phases_in.get(phase_key, phases_out[phase_key]))
	m.phases = phases_out

	var objectives_out: Array[Dictionary] = []
	for obj_v in (d.get("objectives", []) as Array):
		objectives_out.append((obj_v as Dictionary).duplicate(true))
	m.objectives = objectives_out

	m.away_risk = (d.get("away_risk", {}) as Dictionary).duplicate(true)

	var elig_in: Dictionary = d.get("eligibility", {})
	var elig_out: Dictionary = DEFAULT_ELIGIBILITY.duplicate(true)
	for key: String in elig_out.keys():
		elig_out[key] = elig_in.get(key, elig_out[key])
	m.eligibility = elig_out

	m.weight = float(d.get("weight", 1.0))
	m.priority = int(d.get("priority", 0))
	m.repeatable = bool(d.get("repeatable", false))

	var hooks_out: Dictionary = {}
	var hooks_in: Dictionary = d.get("scenario_hooks", {})
	for phase_key: String in hooks_in.keys():
		hooks_out[phase_key] = (hooks_in[phase_key] as Dictionary).duplicate(true)
	m.scenario_hooks = hooks_out

	var rewards_in: Dictionary = d.get("rewards", {})
	var rewards_out: Dictionary = DEFAULT_REWARDS.duplicate(true)
	for key: String in rewards_out.keys():
		rewards_out[key] = rewards_in.get(key, rewards_out[key])
	m.rewards = rewards_out

	m.extra_outcome_flags = (d.get("extra_outcome_flags", {}) as Dictionary).duplicate(true)

	var follow_ons_out: Array[Dictionary] = []
	for fo_v in (d.get("follow_ons", []) as Array):
		follow_ons_out.append((fo_v as Dictionary).duplicate(true))
	m.follow_ons = follow_ons_out

	var tags_out: Array[String] = []
	for tag_v in (d.get("tags", []) as Array):
		tags_out.append(String(tag_v))
	m.tags = tags_out

	return m


# Returns null (with a push_warning) on any read/parse failure — callers (MissionDeck.
# load_all) skip nulls rather than aborting the whole directory scan over one bad file.
static func from_file(path: String) -> MissionDef:
	if not FileAccess.file_exists(path):
		push_warning("MissionDef: file not found — %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("MissionDef: failed to open %s (err=%d)" % [path, FileAccess.get_open_error()])
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("MissionDef: %s did not parse to a JSON object" % path)
		return null
	var m: MissionDef = from_dict(parsed)
	m.source_path = path
	if m.id == "":
		push_warning("MissionDef: %s has no 'id' field" % path)
	return m


# Hook keys are the four phases PLUS the "away_return" pseudo-phase (fires on
# EventBus.shuttle_returned — spec §3's own note). Missing hook -> no scenario offer
# at that phase, so an empty dict (falsy chance) is the correct default, not an error.
func get_hook(phase: String) -> Dictionary:
	return scenario_hooks.get(phase, {})
