extends Area2D

@export var item_id := ""

@onready var label: Label = $Label


func _ready() -> void:

	add_to_group("collectible")
	add_to_group("interactable")

	if label != null:
		label.text = item_id


func restore_state() -> void:

	print(
		"CHECKING:",
		item_id,
		SaveManager.character_data.collected_items
	)

	if SaveManager.is_item_collected(item_id):

		print(
			"REMOVING:",
			item_id
		)

		queue_free()


func interact() -> void:

	var player := get_tree().get_first_node_in_group(
		"player"
	)

	if player == null:
		return

	if player.has_method("collect_item"):
		player.collect_item(item_id)

	queue_free()
