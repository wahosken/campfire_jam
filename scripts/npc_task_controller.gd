extends Node

signal task_changed

enum TaskType {
	NONE,
	TRAVEL
}

var current_task := TaskType.NONE

var target_position := Vector2.ZERO
var has_target := false

var attraction_timer := 0.0

@export var attraction_grace_time := 0.75

func assign_travel_task(position: Vector2) -> void:

	print("TRAVEL TASK ASSIGNED")

	current_task = TaskType.TRAVEL
	target_position = position
	has_target = true

	task_changed.emit()


func clear_task() -> void:

	current_task = TaskType.NONE
	target_position = Vector2.ZERO
	has_target = false

	task_changed.emit()


func is_traveling() -> bool:
	return current_task == TaskType.TRAVEL and has_target


func refresh_attraction() -> void:
	attraction_timer = attraction_grace_time


func update_tasks(delta: float) -> void:

	if attraction_timer > 0.0:
		attraction_timer -= delta

		if attraction_timer <= 0.0:
			clear_task()


func get_target_position() -> Vector2:
	return target_position
