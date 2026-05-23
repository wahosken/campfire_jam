extends CanvasLayer

@export var show_touch_controls_on_start := true

@onready var ui_root: Control = $UI

@onready var left_button: TouchScreenButton = $UI/HBoxContainer/Left
@onready var right_button: TouchScreenButton = $UI/HBoxContainer/Right
@onready var up_button: TouchScreenButton = $UI/HBoxContainer2/Up
@onready var down_button: TouchScreenButton = $UI/HBoxContainer2/Down
@onready var pause_button: TouchScreenButton = $UI/HBoxContainer3/PauseButton
@onready var interact_button: TouchScreenButton = $UI/HBoxContainer4/InteractButton
@onready var jam_button: TouchScreenButton = $UI/HBoxContainer5/JamButton
@onready var cycle_instruments_button: TouchScreenButton = $UI/HBoxContainer5/CycleInstrumentsButton


func _ready() -> void:
	_set_touch_action(left_button, "move_left")
	_set_touch_action(right_button, "move_right")
	_set_touch_action(up_button, "move_up")
	_set_touch_action(down_button, "move_down")
	_set_touch_action(pause_button, "pause")
	_set_touch_action(interact_button, "interact")
	_set_touch_action(jam_button, "play_instrument")
	_set_touch_action(cycle_instruments_button, "cycle_instrument")

	ui_root.visible = show_touch_controls_on_start


func _input(event: InputEvent) -> void:
	if _is_keyboard_or_controller_event(event):
		_hide_touch_controls()
		return

	if _is_touch_or_mouse_event(event):
		_show_touch_controls()
		return


func _set_touch_action(button: TouchScreenButton, action_name: String) -> void:
	if button == null:
		push_warning("Missing TouchScreenButton for action: " + action_name)
		return

	button.action = action_name


func _hide_touch_controls() -> void:
	if ui_root.visible:
		ui_root.visible = false


func _show_touch_controls() -> void:
	if not ui_root.visible:
		ui_root.visible = true


func _is_keyboard_or_controller_event(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed:
		return true

	if event is InputEventJoypadButton and event.pressed:
		return true

	if event is InputEventJoypadMotion:
		return abs(event.axis_value) > 0.25

	return false


func _is_touch_or_mouse_event(event: InputEvent) -> bool:
	if event is InputEventScreenTouch and event.pressed:
		return true

	if event is InputEventMouseButton and event.pressed:
		return true

	return false
