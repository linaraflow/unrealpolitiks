extends Control

@export var min_alpha: float = 0.35
@export var max_alpha: float = 0.6
@export var cycle_seconds: float = 6.0

func _ready() -> void:
	var t := create_tween().set_loops()
	t.tween_property(self, "modulate:a", min_alpha, cycle_seconds)
	t.tween_property(self, "modulate:a", max_alpha, cycle_seconds)
