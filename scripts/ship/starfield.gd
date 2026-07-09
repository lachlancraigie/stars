class_name Starfield
extends Node2D

# Procedural parallax starfield backdrop. Cheap on GL Compatibility: each depth
# layer draws its stars once via _draw() (a handful of draw_circle calls cached
# by the renderer) and is then only ever translated, never redrawn, to animate
# a subtle drift — no per-frame draw calls, no per-star nodes.
#
# Sits behind the ship deck: add as a direct child of Main (NOT of ShipDeck, so
# it stays fixed to the viewport instead of scaling/panning with the deck), with
# a very low z_index so it renders behind the hull silhouette and floors
# regardless of node order.

const LAYER_CONFIG: Array = [
	# {count, radius range, brightness range, drift amplitude, drift speed, parallax_depth}
	# parallax_depth: fraction of DeckCamera's pan that nudges this layer, farthest-first —
	# a cheap depth cue (near layers drift a little opposite the pan, far layers barely move).
	{"count": 160, "radius": [0.6, 1.1], "brightness": [0.35, 0.55], "amp": Vector2(5, 3), "speed": 0.05, "parallax_depth": 0.2},
	{"count": 80,  "radius": [1.0, 1.6], "brightness": [0.55, 0.80], "amp": Vector2(11, 7), "speed": 0.09, "parallax_depth": 0.5},
	{"count": 28,  "radius": [1.4, 2.2], "brightness": [0.80, 1.00], "amp": Vector2(18, 12), "speed": 0.14, "parallax_depth": 1.0},
]
const FIELD_SIZE: Vector2 = Vector2(2400, 1500)  # bigger than the 1920x1080 canvas
const PARALLAX_FACTOR: float = 0.03  # subtle: 3% of DeckCamera's pan distance, at full depth

var _seed: int = 0
var _layers: Array = []  # Node2D per depth layer
var _t: float = 0.0

# Deliberately loose coupling to DeckCamera: looked up lazily by group so this
# still works standalone (no camera in the tree -> parallax_offset() is just
# zero, drift-only, same as before Part A).
var _camera: Node2D = null
var _camera_origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	z_index = -1000
	for i in LAYER_CONFIG.size():
		var layer := _StarLayer.new()
		layer.configure(LAYER_CONFIG[i], _seed + i * 7919)
		add_child(layer)
		_layers.append(layer)


func set_seed_value(value: int) -> void:
	_seed = value


func _process(delta: float) -> void:
	_t += delta
	var parallax: Vector2 = _parallax_offset()
	for i in _layers.size():
		var cfg: Dictionary = LAYER_CONFIG[i]
		var amp: Vector2 = cfg["amp"]
		var speed: float = cfg["speed"]
		var depth: float = cfg.get("parallax_depth", 1.0)
		_layers[i].position = Vector2(
			sin(_t * speed) * amp.x,
			cos(_t * speed * 0.8) * amp.y
		) + parallax * depth


# Tiny counter-drift opposite DeckCamera's pan from its starting position —
# purely cosmetic, never affects gameplay/positioning, degrades to Vector2.ZERO
# if there's no camera (e.g. this scene were reused without one).
func _parallax_offset() -> Vector2:
	if _camera == null:
		_camera = get_tree().get_first_node_in_group("deck_camera") as Node2D
		if _camera == null:
			return Vector2.ZERO
		_camera_origin = _camera.position
	return (_camera_origin - _camera.position) * PARALLAX_FACTOR


class _StarLayer extends Node2D:
	var _points: Array = []  # [{"pos":Vector2,"radius":float,"color":Color}]

	func configure(cfg: Dictionary, layer_seed: int) -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = layer_seed
		var count: int = cfg["count"]
		var r_range: Array = cfg["radius"]
		var b_range: Array = cfg["brightness"]
		for i in count:
			var pos := Vector2(
				rng.randf_range(-FIELD_SIZE.x / 2.0, FIELD_SIZE.x / 2.0),
				rng.randf_range(-FIELD_SIZE.y / 2.0, FIELD_SIZE.y / 2.0)
			)
			var radius: float = rng.randf_range(r_range[0], r_range[1])
			var b: float = rng.randf_range(b_range[0], b_range[1])
			_points.append({"pos": pos, "radius": radius, "color": Color(b, b, b * 1.05 + 0.05, 1.0)})

	func _ready() -> void:
		queue_redraw()  # star positions are static; drift is a transform, not a redraw

	func _draw() -> void:
		for p in _points:
			draw_circle(p["pos"], p["radius"], p["color"])
