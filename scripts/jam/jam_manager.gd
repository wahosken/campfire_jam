# ------------------------------------------------------------
# JamManager
#
# High-level coordinator for:
# - freeform jam creation/destruction
# - jam ownership arbitration
# - player/NPC jam transitions
# - freeform recruitment
# - jamspot handoffs
# - nearby jam queries
#
# Does NOT own:
# - audio playback logic
# - arrangement logic
# - stem synchronization
# - musician movement implementation
#
# Long-term direction:
# - shrink toward coordinator/registry role
# - move freeform runtime state into specialized jam objects
# - become more event-driven over time
# ------------------------------------------------------------

extends Node

signal nearby_jam_changed(jam_source: Node, jam_type: String, jam_name: String)

# ------------------------------------------------------------
# References / configuration
# ------------------------------------------------------------

@onready var jam_formation: Node = $JamFormation

@export var debug_player_freeform := false

@export var fallback_accompanist_radius := 100.0
@export var freeform_leave_padding := 50.0
@export var freeform_player_leave_padding := 50.0
@export var freeform_jam_context_scene: PackedScene
@export var freeform_recruit_scan_interval := 0.25

# Auto-join behavior:
# Any auto-joining NPC enters the jam immediately as "waiting",
# then becomes audible after this delay.
# Later, this can be replaced by equip-instrument animation duration + small global pad.
@export var auto_freeform_join_delay := 2.5

# Once an auto NPC finishes the join delay, they can immediately expand the bubble.
# Keep this at 0.0 because auto_freeform_join_delay now handles the "getting ready" time.
@export var auto_freeform_anchor_delay := 0.0

@export var enable_npc_led_freeform_chains := true
@export var enable_player_led_freeform_chains := true

@export var jamspot_handoff_delay := 0.35

@export var player_stationary_jam_delay := 0.45
@export var player_stationary_speed_threshold := 8.0

const JAM_TYPE_NONE := "none"
const JAM_TYPE_JAM_SPOT := "jam_spot"
const JAM_TYPE_MUSICIAN := "musician"
const JAM_TYPE_PLAYER_FREEFORM := "player_freeform"

# ------------------------------------------------------------
# Runtime state
# ------------------------------------------------------------

var freeform_recruit_scan_timer := 0.0

var freeform_state := FreeformJamState.new()

var music_system: Node = null

var player_is_near_active_jam := false

var current_nearby_jam_source: Node = null
var current_nearby_jam_type := JAM_TYPE_NONE
var current_nearby_jam_name := "None"
var current_nearby_jam_distance := INF

var player_stationary_timer := 0.0
var player_was_stationary_for_jam := false

# ------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------

func _ready() -> void:
	add_to_group("jam_manager")

	music_system = get_tree().get_first_node_in_group("music_system")


func _process(delta: float) -> void:
	update_following_npc_jam_priorities()
	_update_pending_freeform_auto_joins(delta)
	_update_pending_jamspot_handoffs(delta)
	_update_active_freeform_recruitment(delta)
	_update_active_jam_formation_targets(delta)
	_refresh_player_led_auto_follower_requests()

	var player: Node = get_tree().get_first_node_in_group("player")

	if player != null and player is Node2D:
		_check_auto_freeform_leave(player.global_position)


# ------------------------------------------------------------
# Player nearby jam state
# ------------------------------------------------------------

func update_player_jam_proximity(player_position: Vector2) -> void:
	_check_auto_freeform_leave(player_position)

	# JamSpot always has priority over freeform.
	var nearby_jam_spot: Dictionary = _find_best_active_jam_spot(player_position)

	if not nearby_jam_spot.is_empty():
		_set_current_nearby_jam(
			nearby_jam_spot["source"],
			JAM_TYPE_JAM_SPOT,
			nearby_jam_spot["name"],
			nearby_jam_spot["distance"],
			true
		)

		return

	# Only detach from freeform after we know no JamSpot currently owns the player area.
	_detach_player_from_freeform_if_too_far(player_position)

	var nearby_freeform: Dictionary = _find_best_active_musician(player_position)

	if not nearby_freeform.is_empty():
		_set_current_nearby_jam(
			nearby_freeform["source"],
			JAM_TYPE_MUSICIAN,
			nearby_freeform["name"],
			nearby_freeform["distance"],
			true
		)

		return

	_clear_current_nearby_jam()


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
	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if _is_player_near_any_freeform_anchor(player_position):
			return freeform_state.jam_context

	return null


func get_current_nearby_jam_source() -> Node:
	return current_nearby_jam_source


func get_current_nearby_jam_type() -> String:
	return current_nearby_jam_type


func get_current_nearby_jam_name() -> String:
	return current_nearby_jam_name


func get_current_nearby_jam_distance() -> float:
	return current_nearby_jam_distance


func get_player_jam_label_text() -> String:
	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		return "Current Jam: None"

	if not player is Node2D:
		return "Current Jam: None"

	var player_position: Vector2 = player.global_position

	# Authoritative JamSpot check.
	var nearby_jam_spot: Dictionary = _find_best_active_jam_spot(player_position)

	if not nearby_jam_spot.is_empty():
		return "Current Jam: %s" % str(nearby_jam_spot["name"])

	var freeform_info: Dictionary = _get_active_freeform_npc_info(player_position, true)

	if not freeform_info.is_empty():
		return "Current Jam: %s" % get_freeform_leader_text()

	if "is_playing_direct_solo" in player:
		if player.is_playing_direct_solo:
			return "Current Jam: Player Solo"

	return "Current Jam: None"


func get_nearby_jam_debug_text() -> String:
	if current_nearby_jam_source == null:
		return "Nearby Jam: None"

	return "Nearby Jam: %s (%s)" % [
		current_nearby_jam_name,
		current_nearby_jam_type
	]


func _set_current_nearby_jam(
	jam_source: Node,
	jam_type: String,
	jam_name: String,
	jam_distance: float,
	is_near_active_jam: bool
) -> void:
	var source_changed := jam_source != current_nearby_jam_source
	var type_changed := jam_type != current_nearby_jam_type
	var name_changed := jam_name != current_nearby_jam_name
	var near_state_changed := is_near_active_jam != player_is_near_active_jam

	current_nearby_jam_source = jam_source
	current_nearby_jam_type = jam_type
	current_nearby_jam_name = jam_name
	current_nearby_jam_distance = jam_distance
	player_is_near_active_jam = is_near_active_jam

	if music_system != null and music_system.has_method("set_player_near_active_jam"):
		music_system.set_player_near_active_jam(player_is_near_active_jam)

	if source_changed or type_changed or name_changed or near_state_changed:
		nearby_jam_changed.emit(
			current_nearby_jam_source,
			current_nearby_jam_type,
			current_nearby_jam_name
		)


func _clear_current_nearby_jam() -> void:
	_set_current_nearby_jam(
		null,
		JAM_TYPE_NONE,
		"None",
		INF,
		false
	)


# ------------------------------------------------------------
# Player freeform transitions
# ------------------------------------------------------------

func try_recruit_nearby_npcs_to_player(player: Node, player_position: Vector2) -> void:
	_debug_player_freeform("try_recruit_nearby_npcs_to_player START player_playing=" + str(player.is_playing_instrument if "is_playing_instrument" in player else "unknown"))

	if player == null:
		return

	if not "is_playing_instrument" in player:
		return

	if not player.is_playing_instrument:
		return

	# Actual JamSpot owns the player while inside it.
	# Buffer alone should not block recruitment/following.
	if _is_position_inside_active_jamspot(player_position):
		return

	var nearby_npcs: Array[Node] = _find_available_accompanists_near_position(player_position, [player])

	if nearby_npcs.is_empty():
		return

	_debug_player_freeform("try_recruit_nearby_npcs_to_player attaching NPCs")

	if freeform_state.jam_context == null or not is_instance_valid(freeform_state.jam_context):
		_create_player_carried_freeform_context(player)

	if freeform_state.jam_context == null:
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

	_set_current_nearby_jam(
		closest_npc,
		JAM_TYPE_PLAYER_FREEFORM,
		get_freeform_leader_text(),
		closest_distance,
		true
	)


func add_player_to_active_freeform(player: Node) -> void:

	if player == null:
		return

	if freeform_state.jam_context == null:
		return

	if not freeform_state.members.has(player):

		freeform_state.members.append(player)
		_record_freeform_member_join_time(player)


func _create_player_carried_freeform_context(player: Node) -> void:
	_debug_player_freeform("_create_player_carried_freeform_context START")

	if player == null:
		return

	if freeform_jam_context_scene == null:
		push_warning("JamManager is missing freeform_jam_context_scene.")
		return

	freeform_state.jam_context = freeform_jam_context_scene.instantiate()
	add_child(freeform_state.jam_context)

	freeform_state.leader = player
	freeform_state.anchor = player

	freeform_state.members.clear()
	freeform_state.member_join_times.clear()
	freeform_state.pending_auto_joins.clear()

	freeform_state.members.append(player)
	_record_freeform_member_join_time(player)

	var player_song_id := "song_01"

	if player.has_method("get_current_playing_song_id"):
		player_song_id = player.get_current_playing_song_id()
	elif player.has_method("get_selected_song_id"):
		player_song_id = player.get_selected_song_id()

	if freeform_state.jam_context.has_method("apply_song_id"):
		freeform_state.jam_context.apply_song_id(player_song_id)
	elif "song_id" in freeform_state.jam_context:
		freeform_state.jam_context.song_id = player_song_id

	if freeform_state.jam_context.has_method("add_member"):
		freeform_state.jam_context.add_member(player)

	if freeform_state.jam_context.has_method("start_from_existing_member"):
		freeform_state.jam_context.start_from_existing_member(player)

	_set_player_request_on_context(player, freeform_state.jam_context)

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

	if freeform_state.jam_context.has_method("set_member_active"):
		freeform_state.jam_context.set_member_active(player, true)

	if player.has_method("mark_as_freeform_jam_context"):
		player.mark_as_freeform_jam_context(freeform_state.jam_context)

	_debug_player_freeform("_create_player_carried_freeform_context END")


func handle_player_stopped_playing(previous_context: Node) -> void:
	_debug_player_freeform("handle_player_stopped_playing START previous_context=" + str(previous_context))

	reset_all_auto_blocks()

	# If the player stops while JamManager is preserving a player-led freeform
	# follower group, shut that group down.
	if _is_player_led_freeform():
		stop_all_auto_freeform_npcs()
		_cleanup_freeform_context_if_only_player_left(false)

	if previous_context == null:
		return

	if not is_freeform_jam_context(previous_context):
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if player != null:
			if freeform_state.jam_context.has_method("set_member_active"):
				freeform_state.jam_context.set_member_active(player, false)

			if freeform_state.members.has(player):
				freeform_state.members.erase(player)

			_clear_freeform_member_join_time(player)

	if freeform_state.anchor != null:
		if is_instance_valid(freeform_state.anchor):
			if freeform_state.anchor != player:
				_refresh_freeform_leader()

				if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
					if freeform_state.jam_context.has_method("refresh_arrangement"):
						freeform_state.jam_context.refresh_arrangement()

				return

	var remaining_manual_npcs: Array[Node] = _get_active_manual_freeform_npcs()

	if not remaining_manual_npcs.is_empty():
		freeform_state.anchor = remaining_manual_npcs[0]
		freeform_state.leader = remaining_manual_npcs[0]

		if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
			if freeform_state.jam_context.has_method("refresh_arrangement"):
				freeform_state.jam_context.refresh_arrangement()

		return

	stop_all_auto_freeform_npcs()
	_cleanup_freeform_context_if_only_player_left(false)

	_debug_player_freeform("handle_player_stopped_playing END")


func detach_player_from_freeform_if_too_far(player_position: Vector2) -> void:
	_detach_player_from_freeform_if_too_far(player_position)


func _detach_player_from_freeform_if_too_far(player_position: Vector2) -> void:
	if freeform_state.jam_context == null:
		return

	if not is_instance_valid(freeform_state.jam_context):
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		return

	if not player is Node2D:
		return

	if not "current_jam_context" in player:
		return

	if player.current_jam_context != freeform_state.jam_context:
		return

	if not freeform_state.members.has(player):
		return

	var freeform_info: Dictionary = _get_active_freeform_npc_info(player_position, true)

	if not freeform_info.is_empty():
		return

	if player.has_method("detach_from_current_jam_to_carried_solo"):
		player.detach_from_current_jam_to_carried_solo()

	_clear_current_nearby_jam()


func remove_player_from_freeform_members(player: Node, context: Node = null) -> void:
	if player == null:
		return

	var was_active_freeform_context := false

	if context != null:
		if not is_freeform_jam_context(context):
			return

		was_active_freeform_context = context == freeform_state.jam_context
	else:
		was_active_freeform_context = true

	if freeform_state.members.has(player):
		freeform_state.members.erase(player)

	_clear_freeform_member_join_time(player)

	if freeform_state.anchor == player:
		freeform_state.anchor = null

	if freeform_state.leader == player:
		freeform_state.leader = null

	_refresh_freeform_leader()

	if was_active_freeform_context:
		var remaining_manual_npcs: Array[Node] = _get_active_manual_freeform_npcs()

		if remaining_manual_npcs.is_empty():
			if _player_is_still_playing() and _has_auto_freeform_followers():
				freeform_state.anchor = player
				freeform_state.leader = player

				_sync_jam_formation_to_active_freeform()
				_refresh_player_led_auto_follower_requests()

				return

			_stop_all_auto_freeform_followers()
			_cleanup_freeform_context_if_no_freeform_members(false)
			return

		freeform_state.anchor = remaining_manual_npcs[0]
		freeform_state.leader = remaining_manual_npcs[0]

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("refresh_arrangement"):
			freeform_state.jam_context.refresh_arrangement()


func _player_should_use_precise_freeform_slots(delta: float) -> bool:
	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		player_stationary_timer = 0.0
		player_was_stationary_for_jam = false
		return false

	if not player is CharacterBody2D:
		player_stationary_timer = 0.0
		player_was_stationary_for_jam = false
		return false

	if not _is_player_led_freeform():
		player_stationary_timer = 0.0
		player_was_stationary_for_jam = false
		return false

	if not "is_playing_instrument" in player:
		player_stationary_timer = 0.0
		player_was_stationary_for_jam = false
		return false

	if not player.is_playing_instrument:
		player_stationary_timer = 0.0
		player_was_stationary_for_jam = false
		return false

	var speed: float = player.velocity.length()

	if speed <= player_stationary_speed_threshold:
		player_stationary_timer += delta
	else:
		player_stationary_timer = 0.0

	player_was_stationary_for_jam = player_stationary_timer >= player_stationary_jam_delay

	return player_was_stationary_for_jam


# ------------------------------------------------------------
# NPC freeform controls
# ------------------------------------------------------------

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

	if player != null and player_is_playing:
		if player.has_method("get_current_playing_song_id"):
			freeform_song_id = player.get_current_playing_song_id()
		elif player.has_method("get_selected_song_id"):
			freeform_song_id = player.get_selected_song_id()

		if freeform_state.jam_context == null or not is_instance_valid(freeform_state.jam_context):
			_create_player_carried_freeform_context(player)
	else:
		if npc.has_method("get_primary_song_id"):
			freeform_song_id = npc.get_primary_song_id()

		if freeform_state.jam_context == null or not is_instance_valid(freeform_state.jam_context):
			if freeform_jam_context_scene == null:
				npc.start_manual_freeform()
				return true

			freeform_state.jam_context = freeform_jam_context_scene.instantiate()
			add_child(freeform_state.jam_context)

			freeform_state.members.clear()
			freeform_state.member_join_times.clear()
			freeform_state.pending_auto_joins.clear()

			freeform_state.leader = npc
			freeform_state.anchor = npc

			if freeform_state.jam_context.has_method("apply_song_id"):
				freeform_state.jam_context.apply_song_id(freeform_song_id)
			elif "song_id" in freeform_state.jam_context:
				freeform_state.jam_context.song_id = freeform_song_id

	if freeform_state.jam_context == null:
		return false

	if freeform_state.jam_context.has_method("apply_song_id"):
		freeform_state.jam_context.apply_song_id(freeform_song_id)
	elif "song_id" in freeform_state.jam_context:
		freeform_state.jam_context.song_id = freeform_song_id

	_add_npc_to_active_freeform_jam(npc, true)

	if not player_is_playing:
		freeform_state.anchor = npc
		freeform_state.leader = npc

	var nearby_npcs: Array[Node] = _find_available_accompanists_near_position(npc.global_position, [npc])

	for nearby_npc in nearby_npcs:
		_add_npc_to_active_freeform_jam(nearby_npc, false)

	var manual_distance := 0.0

	if player != null and player is Node2D:
		manual_distance = player.global_position.distance_to(npc.global_position)

	_set_current_nearby_jam(
		npc,
		JAM_TYPE_PLAYER_FREEFORM,
		get_freeform_leader_text(),
		manual_distance,
		true
	)

	return true


func stop_auto_freeform_for_npc(npc: Node) -> void:
	if npc == null:
		return

	if freeform_state.pending_jamspot_handoffs.has(npc):
		freeform_state.pending_jamspot_handoffs.erase(npc)

	_clear_pending_freeform_auto_join(npc)

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("set_member_active"):
			freeform_state.jam_context.set_member_active(npc, false)

	if npc.has_method("stop_freeform_immediately"):
		npc.stop_freeform_immediately()

	if freeform_state.members.has(npc):
		freeform_state.members.erase(npc)

	_clear_freeform_member_join_time(npc)

	_cleanup_freeform_context_if_only_player_left()
	_sync_jam_formation_to_active_freeform()


func stop_manual_freeform_for_npc(npc: Node) -> void:
	if npc == null:
		return

	_clear_pending_freeform_auto_join(npc)

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("set_member_active"):
			freeform_state.jam_context.set_member_active(npc, false)

	if npc.has_method("stop_freeform_immediately"):
		npc.stop_freeform_immediately()

	if freeform_state.members.has(npc):
		freeform_state.members.erase(npc)

	_clear_freeform_member_join_time(npc)

	var remaining_manual_npcs: Array[Node] = _get_active_manual_freeform_npcs()

	if remaining_manual_npcs.is_empty():
		_stop_all_auto_freeform_followers()
	else:
		freeform_state.leader = remaining_manual_npcs[0]

	_refresh_freeform_leader()

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("refresh_arrangement"):
			freeform_state.jam_context.refresh_arrangement()

	_sync_jam_formation_to_active_freeform()
	_cleanup_freeform_context_if_no_freeform_members()


func request_jamspot_handoff_if_needed(npc: Node, jam_spot: Node) -> bool:
	if npc == null:
		return false

	if jam_spot == null or not is_instance_valid(jam_spot):
		return false

	# Manual follow is the player override.
	if npc.has_method("is_following_player"):
		if npc.is_following_player():
			return false

	# Already in handoff. Tell JamSpot "do not claim yet."
	if freeform_state.pending_jamspot_handoffs.has(npc):
		return true

	# Only delay auto freeform followers.
	if not npc.has_method("is_auto_freeform"):
		return false

	if not npc.is_auto_freeform():
		return false

	if not freeform_state.members.has(npc):
		return false

	_queue_jamspot_handoff(npc, jam_spot)
	return true



func stop_all_auto_freeform_npcs() -> void:
	var members_to_check: Array[Node] = freeform_state.members.duplicate()

	for member in members_to_check:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if member.has_method("is_auto_freeform"):
			if member.is_auto_freeform():
				stop_auto_freeform_for_npc(member)

	_cleanup_freeform_context_if_only_player_left()


func promote_auto_npc_to_manual(npc: Node) -> void:
	if npc == null:
		return

	_clear_pending_freeform_auto_join(npc)

	if not freeform_state.members.has(npc):
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

	_record_freeform_member_join_time(npc)

	_set_npc_freeform_request_on_context(npc, freeform_state.jam_context)

	_refresh_freeform_leader()

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("refresh_arrangement"):
			freeform_state.jam_context.refresh_arrangement()


func toggle_manual_npc_off(npc: Node) -> void:
	if npc == null:
		return

	_clear_pending_freeform_auto_join(npc)

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("set_member_active"):
			freeform_state.jam_context.set_member_active(npc, false)

	if freeform_state.members.has(npc):
		freeform_state.members.erase(npc)

	_clear_freeform_member_join_time(npc)

	if npc.has_method("stop_freeform_immediately"):
		npc.stop_freeform_immediately()

	var remaining_manual_npcs: Array[Node] = _get_active_manual_freeform_npcs()

	if remaining_manual_npcs.is_empty():
		if freeform_state.anchor == npc:
			freeform_state.anchor = null

		_stop_all_auto_freeform_followers()
		_cleanup_freeform_context_if_no_freeform_members()
		return

	freeform_state.anchor = remaining_manual_npcs[0]
	freeform_state.leader = remaining_manual_npcs[0]

	if _npc_should_rejoin_as_auto(npc):
		_add_npc_to_active_freeform_jam(npc, false)

	_refresh_freeform_leader()

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("refresh_arrangement"):
			freeform_state.jam_context.refresh_arrangement()


func try_add_manual_npc_to_nearby_jam(npc: Node) -> bool:
	if npc == null:
		return false

	if not npc is Node2D:
		return false

	var npc_position: Vector2 = npc.global_position

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

	if _is_position_inside_active_jamspot_buffer(npc_position):
		return true

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		var anchor: Node = freeform_state.anchor

		if anchor != null and is_instance_valid(anchor) and anchor is Node2D:
			var join_radius: float = _get_npc_join_radius(anchor)
			var distance: float = npc_position.distance_to(anchor.global_position)

			if distance <= join_radius:
				if npc.has_method("reset_temporary_music_state_for_jam_join"):
					npc.reset_temporary_music_state_for_jam_join()

				_add_npc_to_active_freeform_jam(npc, true)
				return true

	return false


func _player_is_still_playing() -> bool:
	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		return false

	if not "is_playing_instrument" in player:
		return false

	return player.is_playing_instrument


func _has_auto_freeform_followers() -> bool:
	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member.has_method("is_auto_freeform"):
			continue

		if member.is_auto_freeform():
			return true

	return false


# ------------------------------------------------------------
# Freeform recruitment
# ------------------------------------------------------------

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

		if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
			if freeform_state.members.has(npc):
				continue

			var anchor: Node = freeform_state.anchor

			if anchor != null and is_instance_valid(anchor) and anchor is Node2D:
				var join_radius: float = _get_npc_join_radius(anchor)
				var distance: float = npc.global_position.distance_to(anchor.global_position)

				if distance <= join_radius:
					_add_npc_to_active_freeform_jam(npc, false)


func _update_active_freeform_recruitment(delta: float) -> void:
	if freeform_state.jam_context == null:
		return

	if not is_instance_valid(freeform_state.jam_context):
		return

	freeform_recruit_scan_timer += delta

	if freeform_recruit_scan_timer < freeform_recruit_scan_interval:
		return

	freeform_recruit_scan_timer = 0.0

	_recruit_available_npcs_to_active_freeform_jam()


func _recruit_available_npcs_to_active_freeform_jam() -> void:
	if freeform_state.jam_context == null:
		return

	if not is_instance_valid(freeform_state.jam_context):
		return

	var anchor_positions: Array[Vector2] = _get_freeform_recruitment_anchor_positions()

	_debug_player_freeform(
		"recruit anchors=%d delayed=%d pending=%d player_led=%s npc_led=%s" % [
			anchor_positions.size(),
			_get_delayed_auto_freeform_anchor_positions().size(),
			freeform_state.pending_auto_joins.size(),
			str(_is_player_led_freeform()),
			str(_is_npc_led_freeform())
		]
	)

	if anchor_positions.is_empty():
		return

	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if npc == null or not is_instance_valid(npc):
			continue

		if freeform_state.members.has(npc):
			continue

		if not npc is Node2D:
			continue

		if not npc.has_method("is_available_for_player_accompaniment"):
			continue

		if not npc.is_available_for_player_accompaniment():
			continue

		if npc.has_method("is_controlled_by_active_jam_spot"):
			if npc.is_controlled_by_active_jam_spot():
				continue

		if _get_active_jamspot_containing_position(npc.global_position) != null:
			continue

		if _is_npc_near_any_freeform_anchor(npc, anchor_positions):
			_add_npc_to_active_freeform_jam(npc, false)

func _add_npc_to_active_freeform_jam(npc: Node, make_manual := false) -> bool:
	if npc == null:
		return false

	if freeform_state.jam_context == null:
		return false

	if not is_instance_valid(freeform_state.jam_context):
		return false

	if not npc is Node2D:
		return false

	if _is_position_inside_active_jamspot(npc.global_position):
		return false

	var already_member := freeform_state.members.has(npc)

	if npc.has_method("set_current_jam_context"):
		npc.set_current_jam_context(freeform_state.jam_context)

	if freeform_state.jam_context.has_method("add_member"):
		freeform_state.jam_context.add_member(npc)

	var audio_source: Node = null

	if npc.has_method("get_current_audio_source"):
		audio_source = npc.get_current_audio_source()
	elif npc.has_method("get_jam_audio_source"):
		audio_source = npc.get_jam_audio_source()

	if audio_source != null:
		if audio_source.has_method("force_jam_control"):
			audio_source.force_jam_control()

		if audio_source.has_method("set_song_id"):
			if "song_id" in freeform_state.jam_context:
				audio_source.set_song_id(freeform_state.jam_context.song_id)

	if make_manual:
		_clear_pending_freeform_auto_join(npc)

		if npc.has_method("start_manual_freeform"):
			npc.start_manual_freeform()

		if not already_member:
			freeform_state.members.append(npc)

		_record_freeform_member_join_time(npc)
		_set_npc_freeform_request_on_context(npc, freeform_state.jam_context)
	else:
		if npc.has_method("start_auto_freeform"):
			npc.start_auto_freeform()

		if not already_member:
			freeform_state.members.append(npc)

		# Auto NPCs are real members immediately, but are silent/waiting
		# until the join/equip delay finishes.
		_set_auto_npc_waiting_for_join(npc)

		if not freeform_state.pending_auto_joins.has(npc):
			freeform_state.pending_auto_joins[npc] = auto_freeform_join_delay

	if freeform_state.jam_context.has_method("set_member_active"):
		freeform_state.jam_context.set_member_active(npc, true)

	if freeform_state.jam_context.has_method("refresh_arrangement"):
		freeform_state.jam_context.refresh_arrangement()

	_refresh_freeform_leader()
	_sync_jam_formation_to_active_freeform()

	return true


func _set_auto_npc_waiting_for_join(npc: Node) -> void:
	if npc == null:
		return

	if freeform_state.jam_context == null:
		return

	if not is_instance_valid(freeform_state.jam_context):
		return

	if freeform_state.jam_context.has_method("set_member_requested_parts"):
		freeform_state.jam_context.set_member_requested_parts(npc, false, false)
	elif freeform_state.jam_context.has_method("set_member_requested_part"):
		freeform_state.jam_context.set_member_requested_part(npc, "silent")

	if npc.has_method("set_current_part"):
		npc.set_current_part("waiting")


func _update_pending_freeform_auto_joins(delta: float) -> void:
	if freeform_state.pending_auto_joins.is_empty():
		return

	var pending_npcs: Array = freeform_state.pending_auto_joins.keys()

	for npc in pending_npcs:
		if npc == null or not is_instance_valid(npc):
			freeform_state.pending_auto_joins.erase(npc)
			continue

		if not freeform_state.members.has(npc):
			freeform_state.pending_auto_joins.erase(npc)
			continue

		var containing_jam_spot := _get_active_jamspot_containing_position(npc.global_position)

		if containing_jam_spot != null:
			_queue_jamspot_handoff(npc, containing_jam_spot)
			continue

		var remaining_time: float = float(freeform_state.pending_auto_joins[npc])
		remaining_time -= delta

		if remaining_time > 0.0:
			freeform_state.pending_auto_joins[npc] = remaining_time
			continue

		# Delay is finished, but NPC should not play inside the etiquette buffer.
		# Keep them pending at 0 until formation movement pulls them out.
		if _is_position_inside_buffer_but_not_jamspot(npc.global_position):
			freeform_state.pending_auto_joins[npc] = 0.0
			continue

		freeform_state.pending_auto_joins.erase(npc)
		_finish_auto_npc_join_delay(npc)


func _finish_auto_npc_join_delay(npc: Node) -> void:
	if npc == null:
		return

	if not is_instance_valid(npc):
		return

	if freeform_state.jam_context == null:
		return

	if not is_instance_valid(freeform_state.jam_context):
		return

	if not freeform_state.members.has(npc):
		return

	if freeform_state.pending_jamspot_handoffs.has(npc):
		_silence_freeform_follower_without_waiting(npc)
		return

	if _is_position_inside_buffer_but_not_jamspot(npc.global_position):
		freeform_state.pending_auto_joins[npc] = 0.0
		_silence_freeform_follower_without_waiting(npc)
		return

	_set_npc_freeform_request_on_context(npc, freeform_state.jam_context)

	if freeform_state.jam_context.has_method("set_member_active"):
		freeform_state.jam_context.set_member_active(npc, true)

	if freeform_state.jam_context.has_method("refresh_arrangement"):
		freeform_state.jam_context.refresh_arrangement()

	# Only after the wait finishes can this auto NPC expand the bubble.
	_record_freeform_member_join_time(npc)

	_debug_player_freeform("finished auto join delay npc=" + str(npc.name))


func _clear_pending_freeform_auto_join(npc: Node) -> void:
	if npc == null:
		return

	if freeform_state.pending_auto_joins.has(npc):
		freeform_state.pending_auto_joins.erase(npc)


func _check_auto_freeform_leave(_player_position: Vector2) -> void:
	if freeform_state.jam_context == null:
		return

	if not is_instance_valid(freeform_state.jam_context):
		return

	var members_to_check: Array[Node] = freeform_state.members.duplicate()

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

		var containing_jam_spot := _get_active_jamspot_containing_position(member.global_position)

		if containing_jam_spot != null:
			_queue_jamspot_handoff(member, containing_jam_spot)
			continue

		var leave_anchor_positions: Array[Vector2] = _get_freeform_leave_anchor_positions_for_member(member)

		if leave_anchor_positions.is_empty():
			stop_auto_freeform_for_npc(member)
			continue

		if not _is_npc_near_any_freeform_anchor(member, leave_anchor_positions):
			stop_auto_freeform_for_npc(member)


func remove_npc_from_freeform_members_for_jamspot(npc: Node) -> void:
	if npc == null:
		return

	if freeform_state.pending_jamspot_handoffs.has(npc):
		freeform_state.pending_jamspot_handoffs.erase(npc)

	_clear_pending_freeform_auto_join(npc)

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("set_member_active"):
			freeform_state.jam_context.set_member_active(npc, false)

	if freeform_state.members.has(npc):
		freeform_state.members.erase(npc)

	_clear_freeform_member_join_time(npc)

	if freeform_state.anchor == npc:
		freeform_state.anchor = null

	if freeform_state.leader == npc:
		freeform_state.leader = null
		_refresh_freeform_leader()

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("refresh_arrangement"):
			freeform_state.jam_context.refresh_arrangement()

	_sync_jam_formation_to_active_freeform()
	_cleanup_freeform_context_if_no_freeform_members()


func _queue_jamspot_handoff(npc: Node, jam_spot: Node) -> void:
	if npc == null:
		return

	if jam_spot == null or not is_instance_valid(jam_spot):
		return

	if freeform_state.pending_jamspot_handoffs.has(npc):
		freeform_state.pending_jamspot_handoffs[npc]["jam_spot"] = jam_spot
		return

	freeform_state.pending_jamspot_handoffs[npc] = {
		"jam_spot": jam_spot,
		"remaining": jamspot_handoff_delay
	}

	_clear_pending_freeform_auto_join(npc)

	# Silence the NPC during JamSpot handoff, but keep them active in the
	# freeform context until the handoff finishes.
	# This prevents the freeform JamContext from stopping and touching
	# the player's carried audio.
	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("set_member_requested_parts"):
			freeform_state.jam_context.set_member_requested_parts(npc, false, false)
		elif freeform_state.jam_context.has_method("set_member_requested_part"):
			freeform_state.jam_context.set_member_requested_part(npc, "silent")

	if npc.has_method("set_current_part"):
		npc.set_current_part("silent")


func _update_pending_jamspot_handoffs(delta: float) -> void:
	if freeform_state.pending_jamspot_handoffs.is_empty():
		return

	var npcs := freeform_state.pending_jamspot_handoffs.keys()

	for npc in npcs:
		if npc == null or not is_instance_valid(npc):
			freeform_state.pending_jamspot_handoffs.erase(npc)
			continue

		var handoff: Dictionary = freeform_state.pending_jamspot_handoffs[npc]
		var jam_spot: Node = handoff.get("jam_spot", null)

		if jam_spot == null or not is_instance_valid(jam_spot):
			freeform_state.pending_jamspot_handoffs.erase(npc)
			continue

		# Manual follow cancels JamSpot stealing.
		if npc.has_method("is_following_player"):
			if npc.is_following_player():
				freeform_state.pending_jamspot_handoffs.erase(npc)
				continue

		# If the player leads the NPC back out before the delay finishes,
		# cancel the handoff and let freeform continue.
		if npc is Node2D:
			if _get_active_jamspot_containing_position(npc.global_position) != jam_spot:
				freeform_state.pending_jamspot_handoffs.erase(npc)
				continue

		var remaining: float = float(handoff.get("remaining", 0.0))
		remaining -= delta

		if remaining > 0.0:
			handoff["remaining"] = remaining
			freeform_state.pending_jamspot_handoffs[npc] = handoff
			continue

		freeform_state.pending_jamspot_handoffs.erase(npc)
		_release_freeform_npc_for_actual_jamspot(npc, jam_spot)


func cancel_jamspot_handoff_for_npc(npc: Node) -> void:
	if npc == null:
		return

	if not freeform_state.pending_jamspot_handoffs.has(npc):
		return

	freeform_state.pending_jamspot_handoffs.erase(npc)

	# If this NPC still belongs to the active freeform group, restore normal
	# freeform behavior. If they are still in the buffer, keep them silent;
	# if they are outside the buffer, let them play again.
	if freeform_state.members.has(npc):
		if npc is Node2D:
			if _is_position_inside_buffer_but_not_jamspot(npc.global_position):
				_silence_freeform_follower_without_waiting(npc)
			else:
				_set_npc_freeform_request_on_context(npc, freeform_state.jam_context)

		if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
			if freeform_state.jam_context.has_method("set_member_active"):
				freeform_state.jam_context.set_member_active(npc, true)

			if freeform_state.jam_context.has_method("refresh_arrangement"):
				freeform_state.jam_context.refresh_arrangement()

	_sync_jam_formation_to_active_freeform()


# ------------------------------------------------------------
# Freeform cleanup
# ------------------------------------------------------------

func _cleanup_freeform_context_if_no_freeform_members(return_player_to_solo := true) -> void:
	var has_npc_member := false

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		has_npc_member = true
		break

	if has_npc_member:
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	if return_player_to_solo:
		if player != null and is_instance_valid(player):
			if "is_playing_instrument" in player and player.is_playing_instrument:
				if "current_jam_context" in player:
					if player.current_jam_context == freeform_state.jam_context:
						if player.has_method("return_to_carried_solo_from_freeform"):
							player.return_to_carried_solo_from_freeform()

	_destroy_active_freeform_context()


func _cleanup_freeform_context_if_only_player_left(return_player_to_solo := true) -> void:
	var non_player_count := 0

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		non_player_count += 1

	if non_player_count > 0:
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	if return_player_to_solo:
		if player != null and is_instance_valid(player):
			if "is_playing_instrument" in player and player.is_playing_instrument:
				if "current_jam_context" in player:
					if player.current_jam_context == freeform_state.jam_context:
						if player.has_method("return_to_carried_solo_from_freeform"):
							player.return_to_carried_solo_from_freeform()

	_destroy_active_freeform_context()


func _destroy_active_freeform_context() -> void:
	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		freeform_state.jam_context.queue_free()

	freeform_state.jam_context = null
	freeform_state.leader = null
	freeform_state.anchor = null
	freeform_state.members.clear()
	freeform_state.member_join_times.clear()
	freeform_state.pending_auto_joins.clear()
	freeform_state.pending_jamspot_handoffs.clear()

	player_stationary_timer = 0.0
	player_was_stationary_for_jam = false

	if jam_formation != null and jam_formation.has_method("clear"):
		jam_formation.clear()

	_clear_current_nearby_jam()


func _stop_all_auto_freeform_followers() -> void:
	var members_to_check: Array[Node] = freeform_state.members.duplicate()

	for member in members_to_check:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member.has_method("is_auto_freeform"):
			continue

		if not member.is_auto_freeform():
			continue

		_clear_pending_freeform_auto_join(member)

		if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
			if freeform_state.jam_context.has_method("set_member_active"):
				freeform_state.jam_context.set_member_active(member, false)

		if member.has_method("stop_freeform_immediately"):
			member.stop_freeform_immediately()

		if freeform_state.members.has(member):
			freeform_state.members.erase(member)

		_clear_freeform_member_join_time(member)


# ------------------------------------------------------------
# Search helpers
# ------------------------------------------------------------

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

		if not npc is Node2D:
			continue

		if _get_active_jamspot_containing_position(npc.global_position) != null:
			continue

		var npc_radius: float = _get_npc_join_radius(npc)
		var distance: float = player_position.distance_to(npc.global_position)

		if distance <= npc_radius and distance < best_distance:
			best_npc = npc
			best_distance = distance

	return best_npc


func _find_available_accompanists_near_position(center_position: Vector2, excluded_members: Array[Node] = []) -> Array[Node]:
	var found_npcs: Array[Node] = []

	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if not is_instance_valid(npc):
			continue

		if excluded_members.has(npc):
			continue

		if freeform_state.members.has(npc):
			continue

		if not npc.has_method("is_available_for_player_accompaniment"):
			continue

		if not npc.is_available_for_player_accompaniment():
			continue

		if not npc is Node2D:
			continue

		# Actual JamSpot owns NPCs. Buffer does not.
		if _is_position_inside_active_jamspot(npc.global_position):
			continue

		var npc_radius: float = _get_npc_join_radius(npc)
		var distance: float = center_position.distance_to(npc.global_position)

		if distance <= npc_radius:
			found_npcs.append(npc)

	return found_npcs


func _get_active_manual_freeform_npcs() -> Array[Node]:
	var manual_npcs: Array[Node] = []

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member.has_method("is_manual_freeform"):
			continue

		if member.is_manual_freeform():
			manual_npcs.append(member)

	return manual_npcs


func _npc_should_rejoin_as_auto(npc: Node) -> bool:
	if npc == null:
		return false

	if freeform_state.jam_context == null:
		return false

	if not is_instance_valid(freeform_state.jam_context):
		return false

	if not npc is Node2D:
		return false

	if not npc.has_method("is_available_for_player_accompaniment"):
		return false

	if not npc.is_available_for_player_accompaniment():
		return false

	if _is_position_inside_active_jamspot(npc.global_position):
		return false

	for member in freeform_state.members:
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


# ------------------------------------------------------------
# Radius and anchor helpers
# ------------------------------------------------------------

func _get_freeform_leave_anchor_positions_for_member(member: Node) -> Array[Vector2]:
	var positions: Array[Vector2] = get_freeform_anchor_positions()

	var should_include_delayed_anchors := false

	if _is_player_led_freeform() and enable_player_led_freeform_chains:
		should_include_delayed_anchors = true

	if _is_npc_led_freeform() and enable_npc_led_freeform_chains:
		should_include_delayed_anchors = true

	if should_include_delayed_anchors:
		for delayed_position in _get_delayed_auto_freeform_anchor_positions():
			if not positions.has(delayed_position):
				positions.append(delayed_position)

	if member != null and member is Node2D:
		var member_position: Vector2 = member.global_position

		for i in range(positions.size() - 1, -1, -1):
			if positions[i].distance_to(member_position) < 0.01:
				positions.remove_at(i)

	return positions


func get_freeform_anchor_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []

	if freeform_state.anchor != null and is_instance_valid(freeform_state.anchor):
		if freeform_state.anchor is Node2D:
			positions.append(freeform_state.anchor.global_position)

	for member in freeform_state.members:
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

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if not member.is_in_group("player"):
			continue

		if member is Node2D:

			if not positions.has(member.global_position):
				positions.append(member.global_position)

	return positions


func _get_delayed_auto_freeform_anchor_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member is Node2D:
			continue

		if not member.has_method("is_auto_freeform"):
			continue

		if not member.is_auto_freeform():
			continue

		if freeform_state.pending_auto_joins.has(member):
			continue

		if not _has_freeform_member_anchor_delay_passed(member):
			continue

		if not positions.has(member.global_position):
			positions.append(member.global_position)

	return positions


func _get_freeform_recruitment_anchor_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = get_freeform_anchor_positions()

	var should_include_delayed_anchors := false

	if _is_player_led_freeform() and enable_player_led_freeform_chains:
		should_include_delayed_anchors = true

	if _is_npc_led_freeform() and enable_npc_led_freeform_chains:
		should_include_delayed_anchors = true

	if should_include_delayed_anchors:
		for delayed_position in _get_delayed_auto_freeform_anchor_positions():
			if not positions.has(delayed_position):
				positions.append(delayed_position)

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


func _is_player_near_any_freeform_anchor(player_position: Vector2) -> bool:
	var positions: Array[Vector2] = get_freeform_anchor_positions()

	if positions.is_empty():
		return false

	var join_radius := _get_player_freeform_join_radius()

	for anchor_position in positions:
		var distance: float = player_position.distance_to(anchor_position)

		if distance <= join_radius:
			return true

	return false


func _get_npc_join_radius(npc: Node) -> float:
	if npc != null:
		if "auto_accompany_radius" in npc:
			return float(npc.auto_accompany_radius)

	return fallback_accompanist_radius


func _get_npc_auto_stop_radius(npc: Node) -> float:
	return _get_npc_join_radius(npc) + freeform_leave_padding


func _get_player_freeform_join_radius() -> float:

	if freeform_state.anchor != null:
		return _get_npc_join_radius(
			freeform_state.anchor
		)

	return fallback_accompanist_radius


func _get_player_freeform_leave_radius(npc: Node) -> float:
	return _get_npc_join_radius(npc) + freeform_player_leave_padding


func _get_active_freeform_npc_info(player_position: Vector2, use_leave_radius := false) -> Dictionary:
	var best_npc: Node = null
	var best_distance := INF
	var best_radius := 0.0

	for member in freeform_state.members:
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


func _is_position_inside_active_jamspot_buffer(world_position: Vector2) -> bool:
	for jam_spot in get_tree().get_nodes_in_group("jam_spot"):
		if jam_spot == null or not is_instance_valid(jam_spot):
			continue

		if jam_spot.has_method("is_jam_active"):
			if not jam_spot.is_jam_active():
				continue

		if jam_spot.has_method("is_position_inside_buffer_radius"):
			if jam_spot.is_position_inside_buffer_radius(world_position):
				return true

	return false


func _is_position_inside_active_jamspot(world_position: Vector2) -> bool:
	return _get_active_jamspot_containing_position(world_position) != null


func _is_position_inside_buffer_but_not_jamspot(world_position: Vector2) -> bool:
	if _is_position_inside_active_jamspot(world_position):
		return false

	return _is_position_inside_active_jamspot_buffer(world_position)


func _release_freeform_npc_for_actual_jamspot(npc: Node, jam_spot: Node) -> void:
	if npc == null:
		return

	_clear_pending_freeform_auto_join(npc)

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("set_member_active"):
			freeform_state.jam_context.set_member_active(npc, false)

		if freeform_state.jam_context.has_method("clear_member_requested_part"):
			freeform_state.jam_context.clear_member_requested_part(npc)

	if freeform_state.members.has(npc):
		freeform_state.members.erase(npc)

	_clear_freeform_member_join_time(npc)

	if npc.has_method("clear_jam_formation_target"):
		npc.clear_jam_formation_target()

	if npc.has_method("reset_freeform_state_for_jamspot_buffer"):
		npc.reset_freeform_state_for_jamspot_buffer()
	elif npc.has_method("stop_freeform_immediately"):
		npc.stop_freeform_immediately()

	if freeform_state.anchor == npc:
		freeform_state.anchor = null

	if freeform_state.leader == npc:
		freeform_state.leader = null

	# Hand the NPC to the actual JamSpot after freeform is cleared.
	if jam_spot != null and is_instance_valid(jam_spot):
		if jam_spot.has_method("register_npc"):
			jam_spot.register_npc(npc)

		if jam_spot.has_method("refresh_npc_activity"):
			jam_spot.refresh_npc_activity(npc)

	_refresh_freeform_leader()
	_sync_jam_formation_to_active_freeform()

	if freeform_state.jam_context != null and is_instance_valid(freeform_state.jam_context):
		if freeform_state.jam_context.has_method("refresh_arrangement"):
			freeform_state.jam_context.refresh_arrangement()

	# If the player is still holding play, never force player cleanup here.
	# This transfer is about the NPC joining a JamSpot, not about stopping the player.
	if _player_is_still_playing():
		_cleanup_freeform_context_if_only_player_left(false)
	else:
		_cleanup_freeform_context_if_only_player_left(true)


func _get_active_jamspot_containing_position(world_position: Vector2) -> Node:
	for jam_spot in get_tree().get_nodes_in_group("jam_spot"):
		if jam_spot == null or not is_instance_valid(jam_spot):
			continue

		if jam_spot.has_method("is_jam_active"):
			if not jam_spot.is_jam_active():
				continue

		if jam_spot.has_method("is_position_inside_join_radius"):
			if jam_spot.is_position_inside_join_radius(world_position):
				return jam_spot

	return null


func _is_player_led_freeform() -> bool:
	if freeform_state.anchor == null:
		return false

	if not is_instance_valid(freeform_state.anchor):
		return false

	return freeform_state.anchor.is_in_group("player")


func _is_npc_led_freeform() -> bool:
	if freeform_state.anchor == null:
		return false

	if not is_instance_valid(freeform_state.anchor):
		return false

	return not freeform_state.anchor.is_in_group("player")


# ------------------------------------------------------------
# Freeform member state
# ------------------------------------------------------------


func _record_freeform_member_join_time(member: Node) -> void:
	if member == null:
		return

	freeform_state.member_join_times[member] = Time.get_ticks_msec() / 1000.0


func _clear_freeform_member_join_time(member: Node) -> void:
	if member == null:
		return

	if freeform_state.member_join_times.has(member):
		freeform_state.member_join_times.erase(member)


func _has_freeform_member_anchor_delay_passed(member: Node) -> bool:
	if member == null:
		return false

	if not freeform_state.member_join_times.has(member):
		return false

	var joined_at: float = float(freeform_state.member_join_times[member])
	var now: float = Time.get_ticks_msec() / 1000.0

	return now - joined_at >= auto_freeform_anchor_delay


# ------------------------------------------------------------
# Formation synchronization
# ------------------------------------------------------------


func _sync_jam_formation_to_active_freeform() -> void:
	if jam_formation == null:
		return

	if freeform_state.jam_context == null or not is_instance_valid(freeform_state.jam_context):
		if jam_formation.has_method("clear"):
			jam_formation.clear()
		return

	if freeform_state.anchor == null or not is_instance_valid(freeform_state.anchor):
		if jam_formation.has_method("clear"):
			jam_formation.clear()
		return

	if not freeform_state.anchor is Node2D:
		if jam_formation.has_method("clear"):
			jam_formation.clear()
		return

	var formation_members: Array[Node] = []

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if member == freeform_state.anchor:
			continue

		if member.is_in_group("player"):
			continue

		if not member is Node2D:
			continue

		formation_members.append(member)

	if jam_formation.has_method("set_leader"):
		jam_formation.set_leader(freeform_state.anchor)

	if jam_formation.has_method("set_members"):
		jam_formation.set_members(formation_members)

	var should_use_precise_slots := _is_npc_led_freeform()

	if _is_player_led_freeform():
		should_use_precise_slots = player_was_stationary_for_jam

	if jam_formation.has_method("set_precise_slots"):
		jam_formation.set_precise_slots(should_use_precise_slots)

	if jam_formation.has_method("set_precise_slots"):
		jam_formation.set_precise_slots(should_use_precise_slots)

	if jam_formation.has_method("apply_targets_to_members"):
		jam_formation.apply_targets_to_members()


func _update_active_jam_formation_targets(delta: float) -> void:
	if jam_formation == null:
		return

	if freeform_state.jam_context == null:
		return

	if not is_instance_valid(freeform_state.jam_context):
		return

	if freeform_state.anchor == null:
		return

	if not is_instance_valid(freeform_state.anchor):
		return

	if not freeform_state.anchor is Node2D:
		return

	var should_use_precise_slots := _is_npc_led_freeform()

	if _is_player_led_freeform():
		should_use_precise_slots = _player_should_use_precise_freeform_slots(delta)

	if jam_formation.has_method("set_precise_slots"):
		jam_formation.set_precise_slots(should_use_precise_slots)

	if jam_formation.has_method("apply_targets_to_members"):
		jam_formation.apply_targets_to_members()


# ------------------------------------------------------------
# Arrangement request helpers
# ------------------------------------------------------------


func _refresh_player_led_auto_follower_requests() -> void:
	if not _is_player_led_freeform():
		return

	if freeform_state.jam_context == null:
		return

	if not is_instance_valid(freeform_state.jam_context):
		return

	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		return

	if not "is_playing_instrument" in player:
		return

	if not player.is_playing_instrument:
		return

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if not member.has_method("is_auto_freeform"):
			continue

		if not member.is_auto_freeform():
			continue

		# Pending freeform join should stay silent/waiting.
		if freeform_state.pending_auto_joins.has(member):
			continue

		# Pending JamSpot handoff should stay silent.
		if freeform_state.pending_jamspot_handoffs.has(member):
			continue

		# Inside etiquette buffer should not play freeform audio,
		# but should also not enter the freeform "waiting" join state.
		if member is Node2D:
			if _is_position_inside_buffer_but_not_jamspot(member.global_position):
				_silence_freeform_follower_without_waiting(member)
				continue

		_set_npc_freeform_request_on_context(member, freeform_state.jam_context)

	if freeform_state.jam_context.has_method("refresh_arrangement"):
		freeform_state.jam_context.refresh_arrangement()


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


func _silence_freeform_follower_without_waiting(npc: Node) -> void:
	if npc == null:
		return

	if freeform_state.jam_context == null:
		return

	if not is_instance_valid(freeform_state.jam_context):
		return

	# Important:
	# Do NOT clear_member_requested_part() here.
	# Do NOT set_member_active(npc, false) here.
	#
	# The NPC should remain an active freeform member for movement/formation,
	# but request silence while inside the JamSpot buffer.
	if freeform_state.jam_context.has_method("set_member_requested_parts"):
		freeform_state.jam_context.set_member_requested_parts(npc, false, false)
	elif freeform_state.jam_context.has_method("set_member_requested_part"):
		freeform_state.jam_context.set_member_requested_part(npc, "silent")

	if npc.has_method("set_current_part"):
		npc.set_current_part("silent")


func _set_npc_freeform_request_on_context(npc: Node, jam_context: Node) -> void:
	if npc == null or jam_context == null:
		return

	var rhythm_on := true
	var melody_on := true

	if _is_player_led_freeform():
		var player: Node = get_tree().get_first_node_in_group("player")

		if player != null:
			var player_wants_rhythm := false
			var player_wants_melody := false

			if player.has_method("get_wants_rhythm"):
				player_wants_rhythm = player.get_wants_rhythm()

			if player.has_method("get_wants_melody"):
				player_wants_melody = player.get_wants_melody()

			# Player-led followers should accompany, not replace.
			# Never request both in player-led freeform.
			if player_wants_melody and not player_wants_rhythm:
				rhythm_on = true
				melody_on = false
			elif player_wants_rhythm and not player_wants_melody:
				rhythm_on = false
				melody_on = true
			elif player_wants_rhythm and player_wants_melody:
				rhythm_on = true
				melody_on = false
			else:
				rhythm_on = true
				melody_on = false

	if jam_context.has_method("set_member_requested_parts"):
		jam_context.set_member_requested_parts(npc, rhythm_on, melody_on)
	elif jam_context.has_method("set_member_requested_part"):
		var part_name: String = _get_part_from_flags(rhythm_on, melody_on)
		jam_context.set_member_requested_part(npc, part_name)


func _get_part_from_flags(rhythm_on: bool, melody_on: bool) -> String:
	if rhythm_on and melody_on:
		return "both"
	elif melody_on:
		return "melody"
	elif rhythm_on:
		return "rhythm"

	return "silent"

# ------------------------------------------------------------
# Display / UI helpers
# ------------------------------------------------------------

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


func is_freeform_jam_context(jam_context: Node) -> bool:
	if jam_context == null:
		return false

	if not is_instance_valid(jam_context):
		return false

	if freeform_state.jam_context == null:
		return false

	if not is_instance_valid(freeform_state.jam_context):
		return false

	return jam_context == freeform_state.jam_context


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

		var fallback_leave_radius := 150.0
		return player.global_position.distance_to(jam_spot.global_position) <= fallback_leave_radius

	return false


func reset_all_auto_blocks() -> void:
	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if not is_instance_valid(npc):
			continue

		if npc.has_method("reset_auto_block"):
			npc.reset_auto_block()


func _refresh_freeform_leader() -> void:
	freeform_state.leader = null

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		if member.has_method("is_manual_freeform"):
			if member.is_manual_freeform():
				freeform_state.leader = member
				return

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			freeform_state.leader = member
			return

	for member in freeform_state.members:
		if member == null or not is_instance_valid(member):
			continue

		if not member.is_in_group("player"):
			freeform_state.leader = member
			return


func get_freeform_leader_text() -> String:
	var leader: Node = freeform_state.leader

	if leader == null or not is_instance_valid(leader):
		leader = freeform_state.anchor

	if leader == null or not is_instance_valid(leader):
		return "Freeform"

	if leader.is_in_group("player"):
		return "Player led"

	var instrument_name := ""

	if leader.has_method("get_instrument_display_name"):
		instrument_name = leader.get_instrument_display_name()
	elif leader.has_method("get_current_instrument_display_name"):
		instrument_name = leader.get_current_instrument_display_name()
	elif leader.has_method("get_instrument_id"):
		instrument_name = leader.get_instrument_id().capitalize()
	elif "instrument_name" in leader:
		instrument_name = str(leader.instrument_name).capitalize()
	elif leader.has_method("get_display_name"):
		instrument_name = leader.get_display_name()
	elif "display_name" in leader:
		instrument_name = str(leader.display_name)

	if instrument_name == "":
		instrument_name = "NPC"

	return "%s led" % instrument_name


# ------------------------------------------------------------
# Debug helpers
# ------------------------------------------------------------


func _debug_player_freeform(message: String) -> void:
	if debug_player_freeform:
		print("[JAM_MANAGER_PLAYER] %s | freeform_context=%s anchor=%s leader=%s members=%s pending=%s" % [
			message,
			str(freeform_state.jam_context),
			str(freeform_state.anchor),
			str(freeform_state.leader),
			str(freeform_state.members),
			str(freeform_state.pending_auto_joins.keys())
		])
