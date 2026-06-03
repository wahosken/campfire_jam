extends Control

@onready var character_creation_menu: CanvasLayer = $CharacterCreationMenu
@onready var world_creation_menu: CanvasLayer = $WorldCreationMenu
@onready var load_game_menu = $LoadGameMenu

@onready var character_selector: OptionButton = $CenterContainer/VBoxContainer/CharacterSelector

func _ready() -> void:

	refresh_character_list()


func _on_continue_button_pressed() -> void:

	if SaveManager.continue_game():

		get_tree().change_scene_to_file(
			"res://scenes/world.tscn"
		)

	else:

		print(
			"NO GAME TO CONTINUE"
		)


func _on_new_world_button_pressed() -> void:

	if SaveManager.current_character_id.is_empty():

		print(
			"SELECT A CHARACTER FIRST"
		)

		return

	world_creation_menu.open_menu()


func _on_load_game_button_pressed():

	load_game_menu.open_menu()


func _on_settings_button_pressed() -> void:

	print("OPEN SETTINGS")


func _on_quit_button_pressed() -> void:

	get_tree().quit()


func refresh_character_list() -> void:

	character_selector.clear()

	var dir := DirAccess.open(
		SaveManager.CHARACTER_FOLDER
	)

	if dir == null:
		return

	dir.list_dir_begin()

	var file_name := dir.get_next()

	while file_name != "":

		if file_name.ends_with(".json"):

			var path := \
				SaveManager.CHARACTER_FOLDER + \
				file_name

			var file := FileAccess.open(
				path,
				FileAccess.READ
			)

			if file != null:

				var json_text := \
					file.get_as_text()

				file.close()

				var json := JSON.new()

				if json.parse(json_text) == OK:

					var data = json.data

					var character_name: String = \
						data.get(
							"character_name",
							"Unknown"
						)

					var character_id: String = \
						data.get(
							"character_id",
							""
						)

					character_selector.add_item(
						character_name
					)

					var index := \
						character_selector.item_count - 1

					character_selector.set_item_metadata(
						index,
						character_id
					)

		file_name = dir.get_next()

	dir.list_dir_end()

	# Restore current selection if possible

	for i in range(
		character_selector.item_count
	):

		var id := str(
			character_selector.get_item_metadata(
				i
			)
		)

		if id == SaveManager.current_character_id:

			character_selector.select(i)

			return

	# Otherwise select first character

	if character_selector.item_count > 0:

		character_selector.select(0)

		SaveManager.current_character_id = str(
			character_selector.get_item_metadata(
				0
			)
		)

		print(
			"SELECTED CHARACTER:",
			SaveManager.current_character_id
		)

	character_selector.add_item(
		"Create Character..."
	)

	var create_index := \
		character_selector.item_count - 1

	character_selector.set_item_metadata(
		create_index,
		"create_character"
	)

func get_selected_character_id() -> String:

	var selected := \
		character_selector.get_selected()

	if selected < 0:
		return ""

	return str(
		character_selector.get_item_metadata(
			selected
		)
	)


func _on_character_selector_item_selected(
	index: int
) -> void:

	var value := str(
		character_selector.get_item_metadata(
			index
		)
	)

	if value == "create_character":

		character_creation_menu.open_menu()

		return

	SaveManager.current_character_id = value

	print(
		"SELECTED CHARACTER:",
		SaveManager.current_character_id
	)
