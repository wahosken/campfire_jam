extends Node

@export var circle_min_radius := 125.0
@export var circle_max_radius := 150.0

@export var pit_center_bias := 0.6
@export var stage_arc_strength := 0.0

func get_radius(_style: String, _count: int) -> Vector2:
	# return min/max only — NO behavior logic
	return Vector2(circle_min_radius, circle_max_radius)
