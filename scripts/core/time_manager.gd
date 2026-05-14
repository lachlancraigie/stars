extends Node

# Real-time with pause. Drives all tick-based simulation systems.
# Connect to EventBus.time_ticked rather than using _process directly.

const TICK_INTERVAL: float = 0.25  # seconds per game tick at 1x speed

enum Speed { PAUSED = 0, NORMAL = 1, FAST = 2 }

var current_speed: Speed = Speed.NORMAL
var elapsed: float = 0.0
var _tick_accumulator: float = 0.0


func _process(delta: float) -> void:
	if current_speed == Speed.PAUSED:
		return
	var scaled_delta: float = delta * current_speed
	_tick_accumulator += scaled_delta
	elapsed += scaled_delta
	while _tick_accumulator >= TICK_INTERVAL:
		_tick_accumulator -= TICK_INTERVAL
		EventBus.time_ticked.emit(elapsed, TICK_INTERVAL)


func pause() -> void:
	current_speed = Speed.PAUSED
	EventBus.game_paused.emit()


func unpause() -> void:
	if current_speed == Speed.PAUSED:
		current_speed = Speed.NORMAL
	EventBus.game_unpaused.emit()


func set_speed(speed: Speed) -> void:
	var was_paused: bool = is_paused()
	current_speed = speed
	if speed == Speed.PAUSED and not was_paused:
		EventBus.game_paused.emit()
	elif speed != Speed.PAUSED and was_paused:
		EventBus.game_unpaused.emit()


func is_paused() -> bool:
	return current_speed == Speed.PAUSED
