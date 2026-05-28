extends Control

@export var joystick_size := 140.0
@export var knob_size := 64.0
@export var max_distance := 45.0
@export var deadzone := 0.25

@onready var base: TextureRect = $Base
@onready var knob: TextureRect = $Knob

var touch_index := -1
var center := Vector2.ZERO
var direction := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	custom_minimum_size = Vector2(joystick_size, joystick_size)
	size = Vector2(joystick_size, joystick_size)

	_force_child_layout()

	await get_tree().process_frame

	_force_child_layout()
	_reset_knob()


func _resized() -> void:
	_force_child_layout()
	_reset_knob()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			_update_joystick(event.position)
		elif not event.pressed and event.index == touch_index:
			touch_index = -1
			_release_all()
			_reset_knob()

	if event is InputEventScreenDrag and event.index == touch_index:
		_update_joystick(event.position)

	if event is InputEventMouseButton:
		if event.pressed and touch_index == -1:
			touch_index = -2
			_update_joystick(event.position)
		elif not event.pressed and touch_index == -2:
			touch_index = -1
			_release_all()
			_reset_knob()

	if event is InputEventMouseMotion and touch_index == -2:
		_update_joystick(event.position)


func _force_child_layout() -> void:
	center = size * 0.5

	if base != null:
		base.set_anchors_preset(Control.PRESET_TOP_LEFT)
		base.position = Vector2.ZERO
		base.size = size
		base.scale = Vector2.ONE
		base.pivot_offset = Vector2.ZERO
		base.mouse_filter = Control.MOUSE_FILTER_IGNORE
		base.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	if knob != null:
		knob.set_anchors_preset(Control.PRESET_TOP_LEFT)
		knob.size = Vector2(knob_size, knob_size)
		knob.scale = Vector2.ONE
		knob.pivot_offset = Vector2.ZERO
		knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		knob.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED


func _update_joystick(local_pos: Vector2) -> void:
	var offset := local_pos - center

	if offset.length() > max_distance:
		offset = offset.normalized() * max_distance

	direction = offset / max_distance

	knob.position = center + offset - knob.size * 0.5

	_update_input_actions()


func _update_input_actions() -> void:
	_set_action("move_left", direction.x < -deadzone)
	_set_action("move_right", direction.x > deadzone)
	_set_action("move_up", direction.y < -deadzone)
	_set_action("move_down", direction.y > deadzone)


func _set_action(action_name: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action_name)
	else:
		Input.action_release(action_name)


func _release_all() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")
	direction = Vector2.ZERO


func _reset_knob() -> void:
	if knob == null:
		return

	knob.position = center - knob.size * 0.5
