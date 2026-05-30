extends CanvasLayer

signal closed

@onready var name_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/NameLabel
@onready var dialogue_label: Label = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/DialogueLabel
@onready var talk_button: Button = $CenterContainer/PanelContainer/MarginContainer/VBoxContainer/TalkButton
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


# ------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------

func _ready() -> void:
	add_to_group("npc_dialogue_prompt")

	visible = false

	menu_buttons = [
		talk_button,
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
	talk_button.pressed.connect(_on_talk_button_clicked)

	_set_buttons_focus_mode(false)


func _process(delta: float) -> void:
	if DialogueManager.is_dialogue_active():
		return

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


func _exit_tree() -> void:
	if current_npc != null:
		if current_npc.has_method("enable_interaction"):
			current_npc.enable_interaction()


# ------------------------------------------------------------
# Open / close
# ------------------------------------------------------------

func open_for_npc(npc: Node) -> void:
	if DialogueManager.is_dialogue_active():
		return

	current_npc = npc

	if current_npc == null:
		return

	if current_npc.has_method("disable_interaction_temporarily"):
		current_npc.disable_interaction_temporarily()

	var player: Node = get_tree().get_first_node_in_group("player")

	if player != null and player.has_method("clear_nearby_interactables"):
		player.clear_nearby_interactables()

	visible = true

	name_label.text = _get_npc_display_name(current_npc)

	if current_npc.has_method("get_dialogue_text"):
		dialogue_label.text = current_npc.get_dialogue_text()
	else:
		dialogue_label.text = ""

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


# ------------------------------------------------------------
# Button text
# ------------------------------------------------------------

func _refresh_buttons() -> void:
	if current_npc == null:
		return

	var recruited := false

	if "progression_state" in current_npc:
		recruited = (
			current_npc.progression_state
			== current_npc.NPCProgressionState.RECRUITED
		)

	play_button.text = _get_play_button_text(current_npc)
	follow_button.text = _get_follow_button_text(current_npc)

	talk_button.visible = true

	play_button.visible = recruited
	follow_button.visible = recruited

	close_button.visible = true

	_select_button(0)

	_update_button_visuals()


func _get_play_button_text(npc: Node) -> String:
	if npc == null:
		return "Start Playing"

	# Manual freeform means the player intentionally told this NPC to play.
	if npc.has_method("is_manual_freeform"):
		if npc.is_manual_freeform():
			return "Stop Playing"

	# Auto freeform means they are already temporarily participating.
	# Pressing the button commits them to keep playing.
	if npc.has_method("is_auto_freeform"):
		if npc.is_auto_freeform():
			return "Keep Playing"

	# JamSpot controlled NPCs use enabled/sitting-out state.
	if npc.has_method("is_controlled_by_active_jam_spot"):
		if npc.is_controlled_by_active_jam_spot():
			if npc.has_method("is_npc_enabled"):
				if npc.is_npc_enabled():
					return "Stop Playing"

			return "Start Playing"

	return "Start Playing"


func _get_follow_button_text(npc: Node) -> String:
	if npc == null:
		return "Follow Me"

	if npc.has_method("is_following_player"):
		if npc.is_following_player():
			return "Stop Following"

	return "Follow Me"


func _get_npc_display_name(npc: Node) -> String:
	if npc == null:
		return "Musician"

	if npc.has_method("get_display_name"):
		return npc.get_display_name()

	if "display_name" in npc:
		return str(npc.display_name)

	if npc.name != "":
		return npc.name

	return "Musician"


func _get_visible_buttons() -> Array[Button]:

	var visible_buttons: Array[Button] = []

	for button in menu_buttons:
		if button.visible:
			visible_buttons.append(button)

	return visible_buttons


# ------------------------------------------------------------
# Actions
# ------------------------------------------------------------

func _activate_selected_option() -> void:

	var button := menu_buttons[selected_button_index]

	if button == talk_button:
		_talk_action()
		return

	if button == play_button:
		_play_action()
		return

	if button == follow_button:
		_follow_action()
		return

	if button == close_button:
		close()
		return


func _talk_action() -> void:

	if current_npc == null:
		return

	var npc := current_npc

	if npc.has_method("is_manual_freeform"):
		if npc.is_manual_freeform():

			if npc.has_method("toggle_play_song_request"):
				npc.toggle_play_song_request()

	close()

	await get_tree().process_frame

	if npc.get_current_dialogue() != null:
		DialogueManager.start_dialogue(
			npc.get_current_dialogue(),
			npc
		)


func _play_action() -> void:

	if current_npc == null:
		return

	var npc_to_use: Node = current_npc

	if npc_to_use.has_method("is_following_player"):
		if npc_to_use.is_following_player():

			if npc_to_use.has_method("toggle_follow_player"):
				npc_to_use.toggle_follow_player()

	if npc_to_use.has_method("enable_interaction"):
		npc_to_use.enable_interaction()

	if npc_to_use.has_method("toggle_play_song_request"):
		npc_to_use.toggle_play_song_request()

	close()


func _follow_action() -> void:
	if current_npc == null:
		return

	var npc_to_use: Node = current_npc

	# If manually playing, stop that first.
	if npc_to_use.has_method("is_manual_freeform"):
		if npc_to_use.is_manual_freeform():

			if npc_to_use.has_method("toggle_play_song_request"):
				npc_to_use.toggle_play_song_request()

	if npc_to_use.has_method("enable_interaction"):
		npc_to_use.enable_interaction()

	if npc_to_use.has_method("toggle_follow_player"):
		npc_to_use.toggle_follow_player()

	close()


func _on_talk_button_clicked() -> void:
	_talk_action()


func _on_play_button_clicked() -> void:
	_play_action()


func _on_follow_button_clicked() -> void:
	_follow_action()


func _on_close_button_clicked() -> void:
	close()


# ------------------------------------------------------------
# Menu selection / visuals
# ------------------------------------------------------------

func _move_selection(direction: int) -> void:

	var visible_buttons := _get_visible_buttons()

	if visible_buttons.is_empty():
		return

	var current_visible_index := 0

	for i in visible_buttons.size():
		if visible_buttons[i] == menu_buttons[selected_button_index]:
			current_visible_index = i
			break

	current_visible_index += direction

	if current_visible_index < 0:
		current_visible_index = visible_buttons.size() - 1
	elif current_visible_index >= visible_buttons.size():
		current_visible_index = 0

	var selected_button: Button = visible_buttons[current_visible_index]

	selected_button_index = menu_buttons.find(selected_button)

	_update_button_visuals()


func _select_button(index: int) -> void:

	var visible_buttons := _get_visible_buttons()

	if visible_buttons.is_empty():
		return

	index = clampi(index, 0, visible_buttons.size() - 1)

	var button: Button = visible_buttons[index]

	selected_button_index = menu_buttons.find(button)

	_update_button_visuals()


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


# ------------------------------------------------------------
# Menu navigation input
# ------------------------------------------------------------

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

	if abs(strongest_value) < menu_nav_deadzone:
		menu_nav_locked = false
		return 0

	if menu_nav_locked:
		return 0

	menu_nav_locked = true

	if strongest_value > 0.0:
		return 1

	return -1
