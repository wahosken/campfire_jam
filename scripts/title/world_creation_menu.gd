extends CanvasLayer

@onready var name_input: LineEdit = \
	$PanelContainer/VBoxContainer/WorldNameInput


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

	var world_name := name_input.text.strip_edges()

	if world_name.is_empty():
		return

	var world_id: String = SaveManager.create_world(world_name)

	SaveManager.current_world_id = world_id

	var title_screen := get_parent()

	if title_screen.has_method("load_world_list"): title_screen.load_world_list()

	close_menu()
