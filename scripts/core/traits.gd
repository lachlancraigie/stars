class_name Traits
extends RefCounted

# X-COM-style veterancy trait registry (docs/crew-progression-spec.md §2/§3). Same pattern
# as Items (scripts/core/items.gd): a static REGISTRY of data, consumed by the handful of
# existing mechanical surfaces the spec names — no new subsystems, just reads. This file is
# also the single funnel for GRANTING a trait (see grant() below), the same way
# CrewLifecycle is the one funnel for a death.
#
# CrewMember.traits: Array[String] stores trait ids. Most ids are plain ("iron_lungs"); a
# few are parametrized as "base_id:param" (currently only "field_certified:<skill_name>",
# since that trait's bonus applies to whichever skill family the crisis repair actually
# used — baked into the id rather than adding a second per-crew data structure). base_id()/
# param() split that apart; REGISTRY is always keyed by base_id.
#
# Registry entry shape: {display_name, blurb, polarity: "buff"|"debuff", ...optional hooks}.
# A trait with none of the optional keys below is flavour/memorial-only.
#   tags: Dictionary tag -> int, folded into CrewMember.trait_bonus(tag) — same shape as
#         Items' tags/item_bonus, added as `extra_bonus` at specific Checks.perform_check
#         call sites (door bypass, repair, the suffocation Body check).
#   stat_bonus: Dictionary stat/save name -> int, folded into EVERY
#         CrewMember.get_stat_or_save() read for that stat — used only for traits with no
#         "vs X" qualifier in the spec table (Old Hand/Lifer's all-saves bonus, Scar
#         Tissue's flat Body, Old Wound's flat Speed penalty). Iron Lungs' Body bonus IS
#         qualified ("vs air/vacuum") so it uses `tags` (body_vs_air_bonus) instead, applied
#         only at the suffocation check call site.
#   skill_bonus: int, applied by CrewMember.get_skill_bonus() ONLY when the trait's own
#         param() matches the queried skill_name (Field-Certified).
#   min_stress_add: int, applied ONCE at grant time (crew.min_stress += N) — matches how
#         PanicTable's own min_stress bumps (_overwhelmed/_prophetic_vision/_heart_attack)
#         are permanent ratchets, never rolled back even if the trait is later replaced.
#   loneliness_floor: float 0..1, read continuously by NeedsModel (Widowed).
#   trust_floor / trust_ceiling: float 0..1, read continuously by GameState.set_ai_trust
#         (Believer / Machine-Wary) — a personal clamp on that crew member's AI trust score.
#   fear_disadvantage_low_air_or_airlock: bool flag, read by
#         CrewMember.has_vacuum_nightmares_disadvantage() (Vacuum Nightmares) — the one
#         trait whose effect is a conditional Disadvantage rather than a bonus, since
#         "fear checks at disadvantage in airlock/low-air rooms" isn't a flat number.
#   panic_table_shift: int, read by Checks.panic_check() (Battle Calm).
#   adjacent_panic_stress_bonus: int, read by Checks.panic_check() (Jumpy — renamed
#         "jumpy_nerves" in code to avoid colliding with PanicTable's unrelated roll-3
#         Condition tag, also literally called "jumpy").
#   stress_mult: Dictionary source -> float, read by CrewMember.add_stress() (Hardened).

const MAX_TRAITS: int = 5

const REGISTRY: Dictionary = {
	"iron_lungs": {
		"display_name": "Iron Lungs", "polarity": "buff",
		"blurb": "Survived near-vacuum once. The body rations a breath like it's still rationing that one.",
		"tags": {"body_vs_air_bonus": 5},
	},
	"vacuum_nightmares": {
		"display_name": "Vacuum Nightmares", "polarity": "debuff",
		"blurb": "The airlock cycle sounds exactly like the one that almost didn't open in time.",
		"fear_disadvantage_low_air_or_airlock": true,
	},
	"battle_calm": {
		"display_name": "Battle Calm", "polarity": "buff",
		"blurb": "Panic hasn't fully forgotten how to be useful — it lands a little softer here.",
		"panic_table_shift": -1,
	},
	"jumpy_nerves": {
		"display_name": "Jumpy", "polarity": "debuff",
		"blurb": "Somebody else's panic finds a way in before they can stop it.",
		"adjacent_panic_stress_bonus": 1,
	},
	"hardened": {
		"display_name": "Hardened", "polarity": "buff",
		"blurb": "Grief doesn't land the way it used to. That's not nothing to feel bad about.",
		"stress_mult": {"death": 0.5},
	},
	"survivors_guilt": {
		"display_name": "Survivor's Guilt", "polarity": "debuff",
		"blurb": "Should have been them instead, some quiet part keeps insisting.",
		"min_stress_add": 1,
	},
	"widowed": {
		"display_name": "Widowed", "polarity": "debuff",
		"blurb": "The bunk on the other side of the room stays exactly as it was left.",
		"loneliness_floor": 0.3,
	},
	"field_certified": {
		"display_name": "Field-Certified", "polarity": "buff",
		"blurb": "Learned it live, under fire, and it stuck.",
		"skill_bonus": 5,
	},
	"scar_tissue": {
		"display_name": "Scar Tissue", "polarity": "buff",
		"blurb": "Healed wrong, healed strong.",
		"stat_bonus": {"body": 2},
	},
	"old_wound": {
		"display_name": "Old Wound", "polarity": "debuff",
		"blurb": "Aches before a storm — and out here, it's always about to storm.",
		"stat_bonus": {"speed": -5},
	},
	"cool_hands": {
		"display_name": "Cool Hands", "polarity": "buff",
		"blurb": "Fingers stay steady on a lock or a coupling even when the room doesn't.",
		"tags": {"door_bypass_bonus": 5, "repair_bonus": 5},
	},
	"old_hand": {
		"display_name": "Old Hand", "polarity": "buff",
		"blurb": "Three legs in, still standing. The ship stops feeling like a stranger's.",
		"stat_bonus": {"sanity": 2, "fear": 2, "body": 2},
	},
	"lifer": {
		"display_name": "Lifer", "polarity": "buff",
		"blurb": "Six legs. This ship is more home than home ever was.",
		"stat_bonus": {"sanity": 5, "fear": 5, "body": 5},
	},
	"set_in_their_ways": {
		"display_name": "Set in Their Ways", "polarity": "debuff",
		"blurb": "New methods bounce off old habits — comes bundled with being a Lifer.",
	},
	"believer": {
		"display_name": "Believer", "polarity": "buff",
		"blurb": "The ship's mind pulled them back from the edge once. That earns something like faith.",
		"trust_floor": 0.6,
	},
	"machine_wary": {
		"display_name": "Machine-Wary", "polarity": "debuff",
		"blurb": "Trusts the ship's mind exactly as far as it's already proven itself, and no further.",
		"trust_ceiling": 0.4,
	},
}


static func base_id(trait_id: String) -> String:
	return trait_id.get_slice(":", 0) if ":" in trait_id else trait_id


static func param(trait_id: String) -> String:
	return trait_id.get_slice(":", 1) if ":" in trait_id else ""


static func get_trait(trait_id: String) -> Dictionary:
	return REGISTRY.get(base_id(trait_id), {})


static func display_name(trait_id: String) -> String:
	var entry: Dictionary = get_trait(trait_id)
	var base_name: String = String(entry.get("display_name", base_id(trait_id).capitalize()))
	var p: String = param(trait_id)
	return "%s (%s)" % [base_name, p.capitalize()] if p != "" else base_name


static func blurb(trait_id: String) -> String:
	return String(get_trait(trait_id).get("blurb", ""))


static func polarity(trait_id: String) -> String:
	return String(get_trait(trait_id).get("polarity", "neutral"))


# --- Checks hooks (same shape as Items' tags/item_bonus) ---

static func tag_value(trait_id: String, tag: String) -> float:
	return float(get_trait(trait_id).get("tags", {}).get(tag, 0))


static func sum_tag_bonus(trait_ids: Array, tag: String) -> float:
	var total: float = 0.0
	for tid: String in trait_ids:
		total += tag_value(tid, tag)
	return total


static func stat_bonus(trait_id: String, stat_name: String) -> int:
	return int(get_trait(trait_id).get("stat_bonus", {}).get(stat_name, 0))


static func sum_stat_bonus(trait_ids: Array, stat_name: String) -> int:
	var total: int = 0
	for tid: String in trait_ids:
		total += stat_bonus(tid, stat_name)
	return total


# Field-Certified only: the skill family is baked into the id's ":" suffix, so this only
# ever contributes when `skill_name` matches that specific trait instance's param.
static func skill_bonus_for(trait_id: String, skill_name: String) -> int:
	var entry: Dictionary = get_trait(trait_id)
	if not entry.has("skill_bonus") or param(trait_id) != skill_name:
		return 0
	return int(entry["skill_bonus"])


static func sum_skill_bonus(trait_ids: Array, skill_name: String) -> int:
	var total: int = 0
	for tid: String in trait_ids:
		total += skill_bonus_for(tid, skill_name)
	return total


static func stress_gain_mult(trait_ids: Array, source: String) -> float:
	var mult: float = 1.0
	if source == "":
		return mult
	for tid: String in trait_ids:
		var m: Dictionary = get_trait(tid).get("stress_mult", {})
		if m.has(source):
			mult *= float(m[source])
	return mult


static func loneliness_floor(trait_ids: Array) -> float:
	var floor_val: float = 0.0
	for tid: String in trait_ids:
		floor_val = maxf(floor_val, float(get_trait(tid).get("loneliness_floor", 0.0)))
	return floor_val


static func trust_floor(trait_ids: Array) -> float:
	var floor_val: float = 0.0
	for tid: String in trait_ids:
		floor_val = maxf(floor_val, float(get_trait(tid).get("trust_floor", 0.0)))
	return floor_val


static func trust_ceiling(trait_ids: Array) -> float:
	var ceiling: float = 1.0
	for tid: String in trait_ids:
		var entry: Dictionary = get_trait(tid)
		if entry.has("trust_ceiling"):
			ceiling = minf(ceiling, float(entry["trust_ceiling"]))
	return ceiling


static func panic_table_shift(trait_ids: Array) -> int:
	var shift: int = 0
	for tid: String in trait_ids:
		shift += int(get_trait(tid).get("panic_table_shift", 0))
	return shift


static func adjacent_panic_stress_bonus(trait_ids: Array) -> int:
	var bonus: int = 0
	for tid: String in trait_ids:
		bonus += int(get_trait(tid).get("adjacent_panic_stress_bonus", 0))
	return bonus


# --- The one funnel for adding a trait (mirrors CrewLifecycle.kill) ---
#
# Caps at MAX_TRAITS: a new earn beyond the cap replaces the weakest same-polarity trait,
# with a log line (docs/crew-progression-spec.md §3). "Weakest" has no numeric power
# ranking in this v1 registry — approximated as the OLDEST trait of matching polarity (the
# first one still in the array), a documented simplification. No duplicate ids (exact
# string match, so "field_certified:reactor" and "field_certified:engineering" can coexist
# — different specialties, not a duplicate).
static func grant(crew: CrewMember, trait_id: String) -> void:
	if trait_id == "" or crew == null or trait_id in crew.traits:
		return
	if crew.traits.size() >= MAX_TRAITS:
		var weakest: String = _weakest_same_polarity(crew, polarity(trait_id))
		if weakest == "":
			print("[TRAITS] %s: at cap (%d) with nothing of the same polarity to replace — %s lost." % [
				crew.crew_name, MAX_TRAITS, display_name(trait_id)])
			return
		crew.traits.erase(weakest)
		print("[TRAITS] %s: %s replaced by %s (cap)" % [crew.crew_name, display_name(weakest), display_name(trait_id)])
		EventBus.crew_trait_lost.emit(crew.crew_id, weakest)
	crew.traits.append(trait_id)
	var entry: Dictionary = get_trait(trait_id)
	if entry.has("min_stress_add"):
		crew.min_stress += int(entry["min_stress_add"])
	EventBus.crew_trait_gained.emit(crew.crew_id, trait_id)


static func _weakest_same_polarity(crew: CrewMember, want_polarity: String) -> String:
	for tid: String in crew.traits:
		if polarity(tid) == want_polarity:
			return tid
	return ""
