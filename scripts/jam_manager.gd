extends Node

signal nearby_jam_changed(jam_source: Node, jam_type: String, jam_name: String)

@export var fallback_accompanist_radius := 100.0
@export var freeform_leave_padding := 50.0
@export var freeform_player_leave_padding := 50.0
@export var freeform_jam_context_scene: PackedScene

const JAM_TYPE_NONE := "none"
const JAM_TYPE_JAM_SPOT := "jam_spot"
const JAM_TYPE_MUSICIAN := "musician"
const JAM_TYPE_PLAYER_FREEFORM := "player_freeform"

var active_freeform_jam_context: Node = null
var active_freeform_leader: Node = null
var active_freeform_members: Array[Node] = []

var music_system: Node = null

var player_is_near_active_jam := false
var has_reported_to_music_system := false

var current_nearby_jam_source: Node = null
var current_nearby_jam_type := JAM_TYPE_NONE
var current_nearby_jam_name := "None"
var current_nearby_jam_distance := INF


func _ready() -> void:
	add_to_group("jam_manager")

	music_system = get_tree().get_first_node_in_group("music_system")


func update_player_jam_proximity(player_position: Vector2) -> void:
	_detach_player_from_freeform_if_too_far(player_position)
	update_proximity_blocks(player_position)
	_check_auto_freeform_leave(player_position)

	var best_jam: Dictionary = _find_best_active_jam_source(player_position)

	var new_source: Node = best_jam.get("source", null)
	var new_type: String = best_jam.get("type", JAM_TYPE_NONE)
	var new_name: String = best_jam.get("name", "None")
	var new_distance: float = best_jam.get("distance", INF)

	var new_is_near := new_source != null
	var source_changed := new_source != current_nearby_jam_source
	var type_changed := new_type != current_nearby_jam_type
	var near_state_changed := new_is_near != player_is_near_active_jam

	current_nearby_jam_source = new_source
	current_nearby_jam_type = new_type
	current_nearby_jam_name = new_name
	current_nearby_jam_distance = new_distance
	player_is_near_active_jam = new_is_near

	if source_changed or type_changed:
		nearby_jam_changed.emit(
			current_nearby_jam_source,
			current_nearby_jam_type,
			current_nearby_jam_name
		)

	if near_state_changed or not has_reported_to_music_system:
		has_reported_to_music_system = true

		if music_system != null and music_system.has_method("set_player_near_active_jam"):
			music_system.set_player_near_active_jam(player_is_near_active_jam)


func try_auto_attach_npc_to_player(player: Node, player_position: Vector2) -> void:
	if player == null:
		return

	if not "is_playing_instrument" in player:
		return

	if not player.is_playing_instrument:
		return

	var nearby_jam_spot: Dictionary = _find_best_active_jam_spot(player_position)

	if not nearby_jam_spot.is_empty():
		return

	var npc: Node = _find_best_available_accompanist(player_position)

	if npc == null:
		return

	if active_freeform_jam_context == null or not is_instance_valid(active_freeform_jam_context):
		_create_player_carried_freeform_context(player)

	if active_freeform_jam_context == null:
		return

	if active_freeform_jam_context.has_method("add_member"):
		active_freeform_jam_context.add_member(npc)

	_set_npc_freeform_request_on_context(npc, active_freeform_jam_context)

	if active_freeform_jam_context.has_method("set_member_active"):
		active_freeform_jam_context.set_member_active(npc, true)

	if npc.has_method("start_auto_freeform"):
		npc.start_auto_freeform()
	elif npc.has_method("set_actual_playing"):
		npc.set_actual_playing(true)

	if not active_freeform_members.has(npc):
		active_freeform_members.append(npc)

	current_nearby_jam_source = npc
	current_nearby_jam_type = JAM_TYPE_PLAYER_FREEFORM
	current_nearby_jam_name = _get_jam_source_display_name(npc, "Freeform Jam")
	current_nearby_jam_distance = player_position.distance_to(npc.global_position)
	player_is_near_active_jam = true

	if music_system != null and music_system.has_method("set_player_near_active_jam"):
		music_system.set_player_near_active_jam(true)

	nearby_jam_changed.emit(
		current_nearby_jam_source,
		current_nearby_jam_type,
		current_nearby_jam_name
	)


func start_manual_freeform_npc(npc: Node) -> bool:
	if npc == null:
		return false

	var player: Node = get_tree().get_first_node_in_group("player")

	# If player is currently playing, attach this manual NPC to the player's carried song.
	if player != null and "is_playing_instrument" in player and player.is_playing_instrument:
		if active_freeform_jam_context == null or not is_instance_valid(active_freeform_jam_context):
			_create_player_carried_freeform_context(player)

		if active_freeform_jam_context == null:
			return false

		if active_freeform_jam_context.has_method("add_member"):
			active_freeform_jam_context.add_member(npc)

		_set_npc_freeform_request_on_context(npc, active_freeform_jam_context)

		if active_freeform_jam_context.has_method("set_member_active"):
			active_freeform_jam_context.set_member_active(npc, true)

		if npc.has_method("start_manual_freeform"):
			npc.start_manual_freeform()
		else:
			if npc.has_method("set_actual_playing"):
				npc.set_actual_playing(true)

		if not active_freeform_members.has(npc):
			active_freeform_members.append(npc)

		current_nearby_jam_source = npc
		current_nearby_jam_type = JAM_TYPE_PLAYER_FREEFORM
		current_nearby_jam_name = _get_jam_source_display_name(npc, "Manual Freeform Jam")

		if player is Node2D:
			current_nearby_jam_distance = player.global_position.distance_to(npc.global_position)

		player_is_near_active_jam = true

		if music_system != null and music_system.has_method("set_player_near_active_jam"):
			music_system.set_player_near_active_jam(true)

		nearby_jam_changed.emit(
			current_nearby_jam_source,
			current_nearby_jam_type,
			current_nearby_jam_name
		)

		return true

	# If player is not playing, let the NPC start alone.
	# Create a freeform context with the NPC as the timing source so later the player can join
	# and JamContext can pass melody correctly.
	if freeform_jam_context_scene == null:
		npc.start_manual_freeform()
		return true

	if active_freeform_jam_context == null or not is_instance_valid(active_freeform_jam_context):
		active_freeform_jam_context = freeform_jam_context_scene.instantiate()
		add_child(active_freeform_jam_context)
		active_freeform_leader = npc
		active_freeform_members.clear()

	if active_freeform_jam_context.has_method("add_member"):
		active_freeform_jam_context.add_member(npc)

	_set_npc_freeform_request_on_context(npc, active_freeform_jam_context)

	if active_freeform_jam_context.has_method("set_member_active"):
		active_freeform_jam_context.set_member_active(npc, true)

	if npc.has_method("start_manual_freeform"):
		npc.start_manual_freeform()
	else:
		npc.set_actual_playing(true)

	if not active_freeform_members.has(npc):
		active_freeform_members.append(npc)

	current_nearby_jam_source = npc
	current_nearby_jam_type = JAM_TYPE_PLAYER_FREEFORM
	current_nearby_jam_name = _get_jam_source_display_name(npc, "Manual Freeform Jam")
	player_is_near_active_jam = true

	return true


func stop_auto_freeform_for_npc(npc: Node) -> void:
	if npc == null:
		return

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("set_member_active"):
			active_freeform_jam_context.set_member_active(npc, false)

	if npc.has_method("stop_freeform_immediately"):
		npc.stop_freeform_immediately()

	if active_freeform_members.has(npc):
		active_freeform_members.erase(npc)

	_cleanup_freeform_context_if_only_player_left()


func stop_manual_freeform_for_npc(npc: Node) -> void:
	if npc == null:
		return

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("set_member_active"):
			active_freeform_jam_context.set_member_active(npc, false)

	if npc.has_method("stop_freeform_immediately"):
		npc.stop_freeform_immediately()

	if active_freeform_members.has(npc):
		active_freeform_members.erase(npc)

	_cleanup_freeform_context_if_only_player_left()


func stop_all_auto_freeform_npcs() -> void:
	var members_to_check: Array[Node] = active_freeform_members.duplicate()

	for member in members_to_check:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if member.has_method("is_auto_freeform"):
			if member.is_auto_freeform():
				stop_auto_freeform_for_npc(member)

	_cleanup_freeform_context_if_only_player_left()


func handle_player_stopped_playing(previous_context: Node) -> void:
	reset_all_auto_blocks()

	if previous_context == null:
		return

	if not is_freeform_jam_context(previous_context):
		return

	stop_all_auto_freeform_npcs()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		var player: Node = get_tree().get_first_node_in_group("player")

		if player != null:
			if active_freeform_jam_context.has_method("set_member_active"):
				active_freeform_jam_context.set_member_active(player, false)

			if active_freeform_members.has(player):
				active_freeform_members.erase(player)

	_cleanup_freeform_context_if_only_player_left(false)


func is_freeform_jam_context(jam_context: Node) -> bool:
	if jam_context == null:
		return false

	if not is_instance_valid(jam_context):
		return false

	if active_freeform_jam_context == null:
		return false

	if not is_instance_valid(active_freeform_jam_context):
		return false

	return jam_context == active_freeform_jam_context


func is_player_near_current_jamspot_context(jam_context: Node) -> bool:
	if jam_context == null:
		return false

	if not is_instance_valid(jam_context):
		return false

	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		return false

	if not player is Node2D:
		return false

	for jam_spot in get_tree().get_nodes_in_group("jam_spot"):
		if not is_instance_valid(jam_spot):
			continue

		if not jam_spot.has_method("get_jam_context"):
			continue

		if jam_spot.get_jam_context() != jam_context:
			continue

		if jam_spot.has_method("is_position_inside_leave_radius"):
			return jam_spot.is_position_inside_leave_radius(player.global_position)

		# Last-resort fallback only.
		# JamSpot should normally provide is_position_inside_leave_radius().
		var fallback_leave_radius := 150.0
		return player.global_position.distance_to(jam_spot.global_position) <= fallback_leave_radius

	return false


func get_current_nearby_jam_context() -> Node:
	var player: Node = get_tree().get_first_node_in_group("player")

	if current_nearby_jam_source != null and current_nearby_jam_type == JAM_TYPE_JAM_SPOT:
		if current_nearby_jam_source.has_method("get_jam_context"):
			return current_nearby_jam_source.get_jam_context()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if player != null and player is Node2D:
			var freeform_info: Dictionary = _get_active_freeform_npc_info(player.global_position, false)

			if not freeform_info.is_empty():
				return active_freeform_jam_context

	return null


func get_current_nearby_jam_source() -> Node:
	return current_nearby_jam_source


func get_current_nearby_jam_type() -> String:
	return current_nearby_jam_type


func get_current_nearby_jam_name() -> String:
	return current_nearby_jam_name


func get_current_nearby_jam_distance() -> float:
	return current_nearby_jam_distance


func get_current_jam_active_instruments_text() -> String:
	var jam_context: Node = get_current_nearby_jam_context()

	if jam_context != null and jam_context.has_method("get_active_instruments_text"):
		return jam_context.get_active_instruments_text()

	return "None"


func get_current_jam_featured_instrument_text() -> String:
	var jam_context: Node = get_current_nearby_jam_context()

	if jam_context != null and jam_context.has_method("get_featured_instrument_text"):
		return jam_context.get_featured_instrument_text()

	return "None"


func get_nearby_jam_debug_text() -> String:
	if current_nearby_jam_source == null:
		return "Nearby Jam: None"

	return "Nearby Jam: %s (%s)" % [
		current_nearby_jam_name,
		current_nearby_jam_type
	]


func _create_player_carried_freeform_context(player: Node) -> void:
	if player == null:
		return

	if freeform_jam_context_scene == null:
		push_warning("JamManager is missing freeform_jam_context_scene.")
		return

	active_freeform_jam_context = freeform_jam_context_scene.instantiate()
	add_child(active_freeform_jam_context)

	active_freeform_leader = player
	active_freeform_members.clear()
	active_freeform_members.append(player)

	if active_freeform_jam_context.has_method("add_member"):
		active_freeform_jam_context.add_member(player)

	if active_freeform_jam_context.has_method("start_from_existing_member"):
		active_freeform_jam_context.start_from_existing_member(player)

	_set_player_request_on_context(player, active_freeform_jam_context)

	var player_audio_source: Node = null

	if player.has_method("get_current_audio_source"):
		player_audio_source = player.get_current_audio_source()

	if player_audio_source != null and player_audio_source.has_method("adopt_into_synced_jam"):
		var rhythm_on := true
		var melody_on := true

		if player.has_method("get_wants_rhythm"):
			rhythm_on = player.get_wants_rhythm()

		if player.has_method("get_wants_melody"):
			melody_on = player.get_wants_melody()

		player_audio_source.adopt_into_synced_jam(rhythm_on, melody_on)

	if active_freeform_jam_context.has_method("set_member_active"):
		active_freeform_jam_context.set_member_active(player, true)

	if player.has_method("mark_as_freeform_jam_context"):
		player.mark_as_freeform_jam_context(active_freeform_jam_context)


func _set_player_request_on_context(player: Node, jam_context: Node) -> void:
	if player == null or jam_context == null:
		return

	var rhythm_on := true
	var melody_on := true

	if player.has_method("get_wants_rhythm"):
		rhythm_on = player.get_wants_rhythm()

	if player.has_method("get_wants_melody"):
		melody_on = player.get_wants_melody()

	if jam_context.has_method("set_member_requested_parts"):
		jam_context.set_member_requested_parts(player, rhythm_on, melody_on)
	elif jam_context.has_method("set_member_requested_part"):
		var part_name: String = _get_part_from_flags(rhythm_on, melody_on)
		jam_context.set_member_requested_part(player, part_name)


func _set_npc_freeform_request_on_context(npc: Node, jam_context: Node) -> void:
	if npc == null or jam_context == null:
		return

	if jam_context.has_method("set_member_requested_parts"):
		jam_context.set_member_requested_parts(npc, true, true)
	elif jam_context.has_method("set_member_requested_part"):
		jam_context.set_member_requested_part(npc, "both")


func _get_part_from_flags(rhythm_on: bool, melody_on: bool) -> String:
	if rhythm_on and melody_on:
		return "both"
	elif melody_on:
		return "melody"
	elif rhythm_on:
		return "rhythm"

	return "silent"


func _check_auto_freeform_leave(player_position: Vector2) -> void:
	var members_to_check: Array[Node] = active_freeform_members.duplicate()

	for member in members_to_check:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member.has_method("is_auto_freeform"):
			continue

		if not member.is_auto_freeform():
			continue

		if not member is Node2D:
			continue

		var leave_distance: float = _get_npc_auto_stop_radius(member)
		var current_distance: float = player_position.distance_to(member.global_position)

		if current_distance > leave_distance:
			stop_auto_freeform_for_npc(member)


func update_proximity_blocks(player_position: Vector2) -> void:
	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if not is_instance_valid(npc):
			continue

		if not npc.has_method("is_proximity_blocked"):
			continue

		if not npc.is_proximity_blocked():
			continue

		if not npc is Node2D:
			continue

		var unblock_distance: float = _get_npc_auto_stop_radius(npc)
		var distance: float = player_position.distance_to(npc.global_position)

		if distance > unblock_distance:
			if npc.has_method("reset_auto_block"):
				npc.reset_auto_block()


func _cleanup_freeform_context_if_only_player_left(return_player_to_solo := true) -> void:
	var non_player_count := 0

	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		non_player_count += 1

	# If any NPC is still in the freeform context, keep the context alive.
	# This is important for manual freeform NPCs:
	# player leaves radius -> player detaches -> NPC keeps playing.
	if non_player_count > 0:
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	if return_player_to_solo:
		if player != null and player.has_method("return_to_carried_solo_from_freeform"):
			player.return_to_carried_solo_from_freeform()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		active_freeform_jam_context.queue_free()

	active_freeform_jam_context = null
	active_freeform_leader = null
	active_freeform_members.clear()

	current_nearby_jam_source = null
	current_nearby_jam_type = JAM_TYPE_NONE
	current_nearby_jam_name = "None"
	current_nearby_jam_distance = INF
	player_is_near_active_jam = false

	if music_system != null and music_system.has_method("set_player_near_active_jam"):
		music_system.set_player_near_active_jam(false)


func _find_best_active_jam_source(player_position: Vector2) -> Dictionary:
	var best_jam_spot: Dictionary = _find_best_active_jam_spot(player_position)

	if not best_jam_spot.is_empty():
		return best_jam_spot

	var best_musician: Dictionary = _find_best_active_musician(player_position)

	if not best_musician.is_empty():
		return best_musician

	return {}


func _find_best_active_jam_spot(player_position: Vector2) -> Dictionary:
	var best_source: Node = null
	var best_name := "None"
	var best_distance := INF

	for jam_spot in get_tree().get_nodes_in_group("jam_spot"):
		if not is_instance_valid(jam_spot):
			continue

		if jam_spot.has_method("is_jam_active"):
			if not jam_spot.is_jam_active():
				continue

		var is_inside := false

		if jam_spot.has_method("is_position_inside_leave_radius") and current_nearby_jam_source == jam_spot:
			is_inside = jam_spot.is_position_inside_leave_radius(player_position)
		elif jam_spot.has_method("is_position_inside_join_radius"):
			is_inside = jam_spot.is_position_inside_join_radius(player_position)
		else:
			var fallback_radius := 100.0

			if current_nearby_jam_source == jam_spot:
				fallback_radius = 150.0

			is_inside = player_position.distance_to(jam_spot.global_position) <= fallback_radius

		if not is_inside:
			continue

		var distance: float = player_position.distance_to(jam_spot.global_position)

		if distance < best_distance:
			best_source = jam_spot
			best_distance = distance
			best_name = _get_jam_source_display_name(jam_spot, "Jam Spot")

	if best_source == null:
		return {}

	return {
		"source": best_source,
		"type": JAM_TYPE_JAM_SPOT,
		"name": best_name,
		"distance": best_distance
	}


func _find_best_active_musician(player_position: Vector2) -> Dictionary:
	var best_source: Node = null
	var best_name := "None"
	var best_distance := INF

	for musician in get_tree().get_nodes_in_group("npc_musician"):
		if not is_instance_valid(musician):
			continue

		if not musician.has_method("is_actively_playing_jam"):
			continue

		if not musician.is_actively_playing_jam():
			continue

		if not musician is Node2D:
			continue

		var check_radius: float = _get_npc_join_radius(musician)

		if current_nearby_jam_source == musician:
			check_radius = _get_npc_auto_stop_radius(musician)

		var distance: float = player_position.distance_to(musician.global_position)

		if distance <= check_radius and distance < best_distance:
			best_source = musician
			best_distance = distance
			best_name = _get_jam_source_display_name(musician, "Musician")

	if best_source == null:
		return {}

	return {
		"source": best_source,
		"type": JAM_TYPE_MUSICIAN,
		"name": best_name,
		"distance": best_distance
	}


func _find_best_available_accompanist(player_position: Vector2) -> Node:
	var best_npc: Node = null
	var best_distance := INF

	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if not is_instance_valid(npc):
			continue

		if not npc.has_method("is_available_for_player_accompaniment"):
			continue

		if not npc.is_available_for_player_accompaniment():
			continue

		var npc_radius: float = _get_npc_join_radius(npc)
		var distance: float = player_position.distance_to(npc.global_position)

		if distance <= npc_radius and distance < best_distance:
			best_npc = npc
			best_distance = distance

	return best_npc


func _get_jam_source_display_name(source: Node, fallback_name: String) -> String:
	if source == null:
		return fallback_name

	if source.has_method("get_display_name"):
		return source.get_display_name()

	if "display_name" in source:
		return str(source.display_name)

	if source.name != "":
		return source.name

	return fallback_name


func reset_all_auto_blocks() -> void:
	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if not is_instance_valid(npc):
			continue

		if npc.has_method("reset_auto_block"):
			npc.reset_auto_block()

func detach_player_from_freeform_if_too_far(player_position: Vector2) -> void:
	if active_freeform_jam_context == null:
		return

	if not is_instance_valid(active_freeform_jam_context):
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		return

	if not player is Node2D:
		return

	# Only detach if the player believes they are currently in this freeform context.
	var player_context: Node = null

	if "current_jam_context" in player:
		player_context = player.current_jam_context

	if player_context != active_freeform_jam_context:
		return

	var closest_npc_distance := INF
	var closest_npc: Node = null

	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member is Node2D:
			continue

		var distance: float = player_position.distance_to(member.global_position)

		if distance < closest_npc_distance:
			closest_npc_distance = distance
			closest_npc = member

	if closest_npc == null:
		return

	var leave_distance: float = _get_player_freeform_leave_radius(closest_npc)

	if closest_npc_distance <= leave_distance:
		return

	# Detach only the player. Keep NPC/manual context alive.
	if active_freeform_jam_context.has_method("detach_member_preserve_audio"):
		active_freeform_jam_context.detach_member_preserve_audio(player)
	elif active_freeform_jam_context.has_method("set_member_active"):
		active_freeform_jam_context.set_member_active(player, false)

	if active_freeform_members.has(player):
		active_freeform_members.erase(player)

	if player.has_method("return_to_carried_solo_from_freeform"):
		player.return_to_carried_solo_from_freeform()

	current_nearby_jam_source = null
	current_nearby_jam_type = JAM_TYPE_NONE
	current_nearby_jam_name = "None"
	current_nearby_jam_distance = INF
	player_is_near_active_jam = false

	if music_system != null and music_system.has_method("set_player_near_active_jam"):
		music_system.set_player_near_active_jam(false)


func _detach_player_from_freeform_if_too_far(player_position: Vector2) -> void:
	if active_freeform_jam_context == null:
		return

	if not is_instance_valid(active_freeform_jam_context):
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		return

	if not player is Node2D:
		return

	var freeform_info: Dictionary = _get_active_freeform_npc_info(player_position, true)

	# Still inside at least one active freeform NPC leave radius.
	if not freeform_info.is_empty():
		return

	# Player is outside all active freeform NPC leave radii.
	# Detach only the player. Keep the NPC/context alive.
	if active_freeform_jam_context.has_method("detach_member_preserve_audio"):
		active_freeform_jam_context.detach_member_preserve_audio(player)
	elif active_freeform_jam_context.has_method("set_member_active"):
		active_freeform_jam_context.set_member_active(player, false)

	if active_freeform_members.has(player):
		active_freeform_members.erase(player)

	if player.has_method("return_to_carried_solo_from_freeform"):
		player.return_to_carried_solo_from_freeform()

	current_nearby_jam_source = null
	current_nearby_jam_type = JAM_TYPE_NONE
	current_nearby_jam_name = "None"
	current_nearby_jam_distance = INF
	player_is_near_active_jam = false

	if music_system != null and music_system.has_method("set_player_near_active_jam"):
		music_system.set_player_near_active_jam(false)


func _get_npc_join_radius(npc: Node) -> float:
	if npc != null:
		if "auto_accompany_radius" in npc:
			return float(npc.auto_accompany_radius)

	return fallback_accompanist_radius


func _get_npc_auto_stop_radius(npc: Node) -> float:
	return _get_npc_join_radius(npc) + freeform_leave_padding


func _get_player_freeform_leave_radius(npc: Node) -> float:
	return _get_npc_join_radius(npc) + freeform_player_leave_padding


func _get_active_freeform_npc_info(player_position: Vector2, use_leave_radius := false) -> Dictionary:
	var best_npc: Node = null
	var best_distance := INF
	var best_radius := 0.0

	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member is Node2D:
			continue

		var radius: float = _get_npc_join_radius(member)

		if use_leave_radius:
			radius = _get_player_freeform_leave_radius(member)

		var distance: float = player_position.distance_to(member.global_position)

		if distance <= radius and distance < best_distance:
			best_npc = member
			best_distance = distance
			best_radius = radius

	if best_npc == null:
		return {}

	return {
		"source": best_npc,
		"name": _get_jam_source_display_name(best_npc, "Freeform Jam"),
		"distance": best_distance,
		"radius": best_radius
	}


func get_player_jam_label_text() -> String:
	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		return "Current Jam: None"

	if not player is Node2D:
		return "Current Jam: None"

	# JamSpot takes label priority when player is inside one.
	if current_nearby_jam_source != null and current_nearby_jam_type == JAM_TYPE_JAM_SPOT:
		return "Current Jam: %s" % current_nearby_jam_name

	# Active freeform NPC area.
	var freeform_info: Dictionary = _get_active_freeform_npc_info(player.global_position, true)

	if not freeform_info.is_empty():
		return "Current Jam: %s" % str(freeform_info["name"])

	# Player is carrying their own song outside any jam area.
	if "is_playing_direct_solo" in player:
		if player.is_playing_direct_solo:
			return "Current Jam: Solo"

	return "Current Jam: None"
