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
	# {count, radius range, brightness range, drift amplitude, drift speed}
	{"count": 160, "radius": [0.6, 1.1], "brightness": [0.35, 0.55], "amp": Vector2(5, 3), "speed": 0.05},
	{"count": 80,  "radius": [1.0, 1.6], "brightness": [0.55, 0.80], "amp": Vector2(11, 7), "speed": 0.09},
	{"count": 28,  "radius": [1.4, 2.2], "brightness": [0.80, 1.00], "amp": Vector2(18, 12), "speed": 0.14},
]
const FIELD_SIZE: Vector2 = Vector2(2400, 1500)  # bigger than the 1920x1080 canvas

var _seed: int = 0
var _layers: Array = []  # Node2D per depth layer
var _t: float = 0.0


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
	for i in _layers.size():
		var cfg: Dictionary = LAYER_CONFIG[i]
		var amp: Vector2 = cfg["amp"]
		var speed: float = cfg["speed"]
		_layers[i].position = Vector2(
			sin(_t * speed) * amp.x,
			cos(_t * speed * 0.8) * amp.y
		)


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
