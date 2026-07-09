class_name SideProjects
extends RefCounted

# Small, data-driven per-crew hobby list. Pure flavor: gives each crew member a
# persistent personal activity that (a) drives WHERE they go during their
# recreation schedule window (see CrewSchedule/CrewBehavior) and (b) gives the
# dialogue layer a stable location bias for smalltalk/memory-type lines even
# though the corpus doesn't reference hobbies by id directly yet.
#
# One project is assigned per crew member the first time it's needed and then
# kept for the rest of the run (GameState.crew_side_projects, per Rule 3 — the
# assignment itself lives on GameState, this file only owns the static list +
# lookup logic).

const PROJECTS: Array = [
	{"id": "tinkering",  "label": "tinkering with salvage",  "location": "cargo"},
	{"id": "reading",    "label": "reading",                 "location": "quarters"},
	{"id": "exercise",   "label": "working out",              "location": "cargo"},
	{"id": "plant",      "label": "tending a plant",          "location": "quarters"},
	{"id": "cards",      "label": "playing cards",            "location": "mess"},
	{"id": "journaling", "label": "keeping a journal",        "location": "quarters"},
]


# Deterministic-ish pick from the crew_id's hash so repeated calls within a
# session don't reshuffle a crew member's hobby (no randf() used here — this
# is a stable identity trait, not a moment-to-moment roll).
static func pick_for(crew: CrewMember) -> String:
	var idx: int = int(abs(crew.crew_id.hash())) % PROJECTS.size()
	return String(PROJECTS[idx]["id"])


static func _entry(id: String) -> Dictionary:
	for p: Dictionary in PROJECTS:
		if p["id"] == id:
			return p
	return {}


# Room TYPE the crew member's hobby happens in. Assigns + persists the hobby
# on first call for a given crew member.
static func location_for(crew: CrewMember) -> String:
	var id: String = String(GameState.crew_side_projects.get(crew.crew_id, ""))
	if id == "":
		id = pick_for(crew)
		GameState.crew_side_projects[crew.crew_id] = id
	var entry: Dictionary = _entry(id)
	return String(entry.get("location", "mess"))


static func label_for(crew: CrewMember) -> String:
	var id: String = String(GameState.crew_side_projects.get(crew.crew_id, ""))
	return String(_entry(id).get("label", ""))
