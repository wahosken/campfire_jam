extends CanvasLayer

signal game_started

@onready var color_rect: ColorRect = $ColorRect
@onready var label: Label = $ColorRect/CenterContainer/Label

var has_started := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	visible = true
	get_tree().paused = true
	
	label.text = "Press Any Button to Start"


func _input(event: InputEvent) -> void:
	if has_started:
		return
	
	if _is_start_input(event):
		get_viewport().set_input_as_handled()
		_start_game()


func _is_start_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	
	if event is InputEventMouseButton:
		return event.pressed
	
	if event is InputEventJoypadButton:
		return event.pressed
	
	if event is InputEventScreenTouch:
		return event.pressed
	
	if event is InputEventAction:
		return event.pressed
	
	if event is InputEventJoypadMotion:
		return abs(event.axis_value) > 0.5
	
	return false


func _start_game() -> void:
	has_started = true
	
	get_tree().paused = false
	visible = false
	
	game_started.emit()
	queue_free()
