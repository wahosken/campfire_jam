extends Node2D

@export var jam_id := "campfire_jam"
@export var display_name := "Campfire Jam"
@export var song_id := "song_01"

@export var auto_start_on_ready := true
@export var join_radius := 1000.0
@export var leave_radius := 1100.0

@onready var label: Label = $Label

var registered_npcs: Array[Node] = []
var music_system: Node = null
var jam_is_active := false


func _ready() -> void:
	add_to_group("jam_spot")

	music_system = get_tree().get_first_node_in_group("music_system")

	_update_label()

	if auto_start_on_ready:
		call_deferred("start_jam")


func register_npc(npc: Node) -> void:
	if npc == null:
		return

	if not registered_npcs.has(npc):
		registered_npcs.append(npc)

	if jam_is_active:
		_start_npc_if_available(npc)


func unregister_npc(npc: Node) -> void:
	if registered_npcs.has(npc):
		registered_npcs.erase(npc)

	if npc != null and npc.has_method("stop_music"):
		npc.stop_music()


func start_jam() -> void:
	jam_is_active = true

	if music_system != null and music_system.has_method("set_current_song_id"):
		music_system.set_current_song_id(song_id)

	for npc in registered_npcs:
		_start_npc_if_available(npc)

	_update_label()


func stop_jam() -> void:
	jam_is_active = false

	for npc in registered_npcs:
		if npc != null and npc.has_method("stop_music"):
			npc.stop_music()

	_update_label()


func toggle_jam() -> void:
	if jam_is_active:
		stop_jam()
	else:
		start_jam()


func is_position_inside_join_radius(world_position: Vector2) -> bool:
	return global_position.distance_to(world_position) <= join_radius


func is_position_inside_leave_radius(world_position: Vector2) -> bool:
	return global_position.distance_to(world_position) <= leave_radius


func get_song_id() -> String:
	return song_id


func _start_npc_if_available(npc: Node) -> void:
	if npc == null:
		return

	if not is_instance_valid(npc):
		return

	if npc.has_method("start_music"):
		npc.start_music()


func _update_label() -> void:
	if label == null:
		return

	var state_text := "On" if jam_is_active else "Off"

	label.text = "%s\nSong: %s\n%s" % [
		display_name,
		song_id,
		state_text
	]
