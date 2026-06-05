extends CanvasLayer

@onready var world_list: ItemList = $PanelContainer/VBoxContainer/WorldList


func _ready() -> void:

	visible = false


func open_menu() -> void:

	visible = true

	refresh_worlds()


func close_menu() -> void:

	visible = false


func refresh_worlds() -> void:

	world_list.clear()

	var dir := DirAccess.open(SaveManager.WORLD_FOLDER)

	if dir == null:
		return

	dir.list_dir_begin()

	var file_name := dir.get_next()

	while file_name != "":

		if file_name.ends_with(".json"):

			var path := SaveManager.WORLD_FOLDER + file_name

			var file := FileAccess.open(path,FileAccess.READ)

			if file != null:

				var json_text := file.get_as_text()

				file.close()

				var json := JSON.new()

				if json.parse(json_text) == OK:

					var data = json.data

					var world_name := str(data.get("world_name", "Unknown"))

					var world_id := str(data.get("world_id", ""))

					world_list.add_item(world_name)

					var index := world_list.item_count - 1

					world_list.set_item_metadata(index, world_id)

		file_name = dir.get_next()

	dir.list_dir_end()


func _on_back_button_pressed():

	close_menu()


func _on_load_button_pressed() -> void:

	var selected := world_list.get_selected_items()

	if selected.is_empty():
		return

	var index := selected[0]

	var world_id := str(world_list.get_item_metadata(index))

	if SaveManager.start_game(world_id, SaveManager.current_character_id):

		get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _on_delete_button_pressed() -> void:
	print("DELETE WORLD")
