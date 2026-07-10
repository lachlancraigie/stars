class_name CrewMemberNode
extends Node2D

# Visual representation of a CrewMember resource.
# Registers crew_data into GameState on _ready; renders a per-state/facing/frame gen2
# crew sprite (assets/sprites/gen2/crew/, manifest-driven — see _apply_gen2_sprite),
# falling back to the legacy Kenney astronaut kit whenever the gen2 manifest or a
# specific texture is missing (_apply_legacy_sprite, unchanged from before this sprite
# swap was added). Walks multi-hop routes along the ship graph, and z-sorts against deck
# props by y. Lives inside the ShipDeck node so its position shares the rooms' deck
# coordinate space.
#
# Collision (crew count is capped ~12, so O(N²)/frame is cheap): soft
# pairwise separation nudges `position` apart when crew get within
# PERSONAL_RADIUS of each other (see _apply_separation), and standing points
# picked from DeckPlan.random_point() are claimed in a static registry so two
# crew don't sit on top of each other (_claim_standing_point/_release_claim).
# Both are pure position nudges layered on top of the existing route-walking
# state machine (_route/_target_pos/_moving) — they never touch it, so they
# can't stall a route, fight panic-flee (CrewBehavior just calls
# move_to_room() same as always), or fight hold_room_until (that's a
# CrewBehavior-level gate on issuing new movement, untouched here).

const KIT_DIR: String = "res://assets/sprites/legacy/"
const MOVE_SPEED: float = 190.0          # deck px/sec (one grid cell ~130px)
const ARRIVE_EPSILON: float = 10.0       # px; bumped from 4.0 so separation jostle can't stall arrival
const BOB_HEIGHT: float = 5.0            # px of walk bounce
const BOB_RATE: float = 9.0              # bounces per second while walking

const PERSONAL_RADIUS: float = 60.0      # px, ~half a floor tile; soft-separation trigger distance
const SEPARATION_STRENGTH: float = 130.0 # px/sec of push at full overlap
const SEPARATION_PERP_BIAS_MOVING: float = 0.75  # walking: mostly sideways, so it doesn't fight forward progress
const SEPARATION_PERP_BIAS_IDLE: float = 0.1     # standing: mostly straight-apart
const STANDING_CLAIM_ATTEMPTS: int = 5   # resample tries when a candidate standing point is already claimed

# Role -> kit astronaut variant + tint. Tints multiply, so light suits take
# the colour while dark visors/boots stay dark. Labels match the tint. The gen2 set is a
# single character design (no per-role variant art), so only the tint half of this table
# applies there — see _apply_gen2_sprite.
const ROLE_VARIANT: Dictionary = {
	"captain": "astronautA", "engineer": "astronautA",
	"medic": "astronautB", "general": "astronautB",
}
const ROLE_TINT: Dictionary = {
	"captain":  Color(1.00, 0.86, 0.55),
	"engineer": Color(1.00, 1.00, 1.00),
	"medic":    Color(0.80, 1.00, 0.88),
	"general":  Color(0.72, 0.85, 1.00),
}
const FALLBACK_ROLE: String = "general"

# Gen2 crew art (tools/image_gen/crew_sheet_gen.py; consistency-gate evidence at
# assets/sprites/gen2/crew/_test/test_verdict.json). MANDATORY fallback: manifest.json
# missing, or a specific state/facing/frame texture missing, drops straight back to
# _apply_legacy_sprite() below — see _apply_sprite().
const GEN2_CREW_DIR: String = "res://assets/sprites/gen2/crew/"
const GEN2_MANIFEST_PATH: String = GEN2_CREW_DIR + "manifest.json"

# 8-way facing -> its left/right mirror. A gen2 state's manifest doesn't always cover all
# 8 facings (e.g. "sleeping" is a fixed side-view bunk pose, facing "e" only) — mirroring
# via Sprite2D.flip_h lets a missing e.g. "w" still show the "e" art facing the right way,
# rather than silently picking an arbitrary facing. s/n mirror to themselves (front/back
# views are left-right symmetric enough for this simplified character).
const FACING_MIRROR: Dictionary = {
	"e": "w", "w": "e", "ne": "nw", "nw": "ne", "se": "sw", "sw": "se", "s": "s", "n": "n",
}

# CrewStateMachine states that already have a real, existing signal to key sprite state
# off (wounds/incapacitation/sleep — see _gen2_sprite_state). fight_melee/fight_ranged/
# carry_walk/carry_idle/floating art is generated and listed in the manifest but has no
# live gameplay trigger yet (no combat resolver/carrying-item/zero-g flag exists —
# CLAUDE.md backlog #3) — TODO(crew): map those states here once those systems land.

# Speech/thought bubble (DialogueSystem's EventBus.line_spoken -> here). One reusable
# Panel+RichTextLabel per crew, built once in _ready() and restyled/resized per line rather
# than instantiated per-line — spec: "one reusable Label+Panel per crew". World-space
# (a plain Node2D child, not a CanvasLayer) so it pans/scales with DeckCamera like
# everything else on the deck. z_as_relative=false with a large fixed z_index keeps it
# drawn above the sprite/props regardless of the crew's own dynamic y-sort z.
const BUBBLE_Z_INDEX: int = 4000
const BUBBLE_WIDTH: float = 260.0
const BUBBLE_PADDING: Vector2 = Vector2(10.0, 7.0)
const BUBBLE_BOTTOM_OFFSET: float = -122.0  # bubble's bottom edge, above NameLabel (-108..-88)
const BUBBLE_CHARS_PER_LINE: int = 34       # heuristic auto-size — see _estimate_bubble_size
const BUBBLE_LINE_HEIGHT: float = 18.0
const BUBBLE_DISPLAY_SECONDS: float = 4.0   # + a per-character reading-time bonus, clamped below
const BUBBLE_DISPLAY_MAX_BONUS: float = 2.0
const BUBBLE_FADE_SECONDS: float = 0.6
const BUBBLE_SPEECH_BG: Color = Color(0.06, 0.09, 0.13, 0.90)
const BUBBLE_SPEECH_BORDER: Color = Color(0.55, 0.75, 0.95, 0.55)
const BUBBLE_SPEECH_TEXT: Color = Color(0.93, 0.95, 0.98, 1.0)
const BUBBLE_THOUGHT_BG: Color = Color(0.10, 0.10, 0.16, 0.55)
const BUBBLE_THOUGHT_TEXT: Color = Color(0.75, 0.78, 0.88, 0.85)
const BUBBLE_TAIL_HEIGHT: float = 10.0

const STATE_COLORS: Dictionary = {
	"idle":          Color(0.35, 0.78, 0.40),
	"working":       Color(0.25, 0.55, 0.95),
	"sleeping":      Color(0.60, 0.60, 0.65),
	"eating":        Color(0.95, 0.78, 0.20),
	"panicking":     Color(0.95, 0.25, 0.18),
	"frozen":        Color(0.55, 0.65, 0.85),
	"incapacitated": Color(0.15, 0.12, 0.12),
}

# Registry so directive execution can find a crew's visual node by id.
static var nodes: Dictionary = {}  # crew_id -> CrewMemberNode

# World-px hit radius for "did this click land on a crew member" — shared by every
# world-click UI (DirectiveMenu, EnvironmentMenu) so crew selection is picked exactly the
# same way everywhere and doors/equipment never steal a click that actually landed on crew.
const CLICK_RADIUS: float = 60.0


# Nearest crew member to a world-space point within `radius`, or null if none qualifies.
static func crew_at_world_point(world_point: Vector2, radius: float = CLICK_RADIUS) -> CrewMemberNode:
	var best: CrewMemberNode = null
	var best_dist: float = radius
	for crew_id: String in nodes:
		var node: CrewMemberNode = nodes[crew_id] as CrewMemberNode
		if node == null:
			continue
		var d: float = node.global_position.distance_to(world_point)
		if d <= best_dist:
			best = node
			best_dist = d
	return best

# Standing-point claims so two crew don't pick the same room spot to stand
# at/settle into. crew_id -> {"room": room_id, "point": deck-px Vector2}.
# Node-level and GameState-free by design (view-layer bookkeeping, not
# authoritative simulation state — see CLAUDE.md Rule 3).
static var _point_claims: Dictionary = {}

# Gen2 manifest cache — loaded once for the whole process (every CrewMemberNode shares
# it), not per-instance. _gen2_available stays false (mandatory legacy fallback) when
# manifest.json doesn't exist or fails to parse.
static var _gen2_manifest: Dictionary = {}
static var _gen2_manifest_checked: bool = false
static var _gen2_available: bool = false


static func _ensure_gen2_manifest() -> void:
	if _gen2_manifest_checked:
		return
	_gen2_manifest_checked = true
	# FileAccess.get_file_as_string (matches dialogue_system.gd's JSON-loading convention)
	# returns "" for a missing file, which JSON.parse_string then fails to parse as a
	# Dictionary — that failure IS the mandatory legacy-fallback path, so no separate
	# existence check is needed here.
	var text: String = FileAccess.get_file_as_string(GEN2_MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("states"):
		return
	_gen2_manifest = parsed
	_gen2_available = true

@export var crew_data: CrewMember

@onready var sprite: Sprite2D = $Sprite2D
@onready var name_label: Label = $NameLabel

var speed_mult: float = 1.0              # panic runs faster
var hold_room_until: float = 0.0         # TimeManager.elapsed until which idle wander is suppressed

var _facing: String = "S"
var _moving: bool = false
var _target_pos: Vector2 = Vector2.ZERO
var _route: Array = []                   # remaining room_ids to walk through
var _leg_points: Array = []              # remaining deck positions within the current hop
var _pending_room: String = ""           # room we are currently walking into
var _bob_t: float = 0.0
var _current_texture_key: String = ""
var _status_dot: ColorRect

var _gen2_frame_t: float = 0.0     # accumulates every tick; drives cycle-mode animation frame index
var _gen2_state_key: String = ""   # last resolved gen2 sprite state name, to reset _gen2_frame_t on change
var _gen2_dead_variant: int = -1   # picked once per crew (crew_id hash) — dead poses are variants, not a loop

var _bubble_anchor: Node2D
var _bubble_panel: Panel
var _bubble_label: RichTextLabel
var _bubble_tail: Polygon2D
var _bubble_tween: Tween
var _bubble_gen: int = 0  # invalidates a stale hide-callback if a newer line pre-empts it

# Voice line playback (tools/audio_gen pipeline): line key "TAG#00042" maps to
# assets/audio/dialogue/TAG_00042.mp3. The directory is gitignored (generated audio),
# so streams are built from raw bytes at runtime rather than relying on Godot imports.
const VOICE_DIR: String = "res://assets/audio/dialogue/"
var _voice_player: AudioStreamPlayer2D

# Locked-door bypass in progress (see Door.attempt_crew_bypass): while non-empty, this
# crew member is standing put attempting to force a locked door rather than walking.
var _bypassing_door_id: String = ""
var _bypass_target_room: String = ""
var _bypass_hold: float = 0.0


func _ready() -> void:
	if crew_data == null:
		push_warning("CrewMemberNode has no crew_data assigned.")
		return
	GameState.crew[crew_data.crew_id] = crew_data
	nodes[crew_data.crew_id] = self

	name_label.text = crew_data.crew_name
	var tint: Color = ROLE_TINT.get(crew_data.role, Color.WHITE)
	name_label.add_theme_color_override("font_color", tint.lightened(0.35))
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	name_label.add_theme_constant_override("outline_size", 6)
	sprite.offset = IsoKit.ANCHOR_OFFSET
	sprite.self_modulate = tint

	_status_dot = ColorRect.new()
	_status_dot.size = Vector2(9, 9)
	_status_dot.position = Vector2(-4.5, -86)
	add_child(_status_dot)

	_build_bubble()

	_voice_player = AudioStreamPlayer2D.new()
	_voice_player.max_distance = 2200.0
	_voice_player.volume_db = -4.0
	add_child(_voice_player)

	position = _claim_standing_point(crew_data.location) if DeckPlan.has_room(crew_data.location) \
		else Vector2.ZERO
	z_index = IsoKit.z_for(position.y)
	_apply_sprite()
	_apply_status_dot()

	EventBus.crew_state_changed.connect(_on_state_changed)
	EventBus.door_bypass_result.connect(_on_door_bypass_result)
	EventBus.line_spoken.connect(_on_line_spoken)


func _exit_tree() -> void:
	_release_claim()
	if crew_data and nodes.get(crew_data.crew_id) == self:
		nodes.erase(crew_data.crew_id)


func _process(delta: float) -> void:
	if TimeManager.is_paused():
		return
	# Drives gen2 cycle-mode animation frame indices (_apply_gen2_sprite) — accumulated
	# unconditionally so states that animate while stationary (sleeping/injured_idle) keep
	# advancing even though _moving's branch below returns early for everything else.
	_gen2_frame_t += delta
	if crew_data.current_state in [CrewStateMachine.INCAPACITATED, CrewStateMachine.FROZEN]:
		_moving = false
		_route.clear()
		_leg_points.clear()
		_apply_sprite()
		# Some incapacitation paths (CrewLifecycle.kill, Wound/Panic Table effects) set
		# current_state directly without going through the normal CrewSystem-polled
		# state-machine transition that emits crew_state_changed (see wound_table.gd
		# comment) — refresh the status dot here too so it can't go stale on a same-tick
		# jump straight from e.g. "panicking" to dead.
		_apply_status_dot()
		return
	if not _moving:
		_bob_t = 0.0
		sprite.position = Vector2.ZERO
		if crew_data.current_state == CrewStateMachine.PANICKING:
			sprite.position.x = sin(Time.get_ticks_msec() * 0.04) * 2.0
		_apply_separation(delta, false)
		z_index = IsoKit.z_for(position.y)
		_apply_sprite()  # idle-but-animated gen2 states (sleeping, injured_idle) still need per-frame updates
		return

	var to_target: Vector2 = _target_pos - position
	if to_target.length() <= ARRIVE_EPSILON:
		position = _target_pos
		_arrive()
		return

	_update_facing(to_target)
	position += to_target.normalized() * MOVE_SPEED * speed_mult * delta
	_apply_separation(delta, true)
	z_index = IsoKit.z_for(position.y)
	_bob_t += delta
	sprite.position.y = -absf(sin(_bob_t * BOB_RATE)) * BOB_HEIGHT
	_apply_sprite()


# Walk to another room following the ship graph (multi-hop). hold_seconds
# suppresses idle wandering after arrival — used for directives the crew
# agreed to, so they stay put long enough for it to matter.
func move_to_room(room_id: String, hold_seconds: float = 0.0) -> void:
	if room_id == crew_data.location and not _moving:
		return
	var locked: Array[String] = GameState.get_locked_doors()
	var path: Array = GameState.ship_graph.find_path(crew_data.location, room_id, false, locked)
	if path.is_empty():
		var unrestricted: Array = GameState.ship_graph.find_path(crew_data.location, room_id)
		var blocking_door: Door = _first_locked_door_on_path(unrestricted, locked)
		if blocking_door != null:
			_begin_bypass(blocking_door, room_id, hold_seconds)
		else:
			push_warning("CrewMemberNode: no path %s -> %s" % [crew_data.location, room_id])
		return
	# An unblocked route exists — take it, superseding any earlier bypass attempt this
	# crew member may have had in flight for a different destination (e.g. panic-fleeing
	# picked a neighbour that doesn't require the door being bypassed). The Door's own
	# in-flight timer, if any, still resolves harmlessly — _on_door_bypass_result ignores
	# results whose door_id no longer matches.
	_bypassing_door_id = ""
	path.pop_front()  # first entry is the current room
	_route = path
	if hold_seconds > 0.0:
		hold_room_until = TimeManager.elapsed + hold_seconds
	_advance_route()


# Finds the first locked door along an (unrestricted) room-id path, so a blocked crew
# member can attempt a manual bypass on it instead of just failing to move.
func _first_locked_door_on_path(path: Array, locked: Array[String]) -> Door:
	for i in range(path.size() - 1):
		var door: Door = GameState.door_between(path[i], path[i + 1])
		if door != null and door.door_id in locked:
			return door
	return null


func _begin_bypass(door: Door, target_room: String, hold_seconds: float) -> void:
	if _bypassing_door_id == door.door_id:
		return  # already attempting this exact door
	_bypassing_door_id = door.door_id
	_bypass_target_room = target_room
	_bypass_hold = hold_seconds
	door.attempt_crew_bypass(crew_data)


func _on_door_bypass_result(crew_id: String, door_id: String, success: bool, critical: bool) -> void:
	if crew_id != crew_data.crew_id or door_id != _bypassing_door_id:
		return
	if critical and not success:
		# Jammed — try again shortly (represents fiddling with it / fetching a tool)
		# rather than getting permanently stuck.
		get_tree().create_timer(8.0).timeout.connect(func():
			if _bypassing_door_id == door_id:
				var d: Door = GameState.doors.get(door_id) as Door
				if d != null:
					d.attempt_crew_bypass(crew_data))
		return
	_bypassing_door_id = ""
	var target: String = _bypass_target_room
	var hold: float = _bypass_hold
	move_to_room(target, hold)


# Small repositioning inside the current room (idle flavour movement).
func wander_within_room() -> void:
	if _moving or not DeckPlan.has_room(crew_data.location):
		return
	_pending_room = ""
	_target_pos = _claim_standing_point(crew_data.location)
	_moving = true


func is_headed_to(room_id: String) -> bool:
	return _pending_room == room_id or room_id in _route


func is_busy() -> bool:
	return _moving or not _route.is_empty() or _bypassing_door_id != ""


# Room this crew member is currently walking toward, "" if not moving — the Inspect
# page's "jobs & tasks" section reads this (RosterPanel), same idiom as is_headed_to.
func current_destination() -> String:
	if _pending_room != "":
		return _pending_room
	if not _route.is_empty():
		return String(_route[_route.size() - 1])
	return ""


func _advance_route() -> void:
	if _route.is_empty():
		_moving = false
		return
	var next_room: String = _route.pop_front()
	var old_room: RoomBase = GameState.rooms.get(crew_data.location) as RoomBase
	if old_room:
		old_room.remove_occupant(crew_data.crew_id)
	_pending_room = next_room
	# Cross via the walkway/gate waypoints, then settle somewhere in the room.
	# Claim the settle point now (not on arrival) so two crew converging on the
	# same room from different hops don't both aim for the same spot.
	_leg_points = DeckPlan.hop_waypoints(crew_data.location, next_room)
	_leg_points.append(_claim_standing_point(next_room))
	_target_pos = _leg_points.pop_front()
	_moving = true


func _arrive() -> void:
	if not _leg_points.is_empty():
		_target_pos = _leg_points.pop_front()
		return
	_moving = false
	sprite.position = Vector2.ZERO
	if _pending_room != "":
		var from_room: String = crew_data.location
		crew_data.location = _pending_room
		_pending_room = ""
		EventBus.crew_moved.emit(crew_data.crew_id, from_room, crew_data.location)
		var room: RoomBase = GameState.rooms.get(crew_data.location) as RoomBase
		if room:
			room.add_occupant(crew_data.crew_id)
	if not _route.is_empty():
		_advance_route()
	else:
		_apply_sprite()


# --- Standing-point claiming ---------------------------------------------
# Whenever a route or idle-wander picks a spot to settle at, sample a few
# candidates and keep the first one not already claimed by another crew
# member in that room, then claim it. Falls back to the last sample if every
# attempt collides — this must never fail to return a point (never stalls
# route-following), it just means a rare visible overlap that _apply_separation
# resolves a moment later instead of being avoided up front.

func _claim_standing_point(room_id: String) -> Vector2:
	var point: Vector2 = DeckPlan.random_point(room_id)
	for _attempt in STANDING_CLAIM_ATTEMPTS - 1:
		if not _point_is_claimed(room_id, point):
			break
		point = DeckPlan.random_point(room_id)
	_point_claims[crew_data.crew_id] = {"room": room_id, "point": point}
	return point


func _point_is_claimed(room_id: String, point: Vector2) -> bool:
	for cid: String in _point_claims:
		if cid == crew_data.crew_id:
			continue
		var claim: Dictionary = _point_claims[cid]
		if claim["room"] == room_id and (claim["point"] as Vector2).distance_to(point) < PERSONAL_RADIUS:
			return true
	return false


func _release_claim() -> void:
	if crew_data:
		_point_claims.erase(crew_data.crew_id)


# --- Soft collision avoidance ---------------------------------------------
# Cheap O(N²) pairwise separation (crew count is capped ~12, so this costs
# nothing per frame). Only ever nudges `position` — never touches _route,
# _target_pos, or current_state — so it can't stall route-following, fight
# panic-flee, or fight hold_room_until (all of those live one layer up, in
# CrewBehavior/move_to_room). Displacement is clamped to the current room (or,
# mid-transit, the union of the room being left and the one being entered) so
# crew can never get shoved through a wall.

func _apply_separation(delta: float, moving: bool) -> void:
	var push: Vector2 = Vector2.ZERO
	var bias: float = SEPARATION_PERP_BIAS_MOVING if moving else SEPARATION_PERP_BIAS_IDLE
	for crew_id: String in nodes:
		if crew_id == crew_data.crew_id:
			continue
		var other: CrewMemberNode = nodes[crew_id] as CrewMemberNode
		if other == null or not is_instance_valid(other):
			continue
		var offset: Vector2 = position - other.position
		var dist: float = offset.length()
		if dist >= PERSONAL_RADIUS:
			continue
		var radial: Vector2
		if dist > 0.5:
			radial = offset / dist
		else:
			# Exact (or near-exact) overlap — break the tie deterministically
			# per crew id instead of both agents computing a zero vector and
			# staying stacked forever.
			var ang: float = float(hash(crew_data.crew_id) % 360) * PI / 180.0
			radial = Vector2(cos(ang), sin(ang))
			dist = 0.0
		# Perpendicular-biased: blending in a sideways component (rotate 90°)
		# means two crew converging head-on slide past each other instead of
		# just cancelling out each other's forward progress every frame.
		var perp: Vector2 = Vector2(-radial.y, radial.x)
		var overlap: float = (PERSONAL_RADIUS - dist) / PERSONAL_RADIUS
		push += (radial * (1.0 - bias) + perp * bias) * overlap
	if push == Vector2.ZERO:
		return
	position += push * SEPARATION_STRENGTH * delta
	_clamp_to_room_bounds()


func _clamp_to_room_bounds() -> void:
	var rect: Rect2 = _room_px_bounds(crew_data.location)
	if _pending_room != "":
		var next_rect: Rect2 = _room_px_bounds(_pending_room)
		if next_rect.size != Vector2.ZERO:
			rect = rect.merge(next_rect) if rect.size != Vector2.ZERO else next_rect
	if rect.size == Vector2.ZERO:
		return  # unknown room geometry (shouldn't happen) — skip rather than clamp to garbage
	position.x = clampf(position.x, rect.position.x, rect.end.x)
	position.y = clampf(position.y, rect.position.y, rect.end.y)


# AABB of a room's floor rect in deck pixels, padded a little so separation
# can push crew right up near a wall/doorway without visibly clipping through
# it. Cheap (4 IsoKit projections) — same technique DeckPlan.deck_bounds()
# uses for the whole deck, just for one room.
func _room_px_bounds(room_id: String) -> Rect2:
	if not DeckPlan.has_room(room_id):
		return Rect2()
	var rect: Rect2 = DeckPlan.room_rect(room_id)
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for corner: Vector2 in [
		rect.position,
		rect.position + Vector2(rect.size.x - 1, 0),
		rect.position + Vector2(0, rect.size.y - 1),
		rect.position + rect.size - Vector2.ONE,
	]:
		var p: Vector2 = IsoKit.cell_to_deck(corner)
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var margin: float = PERSONAL_RADIUS * 0.5
	min_p -= Vector2(margin, margin)
	max_p += Vector2(margin, margin)
	return Rect2(min_p, max_p - min_p)


func _update_facing(to_target: Vector2) -> void:
	var angle: float = rad_to_deg(to_target.angle())  # y-down: 90 = screen south
	var bucket: int = wrapi(roundi(angle / 45.0), 0, 8)
	_facing = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"][bucket]


# Picks the gen2 sprite when the manifest/texture resolve, otherwise falls back to the
# legacy Kenney kit exactly as before this sprite-swap system existed (mandatory per the
# animation workstream brief — see the GEN2_CREW_DIR const comment above).
func _apply_sprite() -> void:
	_ensure_gen2_manifest()
	if _gen2_available and _apply_gen2_sprite():
		return
	_apply_legacy_sprite()


# Maps the crew's live simulation fields onto a gen2 manifest state name. Only covers
# states with a real existing trigger today (current_state/wounds) — see the
# GEN2_CREW_DIR const comment for the generated-but-unwired states (fight/carry/floating).
func _gen2_sprite_state() -> String:
	if crew_data.current_state == CrewStateMachine.INCAPACITATED:
		# Covers actual death AND alive-but-down (unconscious/comatose/dying —
		# CrewStateMachine.evaluate() routes all of them through INCAPACITATED). Matches
		# the legacy kit's own rotate-90 treatment of the same state, which doesn't
		# distinguish "dead" from "down" either.
		return "dead"
	if crew_data.current_state == CrewStateMachine.SLEEPING:
		return "sleeping"
	if crew_data.current_state == CrewStateMachine.FROZEN:
		return "injured_idle"  # catatonic — no dedicated art commissioned; closest "not okay, standing" pose
	if crew_data.wounds > 0:
		return "injured_walk" if _moving else "injured_idle"
	return "walk" if _moving else "idle"


# Resolves a facing against a manifest state that may not cover all 8 compass directions
# (e.g. "sleeping" is "e" only) — exact facing, then its mirror via flip_h, then whatever
# facing the state does have, so something always renders instead of silently failing.
func _gen2_resolve_facing(facings: Array, facing: String) -> Dictionary:
	if facing in facings:
		return {"facing": facing, "flip_h": false}
	var mirrored: String = FACING_MIRROR.get(facing, "")
	if mirrored in facings:
		return {"facing": mirrored, "flip_h": true}
	if not facings.is_empty():
		return {"facing": facings[0], "flip_h": false}
	return {"facing": "", "flip_h": false}


# Returns true if a gen2 frame was actually applied. False means "no usable manifest
# entry or texture for this state" and the caller (_apply_sprite) falls back to legacy.
func _apply_gen2_sprite() -> bool:
	var state: String = _gen2_sprite_state()
	var state_info: Dictionary = (_gen2_manifest.get("states", {}) as Dictionary).get(state, {})
	if state_info.is_empty():
		return false

	if state != _gen2_state_key:
		_gen2_state_key = state
		_gen2_frame_t = 0.0

	var frame_count: int = int(state_info.get("frame_count", 1))
	var frame: int = 0
	if state_info.get("animation_mode", "cycle") == "static_variant":
		# Corpse pose variants, not a loop — pick once per crew member and hold it.
		if _gen2_dead_variant < 0:
			_gen2_dead_variant = absi(hash(crew_data.crew_id)) % maxi(1, frame_count)
		frame = _gen2_dead_variant
	elif frame_count > 1:
		var fps: float = float(state_info.get("fps", 0.0))
		if fps > 0.0:
			frame = int(_gen2_frame_t * fps) % frame_count

	var resolved: Dictionary = _gen2_resolve_facing(state_info.get("facings", []), _facing.to_lower())
	var facing: String = resolved.get("facing", "")
	if facing == "":
		return false

	var key: String = "gen2:%s:%s:%d" % [state, facing, frame]
	if key != _current_texture_key:
		var path: String = "%screw_%s_%s_%d.png" % [GEN2_CREW_DIR, state, facing, frame]
		if not ResourceLoader.exists(path):
			return false
		var texture: Texture2D = load(path)
		if texture == null:
			return false
		sprite.texture = texture
		sprite.flip_h = resolved.get("flip_h", false)
		_current_texture_key = key

	sprite.rotation_degrees = 0.0  # gen2 "dead" is a real prone sprite — no rotate-90 hack needed
	var role: String = crew_data.role if ROLE_VARIANT.has(crew_data.role) else FALLBACK_ROLE
	var tint: Color = ROLE_TINT.get(role, Color.WHITE)
	if state == "dead":
		tint = tint.darkened(0.55)
	elif crew_data.current_state == CrewStateMachine.PANICKING:
		tint = tint * Color(1.0, 0.62, 0.58)
	sprite.self_modulate = tint
	return true


func _apply_legacy_sprite() -> void:
	var role: String = crew_data.role if ROLE_VARIANT.has(crew_data.role) else FALLBACK_ROLE
	var key: String = "%s_%s" % [ROLE_VARIANT[role], _facing]
	var collapsed: bool = crew_data.current_state == CrewStateMachine.INCAPACITATED

	if key != _current_texture_key:
		var texture: Texture2D = load(KIT_DIR + key + ".png")
		if texture == null:
			push_warning("CrewMemberNode '%s': missing kit sprite '%s'" % [crew_data.crew_id, key])
			return
		sprite.texture = texture
		sprite.flip_h = false
		_current_texture_key = key

	sprite.rotation_degrees = 90.0 if collapsed else 0.0
	var tint: Color = ROLE_TINT.get(role, Color.WHITE)
	if collapsed:
		tint = tint.darkened(0.55)
	elif crew_data.current_state == CrewStateMachine.PANICKING:
		tint = tint * Color(1.0, 0.62, 0.58)
	sprite.self_modulate = tint


func _apply_status_dot() -> void:
	if _status_dot:
		_status_dot.color = STATE_COLORS.get(crew_data.current_state, Color.WHITE)


func _on_state_changed(crew_id: String, _old_state: String, _new_state: String) -> void:
	if crew_id != crew_data.crew_id:
		return
	_apply_sprite()
	_apply_status_dot()


# --- Speech / thought bubble (docs/dialogue_spec.md "Display") ---------------------------
# DialogueSystem already strips [TAGS] and picks the line; this is purely presentational.
# Declarations (target: open_air) arrive with line_type "declaration" and are rendered as
# THOUGHTS — italic/dimmed, no tail, no sound, matching the spec's Display section ("Thought
# bubbles... reuse declaration lines with target: open_air"). Everything else (opener/reply/
# closer — always addressed to another crew member) is rendered as normal SPEECH.

func _build_bubble() -> void:
	_bubble_anchor = Node2D.new()
	_bubble_anchor.z_as_relative = false
	_bubble_anchor.z_index = BUBBLE_Z_INDEX
	add_child(_bubble_anchor)

	_bubble_panel = Panel.new()
	_bubble_panel.visible = false
	_bubble_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_anchor.add_child(_bubble_panel)

	_bubble_label = RichTextLabel.new()
	_bubble_label.bbcode_enabled = true
	_bubble_label.scroll_active = false
	_bubble_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_label.add_theme_font_size_override("normal_font_size", 14)
	_bubble_panel.add_child(_bubble_label)

	_bubble_tail = Polygon2D.new()
	_bubble_tail.polygon = PackedVector2Array([
		Vector2(-7, 0), Vector2(7, 0), Vector2(0, BUBBLE_TAIL_HEIGHT)])
	_bubble_tail.visible = false
	_bubble_anchor.add_child(_bubble_tail)


# Wrapped-line-count estimate from character count rather than an async layout pass
# (RichTextLabel.fit_content/get_content_height need a frame to settle) — deterministic and
# safe against overlapping calls when lines arrive close together (declaration right after a
# conversation turn, etc).
func _estimate_bubble_size(text: String) -> Vector2:
	var wrapped_lines: int = maxi(1, ceili(float(text.length()) / float(BUBBLE_CHARS_PER_LINE)))
	var explicit_lines: int = text.split("\n").size()
	var line_count: int = maxi(wrapped_lines, explicit_lines)
	var height: float = float(line_count) * BUBBLE_LINE_HEIGHT + BUBBLE_PADDING.y * 2.0
	return Vector2(BUBBLE_WIDTH, height)


func _bbcode_safe(text: String) -> String:
	# Defensive: DialogueSystem already strips [EMOTIVE] tags before emitting line_spoken;
	# this just guards against any stray bracket breaking bbcode parsing.
	return text.replace("[", "(").replace("]", ")")


func _on_line_spoken(crew_id: String, line_key: String, text: String, line_type: String) -> void:
	if crew_id != crew_data.crew_id or text == "":
		return
	var is_thought: bool = line_type == "declaration"
	_show_bubble(text, is_thought)
	# Thoughts are silent by spec (docs/dialogue_spec.md "Display"); speech plays its
	# generated voice line when the audio exists (the corpus is only partially voiced
	# until the ElevenLabs quota resets — missing files just mean a silent bubble).
	if not is_thought:
		_play_voice_line(line_key)


func _play_voice_line(line_key: String) -> void:
	if _voice_player == null or line_key == "":
		return
	var path: String = VOICE_DIR + line_key.replace("#", "_") + ".mp3"
	if not FileAccess.file_exists(path):
		return
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return
	var stream: AudioStreamMP3 = AudioStreamMP3.new()
	stream.data = bytes
	_voice_player.stop()
	_voice_player.stream = stream
	_voice_player.play()


func _show_bubble(text: String, is_thought: bool) -> void:
	if _bubble_panel == null:
		return
	_bubble_gen += 1
	var my_gen: int = _bubble_gen

	var size: Vector2 = _estimate_bubble_size(text)
	_bubble_panel.size = size
	_bubble_panel.position = Vector2(-size.x / 2.0, BUBBLE_BOTTOM_OFFSET - size.y)
	_bubble_label.position = BUBBLE_PADDING
	_bubble_label.size = size - BUBBLE_PADDING * 2.0

	var safe_text: String = _bbcode_safe(text)
	var style := StyleBoxFlat.new()
	if is_thought:
		_bubble_label.text = "[i]%s[/i]" % safe_text
		style.bg_color = BUBBLE_THOUGHT_BG
		style.set_corner_radius_all(16)
		_bubble_label.add_theme_color_override("default_color", BUBBLE_THOUGHT_TEXT)
		_bubble_tail.visible = false
	else:
		_bubble_label.text = safe_text
		style.bg_color = BUBBLE_SPEECH_BG
		style.set_corner_radius_all(6)
		style.set_border_width_all(1)
		style.border_color = BUBBLE_SPEECH_BORDER
		_bubble_label.add_theme_color_override("default_color", BUBBLE_SPEECH_TEXT)
		_bubble_tail.position = Vector2(0, BUBBLE_BOTTOM_OFFSET)
		_bubble_tail.color = BUBBLE_SPEECH_BG
		_bubble_tail.visible = true
	_bubble_panel.add_theme_stylebox_override("panel", style)

	_bubble_panel.modulate.a = 1.0
	_bubble_tail.modulate.a = 1.0
	_bubble_panel.visible = true

	if _bubble_tween != null and _bubble_tween.is_valid():
		_bubble_tween.kill()
	_bubble_tween = create_tween()
	var hold: float = BUBBLE_DISPLAY_SECONDS + clampf(text.length() * 0.03, 0.0, BUBBLE_DISPLAY_MAX_BONUS)
	_bubble_tween.tween_interval(hold)
	_bubble_tween.tween_property(_bubble_panel, "modulate:a", 0.0, BUBBLE_FADE_SECONDS)
	_bubble_tween.parallel().tween_property(_bubble_tail, "modulate:a", 0.0, BUBBLE_FADE_SECONDS)
	_bubble_tween.tween_callback(func():
		if my_gen == _bubble_gen and is_instance_valid(_bubble_panel):
			_bubble_panel.visible = false
			_bubble_tail.visible = false)
