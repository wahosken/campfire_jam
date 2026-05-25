extends Node2D

@export var jam_id := "campfire_jam"
@export var display_name := "Campfire Jam"
@export var song_id := "song_01"

@export var auto_start_on_ready := true
@export var leave_radius_padding := 50.0

@onready var label: Label = $Label
@onready var jam_context: Node = $JamContext
@onready var jam_area: Area2D = $JamArea
@onready var jam_collision_shape: CollisionShape2D = $JamArea/CollisionShape2D

var registered_npcs: Array[Node] = []
var jam_is_active := false


func _ready() -> void:
	add_to_group("jam_spot")

	if jam_area != null:
		if not jam_area.area_entered.is_connected(_on_jam_area_area_entered):
			jam_area.area_entered.connect(_on_jam_area_area_entered)

		if not jam_area.area_exited.is_connected(_on_jam_area_area_exited):
			jam_area.area_exited.connect(_on_jam_area_area_exited)

		if not jam_area.body_entered.is_connected(_on_jam_area_body_entered):
			jam_area.body_entered.connect(_on_jam_area_body_entered)

		if not jam_area.body_exited.is_connected(_on_jam_area_body_exited):
			jam_area.body_exited.connect(_on_jam_area_body_exited)

	_sync_jam_context_song()
	_update_label()

	# For browser builds, you may still prefer StartGate calling start_if_auto_enabled()
	# instead of starting directly in _ready().
	# if auto_start_on_ready:
	#	call_deferred("start_jam")


func start_if_auto_enabled() -> void:
	if auto_start_on_ready:
		start_jam()


func interact() -> void:
	toggle_jam()


func register_npc(npc: Node) -> void:
	if npc == null:
		return

	if not is_instance_valid(npc):
		return

	if not registered_npcs.has(npc):
		registered_npcs.append(npc)

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(self)

	# Important:
	# Merely being inside the JamSpot does not mean JamSpot controls the NPC.
	# Only active JamSpots take control.
	refresh_npc_activity(npc)
	_update_label()


func unregister_npc(npc: Node) -> void:
	if npc == null:
		return

	if registered_npcs.has(npc):
		registered_npcs.erase(npc)

	# If this JamSpot currently controls the NPC, release it.
	if npc.has_method("end_jam_spot_control"):
		npc.end_jam_spot_control(self)
	else:
		if jam_context != null and jam_context.has_method("set_member_active"):
			jam_context.set_member_active(npc, false)

		if npc.has_method("set_current_jam_context"):
			npc.set_current_jam_context(null)

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(null)

	_update_label()


func start_jam() -> void:
	if jam_is_active:
		return

	jam_is_active = true
	_sync_jam_context_song()

	_rescan_npcs_inside_jam_area()
	refresh_all_npc_activity()
	_update_label()


func stop_jam() -> void:
	if not jam_is_active:
		return

	jam_is_active = false

	for npc in registered_npcs.duplicate():
		if npc == null or not is_instance_valid(npc):
			continue

		if jam_context != null and jam_context.has_method("set_member_active"):
			jam_context.set_member_active(npc, false)

		if npc.has_method("end_jam_spot_control"):
			npc.end_jam_spot_control(self)
		else:
			if npc.has_method("set_current_jam_context"):
				npc.set_current_jam_context(null)

			if npc.has_method("set_current_jam_spot"):
				npc.set_current_jam_spot(null)

			if npc.has_method("set_current_part"):
				npc.set_current_part("silent")

		# Reset temporary JamSpot opt-out.
		if npc.has_method("set_npc_enabled"):
			npc.set_npc_enabled(true)
		elif "npc_enabled" in npc:
			npc.npc_enabled = true

		if npc.has_method("set_current_jam_spot"):
			npc.set_current_jam_spot(null)

	registered_npcs.clear()

	if jam_context != null and jam_context.has_method("stop_all_members"):
		jam_context.stop_all_members()

	_update_label()


func _rescan_npcs_inside_jam_area() -> void:
	registered_npcs.clear()

	if jam_area == null:
		return

	for area in jam_area.get_overlapping_areas():
		var possible_npc: Node = area.get_parent()

		if possible_npc != null and possible_npc.is_in_group("npc_musician"):
			register_npc(possible_npc)

	for body in jam_area.get_overlapping_bodies():
		if body != null and body.is_in_group("npc_musician"):
			register_npc(body)


func set_jam_active(should_be_active: bool) -> void:
	if should_be_active:
		start_jam()
	else:
		stop_jam()


func toggle_jam() -> void:
	if jam_is_active:
		stop_jam()
	else:
		start_jam()


func refresh_all_npc_activity() -> void:
	for npc in registered_npcs.duplicate():
		refresh_npc_activity(npc)


func refresh_npc_activity(npc: Node) -> void:
	if npc == null:
		return

	if not is_instance_valid(npc):
		return

	if not npc.has_method("is_npc_enabled"):
		return

	var should_play: bool = jam_is_active and npc.is_npc_enabled()

	if not should_play:
		# JamSpot is off or NPC disabled.
		# NPC remains physically registered inside the JamSpot,
		# but the JamSpot must release musical control completely.
		if jam_context != null and jam_context.has_method("set_member_active"):
			jam_context.set_member_active(npc, false)

		if npc.has_method("end_jam_spot_control"):
			npc.end_jam_spot_control(self)
		else:
			if npc.has_method("set_current_jam_context"):
				npc.set_current_jam_context(null)

			if npc.has_method("set_current_part"):
				npc.set_current_part("silent")

		return

	# JamSpot is active, so it takes control.
	if npc.has_method("begin_jam_spot_control"):
		npc.begin_jam_spot_control(self, jam_context)
	else:
		if npc.has_method("set_current_jam_spot"):
			npc.set_current_jam_spot(self)

		if npc.has_method("set_current_jam_context"):
			npc.set_current_jam_context(jam_context)

	if jam_context != null and jam_context.has_method("add_member"):
		jam_context.add_member(npc)

	if jam_context != null:
		if jam_context.has_method("set_member_requested_parts"):
			jam_context.set_member_requested_parts(npc, true, true)
		elif jam_context.has_method("set_member_requested_part"):
			jam_context.set_member_requested_part(npc, "both")

	if "wants_to_play" in npc:
		npc.wants_to_play = true

	if jam_context != null and jam_context.has_method("set_member_active"):
		jam_context.set_member_active(npc, true)


func is_jam_active() -> bool:
	return jam_is_active


func is_active() -> bool:
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


func _sync_jam_context_song() -> void:
	if jam_context == null:
		return

	if jam_context.has_method("apply_song_id"):
		jam_context.apply_song_id(song_id)
	elif "song_id" in jam_context:
		jam_context.song_id = song_id


func _on_jam_area_area_entered(area: Area2D) -> void:
	var possible_npc: Node = area.get_parent()
	_try_register_possible_npc(possible_npc)


func _on_jam_area_area_exited(area: Area2D) -> void:
	var possible_npc: Node = area.get_parent()
	_try_unregister_possible_npc(possible_npc)


func _on_jam_area_body_entered(body: Node) -> void:
	_try_register_possible_npc(body)


func _on_jam_area_body_exited(body: Node) -> void:
	_try_unregister_possible_npc(body)


func _try_register_possible_npc(node: Node) -> void:
	if not jam_is_active:
		return

	if node == null:
		return

	if not is_instance_valid(node):
		return

	if not node.is_in_group("npc_musician"):
		return

	register_npc(node)


func _try_unregister_possible_npc(node: Node) -> void:
	if node == null:
		return

	if not is_instance_valid(node):
		return

	if not node.is_in_group("npc_musician"):
		return

	if registered_npcs.has(node):
		unregister_npc(node)


func _update_label() -> void:
	if label == null:
		return

	var state_text := "On" if jam_is_active else "Off"

	label.text = "%s\nSong: %s\n%s\nNPCs: %d" % [
		display_name,
		song_id,
		state_text,
		registered_npcs.size()
	]
