extends Node

# Tick-based resource consumption. All rates are per-tick at 1x speed (0.25s).
# Tuned so oxygen runs out in ~10 real minutes with 4 crew under normal conditions.

const OXYGEN_PER_CREW: float = 0.0001
const FOOD_PER_CREW: float   = 0.00005
const WATER_PER_CREW: float  = 0.00007
const POWER_BASE: float      = 0.0002   # always-on systems
const FUEL_IN_TRANSIT: float = 0.00003  # per tick while propulsion is active


func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)


func _on_tick(_elapsed: float, _delta: float) -> void:
	var crew_count: int = GameState.crew.size()

	# Biological — oxygen drain scales inversely with life support efficiency.
	# Damaged life support = faster drain.
	var ls_eff: float = maxf(_system_efficiency("life_support"), 0.1)
	_drain("oxygen", OXYGEN_PER_CREW * crew_count / ls_eff)
	_drain("food",   FOOD_PER_CREW * crew_count)
	_drain("water",  WATER_PER_CREW * crew_count)

	# Power — base draw plus whatever active systems are pulling.
	# TODO(ship): sum per-system power draw once ShipSystem is implemented
	_drain("power", POWER_BASE + _active_system_draw())

	# Fuel — only while propulsion is running.
	# TODO(ship): gate on propulsion ShipSystem status
	if _propulsion_active():
		_drain("fuel", FUEL_IN_TRANSIT)


func _drain(resource_name: String, amount: float) -> void:
	GameState.set_resource(resource_name, GameState.get_resource(resource_name) - amount)


func _system_efficiency(system_name: String) -> float:
	# TODO(ship): return system integrity from DamageModel once implemented
	return 1.0


func _active_system_draw() -> float:
	# TODO(ship): iterate active ShipSystem instances and sum their power_draw
	return 0.0


func _propulsion_active() -> bool:
	# TODO(ship): check propulsion ShipSystem.is_online
	return true
