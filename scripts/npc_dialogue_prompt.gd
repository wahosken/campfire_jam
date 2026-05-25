extends CanvasLayer

signal closed

@onready var name_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameLabel
@onready var play_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/PlayButton
@onready var follow_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/FollowButton
@onready var close_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/CloseButton

var current_npc: Node = null
var menu_buttons: Array[Button] = []
var selected_button_index := 0
var input_cooldown := 0.0


func _ready() -> void:
	add_to_group("npc_dialogue_prompt")

	visible = false

	menu_buttons = [
		play_button,
		follow_button,
		close_button
	]

	play_button.pressed.connect(_on_play_button_pressed)
	follow_button.pressed.connect(_on_follow_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)


func _process(delta: float) -> void:
	if not visible:
		return

	if input_cooldown > 0.0:
		input_cooldown -= delta
		return

	if Input.is_action_just_pressed("move_down") \
		or Input.is_action_just_pressed("ui_down") \
		or Input.is_action_just_pressed("move_right") \
		or Input.is_action_just_pressed("ui_right"):
		_move_selection(1)
		input_cooldown = 0.12
		return

	if Input.is_action_just_pressed("move_up") \
		or Input.is_action_just_pressed("ui_up") \
		or Input.is_action_just_pressed("move_left") \
		or Input.is_action_just_pressed("ui_left"):
		_move_selection(-1)
		input_cooldown = 0.12
		return

	if Input.is_action_just_pressed("interact") \
		or Input.is_action_just_pressed("ui_accept"):
		_press_selected_button()
		input_cooldown = 0.12
		return


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
	input_cooldown = 0.2


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


func _move_selection(direction: int) -> void:
	if menu_buttons.is_empty():
		return

	selected_button_index += direction

	if selected_button_index < 0:
		selected_button_index = menu_buttons.size() - 1
	elif selected_button_index >= menu_buttons.size():
		selected_button_index = 0

	_select_button(selected_button_index)


func _select_button(index: int) -> void:
	if menu_buttons.is_empty():
		return

	selected_button_index = clampi(index, 0, menu_buttons.size() - 1)

	var selected_button: Button = menu_buttons[selected_button_index]

	if selected_button != null:
		selected_button.grab_focus()


func _press_selected_button() -> void:
	if menu_buttons.is_empty():
		return

	var selected_button: Button = menu_buttons[selected_button_index]

	if selected_button == null:
		return

	if selected_button == play_button:
		_on_play_button_pressed()
	elif selected_button == follow_button:
		_on_follow_button_pressed()
	elif selected_button == close_button:
		_on_close_button_pressed()


func _on_play_button_pressed() -> void:
	if current_npc == null:
		return

	var npc_to_use: Node = current_npc

	if npc_to_use.has_method("enable_interaction"):
		npc_to_use.enable_interaction()

	if npc_to_use.has_method("toggle_play_song_request"):
		npc_to_use.toggle_play_song_request()

	close()


func _on_follow_button_pressed() -> void:
	if current_npc == null:
		return

	var npc_to_use: Node = current_npc

	if npc_to_use.has_method("enable_interaction"):
		npc_to_use.enable_interaction()

	if npc_to_use.has_method("toggle_follow_player"):
		npc_to_use.toggle_follow_player()

	close()


func _on_close_button_pressed() -> void:
	close()


func _exit_tree() -> void:
	if current_npc != null:
		if current_npc.has_method("enable_interaction"):
			current_npc.enable_interaction()
