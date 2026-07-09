class_name DeckCamera
extends Camera2D

# Pan & zoom controller for the ship deck. Replaces the old static fit where
# main.gd baked a scale/position directly onto the ShipDeck container.
#
# Default framing: configure() auto-fits DeckPlan.deck_bounds() to the
# viewport, exactly like the old _fit_deck_to_view() did — same formula, same
# "never upscale past 1:1" cap — so a fresh scene looks identical to before.
# That fit zoom is also the pivot for the zoom clamp (0.5x-2.5x of it).
#
# Panning is clamped via Camera2D's own limit_left/top/right/bottom (built
# from DeckPlan.deck_bounds() + CLAMP_MARGIN): Godot keeps the camera's view
# rect inside those limits when it fits, and CENTERS the view within them the
# moment the view rect is larger than the limit rect (i.e. zoomed out past the
# point where the whole deck+margin already fits on screen). That's exactly
# "zoom clamp and pan clamp cooperate — zoomed fully out = deck centered"
# with zero custom clamping math needed.
#
# Lives as a direct sibling of ShipDeck under Main (see main.gd), NOT inside
# it — Camera2D.current affects the whole viewport's canvas transform, not
# just its own subtree, so nothing needs to be reparented for the camera to
# take over framing. CanvasLayers (Starfield's own layer, HUD, DirectiveMenu)
# are untouched by a Camera2D's transform by design, which is what keeps them
# screen-fixed (see starfield.gd / main.gd _setup_starfield()).

const ZOOM_MIN_MULT: float = 0.5          # relative to the auto-fit zoom
const ZOOM_MAX_MULT: float = 2.5
const ZOOM_STEP: float = 1.12             # multiplicative change per wheel notch
const PAN_SPEED: float = 900.0            # keyboard pan, screen px/sec (scaled by zoom)
const DRAG_THRESHOLD: float = 6.0         # screen px of movement before a press becomes a pan
const CLAMP_MARGIN: float = 220.0         # world px of breathing room around deck_bounds
const EDGE_SCROLL_MARGIN: float = 14.0    # screen px from the viewport edge that triggers scroll
const EDGE_SCROLL_SPEED: float = 700.0    # screen px/sec (scaled by zoom)

var _fit_zoom: float = 1.0
var _min_zoom: float = 1.0
var _max_zoom: float = 1.0
var _deck_bounds: Rect2 = Rect2()

# Drag-pan state. Any of left/middle/right can drag; left additionally has a
# threshold so a plain click-on-crew (handled by DirectiveMenu, independently,
# on the same press event) never gets misread as an accidental pan.
var _drag_button: int = -1
var _drag_active: bool = false
var _press_screen_pos: Vector2 = Vector2.ZERO
var _last_drag_screen: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("deck_camera")
	position_smoothing_enabled = false
	limit_smoothed = false


# Called once by main.gd after ShipLayoutGen has filled DeckPlan for this run.
# fit_view is the rect (in screen px) the deck should fill at the default
# zoom — mirrors the old DECK_VIEW const main.gd used to fit ShipDeck's scale.
func configure(bounds: Rect2, fit_view: Rect2) -> void:
	_deck_bounds = bounds
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var s: float = minf(fit_view.size.x / bounds.size.x, fit_view.size.y / bounds.size.y)
	s = minf(s, 1.0)  # never upscale a small deck past 1:1, matches old behaviour
	_fit_zoom = s
	_min_zoom = _fit_zoom * ZOOM_MIN_MULT
	_max_zoom = _fit_zoom * ZOOM_MAX_MULT

	zoom = Vector2(_fit_zoom, _fit_zoom)
	position = bounds.get_center()

	limit_left = int(floor(bounds.position.x - CLAMP_MARGIN))
	limit_top = int(floor(bounds.position.y - CLAMP_MARGIN))
	limit_right = int(ceil(bounds.position.x + bounds.size.x + CLAMP_MARGIN))
	limit_bottom = int(ceil(bounds.position.y + bounds.size.y + CLAMP_MARGIN))

	reset_smoothing()
	make_current()


func _process(delta: float) -> void:
	if _deck_bounds.size == Vector2.ZERO:
		return
	_handle_mouse_drag()
	_handle_keyboard_pan(delta)
	_handle_edge_scroll(delta)


func _unhandled_input(event: InputEvent) -> void:
	if _deck_bounds.size == Vector2.ZERO:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)


func _handle_mouse_button(mb: InputEventMouseButton) -> void:
	# Wheel: zoom toward the cursor. Consumed (harmless — nothing else reads
	# wheel events) so it can't also fall through as anything else.
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
		_zoom_at(mb.position, ZOOM_STEP)
		get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
		_zoom_at(mb.position, 1.0 / ZOOM_STEP)
		get_viewport().set_input_as_handled()
		return

	# Drag tracking only — deliberately NEVER call set_input_as_handled() here.
	# DirectiveMenu also reads raw left-press events via _unhandled_input to
	# select/deselect crew; that must keep firing on every press regardless of
	# whether it turns into a drag, so clicks-that-don't-drag still work and
	# clicks-that-do-drag still opened the menu at press time.
	if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
		if mb.pressed:
			if _drag_button == -1:
				_drag_button = mb.button_index
				_drag_active = false
				_press_screen_pos = mb.position
		elif mb.button_index == _drag_button:
			_drag_button = -1
			_drag_active = false


func _handle_mouse_drag() -> void:
	if _drag_button == -1:
		return
	var mouse_screen: Vector2 = get_viewport().get_mouse_position()
	if not _drag_active:
		if mouse_screen.distance_to(_press_screen_pos) < DRAG_THRESHOLD:
			return
		_drag_active = true
		_last_drag_screen = _press_screen_pos  # apply the full delta since press, nothing lost
	var delta_screen: Vector2 = mouse_screen - _last_drag_screen
	if delta_screen == Vector2.ZERO:
		return
	position -= delta_screen / zoom.x
	_last_drag_screen = mouse_screen


func _handle_keyboard_pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * delta / zoom.x


func _handle_edge_scroll(delta: float) -> void:
	if _drag_active or EDGE_SCROLL_MARGIN <= 0.0:
		return
	if not get_window().has_focus():
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var m: Vector2 = get_viewport().get_mouse_position()
	if m.x < 0.0 or m.y < 0.0 or m.x > vp_size.x or m.y > vp_size.y:
		return  # cursor outside the window entirely — ignore
	var dir := Vector2.ZERO
	if m.x < EDGE_SCROLL_MARGIN:
		dir.x -= 1.0
	elif m.x > vp_size.x - EDGE_SCROLL_MARGIN:
		dir.x += 1.0
	if m.y < EDGE_SCROLL_MARGIN:
		dir.y -= 1.0
	elif m.y > vp_size.y - EDGE_SCROLL_MARGIN:
		dir.y += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * EDGE_SCROLL_SPEED * delta / zoom.x


# Zoom in/out by `factor`, keeping the world point under `cursor_screen` fixed
# on screen. Clamped to [_min_zoom, _max_zoom]; panning stays clamped by the
# Camera2D limit_* set in configure().
func _zoom_at(cursor_screen: Vector2, factor: float) -> void:
	var old_zoom: float = zoom.x
	var new_zoom: float = clampf(old_zoom * factor, _min_zoom, _max_zoom)
	if is_equal_approx(new_zoom, old_zoom):
		return
	var world_before: Vector2 = get_global_mouse_position()
	zoom = Vector2(new_zoom, new_zoom)
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	position = world_before - (cursor_screen - vp_size * 0.5) / new_zoom
