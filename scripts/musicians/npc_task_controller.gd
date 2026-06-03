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

var pending_travel_task := false
var pending_target_position := Vector2.ZERO

@export var task_accept_delay := 1.0
var task_accept_timer := 0.0


func assign_travel_task(position: Vector2) -> void:

	if is_traveling():
		return

	if pending_travel_task:
		return

	pending_travel_task = true
	pending_target_position = position

	task_accept_timer = task_accept_delay


func clear_task() -> void:

	current_task = TaskType.NONE
	target_position = Vector2.ZERO
	has_target = false

	pending_travel_task = false
	task_accept_timer = 0.0

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

	if pending_travel_task:

		task_accept_timer -= delta

		if task_accept_timer <= 0.0:

			pending_travel_task = false

			current_task = TaskType.TRAVEL
			target_position = pending_target_position
			has_target = true

			task_changed.emit()


func get_target_position() -> Vector2:
	return target_position
