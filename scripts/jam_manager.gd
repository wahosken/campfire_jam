extends Node

signal nearby_jam_changed(jam_source: Node, jam_type: String, jam_name: String)

@export var debug_player_freeform := false

@export var fallback_accompanist_radius := 100.0
@export var freeform_leave_padding := 50.0
@export var freeform_player_leave_padding := 50.0
@export var freeform_jam_context_scene: PackedScene

@export var freeform_recruit_scan_interval := 0.25

var freeform_recruit_scan_timer := 0.0

const JAM_TYPE_NONE := "none"
const JAM_TYPE_JAM_SPOT := "jam_spot"
const JAM_TYPE_MUSICIAN := "musician"
const JAM_TYPE_PLAYER_FREEFORM := "player_freeform"

var active_freeform_jam_context: Node = null
var active_freeform_leader: Node = null
var active_freeform_members: Array[Node] = []
var active_freeform_anchor: Node = null

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


func _process(delta: float) -> void:
	update_following_npc_jam_priorities()
	_update_active_freeform_recruitment(delta)

	var player: Node = get_tree().get_first_node_in_group("player")

	if player != null and player is Node2D:
		_check_auto_freeform_leave(player.global_position)


func update_player_jam_proximity(player_position: Vector2) -> void:
	_check_auto_freeform_leave(player_position)

	# 1. Active JamSpots always have priority.
	var nearby_jam_spot: Dictionary = _find_best_active_jam_spot(player_position)

	if not nearby_jam_spot.is_empty():
		current_nearby_jam_source = nearby_jam_spot["source"]
		current_nearby_jam_type = JAM_TYPE_JAM_SPOT
		current_nearby_jam_name = nearby_jam_spot["name"]
		current_nearby_jam_distance = nearby_jam_spot["distance"]
		player_is_near_active_jam = true

		if music_system != null and music_system.has_method("set_player_near_active_jam"):
			music_system.set_player_near_active_jam(true)

		nearby_jam_changed.emit(
			current_nearby_jam_source,
			current_nearby_jam_type,
			current_nearby_jam_name
		)

		return

	# Only detach from freeform after we know no JamSpot currently owns the player area.
	_detach_player_from_freeform_if_too_far(player_position)

	# 2. Only check freeform if no active JamSpot was found.
	var nearby_freeform: Dictionary = _find_best_active_musician(player_position)

	if not nearby_freeform.is_empty():
		current_nearby_jam_source = nearby_freeform["source"]
		current_nearby_jam_type = JAM_TYPE_MUSICIAN
		current_nearby_jam_name = nearby_freeform["name"]
		current_nearby_jam_distance = nearby_freeform["distance"]
		player_is_near_active_jam = true

		if music_system != null and music_system.has_method("set_player_near_active_jam"):
			music_system.set_player_near_active_jam(true)

		nearby_jam_changed.emit(
			current_nearby_jam_source,
			current_nearby_jam_type,
			current_nearby_jam_name
		)

		return

	# 3. Nothing nearby.
	current_nearby_jam_source = null
	current_nearby_jam_type = JAM_TYPE_NONE
	current_nearby_jam_name = "None"
	current_nearby_jam_distance = INF
	player_is_near_active_jam = false

	if music_system != null and music_system.has_method("set_player_near_active_jam"):
		music_system.set_player_near_active_jam(false)

	nearby_jam_changed.emit(
		current_nearby_jam_source,
		current_nearby_jam_type,
		current_nearby_jam_name
	)


func try_auto_attach_npc_to_player(player: Node, player_position: Vector2) -> void:
	_debug_player_freeform("try_auto_attach_npc_to_player START player_playing=" + str(player.is_playing_instrument if "is_playing_instrument" in player else "unknown"))
	
	if player == null:
		return

	if not "is_playing_instrument" in player:
		return

	if not player.is_playing_instrument:
		return

	var nearby_jam_spot: Dictionary = _find_best_active_jam_spot(player_position)

	if not nearby_jam_spot.is_empty():
		return

	var nearby_npcs: Array[Node] = _find_available_accompanists_near_position(player_position, [player])

	if nearby_npcs.is_empty():
		return

	_debug_player_freeform("try_auto_attach_npc_to_player attaching NPCs")

	if active_freeform_jam_context == null or not is_instance_valid(active_freeform_jam_context):
		_create_player_carried_freeform_context(player)

	if active_freeform_jam_context == null:
		return

	for npc in nearby_npcs:
		_add_npc_to_active_freeform_jam(npc, false)

	var closest_npc: Node = nearby_npcs[0]
	var closest_distance: float = player_position.distance_to(closest_npc.global_position)

	for npc in nearby_npcs:
		var distance: float = player_position.distance_to(npc.global_position)

		if distance < closest_distance:
			closest_npc = npc
			closest_distance = distance

	current_nearby_jam_source = closest_npc
	current_nearby_jam_type = JAM_TYPE_PLAYER_FREEFORM
	current_nearby_jam_name = _get_jam_source_display_name(closest_npc, "Freeform Jam")
	current_nearby_jam_distance = closest_distance
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

	if not npc is Node2D:
		return false

	var player: Node = get_tree().get_first_node_in_group("player")
	var player_is_playing := false

	if player != null:
		if "is_playing_instrument" in player:
			player_is_playing = player.is_playing_instrument

	var freeform_song_id := "song_01"

	# If the player is already playing, the manual NPC joins the player's song.
	if player != null and player_is_playing:
		if player.has_method("get_selected_song_id"):
			freeform_song_id = player.get_selected_song_id()

		if active_freeform_jam_context == null or not is_instance_valid(active_freeform_jam_context):
			_create_player_carried_freeform_context(player)

	# If the player is not playing, the NPC starts their own primary song.
	else:
		if npc.has_method("get_primary_song_id"):
			freeform_song_id = npc.get_primary_song_id()

		if active_freeform_jam_context == null or not is_instance_valid(active_freeform_jam_context):
			if freeform_jam_context_scene == null:
				npc.start_manual_freeform()
				return true

			active_freeform_jam_context = freeform_jam_context_scene.instantiate()
			add_child(active_freeform_jam_context)

			active_freeform_members.clear()
			active_freeform_leader = npc
			active_freeform_anchor = npc

			if active_freeform_jam_context.has_method("apply_song_id"):
				active_freeform_jam_context.apply_song_id(freeform_song_id)
			elif "song_id" in active_freeform_jam_context:
				active_freeform_jam_context.song_id = freeform_song_id

	if active_freeform_jam_context == null:
		return false

	# Make sure the context has the correct song before adding members.
	if active_freeform_jam_context.has_method("apply_song_id"):
		active_freeform_jam_context.apply_song_id(freeform_song_id)
	elif "song_id" in active_freeform_jam_context:
		active_freeform_jam_context.song_id = freeform_song_id

	# Interacted NPC becomes indefinite/manual.
	_add_npc_to_active_freeform_jam(npc, true)

	if not player_is_playing:
		active_freeform_anchor = npc
		active_freeform_leader = npc

	# Other nearby available NPCs join as auto/freeform followers.
	var nearby_npcs: Array[Node] = _find_available_accompanists_near_position(npc.global_position, [npc])

	for nearby_npc in nearby_npcs:
		_add_npc_to_active_freeform_jam(nearby_npc, false)

	current_nearby_jam_source = npc
	current_nearby_jam_type = JAM_TYPE_PLAYER_FREEFORM
	current_nearby_jam_name = _get_jam_source_display_name(npc, "Manual Freeform Jam")

	if player != null and player is Node2D:
		current_nearby_jam_distance = player.global_position.distance_to(npc.global_position)
	else:
		current_nearby_jam_distance = 0.0

	player_is_near_active_jam = true

	if music_system != null and music_system.has_method("set_player_near_active_jam"):
		music_system.set_player_near_active_jam(true)

	nearby_jam_changed.emit(
		current_nearby_jam_source,
		current_nearby_jam_type,
		current_nearby_jam_name
	)

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

	# First remove the manually toggled NPC.
	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("set_member_active"):
			active_freeform_jam_context.set_member_active(npc, false)

	if npc.has_method("stop_freeform_immediately"):
		npc.stop_freeform_immediately()

	if active_freeform_members.has(npc):
		active_freeform_members.erase(npc)

	# Now check if any manual/interaction-started NPCs remain.
	var remaining_manual_npcs: Array[Node] = _get_active_manual_freeform_npcs()

	if remaining_manual_npcs.is_empty():
		# No manual anchor remains.
		# All auto followers should stop too.
		_stop_all_auto_freeform_followers()
	else:
		# Another manually activated NPC becomes the leader.
		active_freeform_leader = remaining_manual_npcs[0]

	_refresh_freeform_leader()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("refresh_arrangement"):
			active_freeform_jam_context.refresh_arrangement()

	_cleanup_freeform_context_if_no_freeform_members()


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
	_debug_player_freeform("handle_player_stopped_playing START previous_context=" + str(previous_context))
	
	reset_all_auto_blocks()

	if previous_context == null:
		return

	if not is_freeform_jam_context(previous_context):
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	# Remove player from the freeform context.
	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if player != null:
			if active_freeform_jam_context.has_method("set_member_active"):
				active_freeform_jam_context.set_member_active(player, false)

			if active_freeform_members.has(player):
				active_freeform_members.erase(player)

	# If this is NPC-led, the player stopping should NOT stop auto followers.
	if active_freeform_anchor != null:
		if is_instance_valid(active_freeform_anchor):
			if active_freeform_anchor != player:
				_refresh_freeform_leader()

				if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
					if active_freeform_jam_context.has_method("refresh_arrangement"):
						active_freeform_jam_context.refresh_arrangement()

				return

	# If any manual NPC remains, they become the anchor/leader.
	var remaining_manual_npcs: Array[Node] = _get_active_manual_freeform_npcs()

	if not remaining_manual_npcs.is_empty():
		active_freeform_anchor = remaining_manual_npcs[0]
		active_freeform_leader = remaining_manual_npcs[0]

		if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
			if active_freeform_jam_context.has_method("refresh_arrangement"):
				active_freeform_jam_context.refresh_arrangement()

		return

	# No NPC anchor remains, so this was player-led.
	stop_all_auto_freeform_npcs()
	_cleanup_freeform_context_if_only_player_left(false)
	
	_debug_player_freeform("handle_player_stopped_playing END")


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

	if player == null:
		return null

	if not player is Node2D:
		return null

	var player_position: Vector2 = player.global_position

	# JamSpot always wins.
	var nearby_jam_spot: Dictionary = _find_best_active_jam_spot(player_position)

	if not nearby_jam_spot.is_empty():
		var jam_spot: Node = nearby_jam_spot["source"]

		if jam_spot != null and is_instance_valid(jam_spot):
			if jam_spot.has_method("get_jam_context"):
				return jam_spot.get_jam_context()

	# Freeform only matters if no JamSpot is valid.
	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if _is_player_near_any_freeform_anchor(player_position):
			return active_freeform_jam_context

	return null


func _is_player_near_any_freeform_anchor(player_position: Vector2) -> bool:
	var anchor_positions: Array[Vector2] = _get_active_freeform_anchor_positions()

	if anchor_positions.is_empty():
		return false

	for anchor_position in anchor_positions:
		var distance: float = player_position.distance_to(anchor_position)

		if distance <= 300.0:
			return true

	return false


func _get_player_freeform_join_radius() -> float:
	var fallback_radius := 300.0

	var player: Node = get_tree().get_first_node_in_group("player")

	if player != null and "auto_accompany_radius" in player:
		return float(player.auto_accompany_radius)

	return fallback_radius


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
	_debug_player_freeform("_create_player_carried_freeform_context START")
	
	
	if player == null:
		return

	if freeform_jam_context_scene == null:
		push_warning("JamManager is missing freeform_jam_context_scene.")
		return

	active_freeform_jam_context = freeform_jam_context_scene.instantiate()
	add_child(active_freeform_jam_context)

	active_freeform_leader = player
	active_freeform_anchor = player
	active_freeform_members.clear()
	active_freeform_members.append(player)

	var player_song_id := "song_01"

	if player.has_method("get_selected_song_id"):
		player_song_id = player.get_selected_song_id()

	if active_freeform_jam_context.has_method("apply_song_id"):
		active_freeform_jam_context.apply_song_id(player_song_id)
	elif "song_id" in active_freeform_jam_context:
		active_freeform_jam_context.song_id = player_song_id

	if active_freeform_jam_context.has_method("add_member"):
		active_freeform_jam_context.add_member(player)

	if active_freeform_jam_context.has_method("start_from_existing_member"):
		active_freeform_jam_context.start_from_existing_member(player)

	_set_player_request_on_context(player, active_freeform_jam_context)

	var player_audio_source: Node = null

	if player.has_method("get_current_audio_source"):
		player_audio_source = player.get_current_audio_source()

	if player_audio_source != null:
		if player_audio_source.has_method("set_song_id"):
			player_audio_source.set_song_id(player_song_id)

		if player_audio_source.has_method("adopt_into_synced_jam"):
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
		
	_debug_player_freeform("_create_player_carried_freeform_context END")


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


func _check_auto_freeform_leave(_player_position: Vector2) -> void:
	if active_freeform_jam_context == null:
		return

	if not is_instance_valid(active_freeform_jam_context):
		return

	var anchor_positions: Array[Vector2] = _get_active_freeform_anchor_positions()

	if anchor_positions.is_empty():
		return

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

		if not _is_npc_near_any_freeform_anchor(member, anchor_positions):
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


func _cleanup_freeform_context_if_no_freeform_members() -> void:
	var has_npc_member := false

	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		has_npc_member = true
		break

	if has_npc_member:
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	if player != null:
		if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
			if active_freeform_jam_context.has_method("detach_member_preserve_audio"):
				active_freeform_jam_context.detach_member_preserve_audio(player)

		if player.has_method("return_to_carried_solo_from_freeform"):
			if player != null and is_instance_valid(player):
				if "is_playing_instrument" in player and player.is_playing_instrument:
					if player.has_method("return_to_carried_solo_from_freeform"):
						player.return_to_carried_solo_from_freeform()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		active_freeform_jam_context.queue_free()

	active_freeform_jam_context = null
	active_freeform_leader = null
	active_freeform_anchor = null
	active_freeform_members.clear()

	current_nearby_jam_source = null
	current_nearby_jam_type = JAM_TYPE_NONE
	current_nearby_jam_name = "None"
	current_nearby_jam_distance = INF
	player_is_near_active_jam = false

	if music_system != null and music_system.has_method("set_player_near_active_jam"):
		music_system.set_player_near_active_jam(false)


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
		if player != null and is_instance_valid(player):
			if "is_playing_instrument" in player and player.is_playing_instrument:
				if player.has_method("return_to_carried_solo_from_freeform"):
					player.return_to_carried_solo_from_freeform()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		active_freeform_jam_context.queue_free()

	active_freeform_jam_context = null
	active_freeform_leader = null
	active_freeform_anchor = null
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
	_detach_player_from_freeform_if_too_far(player_position)


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

	if not "current_jam_context" in player:
		return

	# Critical guard:
	# Only detach the player if they are actually currently attached
	# to this active freeform context.
	if player.current_jam_context != active_freeform_jam_context:
		return

	# If the player is not tracked as a freeform member, do not detach them.
	if not active_freeform_members.has(player):
		return

	var freeform_info: Dictionary = _get_active_freeform_npc_info(player_position, true)

	# Still inside at least one active freeform NPC leave radius.
	if not freeform_info.is_empty():
		return

	# Player is outside the active freeform area.
	# Let the PLAYER own the detach-to-carried-solo transition.
	if player.has_method("detach_from_current_jam_to_carried_solo"):
		player.detach_from_current_jam_to_carried_solo()

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


func on_game_started() -> void:
	print("JamManager received game start.")


func _find_available_accompanists_near_position(center_position: Vector2, excluded_members: Array[Node] = []) -> Array[Node]:
	var found_npcs: Array[Node] = []

	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if not is_instance_valid(npc):
			continue

		if excluded_members.has(npc):
			continue

		if active_freeform_members.has(npc):
			continue

		if not npc.has_method("is_available_for_player_accompaniment"):
			continue

		if not npc.is_available_for_player_accompaniment():
			continue

		if not npc is Node2D:
			continue

		var npc_radius: float = _get_npc_join_radius(npc)
		var distance: float = center_position.distance_to(npc.global_position)

		if distance <= npc_radius:
			found_npcs.append(npc)

	return found_npcs


func _add_npc_to_active_freeform_jam(npc: Node, make_manual := false) -> bool:
	if npc == null:
		return false

	if active_freeform_jam_context == null:
		return false

	if not is_instance_valid(active_freeform_jam_context):
		return false

	if npc.has_method("set_current_jam_context"):
		npc.set_current_jam_context(active_freeform_jam_context)

	if active_freeform_jam_context.has_method("add_member"):
		active_freeform_jam_context.add_member(npc)

	_set_npc_freeform_request_on_context(npc, active_freeform_jam_context)

	var audio_source: Node = null

	if npc.has_method("get_current_audio_source"):
		audio_source = npc.get_current_audio_source()
	elif npc.has_method("get_jam_audio_source"):
		audio_source = npc.get_jam_audio_source()

	if audio_source != null:
		if audio_source.has_method("force_jam_control"):
			audio_source.force_jam_control()

		if audio_source.has_method("set_song_id"):
			if "song_id" in active_freeform_jam_context:
				audio_source.set_song_id(active_freeform_jam_context.song_id)

	if make_manual:
		if npc.has_method("start_manual_freeform"):
			npc.start_manual_freeform()
	else:
		if npc.has_method("start_auto_freeform"):
			npc.start_auto_freeform()

	if not active_freeform_members.has(npc):
		active_freeform_members.append(npc)

	if active_freeform_jam_context.has_method("set_member_active"):
		active_freeform_jam_context.set_member_active(npc, true)

	if active_freeform_jam_context.has_method("refresh_arrangement"):
		active_freeform_jam_context.refresh_arrangement()

	_refresh_freeform_leader()

	return true


func _refresh_freeform_leader() -> void:
	active_freeform_leader = null

	# Prefer manual NPCs as leaders.
	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if member.has_method("is_manual_freeform"):
			if member.is_manual_freeform():
				active_freeform_leader = member
				return

	# Then prefer player if present.
	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			active_freeform_leader = member
			return

	# Last fallback: any active NPC.
	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if not member.is_in_group("player"):
			active_freeform_leader = member
			return


func _get_active_manual_freeform_npcs() -> Array[Node]:
	var manual_npcs: Array[Node] = []

	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member.has_method("is_manual_freeform"):
			continue

		if member.is_manual_freeform():
			manual_npcs.append(member)

	return manual_npcs


func _stop_all_auto_freeform_followers() -> void:
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

		if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
			if active_freeform_jam_context.has_method("set_member_active"):
				active_freeform_jam_context.set_member_active(member, false)

		if member.has_method("stop_freeform_immediately"):
			member.stop_freeform_immediately()

		if active_freeform_members.has(member):
			active_freeform_members.erase(member)


func promote_auto_npc_to_manual(npc: Node) -> void:
	if npc == null:
		return

	if not active_freeform_members.has(npc):
		return

	if npc.has_method("start_manual_freeform"):
		npc.start_manual_freeform()
	else:
		if "freeform_mode" in npc:
			npc.freeform_mode = npc.FreeformMode.MANUAL

		if "music_control_mode" in npc:
			npc.music_control_mode = npc.MusicControlMode.FREEFORM_MANUAL

		if npc.has_method("set_actual_playing"):
			npc.set_actual_playing(true)

	_refresh_freeform_leader()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("refresh_arrangement"):
			active_freeform_jam_context.refresh_arrangement()


func toggle_manual_npc_off(npc: Node) -> void:
	if npc == null:
		return

	# First remove manual ownership from this NPC.
	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("set_member_active"):
			active_freeform_jam_context.set_member_active(npc, false)

	if active_freeform_members.has(npc):
		active_freeform_members.erase(npc)

	if npc.has_method("stop_freeform_immediately"):
		npc.stop_freeform_immediately()

	# If another manual NPC still anchors the jam, this NPC may fall back to AUTO
	# if they are still close enough to that active jam.
	var remaining_manual_npcs: Array[Node] = _get_active_manual_freeform_npcs()

	if remaining_manual_npcs.is_empty():
		if active_freeform_anchor == npc:
			active_freeform_anchor = null

		_stop_all_auto_freeform_followers()
		_cleanup_freeform_context_if_no_freeform_members()
		return

	active_freeform_anchor = remaining_manual_npcs[0]
	active_freeform_leader = remaining_manual_npcs[0]

	if _npc_should_rejoin_as_auto(npc):
		_add_npc_to_active_freeform_jam(npc, false)

	_refresh_freeform_leader()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("refresh_arrangement"):
			active_freeform_jam_context.refresh_arrangement()


func _npc_should_rejoin_as_auto(npc: Node) -> bool:
	if npc == null:
		return false

	if active_freeform_jam_context == null:
		return false

	if not is_instance_valid(active_freeform_jam_context):
		return false

	if not npc is Node2D:
		return false

	if not npc.has_method("is_available_for_player_accompaniment"):
		return false

	if not npc.is_available_for_player_accompaniment():
		return false

	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member == npc:
			continue

		if member.is_in_group("player"):
			continue

		if not member is Node2D:
			continue

		var radius: float = _get_npc_join_radius(member)
		var distance: float = npc.global_position.distance_to(member.global_position)

		if distance <= radius:
			return true

	return false


func try_add_manual_npc_to_nearby_jam(npc: Node) -> bool:
	if npc == null:
		return false

	if not npc is Node2D:
		return false

	var npc_position: Vector2 = npc.global_position

	# 1. Active JamSpot wins.
	var nearby_jam_spot: Dictionary = _find_best_active_jam_spot(npc_position)

	if not nearby_jam_spot.is_empty():
		var jam_spot: Node = nearby_jam_spot["source"]

		if jam_spot != null and is_instance_valid(jam_spot):
			if npc.has_method("reset_temporary_music_state_for_jam_join"):
				npc.reset_temporary_music_state_for_jam_join()

			if jam_spot.has_method("register_npc"):
				jam_spot.register_npc(npc)

			if jam_spot.has_method("refresh_npc_activity"):
				jam_spot.refresh_npc_activity(npc)

			return true

	# 2. Existing freeform jam nearby.
	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		var anchor: Node = active_freeform_anchor

		if anchor != null and is_instance_valid(anchor) and anchor is Node2D:
			var join_radius: float = _get_npc_join_radius(anchor)
			var distance: float = npc_position.distance_to(anchor.global_position)

			if distance <= join_radius:
				if npc.has_method("reset_temporary_music_state_for_jam_join"):
					npc.reset_temporary_music_state_for_jam_join()

				_add_npc_to_active_freeform_jam(npc, true)
				return true

	return false


func update_following_npc_jam_priorities() -> void:
	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if npc == null or not is_instance_valid(npc):
			continue

		if not npc.has_method("is_following_player"):
			continue

		if not npc.is_following_player():
			continue

		if not npc is Node2D:
			continue

		# Active JamSpot priority.
		var nearby_jam_spot: Dictionary = _find_best_active_jam_spot(npc.global_position)

		if not nearby_jam_spot.is_empty():
			var jam_spot: Node = nearby_jam_spot["source"]

			if jam_spot != null and is_instance_valid(jam_spot):
				if npc.has_method("is_controlled_by_active_jam_spot"):
					if npc.is_controlled_by_active_jam_spot():
						continue

				if npc.has_method("reset_temporary_music_state_for_jam_join"):
					npc.reset_temporary_music_state_for_jam_join()

				if jam_spot.has_method("register_npc"):
					jam_spot.register_npc(npc)

				if jam_spot.has_method("refresh_npc_activity"):
					jam_spot.refresh_npc_activity(npc)

				continue

		# Existing freeform jam priority.
		if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
			if active_freeform_members.has(npc):
				continue

			var anchor: Node = active_freeform_anchor

			if anchor != null and is_instance_valid(anchor) and anchor is Node2D:
				var join_radius: float = _get_npc_join_radius(anchor)
				var distance: float = npc.global_position.distance_to(anchor.global_position)

				if distance <= join_radius:
					if npc.has_method("reset_temporary_music_state_for_jam_join"):
						npc.reset_temporary_music_state_for_jam_join()

					_add_npc_to_active_freeform_jam(npc, false)


func _update_active_freeform_recruitment(delta: float) -> void:
	if active_freeform_jam_context == null:
		return

	if not is_instance_valid(active_freeform_jam_context):
		return

	freeform_recruit_scan_timer += delta

	if freeform_recruit_scan_timer < freeform_recruit_scan_interval:
		return

	freeform_recruit_scan_timer = 0.0

	_recruit_available_npcs_to_active_freeform_jam()


func _recruit_available_npcs_to_active_freeform_jam() -> void:
	if active_freeform_jam_context == null:
		return

	if not is_instance_valid(active_freeform_jam_context):
		return

	var anchor_positions: Array[Vector2] = _get_active_freeform_anchor_positions()

	if anchor_positions.is_empty():
		return

	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if npc == null or not is_instance_valid(npc):
			continue

		if active_freeform_members.has(npc):
			continue

		if not npc is Node2D:
			continue

		if not npc.has_method("is_available_for_player_accompaniment"):
			continue

		if not npc.is_available_for_player_accompaniment():
			continue

		# Active JamSpot always wins. Do not recruit NPCs who are currently
		# inside/controlled by an active JamSpot.
		if npc.has_method("is_controlled_by_active_jam_spot"):
			if npc.is_controlled_by_active_jam_spot():
				continue

		if _is_npc_near_any_freeform_anchor(npc, anchor_positions):
			_add_npc_to_active_freeform_jam(npc, false)


func _get_active_freeform_anchor_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []

	# Primary anchor first: player for player-led jams, NPC for NPC-led jams.
	if active_freeform_anchor != null and is_instance_valid(active_freeform_anchor):
		if active_freeform_anchor is Node2D:
			positions.append(active_freeform_anchor.global_position)

	# Any manual NPC also acts as a stable jam anchor.
	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member is Node2D:
			continue

		if member.has_method("is_manual_freeform"):
			if member.is_manual_freeform():
				if not positions.has(member.global_position):
					positions.append(member.global_position)

	# If player is actively part of the freeform jam, they can also recruit.
	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if not member.is_in_group("player"):
			continue

		if member is Node2D:
			if not positions.has(member.global_position):
				positions.append(member.global_position)

	return positions


func _is_npc_near_any_freeform_anchor(npc: Node, anchor_positions: Array[Vector2]) -> bool:
	if npc == null:
		return false

	if not npc is Node2D:
		return false

	for anchor_position in anchor_positions:
		var distance: float = npc.global_position.distance_to(anchor_position)

		if distance <= _get_npc_join_radius(npc):
			return true

	return false


func force_detach_player_from_freeform(player: Node) -> void:
	_debug_player_freeform("force_detach_player_from_freeform START")
	
	if player == null:
		return

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("set_member_active"):
			active_freeform_jam_context.set_member_active(player, false)

		if active_freeform_jam_context.has_method("clear_member_requested_part"):
			active_freeform_jam_context.clear_member_requested_part(player)

		if active_freeform_jam_context.has_method("detach_member_preserve_audio"):
			active_freeform_jam_context.detach_member_preserve_audio(player)

	if active_freeform_members.has(player):
		active_freeform_members.erase(player)

	if active_freeform_anchor == player:
		active_freeform_anchor = null

	if active_freeform_leader == player:
		_refresh_freeform_leader()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("refresh_arrangement"):
			active_freeform_jam_context.refresh_arrangement()

	_debug_player_freeform("force_detach_player_from_freeform END")

func _debug_player_freeform(message: String) -> void:
	if debug_player_freeform:
		print("[JAM_MANAGER_PLAYER] %s | freeform_context=%s anchor=%s leader=%s members=%s" % [
			message,
			str(active_freeform_jam_context),
			str(active_freeform_anchor),
			str(active_freeform_leader),
			str(active_freeform_members)
		])


func remove_player_from_freeform_members(player: Node, context: Node = null) -> void:
	if player == null:
		return

	if context != null:
		if not is_freeform_jam_context(context):
			return

	if active_freeform_members.has(player):
		active_freeform_members.erase(player)

	if active_freeform_anchor == player:
		active_freeform_anchor = null

	if active_freeform_leader == player:
		active_freeform_leader = null
		_refresh_freeform_leader()

	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		if active_freeform_jam_context.has_method("refresh_arrangement"):
			active_freeform_jam_context.refresh_arrangement()
