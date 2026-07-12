class_name CrewModelRegistry
extends RefCounted

# Lazy-loading frame provider for the gen3 character models
# (assets/sprites/gen3_chars/, tools/image_gen/reskin_batch.py — 24 crew archetypes + 6 npc
# + 3 robot, manifest.json-driven). Mirrors IsoKit/the gen2 manifest pattern: static state
# shared by every CrewMemberNode, one manifest parse for the whole process, textures loaded
# (and cached) only for the specific (model, anim, facing) combinations actually rendered —
# with 33 models on disk and a boot roster of ~4-12 crew, this must never eagerly walk the
# whole gen3_chars/ tree.
#
# Row->facing layout: neither manifest.json nor reskin_batch.py states which of the 8 grid
# rows is which compass facing (the prompt only says "each row is one compass facing" — the
# actual order comes from the hand-authored mannequin sheet reskin_batch.py paints onto,
# assets/scratch/isometric_character_*.aseprite, which has no facing labels either). Verified
# empirically rather than guessed: idle-sheet silhouette width (front/back rows are widest;
# pure-profile rows are narrowest) plus per-row lean direction and face-visible/hidden across
# the FULL run-cycle (all 6 columns, not a single frame, to rule out single-pose ambiguity),
# cross-checked against gr_ml_eng_cm, robot_security (front-only red optic), pa_fe_and_of and
# ev_ml_mar_cm. Confirmed order (not a uniform 45deg/row sweep -- S's two neighbours both sit
# right after it, then the sweep continues around from SW to E):
const ROW_FOR_FACING: Dictionary = {
	"S": 0, "SE": 1, "SW": 2, "W": 3, "NW": 4, "N": 5, "NE": 6, "E": 7,
}

# Columns (animation frames) per row, per anim -- reskin_batch.py's GRID = (cols, rows);
# rows are always 8 (facings), cols vary per anim. Restated here since the manifest doesn't.
const FRAME_COLS: Dictionary = {"idle": 8, "walk": 12, "run": 6, "punch": 4}

const GEN3_DIR: String = "res://assets/sprites/gen3_chars/"
const MANIFEST_PATH: String = GEN3_DIR + "manifest.json"

# Manifest cache -- loaded once for the whole process (every CrewModelRegistry caller shares
# it), same idiom as CrewMemberNode._ensure_gen2_manifest.
static var _manifest: Dictionary = {}
static var _manifest_loaded: bool = false
static var _crew_ids: Array[String] = []
static var _npc_ids: Array[String] = []
static var _robot_ids: Array[String] = []

# "<model_id>:<anim>:<facing>" -> Array[Texture2D], populated on first request only.
static var _frame_cache: Dictionary = {}

# One push_warning per model (not per frame/anim/facing) -- a character with one missing
# sheet would otherwise spam a warning every _process tick for every facing it's asked for.
static var _warned_models: Dictionary = {}


static func _ensure_manifest() -> void:
	if _manifest_loaded:
		return
	_manifest_loaded = true
	var text: String = FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("characters"):
		push_warning("CrewModelRegistry: gen3_chars/manifest.json missing or unparsable -- no gen3 models available.")
		return
	_manifest = parsed
	var characters: Dictionary = _manifest.get("characters", {})
	for model_id: String in characters:
		match String((characters[model_id] as Dictionary).get("kind", "")):
			"crew": _crew_ids.append(model_id)
			"npc": _npc_ids.append(model_id)
			"robot": _robot_ids.append(model_id)


static func has_model(model_id: String) -> bool:
	_ensure_manifest()
	return (_manifest.get("characters", {}) as Dictionary).has(model_id)


# Crew archetype ids only (kind == "crew") -- npc_*/robot_* below are exposed separately
# for future non-crew entities (intruder/NPC sprites etc.), not consumed by CrewMemberNode.
static func crew_ids() -> Array[String]:
	_ensure_manifest()
	return _crew_ids.duplicate()


static func npc_ids() -> Array[String]:
	_ensure_manifest()
	return _npc_ids.duplicate()


static func robot_ids() -> Array[String]:
	_ensure_manifest()
	return _robot_ids.duplicate()


# CrewMember.archetype_tag (e.g. "GR_ML_ENG_CM", dialogue-spec dimensional tag) -> gen3
# model id. Model ids ARE the lowercased tag (reskin_batch.py's _crew_roster() derives one
# from the other), so this is a direct lookup for any archetype whose model was generated.
# Falls back to a deterministic pick (hash of the tag) when the tag is blank or its model
# doesn't exist (e.g. a future archetype added before its model is painted) -- deterministic
# so the same crew member always renders the same gen3 model rather than reroll-per-frame.
static func model_for_archetype(tag: String) -> String:
	_ensure_manifest()
	if _crew_ids.is_empty():
		return ""
	var key: String = tag.to_lower()
	if key != "" and key in _crew_ids:
		return key
	var idx: int = absi(hash(tag if tag != "" else "unknown")) % _crew_ids.size()
	return _crew_ids[idx]


# Lazy, cached per (model, anim, facing). Empty array means "not renderable" (unknown
# model/anim/facing, or every frame in that row failed to load) -- callers fall back to
# another rendering system exactly like the gen2 manifest's missing-texture path.
static func get_frames(model_id: String, anim: String, facing: String) -> Array[Texture2D]:
	_ensure_manifest()
	if not has_model(model_id):
		return []
	var anim_key: String = anim.to_lower()
	var cols: int = int(FRAME_COLS.get(anim_key, 0))
	if cols <= 0:
		return []  # not one of the 4 painted anims (idle/walk/run/punch)
	var facing_key: String = facing.to_upper()
	if not ROW_FOR_FACING.has(facing_key):
		return []
	var row: int = int(ROW_FOR_FACING[facing_key])
	var cache_key: String = "%s:%s:%s" % [model_id, anim_key, facing_key]
	if _frame_cache.has(cache_key):
		return _frame_cache[cache_key]

	var dir: String = "%s%s/frames/" % [GEN3_DIR, model_id]
	var frames: Array[Texture2D] = []
	var any_missing: bool = false
	for col in cols:
		var path: String = "%s%s_%d_%d.png" % [dir, anim_key, row, col]
		var tex: Texture2D = load(path) if ResourceLoader.exists(path) else null
		if tex == null:
			any_missing = true
			continue
		frames.append(tex)

	if frames.is_empty():
		_warn_once(model_id, "no frames found for %s/%s (row %d)" % [anim_key, facing_key, row])
	elif any_missing:
		_warn_once(model_id, "partial frame set for %s/%s (row %d) -- some columns missing" % [anim_key, facing_key, row])
	_frame_cache[cache_key] = frames
	return frames


static func _warn_once(model_id: String, message: String) -> void:
	if _warned_models.has(model_id):
		return
	_warned_models[model_id] = true
	push_warning("CrewModelRegistry '%s': %s" % [model_id, message])
