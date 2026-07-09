class_name IsoKit
extends RefCounted

# Helpers for the legacy isometric sprite kit (assets/sprites/legacy/).
# Every kit sprite is a 512x512 canvas with a consistent registration:
# the floor diamond is 130x65 px with its centre at canvas (256, 311).
# That means any sprite placed with ANCHOR_OFFSET sits correctly on the
# grid cell at its node position — tiles, props, and characters alike.

const KIT_DIR: String = "res://assets/sprites/legacy/"

const TILE_HALF_W: float = 65.0   # half of the 130px diamond width
const TILE_HALF_H: float = 32.5   # half of the 65px diamond height
const ANCHOR_OFFSET: Vector2 = Vector2(0, -55)  # canvas centre -> diamond centre

# Props and crew z-sort by their deck-space y; floors sit beneath everything.
const Z_FLOOR: int = 0
const Z_PROP_BASE: int = 100


# Centre of grid cell (cx, cy) in deck pixels. Fractional cells are fine
# (used for door gates that sit on a cell boundary).
static func cell_to_deck(cell: Vector2) -> Vector2:
	return Vector2(
		(cell.x - cell.y) * TILE_HALF_W,
		(cell.x + cell.y) * TILE_HALF_H
	)


static func texture(sprite_name: String) -> Texture2D:
	return load(KIT_DIR + sprite_name + ".png")


# Build a kit sprite anchored to its grid cell. deck_y_abs is the sprite's
# absolute deck-space y, used for painter's-order z (pass the parent-relative
# position added to the parent's deck position).
static func make_sprite(sprite_name: String, local_pos: Vector2, deck_y_abs: float,
		is_floor: bool = false) -> Sprite2D:
	var sprite := Sprite2D.new()
	var tex: Texture2D = texture(sprite_name)
	if tex == null:
		push_warning("IsoKit: missing kit sprite '%s'" % sprite_name)
		return sprite
	sprite.texture = tex
	sprite.offset = ANCHOR_OFFSET
	sprite.position = local_pos
	sprite.z_index = Z_FLOOR if is_floor else Z_PROP_BASE + int(deck_y_abs)
	return sprite


# z_index for a dynamic object (crew) at absolute deck-space y.
static func z_for(deck_y_abs: float) -> int:
	return Z_PROP_BASE + int(deck_y_abs)
