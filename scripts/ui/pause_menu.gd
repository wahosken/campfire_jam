extends CanvasLayer

@export var touch_overlay_path: NodePath

@onready var panel: Control = $PanelContainer
@onready var resume_button: Button = $PanelContainer/VBoxContainer/BodyTabContainer/SystemTab/ResumeButton
@onready var restart_scene_button: Button = $PanelContainer/VBoxContainer/BodyTabContainer/SystemTab/RestartSceneButton
@onready var mute_button: Button = $PanelContainer/VBoxContainer/BodyTabContainer/SystemTab/MuteButton
@onready var touch_arrows_button: Button = $PanelContainer/VBoxContainer/BodyTabContainer/SystemTab/TouchArrowsButton
@onready var touch_joystick_button: Button = $PanelContainer/VBoxContainer/BodyTabContainer/SystemTab/TouchJoystickButton
@onready var show_jam_radius_button: CheckButton = $PanelContainer/VBoxContainer/BodyTabContainer/SystemTab/ShowJamRadiusButton
@onready var show_fps_button: CheckButton = $PanelContainer/VBoxContainer/BodyTabContainer/SystemTab/ShowFPSButton
@onready var close_button: Button = $PanelContainer/VBoxContainer/BodyTabContainer/SystemTab/CloseButton

@onready var debug_overlay: Label = $DebugOverlay

@onready var body_tab_container: TabContainer = $PanelContainer/VBoxContainer/BodyTabContainer
@onready var songbook_text: RichTextLabel = $PanelContainer/VBoxContainer/BodyTabContainer/SongbookTab/SongbookText
@onready var journal_text: RichTextLabel = $PanelContainer/VBoxContainer/BodyTabContainer/JournalTab/JournalText
@onready var community_text: RichTextLabel = $PanelContainer/VBoxContainer/BodyTabContainer/CommunityTab/CommunityText

@onready var songbook_button: Button = $PanelContainer/VBoxContainer/Tabs/SongbookButton
@onready var journal_button: Button = $PanelContainer/VBoxContainer/Tabs/JournalButton
@onready var community_button: Button = $PanelContainer/VBoxContainer/Tabs/CommunityButton
@onready var system_button: Button = $PanelContainer/VBoxContainer/Tabs/SystemButton

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


func _on_songbook_button_pressed() -> void:
	open_tab(0)

func _on_journal_button_pressed() -> void:
	open_tab(1)

func _on_community_button_pressed() -> void:
	open_tab(2)

func _on_system_button_pressed() -> void:
	open_tab(3)


func _on_save_button_pressed() -> void:

	SaveManager.save_game()

	print("MANUAL SAVE")


func _on_return_to_title_button_pressed() -> void:

	SaveManager.save_game()

	SaveManager.save_profile()

	get_tree().paused = false

	get_tree().change_scene_to_file(
		"res://scenes/title_screen.tscn"
	)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if not _can_pause_now():
			return

		toggle_pause()
		get_viewport().set_input_as_handled()


func _can_pause_now() -> bool:

	if DialogueManager.is_dialogue_active():
		return false

	return true


func open_tab(tab_index: int) -> void:

	body_tab_container.current_tab = tab_index

	match tab_index:

		0:
			songbook_button.grab_focus()

		1:
			journal_button.grab_focus()

		2:
			community_button.grab_focus()

		3:
			resume_button.grab_focus()


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


func toggle_pause() -> void:
	if is_paused:
		resume_game()
	else:
		pause_game()


func pause_game() -> void:

	is_paused = true

	get_tree().paused = true

	refresh_songbook()
	refresh_journal()
	refresh_community()

	panel.visible = true

	open_tab(3)

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


func refresh_songbook() -> void:

	var player := get_tree().get_first_node_in_group(
		"player"
	)

	if player == null:
		return

	var text := ""

	text += "SONGS\n"
	text += "-----\n"

	for song in player.unlocked_songs:
		text += "♪ %s\n" % song

	text += "\n"

	text += "INSTRUMENTS\n"
	text += "-----------\n"

	for instrument in player.unlocked_instruments:
		text += "%s\n" % instrument.capitalize()

	text += "\n"

	text += "ITEMS\n"
	text += "-----\n"

	for item in player.collected_items:
		text += "%s\n" % item

	songbook_text.text = text


func refresh_journal() -> void:

	if QuestManager == null:
		return

	var text := ""

	text += "JOURNAL\n"
	text += "=======\n\n"

	for quest in QuestManager.quests:

		if quest == null:
			continue

		if quest.journal_text.is_empty():
			continue

		text += quest.journal_text
		text += "\n\n"

	journal_text.text = text


func refresh_community() -> void:

	var player := get_tree().get_first_node_in_group(
		"player"
	)

	if player == null:
		return

	var recruited_count := 0

	for npc in get_tree().get_nodes_in_group(
		"npc_musician"
	):

		if not is_instance_valid(npc):
			continue

		if npc.is_recruited():
			recruited_count += 1

	var text := ""

	text += "COMMUNITY\n"
	text += "=========\n\n"

	text += "Musicians Recruited: "
	text += str(recruited_count)
	text += " / 4\n"

	text += "Songs Learned: "
	text += str(player.unlocked_songs.size())
	text += " / 2\n"

	text += "Instruments Collected: "
	text += str(player.unlocked_instruments.size())
	text += " / 4\n"

	text += "Village Projects: "
	text += str(QuestManager.completed_quests.size())
	text += " / 4\n"

	text += "\n"

	if recruited_count >= 4:
		text += "Festival Ready: YES"
	else:
		text += "Festival Ready: NO"

	community_text.text = text
