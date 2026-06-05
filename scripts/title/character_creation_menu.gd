extends CanvasLayer

@onready var name_input: LineEdit = $PanelContainer/VBoxContainer/CharacterNameInput

func _ready() -> void:

	visible = false


func open_menu() -> void:

	visible = true

	name_input.clear()

	await get_tree().process_frame

	name_input.grab_focus()


func close_menu() -> void:

	visible = false


func _on_cancel_button_pressed() -> void:

	close_menu()


func _on_create_button_pressed() -> void:

	var character_name := name_input.text.strip_edges()

	if character_name.is_empty():
		return

	var character_id := SaveManager.create_character(character_name)

	SaveManager.current_character_id = character_id

	var title_screen := get_parent()

	if title_screen.has_method("refresh_character_list"): title_screen.refresh_character_list()

	close_menu()
