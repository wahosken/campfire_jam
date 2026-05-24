extends Node2D

@export var jam_id := "campfire_jam"
@export var display_name := "Campfire Jam"
@export var song_id := "song_01"

# For now this is useful for testing.
# Later, schedules/story events can call activate_jam() and deactivate_jam().
@export var auto_start_on_ready := true

@export var leave_radius_padding := 50.0

@onready var jam_area: Area2D = $JamArea
@onready var jam_collision_shape: CollisionShape2D = $JamArea/CollisionShape2D

@onready var label: Label = $Label
@onready var jam_context: Node = $JamContext

var registered_npcs: Array[Node] = []
var jam_is_active := false


func _ready() -> void:
	add_to_group("jam_spot")
	add_to_group("interactable")

	_sync_jam_context_song()
	_update_label()


func start_if_auto_enabled() -> void:
	if auto_start_on_ready:
		start_jam()


func interact() -> void:
	# Placeholder/debug behavior.
	# Later, jam spots probably should not be directly toggled by player input.
	# Schedules, quests, dialogue, or story events should call activate_jam()
	# and deactivate_jam() instead.
	toggle_jam()


func register_npc(npc: Node) -> void:
	if npc == null:
		return

	if not registered_npcs.has(npc):
		registered_npcs.append(npc)

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(self)

	if npc.has_method("set_current_jam_context"):
		npc.set_current_jam_context(jam_context)

	if jam_context != null and jam_context.has_method("add_member"):
		jam_context.add_member(npc)

	refresh_npc_activity(npc)
	_update_label()


func unregister_npc(npc: Node) -> void:
	if npc == null:
		return

	if registered_npcs.has(npc):
		registered_npcs.erase(npc)

	if npc.has_method("set_actual_playing"):
		npc.set_actual_playing(false)

	if jam_context != null and jam_context.has_method("remove_member"):
		jam_context.remove_member(npc)

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(null)

	if npc.has_method("set_current_jam_context"):
		npc.set_current_jam_context(null)

	_update_label()


func start_jam() -> void:
	if jam_is_active:
		return

	jam_is_active = true

	_sync_jam_context_song()
	refresh_all_npc_activity()
	_update_label()


func stop_jam() -> void:
	if not jam_is_active:
		return

	jam_is_active = false

	refresh_all_npc_activity()
	_update_label()


func toggle_jam() -> void:
	if jam_is_active:
		stop_jam()
	else:
		start_jam()


func activate_jam() -> void:
	start_jam()


func deactivate_jam() -> void:
	stop_jam()


func set_jam_active(should_be_active: bool) -> void:
	if should_be_active:
		start_jam()
	else:
		stop_jam()


func refresh_all_npc_activity() -> void:
	for npc in registered_npcs:
		refresh_npc_activity(npc)


func refresh_npc_activity(npc: Node) -> void:
	if npc == null:
		return

	if not is_instance_valid(npc):
		return

	if not npc.has_method("is_npc_enabled"):
		return

	var should_play: bool = jam_is_active and npc.is_npc_enabled()

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(self)

	if npc.has_method("set_current_jam_context"):
		npc.set_current_jam_context(jam_context)

	if jam_context != null and jam_context.has_method("add_member"):
		jam_context.add_member(npc)

	if should_play:
		# JamSpot NPCs are fully available.
		# JamContext decides who is rhythm/melody.
		if jam_context != null:
			if jam_context.has_method("set_member_requested_parts"):
				jam_context.set_member_requested_parts(npc, true, true)
			elif jam_context.has_method("set_member_requested_part"):
				jam_context.set_member_requested_part(npc, "both")

		if "wants_to_play" in npc:
			npc.wants_to_play = true

		if jam_context != null and jam_context.has_method("set_member_active"):
			jam_context.set_member_active(npc, true)
	else:
		if jam_context != null and jam_context.has_method("set_member_active"):
			jam_context.set_member_active(npc, false)

		if "wants_to_play" in npc:
			npc.wants_to_play = false

		if npc.has_method("set_current_part"):
			npc.set_current_part("silent")


func is_jam_active() -> bool:
	return jam_is_active


func is_active() -> bool:
	return is_jam_active()


func get_display_name() -> String:
	return display_name


func get_jam_id() -> String:
	return jam_id


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


func get_join_radius() -> float:
	if jam_collision_shape == null:
		return 100.0

	if jam_collision_shape.shape == null:
		return 100.0

	if jam_collision_shape.shape is CircleShape2D:
		var circle_shape: CircleShape2D = jam_collision_shape.shape as CircleShape2D
		return circle_shape.radius * jam_collision_shape.global_scale.x

	if jam_collision_shape.shape is RectangleShape2D:
		var rectangle_shape: RectangleShape2D = jam_collision_shape.shape as RectangleShape2D
		var scaled_size: Vector2 = rectangle_shape.size * jam_collision_shape.global_scale
		return maxf(scaled_size.x, scaled_size.y) * 0.5

	return 100.0


func get_leave_radius() -> float:
	return get_join_radius() + leave_radius_padding


func is_position_inside_join_radius(world_position: Vector2) -> bool:
	return global_position.distance_to(world_position) <= get_join_radius()


func is_position_inside_leave_radius(world_position: Vector2) -> bool:
	return global_position.distance_to(world_position) <= get_leave_radius()


func can_player_join() -> bool:
	return jam_is_active and jam_context != null


func _sync_jam_context_song() -> void:
	if jam_context == null:
		return

	if "song_id" in jam_context:
		jam_context.song_id = song_id


func _update_label() -> void:
	if label == null:
		return

	var state_text := "On" if jam_is_active else "Off"

	label.text = "%s\nSong: %s\n%s" % [
		display_name,
		song_id,
		state_text
	]
