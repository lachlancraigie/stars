class_name PowerModel
extends RefCounted

# Ship power grid (Mothership-flavoured, not a rules.md system directly — this is the
# "situational resource model" called for in the overhaul spec). While the reactor
# (engine_room) is running, every room is powered for free. On reactor failure the ship
# falls to a battery budget: the AI diverts limited power room-by-room, with a hard cap on
# how many rooms can be powered simultaneously and a drain rate that scales with how many
# rooms are currently drawing from the battery. Ticked from ShipSystemsTick (formerly
# ResourceTick) via EventBus.time_ticked.

const MAX_BATTERY_ROOMS: int = 3
const BASE_DRAIN_PER_SEC: float = 0.03        # battery % / sec even with zero rooms powered (life support/ai core draw, etc.)
const PER_ROOM_DRAIN_PER_SEC: float = 0.12    # additional % / sec for each currently-powered room
const LOW_BATTERY_FRACTION: float = 0.25      # battery_charge / battery_capacity at/under this = "power_low"


static func tick(delta: float) -> void:
	if GameState.reactor_online:
		return
	var drain: float = BASE_DRAIN_PER_SEC + PER_ROOM_DRAIN_PER_SEC * GameState.powered_rooms.size()
	GameState.set_battery_charge(GameState.battery_charge - drain * delta)
