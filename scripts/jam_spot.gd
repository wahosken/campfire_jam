extends Node2D

@export var debug_jamspot := false

@export var jam_id := "campfire_jam"
@export var display_name := "Campfire Jam"
@export var song_id := "song_01"

@export var auto_start_on_ready := true
@export var leave_radius_padding := 50.0
@export var buffer_radius_padding := 150.0
@export var active_refresh_interval := 0.25

@onready var label: Label = $Label
@onready var jam_context: Node = $JamContext
@onready var jam_area: Area2D = $JamArea
@onready var jam_collision_shape: CollisionShape2D = $JamArea/CollisionShape2D
@onready var jam_spot_formation: Node = $JamSpotFormation

var active_refresh_timer := 0.0

var registered_npcs: Array[Node] = []
var jam_is_active := false


# ------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------

func _ready() -> void:
	add_to_group("jam_spot")

	if jam_spot_formation != null and jam_spot_formation.has_method("set_jam_spot"):
		jam_spot_formation.set_jam_spot(self)

	_connect_jam_area_signals()
	_sync_jam_context_song()
	_update_label()


func _process(delta: float) -> void:
	if not jam_is_active:
		return

	active_refresh_timer += delta

	if active_refresh_timer < active_refresh_interval:
		return

	active_refresh_timer = 0.0
	_rescan_and_refresh_active_jam()


func _connect_jam_area_signals() -> void:
	if jam_area == null:
		return

	if not jam_area.area_entered.is_connected(_on_jam_area_area_entered):
		jam_area.area_entered.connect(_on_jam_area_area_entered)

	if not jam_area.area_exited.is_connected(_on_jam_area_area_exited):
		jam_area.area_exited.connect(_on_jam_area_area_exited)

	if not jam_area.body_entered.is_connected(_on_jam_area_body_entered):
		jam_area.body_entered.connect(_on_jam_area_body_entered)

	if not jam_area.body_exited.is_connected(_on_jam_area_body_exited):
		jam_area.body_exited.connect(_on_jam_area_body_exited)


# ------------------------------------------------------------
# Public controls
# ------------------------------------------------------------

func start_if_auto_enabled() -> void:
	if auto_start_on_ready:
		start_jam()


func interact() -> void:
	toggle_jam()


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


func start_jam() -> void:
	if jam_is_active:
		return

	jam_is_active = true
	active_refresh_timer = 0.0

	_sync_jam_context_song()
	_rescan_npcs_inside_jam_area()
	refresh_all_npc_activity()
	_update_label()


func stop_jam() -> void:
	if not jam_is_active:
		return

	jam_is_active = false

	var player: Node = get_tree().get_first_node_in_group("player")

	if player != null:
		_release_player_from_stopped_jam_preserve_audio(player)

	var npcs_to_release: Array[Node] = registered_npcs.duplicate()

	for npc in npcs_to_release:
		_release_npc_from_stopped_jam(npc)

	registered_npcs.clear()
	_sync_jamspot_formation()

	# Do NOT use stop_all_members() here.
	# That can stop the player while they are holding play.
	if jam_context != null and jam_context.has_method("stop_all_non_player_members"):
		jam_context.stop_all_non_player_members()

	_update_label()


# ------------------------------------------------------------
# NPC registration
# ------------------------------------------------------------

func register_npc(npc: Node) -> void:
	if not _is_valid_npc(npc):
		return

	if not registered_npcs.has(npc):
		registered_npcs.append(npc)

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(self)

	if jam_is_active:
		call_deferred("refresh_all_npc_activity")
	else:
		refresh_npc_activity(npc)

	_sync_jamspot_formation()
	_update_label()


func unregister_npc(npc: Node) -> void:
	if npc == null:
		return

	if registered_npcs.has(npc):
		registered_npcs.erase(npc)

	var jam_manager: Node = get_tree().get_first_node_in_group("jam_manager")

	if jam_manager != null:
		if jam_manager.has_method("cancel_jamspot_handoff_for_npc"):
			jam_manager.cancel_jamspot_handoff_for_npc(npc)

	# Only end JamSpot control if the NPC was actually claimed by this JamSpot.
	# Pending handoff NPCs should NOT run end_jam_spot_control(), because they
	# may still be in a player-led freeform context.
	var should_end_jamspot_control := false

	if npc.has_method("is_controlled_by_jam_spot"):
		if npc.is_controlled_by_jam_spot():
			should_end_jamspot_control = true

	if should_end_jamspot_control:
		if npc.has_method("end_jam_spot_control"):
			npc.end_jam_spot_control(self)
		else:
			_fallback_release_npc(npc)
	else:
		# They were only pending/nearby, so just clear this JamSpot reference.
		if npc.has_method("set_current_jam_spot"):
			npc.set_current_jam_spot(null)

	_sync_jamspot_formation()
	_update_label()


func _rescan_npcs_inside_jam_area() -> void:
	registered_npcs.clear()

	if jam_area == null:
		return

	# Important:
	# Actual JamSpot ownership should use NPC body collision only,
	# not the larger InteractionArea.
	for body in jam_area.get_overlapping_bodies():
		if _is_valid_npc(body):
			register_npc(body)


func _rescan_and_refresh_active_jam() -> void:
	if not jam_is_active:
		return

	if jam_area == null:
		return

	var found_npcs: Array[Node] = _get_npcs_currently_inside_jam_area()

	# Add newly found NPCs.
	for npc in found_npcs:
		if not registered_npcs.has(npc):
			registered_npcs.append(npc)

		if npc.has_method("set_current_jam_spot"):
			npc.set_current_jam_spot(self)

	# Remove NPCs that are no longer actually inside the JamArea.
	for npc in registered_npcs.duplicate():
		if npc == null or not is_instance_valid(npc):
			registered_npcs.erase(npc)
			continue

		if not found_npcs.has(npc):
			unregister_npc(npc)

	# Refresh the whole group together.
	refresh_all_npc_activity()
	_update_label()


func _get_npcs_currently_inside_jam_area() -> Array[Node]:
	var found_npcs: Array[Node] = []

	if jam_area == null:
		return found_npcs

	# Important:
	# Actual JamSpot ownership should use NPC body collision only.
	for body in jam_area.get_overlapping_bodies():
		if _is_valid_npc(body):
			if not found_npcs.has(body):
				found_npcs.append(body)

	return found_npcs


# ------------------------------------------------------------
# NPC activity / fixed-area priority
# ------------------------------------------------------------

func refresh_all_npc_activity() -> void:
	for npc in registered_npcs.duplicate():
		refresh_npc_activity(npc)

	_sync_jamspot_formation()


func refresh_npc_activity(npc: Node) -> void:
	if not _is_valid_npc(npc):
		return

	if not npc.has_method("is_npc_enabled"):
		return

	var should_play: bool = jam_is_active and npc.is_npc_enabled()

	if not should_play:
		_handle_npc_should_not_play(npc)
		return

	_claim_npc_for_active_jam(npc)


func _handle_npc_should_not_play(npc: Node) -> void:
	if jam_context != null and jam_context.has_method("set_member_active"):
		jam_context.set_member_active(npc, false)

	if jam_is_active:
		_mark_npc_sitting_out(npc)
	else:
		_release_npc_from_inactive_jam(npc)


func _mark_npc_sitting_out(npc: Node) -> void:
	# JamSpot is still ON, but this NPC is sitting out.
	# Keep current_jam_spot intact so they can rejoin this same JamSpot.
	if npc.has_method("set_current_jam_context"):
		npc.set_current_jam_context(null)

	if npc.has_method("set_current_part"):
		npc.set_current_part("silent")

	if "wants_to_play" in npc:
		npc.wants_to_play = false

	if "wants_rhythm" in npc:
		npc.wants_rhythm = false

	if "wants_melody" in npc:
		npc.wants_melody = false


func _release_npc_from_inactive_jam(npc: Node) -> void:
	# JamSpot is OFF, so fully release JamSpot control.
	if npc.has_method("end_jam_spot_control"):
		npc.end_jam_spot_control(self)
	else:
		_fallback_release_npc(npc)


func _claim_npc_for_active_jam(npc: Node) -> void:
	# JamSpot is active and NPC is enabled, so JamSpot takes priority.
	# Any freeform/manual state should reset before the fixed JamSpot controls it.

	if _npc_is_already_claimed_by_this_jam(npc):
		_request_npc_both_parts(npc)

		if jam_context != null and jam_context.has_method("set_member_active"):
			jam_context.set_member_active(npc, true)

		return

	var jam_manager: Node = get_tree().get_first_node_in_group("jam_manager")

	if jam_manager != null:
		if jam_manager.has_method("request_jamspot_handoff_if_needed"):
			var handoff_started: bool = jam_manager.request_jamspot_handoff_if_needed(npc, self)

			if handoff_started:
				return

		if jam_manager.has_method("remove_npc_from_freeform_members_for_jamspot"):
			jam_manager.remove_npc_from_freeform_members_for_jamspot(npc)

	if npc.has_method("reset_temporary_music_state_for_jam_join"):
		npc.reset_temporary_music_state_for_jam_join()

	if npc.has_method("begin_jam_spot_control"):
		npc.begin_jam_spot_control(self, jam_context)
	else:
		if npc.has_method("set_current_jam_spot"):
			npc.set_current_jam_spot(self)

		if npc.has_method("set_current_jam_context"):
			npc.set_current_jam_context(jam_context)

	_request_npc_both_parts(npc)

	if "wants_to_play" in npc:
		npc.wants_to_play = true

	if "wants_rhythm" in npc:
		npc.wants_rhythm = true

	if "wants_melody" in npc:
		npc.wants_melody = true

	if jam_context != null and jam_context.has_method("set_member_active"):
		jam_context.set_member_active(npc, true)


func _request_npc_both_parts(npc: Node) -> void:
	if jam_context == null:
		return

	if jam_context.has_method("add_member"):
		jam_context.add_member(npc)

	if jam_context.has_method("set_member_requested_parts"):
		jam_context.set_member_requested_parts(npc, true, true)
	elif jam_context.has_method("set_member_requested_part"):
		jam_context.set_member_requested_part(npc, "both")


func _release_npc_from_stopped_jam(npc: Node) -> void:
	if npc == null or not is_instance_valid(npc):
		return

	if jam_context != null and jam_context.has_method("set_member_active"):
		jam_context.set_member_active(npc, false)

	if npc.has_method("end_jam_spot_control"):
		npc.end_jam_spot_control(self)
	else:
		_fallback_release_npc(npc)

	# Reset availability only.
	# Do not call set_npc_enabled(true), because that can restart music.
	if "npc_enabled" in npc:
		npc.npc_enabled = true

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(null)


func _release_player_from_stopped_jam_preserve_audio(player: Node) -> void:
	if player == null or not is_instance_valid(player):
		return

	if not player.is_in_group("player"):
		return

	var player_is_playing := false

	if "is_playing_instrument" in player:
		player_is_playing = player.is_playing_instrument

	if player_is_playing:
		# Remove from JamContext without stopping the player's audio.
		if jam_context != null and is_instance_valid(jam_context):
			if jam_context.has_method("detach_member_preserve_audio"):
				jam_context.detach_member_preserve_audio(player)
			else:
				if jam_context.has_method("clear_member_requested_part"):
					jam_context.clear_member_requested_part(player)

				if jam_context.has_method("set_member_active"):
					# Avoid this if possible because it may stop player audio.
					pass

		if player.has_method("detach_from_current_jam_to_carried_solo"):
			player.detach_from_current_jam_to_carried_solo()

		return

	# If player is not actively holding play, normal cleanup is fine.
	if jam_context != null and is_instance_valid(jam_context):
		if jam_context.has_method("set_member_active"):
			jam_context.set_member_active(player, false)


func _fallback_release_npc(npc: Node) -> void:
	if jam_context != null and jam_context.has_method("set_member_active"):
		jam_context.set_member_active(npc, false)

	if npc.has_method("set_current_jam_context"):
		npc.set_current_jam_context(null)

	if npc.has_method("set_current_jam_spot"):
		npc.set_current_jam_spot(null)

	if npc.has_method("set_current_part"):
		npc.set_current_part("silent")

	var source: Node = _get_npc_audio_source(npc)

	if source != null:
		if source.has_method("stop_all"):
			source.stop_all()
		elif source.has_method("stop_solo_jam"):
			source.stop_solo_jam()


func _get_npc_audio_source(npc: Node) -> Node:
	if npc == null:
		return null

	if npc.has_method("get_current_audio_source"):
		return npc.get_current_audio_source()

	if npc.has_method("get_jam_audio_source"):
		return npc.get_jam_audio_source()

	return null


func _sync_jamspot_formation() -> void:
	if jam_spot_formation == null:
		return

	if not jam_is_active:
		if jam_spot_formation.has_method("clear"):
			jam_spot_formation.clear()

		return

	var formation_members: Array[Node] = []

	for npc in registered_npcs:
		if npc == null or not is_instance_valid(npc):
			continue

		if not npc.is_in_group("musician"):
			continue

		if not npc is Node2D:
			continue

		if npc.has_method("is_following_player"):
			if npc.is_following_player():
				continue

		formation_members.append(npc)

	if jam_spot_formation.has_method("set_members"):
		jam_spot_formation.set_members(formation_members)


# ------------------------------------------------------------
# Jam area callbacks
# ------------------------------------------------------------

func _on_jam_area_area_entered(_area: Area2D) -> void:
	# Do not register NPCs through InteractionArea.
	# Actual JamSpot ownership uses body_entered/body_exited only.
	pass


func _on_jam_area_area_exited(_area: Area2D) -> void:
	# Do not unregister NPCs through InteractionArea.
	pass


func _on_jam_area_body_entered(body: Node) -> void:
	_try_register_possible_npc(body)


func _on_jam_area_body_exited(body: Node) -> void:
	_try_unregister_possible_npc(body)


func _try_register_possible_npc(node: Node) -> void:
	if not jam_is_active:
		return

	if not _is_valid_npc(node):
		return

	register_npc(node)


func _try_unregister_possible_npc(node: Node) -> void:
	if not _is_valid_npc(node):
		return

	if registered_npcs.has(node):
		unregister_npc(node)


func _npc_is_already_claimed_by_this_jam(npc: Node) -> bool:
	if npc == null or not is_instance_valid(npc):
		return false

	if not "current_jam_spot" in npc:
		return false

	if npc.current_jam_spot != self:
		return false

	if not npc.has_method("is_controlled_by_jam_spot"):
		return false

	return npc.is_controlled_by_jam_spot()



# ------------------------------------------------------------
# Radius helpers
# ------------------------------------------------------------

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


func get_buffer_radius() -> float:
	return get_join_radius() + buffer_radius_padding


func is_position_inside_buffer_radius(world_position: Vector2) -> bool:
	return global_position.distance_to(world_position) <= get_buffer_radius()


# ------------------------------------------------------------
# Queries
# ------------------------------------------------------------

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


# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

func _sync_jam_context_song() -> void:
	if jam_context == null:
		return

	if jam_context.has_method("apply_song_id"):
		jam_context.apply_song_id(song_id)
	elif "song_id" in jam_context:
		jam_context.song_id = song_id


func _is_valid_npc(node: Node) -> bool:
	if node == null:
		return false

	if not is_instance_valid(node):
		return false

	return node.is_in_group("npc_musician")


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


func _debug_spot(message: String) -> void:
	if debug_jamspot:
		print("[%s] %s | active=%s registered=%d" % [
			name,
			message,
			str(jam_is_active),
			registered_npcs.size()
		])
