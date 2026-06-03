extends Node2D

func interact() -> void:

	var pause_menu := get_tree().get_first_node_in_group(
		"pause_menu"
	)

	if pause_menu == null:
		return

	pause_menu.pause_game()

	pause_menu.open_tab(2)
