extends Node2D

@export var instrument_id: String = "guitar"
@export var display_name: String = "Musician"

var music_system: Node = null
var visually_playing := false


func _ready() -> void:
	add_to_group("npc_musician")
	music_system = get_tree().get_first_node_in_group("music_system")
	set_visual_playing(false)


func get_instrument_id() -> String:
	return instrument_id


func interact() -> void:
	if music_system == null:
		music_system = get_tree().get_first_node_in_group("music_system")

	if music_system == null:
		push_warning(display_name + " could not find music_system.")
		return

	if music_system.has_method("npc_toggle_instrument"):
		music_system.npc_toggle_instrument(instrument_id)


func set_visual_playing(value: bool) -> void:
	if visually_playing == value:
		return

	visually_playing = value

	if visually_playing:
		modulate = Color(1.25, 1.1, 0.75, 1.0)
	else:
		modulate = Color(1, 1, 1, 1)

	print(display_name, " visual playing: ", visually_playing)
