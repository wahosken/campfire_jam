extends Node2D

@export var jam_id := "campfire_jam"
@export var display_name := "Campfire Jam"
@export var song_id := "song_01"

@export var auto_start_on_ready := true
@export var join_radius := 1000.0
@export var leave_radius := 1100.0

@onready var label: Label = $Label
@onready var jam_context: Node = $JamContext

var registered_npcs: Array[Node] = []
var jam_is_active := false


func _ready() -> void:
	add_to_group("jam_spot")
	add_to_group("interactable")

	_update_label()

	if auto_start_on_ready:
		call_deferred("start_jam")


func interact() -> void:
	toggle_jam()


func register_npc(npc: Node) -> void:
	if npc == null:
		return

	if not registered_npcs.has(npc):
		registered_npcs.append(npc)

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(self)

	if jam_context != null and jam_context.has_method("add_member"):
		jam_context.add_member(npc)

	if jam_is_active:
		_start_npc_if_available(npc)

	_update_label()


func unregister_npc(npc: Node) -> void:
	if npc == null:
		return

	if registered_npcs.has(npc):
		registered_npcs.erase(npc)

	if npc.has_method("stop_music"):
		npc.stop_music()

	if jam_context != null and jam_context.has_method("remove_member"):
		jam_context.remove_member(npc)

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(null)

	_update_label()


func start_jam() -> void:
	if jam_is_active:
		return

	jam_is_active = true

	if jam_context != null:
		if "song_id" in jam_context:
			jam_context.song_id = song_id

	for npc in registered_npcs:
		_start_npc_if_available(npc)

	_update_label()


func stop_jam() -> void:
	if not jam_is_active:
		return

	jam_is_active = false

	if jam_context != null and jam_context.has_method("stop_all_members"):
		jam_context.stop_all_members()
	else:
		for npc in registered_npcs:
			if npc != null and npc.has_method("stop_music"):
				npc.stop_music()

	_update_label()


func toggle_jam() -> void:
	if jam_is_active:
		stop_jam()
	else:
		start_jam()


func is_jam_active() -> bool:
	return jam_is_active


func get_display_name() -> String:
	return display_name


func get_song_id() -> String:
	return song_id


func get_jam_context() -> Node:
	return jam_context


func get_active_instruments_text() -> String:
	if jam_context != null and jam_context.has_method("get_active_instruments_text"):
		return jam_context.get_active_instruments_text()

	return "None"


func get_featured_instrument_text() -> String:
	if jam_context != null and jam_context.has_method("get_featured_instrument_text"):
		return jam_context.get_featured_instrument_text()

	return "None"


func is_position_inside_join_radius(world_position: Vector2) -> bool:
	return global_position.distance_to(world_position) <= join_radius


func is_position_inside_leave_radius(world_position: Vector2) -> bool:
	return global_position.distance_to(world_position) <= leave_radius


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
