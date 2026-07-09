class_name Items
extends RefCounted

# Equipment/weapon registry (docs/rules.md "Weapons" / "Equipment (Selected Rules)" /
# "Armor"). Not a full economy simulation — cost/range/shots are kept for flavour and
# future combat work, but the fields mechanics actually read today are the `tags`
# dictionary: tag -> bonus value, consumed by Checks.perform_check() call sites via
# CrewMember.item_bonus(tag) / CrewMember.has_item_tag(tag). Adding a new tag here is
# how a future system (combat, hacking, etc.) plugs equipment bonuses into checks
# without touching CrewMember itself.
#
# Known tags in active use:
#   door_bypass_bonus  - flat bonus added to the Intellect+tech check in Door bypass
#   door_bypass_time_mult - multiplies bypass duration (<1.0 = faster)
#   repair_bonus       - flat bonus added to repair-job stat checks
#   medical_bonus      - flat bonus added to Field Medicine/Surgery-style checks

const REGISTRY: Dictionary = {
	# --- Tools (mechanically load-bearing) ---
	"crowbar": {
		"name": "Crowbar", "cost": 25, "kind": "tool_weapon",
		"damage_dice": "1d5", "wound_type": "blunt_force", "range": "adjacent",
		"tags": {"door_bypass_bonus": 10},
	},
	"cutting_torch": {
		"name": "Cutting Torch", "cost": 300, "kind": "tool",
		"tags": {"door_bypass_bonus": 20, "door_bypass_time_mult": 0.5},
	},
	"engineers_toolkit": {
		"name": "Engineer's Toolkit", "cost": 200, "kind": "tool",
		"tags": {"repair_bonus": 15, "door_bypass_bonus": 5},
	},
	"jury_rig_kit": {
		"name": "Jury-Rig Kit", "cost": 80, "kind": "tool",
		"tags": {"repair_bonus": 10},
	},
	"medscanner": {
		"name": "Medscanner", "cost": 150, "kind": "tool",
		"tags": {"medical_bonus": 15},
	},
	"med_kit": {
		"name": "Med Kit", "cost": 100, "kind": "tool",
		"tags": {"medical_bonus": 10},
	},

	# --- Weapons (rules.md "Weapon Table") ---
	"unarmed": {
		"name": "Unarmed", "cost": 0, "kind": "weapon",
		"damage_dice": "STR/10", "wound_type": "blunt_force", "range": "adjacent", "shots": -1,
		"tags": {},
	},
	"stun_baton": {
		"name": "Stun Baton", "cost": 150, "kind": "weapon",
		"damage_dice": "1d5", "wound_type": "blunt_force", "range": "adjacent", "shots": -1,
		"tags": {},
	},
	"revolver": {
		"name": "Revolver", "cost": 750, "kind": "weapon",
		"damage_dice": "1d10+1", "wound_type": "gunshot", "range": "close", "shots": 6,
		"tags": {},
	},
	"combat_shotgun": {
		"name": "Combat Shotgun", "cost": 1400, "kind": "weapon",
		"damage_dice": "4d10", "wound_type": "gunshot", "range": "close", "shots": 4,
		"tags": {},
	},
	"scalpel": {
		"name": "Scalpel", "cost": 50, "kind": "weapon",
		"damage_dice": "1d5", "wound_type": "bleeding", "range": "adjacent", "shots": -1,
		"tags": {"medical_bonus": 5},
	},
	"boarding_axe": {
		"name": "Boarding Axe", "cost": 150, "kind": "weapon",
		"damage_dice": "2d10", "wound_type": "gore_massive", "range": "adjacent", "shots": -1,
		"tags": {"door_bypass_bonus": 5},
	},

	# --- Armor (rules.md "Armor") ---
	"standard_crew_attire": {
		"name": "Standard Crew Attire", "cost": 100, "kind": "armor",
		"ap": 1, "tags": {},
	},
	"vaccsuit": {
		"name": "Vaccsuit", "cost": 10000, "kind": "armor",
		"ap": 3, "tags": {"speed_disadvantage": 1},
	},
	"hazard_suit": {
		"name": "Hazard Suit", "cost": 4000, "kind": "armor",
		"ap": 5, "tags": {},
	},
	"standard_battle_dress": {
		"name": "Standard Battle Dress", "cost": 2000, "kind": "armor",
		"ap": 7, "tags": {},
	},
	"advanced_battle_dress": {
		"name": "Advanced Battle Dress", "cost": 12000, "kind": "armor",
		"ap": 10, "dr": 3, "tags": {"strength_advantage": 1, "speed_disadvantage": 1},
	},

	# --- Consumables ---
	"stimpak": {
		"name": "Stimpak", "cost": 1000, "kind": "consumable",
		"tags": {},
	},
}

# Default loadouts per Mothership class (docs/rules.md classes + equipment tables).
# Used by CrewGen when generating random crew; scenario authors may override per-crew.
const CLASS_LOADOUTS: Dictionary = {
	"Marine":    ["standard_battle_dress", "combat_shotgun", "stun_baton"],
	"Android":   ["standard_crew_attire", "engineers_toolkit"],
	"Scientist": ["standard_crew_attire", "medscanner", "scalpel"],
	"Teamster":  ["standard_crew_attire", "engineers_toolkit", "crowbar"],
}


static func get_item(item_id: String) -> Dictionary:
	return REGISTRY.get(item_id, {})


static func tag_value(item_id: String, tag: String) -> float:
	var item: Dictionary = get_item(item_id)
	var tags: Dictionary = item.get("tags", {})
	return float(tags.get(tag, 0))


static func best_tag_bonus(item_ids: Array, tag: String) -> float:
	var best: float = 0.0
	for item_id: String in item_ids:
		best = maxf(best, tag_value(item_id, tag))
	return best


static func sum_tag_bonus(item_ids: Array, tag: String) -> float:
	var total: float = 0.0
	for item_id: String in item_ids:
		total += tag_value(item_id, tag)
	return total


static func has_tag(item_ids: Array, tag: String) -> bool:
	for item_id: String in item_ids:
		if tag_value(item_id, tag) != 0.0:
			return true
	return false


static func loadout_for_class(mship_class: String) -> Array[String]:
	var loadout: Array = CLASS_LOADOUTS.get(mship_class, ["standard_crew_attire"])
	var typed: Array[String] = []
	for item_id in loadout:
		typed.append(String(item_id))
	return typed
