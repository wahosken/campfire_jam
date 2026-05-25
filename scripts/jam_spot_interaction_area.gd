extends Area2D

@onready var jam_spot: Node = get_parent()


func _ready() -> void:
	add_to_group("interactable")


func interact() -> void:
	if jam_spot != null and jam_spot.has_method("interact"):
		jam_spot.interact()


func get_display_name() -> String:
	if jam_spot != null and jam_spot.has_method("get_display_name"):
		return jam_spot.get_display_name()

	return "Jam Spot"
