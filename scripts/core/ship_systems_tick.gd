extends Node

# Tick source for the situational power/life-support/repair models (Mothership rewrite).
# Formerly ResourceTick, which drained the old normalised oxygen/power/food/water/fuel/
# spare-parts/medicine bars each tick — that whole bar system is gone (see CLAUDE.md
# 2026-07-09 session note). This autoload now just fans EventBus.time_ticked out to the
# static tick() functions that own each situational model's math, so the tick-source role
# survives even though "resources" as a concept doesn't.

func _ready() -> void:
	EventBus.time_ticked.connect(_on_tick)


func _on_tick(_elapsed: float, delta: float) -> void:
	PowerModel.tick(delta)
	LifeSupportModel.tick(delta)
	RepairModel.tick(delta)
