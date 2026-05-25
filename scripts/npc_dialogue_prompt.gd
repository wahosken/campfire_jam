extends CanvasLayer

signal closed

@onready var name_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameLabel
@onready var play_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PlayButton
@onready var follow_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/FollowButton
@onready var close_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseButton

@export var input_open_grace_time := 0.2
@export var joystick_deadzone := 0.55

@export var menu_nav_deadzone := 0.5

var menu_nav_locked := false
var menu_accept_locked := false

var current_npc: Node = null
var menu_buttons: Array[Button] = []
var selected_button_index := 0

var input_cooldown := 0.0
var menu_axis_locked := false


func _ready() -> void:
	add_to_group("npc_dialogue_prompt")

	visible = false

	menu_buttons = [
		play_button,
		follow_button,
		close_button
	]

	for button in menu_buttons:
		if button != null:
			button.toggle_mode = false
			button.button_pressed = false
			button.focus_mode = Control.FOCUS_NONE

	play_button.pressed.connect(_on_play_button_clicked)
	follow_button.pressed.connect(_on_follow_button_clicked)
	close_button.pressed.connect(_on_close_button_clicked)

	_set_buttons_focus_mode(false)


func _process(delta: float) -> void:
	if not visible:
		return

	if input_cooldown > 0.0:
		input_cooldown -= delta
		return

	if Input.is_action_just_pressed("close_menu") or Input.is_action_just_pressed("ui_cancel"):
		close()
		return

	if menu_accept_locked:
		if not Input.is_action_pressed("interact") and not Input.is_action_pressed("ui_accept"):
			menu_accept_locked = false
	else:
		if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("ui_accept"):
			_activate_selected_option()
			return

	var nav_direction: int = _get_single_menu_nav_direction()

	if nav_direction != 0:
		_move_selection(nav_direction)


func open_for_npc(npc: Node) -> void:
	current_npc = npc

	if current_npc == null:
		return

	if current_npc.has_method("disable_interaction_temporarily"):
		current_npc.disable_interaction_temporarily()

	var player: Node = get_tree().get_first_node_in_group("player")

	if player != null and player.has_method("clear_nearby_interactables"):
		player.clear_nearby_interactables()

	visible = true

	var npc_name := "Musician"

	if current_npc.has_method("get_display_name"):
		npc_name = current_npc.get_display_name()
	elif "display_name" in current_npc:
		npc_name = str(current_npc.display_name)
	elif current_npc.name != "":
		npc_name = current_npc.name

	name_label.text = npc_name

	_refresh_buttons()
	_select_button(0)

	input_cooldown = 0.0
	menu_nav_locked = true
	menu_accept_locked = true


func close() -> void:
	if current_npc != null:
		if current_npc.has_method("enable_interaction"):
			current_npc.enable_interaction()

	current_npc = null
	visible = false
	closed.emit()

	await get_tree().process_frame

	var player: Node = get_tree().get_first_node_in_group("player")

	if player != null and player.has_method("refresh_nearby_interactables"):
		player.refresh_nearby_interactables()


func _refresh_buttons() -> void:
	if current_npc == null:
		return

	var is_playing := false
	var is_following := false

	if current_npc.has_method("is_actively_playing_jam"):
		is_playing = current_npc.is_actively_playing_jam()

	if current_npc.has_method("is_following_player"):
		is_following = current_npc.is_following_player()

	play_button.text = "Stop Playing" if is_playing else "Play Song"
	follow_button.text = "Stop Following" if is_following else "Follow Me"

	_update_button_visuals()


func _move_selection(direction: int) -> void:
	if menu_buttons.is_empty():
		return

	selected_button_index += direction

	if selected_button_index < 0:
		selected_button_index = menu_buttons.size() - 1
	elif selected_button_index >= menu_buttons.size():
		selected_button_index = 0

	_update_button_visuals()


func _select_button(index: int) -> void:
	if menu_buttons.is_empty():
		return

	selected_button_index = clampi(index, 0, menu_buttons.size() - 1)
	_update_button_visuals()


func _activate_selected_option() -> void:
	match selected_button_index:
		0:
			_play_action()
		1:
			_follow_action()
		2:
			close()


func _play_action() -> void:
	if current_npc == null:
		return

	var npc_to_use: Node = current_npc

	if npc_to_use.has_method("enable_interaction"):
		npc_to_use.enable_interaction()

	if npc_to_use.has_method("toggle_play_song_request"):
		npc_to_use.toggle_play_song_request()

	close()


func _follow_action() -> void:
	if current_npc == null:
		return

	var npc_to_use: Node = current_npc

	if npc_to_use.has_method("enable_interaction"):
		npc_to_use.enable_interaction()

	if npc_to_use.has_method("toggle_follow_player"):
		npc_to_use.toggle_follow_player()

	close()


func _on_play_button_clicked() -> void:
	_play_action()


func _on_follow_button_clicked() -> void:
	_follow_action()


func _on_close_button_clicked() -> void:
	close()


func _update_button_visuals() -> void:
	for i in menu_buttons.size():
		var button: Button = menu_buttons[i]

		if button == null:
			continue

		button.button_pressed = false

		if i == selected_button_index:
			button.modulate = Color(3.365, 3.365, 3.365, 1.0)
		else:
			button.modulate = Color(1.0, 1.0, 1.0, 1.0)


func _set_buttons_focus_mode(can_focus: bool) -> void:
	var focus_mode := Control.FOCUS_ALL if can_focus else Control.FOCUS_NONE

	for button in menu_buttons:
		if button != null:
			button.focus_mode = focus_mode


func _exit_tree() -> void:
	if current_npc != null:
		if current_npc.has_method("enable_interaction"):
			current_npc.enable_interaction()


func _get_single_menu_nav_direction() -> int:
	var down_strength: float = Input.get_action_strength("move_down") + Input.get_action_strength("ui_down")
	var up_strength: float = Input.get_action_strength("move_up") + Input.get_action_strength("ui_up")
	var right_strength: float = Input.get_action_strength("move_right") + Input.get_action_strength("ui_right")
	var left_strength: float = Input.get_action_strength("move_left") + Input.get_action_strength("ui_left")

	var vertical: float = down_strength - up_strength
	var horizontal: float = right_strength - left_strength

	var strongest_value := vertical

	if abs(horizontal) > abs(vertical):
		strongest_value = horizontal

	# Neutral zone: unlock navigation only after the player releases the stick/key.
	if abs(strongest_value) < menu_nav_deadzone:
		menu_nav_locked = false
		return 0

	# Direction is still held, so do not move again.
	if menu_nav_locked:
		return 0

	menu_nav_locked = true

	# Use your corrected direction mapping.
	if strongest_value > 0.0:
		return 1

	return -1
