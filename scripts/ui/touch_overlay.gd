extends CanvasLayer

enum TouchMode {
	ARROWS,
	JOYSTICK
}

@export var show_touch_controls_on_start := false
@export var touch_mode: TouchMode = TouchMode.ARROWS

@onready var ui_root: Control = $UI

@onready var left_button: TouchScreenButton = $UI/HBoxContainer/Left
@onready var right_button: TouchScreenButton = $UI/HBoxContainer/Right
@onready var up_button: TouchScreenButton = $UI/HBoxContainer2/Up
@onready var down_button: TouchScreenButton = $UI/HBoxContainer2/Down
@onready var pause_button: TouchScreenButton = $UI/HBoxContainer3/PauseButton
@onready var interact_button: TouchScreenButton = $UI/HBoxContainer4/InteractButton
@onready var melody_button: TouchScreenButton = $UI/HBoxContainer4/MelodyButton
@onready var rhythm_button: TouchScreenButton = $UI/HBoxContainer4/RhythmButton
@onready var cycle_instruments_button: TouchScreenButton = $UI/HBoxContainer4/CycleInstrumentsButton

@onready var joystick_controls: Control = $UI/HBoxContainer5/JoystickControls


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_set_touch_action(left_button, "move_left")
	_set_touch_action(right_button, "move_right")
	_set_touch_action(up_button, "move_up")
	_set_touch_action(down_button, "move_down")
	_set_touch_action(pause_button, "pause")
	_set_touch_action(interact_button, "interact")
	_set_touch_action(melody_button, "play_melody")
	_set_touch_action(rhythm_button, "play_rhythm")
	_set_touch_action(cycle_instruments_button, "cycle_instrument")

	if ui_root != null:
		ui_root.visible = show_touch_controls_on_start

	_apply_touch_mode()


func _input(event: InputEvent) -> void:
	if _is_keyboard_or_controller_event(event):
		_hide_touch_controls()
		return

	if _is_touch_or_mouse_event(event):
		_show_touch_controls()
		return


func set_touch_mode(new_mode: TouchMode) -> void:
	touch_mode = new_mode
	_apply_touch_mode()


func set_touch_mode_arrows() -> void:
	set_touch_mode(TouchMode.ARROWS)


func set_touch_mode_joystick() -> void:
	set_touch_mode(TouchMode.JOYSTICK)


func _apply_touch_mode() -> void:
	var using_arrows := touch_mode == TouchMode.ARROWS
	var using_joystick := touch_mode == TouchMode.JOYSTICK

	_set_direction_buttons_visible(using_arrows)

	if joystick_controls != null:
		joystick_controls.visible = using_joystick


func _set_direction_buttons_visible(should_show: bool) -> void:
	if left_button != null:
		left_button.visible = should_show

	if right_button != null:
		right_button.visible = should_show

	if up_button != null:
		up_button.visible = should_show

	if down_button != null:
		down_button.visible = should_show


func _set_touch_action(button: TouchScreenButton, action_name: String) -> void:
	if button == null:
		push_warning("Missing TouchScreenButton for action: " + action_name)
		return

	button.action = action_name


func _hide_touch_controls() -> void:
	if ui_root == null:
		return

	if ui_root.visible:
		ui_root.visible = false


func _show_touch_controls() -> void:
	if ui_root == null:
		return

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
