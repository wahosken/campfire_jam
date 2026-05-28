extends CanvasLayer

@export var touch_overlay_path: NodePath
@export var require_start_gate_open := true
@export var start_gate_path: NodePath

@onready var panel: Control = $PanelContainer
@onready var resume_button: Button = $PanelContainer/VBoxContainer/ResumeButton
@onready var restart_scene_button: Button = $PanelContainer/VBoxContainer/RestartSceneButton
@onready var mute_button: Button = $PanelContainer/VBoxContainer/MuteButton
@onready var touch_arrows_button: Button = $PanelContainer/VBoxContainer/TouchArrowsButton
@onready var touch_joystick_button: Button = $PanelContainer/VBoxContainer/TouchJoystickButton
@onready var show_jam_radius_button: CheckButton = $PanelContainer/VBoxContainer/ShowJamRadiusButton
@onready var show_fps_button: CheckButton = $PanelContainer/VBoxContainer/ShowFPSButton
@onready var close_button: Button = $PanelContainer/VBoxContainer/CloseButton

@onready var debug_overlay: Label = $DebugOverlay

var volume_slider: HSlider

var is_paused := false
var previous_volume_db := 0.0
var is_muted := false

var show_jam_radius_debug := false
var show_fps_debug := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Important: keep the CanvasLayer visible.
	# Only hide the pause panel.
	panel.visible = false

	if debug_overlay != null:
		debug_overlay.text = ""
		debug_overlay.visible = false
		debug_overlay.position = Vector2(20, 20)
		debug_overlay.size = Vector2(400, 120)
		debug_overlay.z_index = 999
		debug_overlay.add_theme_color_override("font_color", Color.WHITE)
	else:
		push_warning("PauseMenu could not find DebugOverlay.")

	volume_slider = find_child("VolumeSlider", true, false) as HSlider

	resume_button.pressed.connect(resume_game)
	close_button.pressed.connect(resume_game)
	restart_scene_button.pressed.connect(_restart_scene)
	mute_button.pressed.connect(_toggle_mute)
	touch_arrows_button.pressed.connect(_set_touch_arrows)
	touch_joystick_button.pressed.connect(_set_touch_joystick)
	show_jam_radius_button.toggled.connect(_toggle_jam_radius_debug)
	show_fps_button.toggled.connect(_toggle_fps_debug)

	if volume_slider != null:
		volume_slider.min_value = 0
		volume_slider.max_value = 100
		volume_slider.value = 100
		volume_slider.value_changed.connect(_on_volume_changed)
	else:
		push_warning("PauseMenu could not find VolumeSlider.")

	_setup_focus()
	_position_debug_overlay()


func _process(_delta: float) -> void:
	_position_debug_overlay()
	_update_debug_overlay()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if not _can_pause_now():
			return

		toggle_pause()
		get_viewport().set_input_as_handled()


func _handle_touch_press(touch_position: Vector2) -> void:
	var buttons: Array[Button] = [
		resume_button,
		restart_scene_button,
		mute_button,
		touch_arrows_button,
		touch_joystick_button,
		show_jam_radius_button,
		show_fps_button,
		close_button
	]

	for button in buttons:
		if button == null:
			continue

		if not button.visible:
			continue

		var rect := button.get_global_rect()

		if rect.has_point(touch_position):
			button.grab_focus()

			if button is CheckButton:
				button.button_pressed = not button.button_pressed
				button.toggled.emit(button.button_pressed)
			else:
				button.pressed.emit()

			return


func _can_pause_now() -> bool:
	if not require_start_gate_open:
		return true

	if start_gate_path == NodePath():
		return false

	var start_gate := get_node_or_null(start_gate_path)

	if start_gate == null:
		return true

	if "has_started" in start_gate:
		return start_gate.has_started

	return false


func toggle_pause() -> void:
	if is_paused:
		resume_game()
	else:
		pause_game()


func pause_game() -> void:
	is_paused = true
	get_tree().paused = true
	panel.visible = true

	await get_tree().process_frame
	resume_button.grab_focus()


func resume_game() -> void:
	is_paused = false
	get_tree().paused = false
	panel.visible = false


func _restart_scene() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_volume_changed(value: float) -> void:
	if is_muted:
		return

	var bus_index := AudioServer.get_bus_index("Master")

	if value <= 0:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
	else:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(value / 100.0))


func _toggle_mute() -> void:
	var bus_index := AudioServer.get_bus_index("Master")

	if is_muted:
		AudioServer.set_bus_volume_db(bus_index, previous_volume_db)
		is_muted = false
		mute_button.text = "Mute"

		if volume_slider != null:
			volume_slider.editable = true
			volume_slider.modulate = Color.WHITE
	else:
		previous_volume_db = AudioServer.get_bus_volume_db(bus_index)
		AudioServer.set_bus_volume_db(bus_index, -80.0)
		is_muted = true
		mute_button.text = "Unmute"

		if volume_slider != null:
			volume_slider.editable = false
			volume_slider.modulate = Color(1, 1, 1, 0.35)


func _set_touch_arrows() -> void:
	var touch_overlay := get_node_or_null(touch_overlay_path)

	if touch_overlay != null and touch_overlay.has_method("set_touch_mode"):
		touch_overlay.set_touch_mode(0)


func _set_touch_joystick() -> void:
	var touch_overlay := get_node_or_null(touch_overlay_path)

	if touch_overlay != null and touch_overlay.has_method("set_touch_mode"):
		touch_overlay.set_touch_mode(1)


func _toggle_jam_radius_debug(enabled: bool) -> void:
	show_jam_radius_debug = enabled

	get_tree().debug_collisions_hint = enabled

	for shape in get_tree().get_nodes_in_group("jam_activation_shape"):
		if not is_instance_valid(shape):
			continue

		if shape is CollisionShape2D:
			shape.debug_color = Color(0.0, 0.682, 0.682, 0.337)

	_update_debug_overlay()


func _toggle_fps_debug(enabled: bool) -> void:
	show_fps_debug = enabled
	_update_debug_overlay()


func _setup_focus() -> void:
	var controls: Array[Control] = [
		resume_button,
		restart_scene_button,
		volume_slider,
		mute_button,
		touch_arrows_button,
		touch_joystick_button,
		show_jam_radius_button,
		show_fps_button,
		close_button
	]

	for control in controls:
		if control != null:
			control.focus_mode = Control.FOCUS_ALL


func _update_debug_overlay() -> void:
	if debug_overlay == null:
		return

	var lines: Array[String] = []

	if show_fps_debug:
		lines.append("FPS: " + str(Engine.get_frames_per_second()))

	if show_jam_radius_debug:
		lines.append("Jam activation shapes: " + str(get_tree().get_nodes_in_group("jam_activation_shape").size()))
		lines.append("Jamspot area: ON")

	debug_overlay.text = "\n".join(lines)
	debug_overlay.show()
	debug_overlay.visible = lines.size() > 0

func _position_debug_overlay() -> void:
	debug_overlay.position = Vector2(
		get_viewport().get_visible_rect().size.x - 200,
		20
	)
	debug_overlay.size = Vector2(400, 120)
