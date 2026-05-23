extends Node

signal nearby_jam_changed(jam_source: Node, jam_type: String, jam_name: String)

@export var join_radius := 1000.0
@export var leave_radius := 1100.0
@export var accompanist_search_radius := 300.0
@export var freeform_jam_context_scene: PackedScene

var active_freeform_jam_context: Node = null
var active_freeform_leader: Node = null
var active_freeform_started_by_npc := false
var active_freeform_members: Array[Node] = []

var music_system: Node = null

var player_is_near_active_jam := false
var has_reported_to_music_system := false

var current_nearby_jam_source: Node = null
var current_nearby_jam_type := "none"
var current_nearby_jam_name := "None"
var current_nearby_jam_distance := INF


func _ready() -> void:
	add_to_group("jam_manager")

	music_system = get_tree().get_first_node_in_group("music_system")


func update_player_jam_proximity(player_position: Vector2) -> void:
	var best_jam := _find_best_active_jam_source(player_position)

	var new_source: Node = best_jam.get("source", null)
	var new_type: String = best_jam.get("type", "none")
	var new_name: String = best_jam.get("name", "None")
	var new_distance: float = best_jam.get("distance", INF)

	var new_is_near := new_source != null
	var source_changed := new_source != current_nearby_jam_source
	var near_state_changed := new_is_near != player_is_near_active_jam

	current_nearby_jam_source = new_source
	current_nearby_jam_type = new_type
	current_nearby_jam_name = new_name
	current_nearby_jam_distance = new_distance
	player_is_near_active_jam = new_is_near

	if source_changed:
		nearby_jam_changed.emit(
			current_nearby_jam_source,
			current_nearby_jam_type,
			current_nearby_jam_name
		)

	if near_state_changed or not has_reported_to_music_system:
		has_reported_to_music_system = true

		if music_system != null and music_system.has_method("set_player_near_active_jam"):
			music_system.set_player_near_active_jam(player_is_near_active_jam)


func create_freeform_jam_with_accompanist(player: Node, player_position: Vector2) -> Node:
	var accompanist := get_nearby_player_accompanist(player_position)
	var started_by_npc := false

	if accompanist == null:
		accompanist = _find_best_joinable_freeform_leader(player_position)
		started_by_npc = accompanist != null

	if accompanist == null:
		return null

	if freeform_jam_context_scene == null:
		push_warning("JamManager is missing freeform_jam_context_scene.")
		return null

	_clear_freeform_jam()

	active_freeform_jam_context = freeform_jam_context_scene.instantiate()
	add_child(active_freeform_jam_context)

	active_freeform_leader = accompanist if started_by_npc else player
	active_freeform_started_by_npc = started_by_npc
	active_freeform_members = [
		accompanist,
		player
	]

	if active_freeform_jam_context.has_method("add_member"):
		active_freeform_jam_context.add_member(accompanist)
		active_freeform_jam_context.add_member(player)
	else:
		push_warning("FreeformJamContext is missing add_member().")
		_clear_freeform_jam()
		return null

	if started_by_npc:
		if active_freeform_jam_context.has_method("start_from_existing_member"):
			active_freeform_jam_context.start_from_existing_member(accompanist)

		if accompanist.has_method("prepare_for_jam_context_transfer"):
			accompanist.prepare_for_jam_context_transfer()

	if active_freeform_jam_context.has_method("set_member_active"):
		active_freeform_jam_context.set_member_active(accompanist, true)
	else:
		push_warning("FreeformJamContext is missing set_member_active().")
		_clear_freeform_jam()
		return null

	current_nearby_jam_source = active_freeform_leader
	current_nearby_jam_type = "npc_freeform" if started_by_npc else "player_freeform"
	current_nearby_jam_name = _get_jam_source_display_name(active_freeform_leader, "Freeform Jam")
	current_nearby_jam_distance = player_position.distance_to(active_freeform_leader.global_position)
	player_is_near_active_jam = true

	if music_system != null and music_system.has_method("set_player_near_active_jam"):
		music_system.set_player_near_active_jam(true)

	nearby_jam_changed.emit(
		current_nearby_jam_source,
		current_nearby_jam_type,
		current_nearby_jam_name
	)

	return active_freeform_jam_context


func end_freeform_jam() -> void:
	_clear_freeform_jam()

	current_nearby_jam_source = null
	current_nearby_jam_type = "none"
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


func end_freeform_jam_if_leader(member: Node) -> void:
	if member == null:
		return

	if active_freeform_jam_context == null:
		return

	if active_freeform_leader != member:
		return

	end_freeform_jam()


func get_nearby_player_accompanist(player_position: Vector2) -> Node:
	var nearby_jam_spot := _find_best_active_jam_spot(player_position)

	if not nearby_jam_spot.is_empty():
		return null

	return _find_best_available_accompanist(player_position)


func is_freeform_jam_context(jam_context: Node) -> bool:
	if jam_context == null:
		return false

	if active_freeform_jam_context == null:
		return false

	if not is_instance_valid(active_freeform_jam_context):
		return false

	return jam_context == active_freeform_jam_context


func is_active_freeform_started_by_npc() -> bool:
	return active_freeform_started_by_npc


func is_player_near_active_jam() -> bool:
	return player_is_near_active_jam


func get_current_nearby_jam_source() -> Node:
	return current_nearby_jam_source


func get_current_nearby_jam_type() -> String:
	return current_nearby_jam_type


func get_current_nearby_jam_name() -> String:
	return current_nearby_jam_name


func get_current_nearby_jam_distance() -> float:
	return current_nearby_jam_distance


func get_current_nearby_jam_context() -> Node:
	if active_freeform_jam_context != null and is_instance_valid(active_freeform_jam_context):
		return active_freeform_jam_context

	if current_nearby_jam_source == null:
		return null

	if current_nearby_jam_type == "jam_spot":
		if current_nearby_jam_source.has_method("get_jam_context"):
			return current_nearby_jam_source.get_jam_context()

	return null


func get_current_jam_active_instruments_text() -> String:
	var jam_context := get_current_nearby_jam_context()

	if jam_context != null and jam_context.has_method("get_active_instruments_text"):
		return jam_context.get_active_instruments_text()

	if current_nearby_jam_source == null:
		return "None"

	if current_nearby_jam_type == "musician":
		if current_nearby_jam_source.has_method("get_instrument_display_name"):
			return current_nearby_jam_source.get_instrument_display_name()

	return "None"


func get_current_jam_featured_instrument_text() -> String:
	var jam_context := get_current_nearby_jam_context()

	if jam_context != null and jam_context.has_method("get_featured_instrument_text"):
		return jam_context.get_featured_instrument_text()

	if current_nearby_jam_source == null:
		return "None"

	if current_nearby_jam_type == "musician":
		if current_nearby_jam_source.has_method("get_instrument_display_name"):
			return current_nearby_jam_source.get_instrument_display_name()

	return "None"


func get_nearby_jam_debug_text() -> String:
	if current_nearby_jam_source == null:
		return "Nearby Jam: None"

	return "Nearby Jam: %s (%s)" % [
		current_nearby_jam_name,
		current_nearby_jam_type
	]


func _find_best_active_jam_source(player_position: Vector2) -> Dictionary:
	var best_jam_spot := _find_best_active_jam_spot(player_position)

	if not best_jam_spot.is_empty():
		return best_jam_spot

	var best_musician := _find_best_active_musician(player_position)

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
			var check_radius := leave_radius if current_nearby_jam_source == jam_spot else join_radius
			is_inside = player_position.distance_to(jam_spot.global_position) <= check_radius

		if not is_inside:
			continue

		var distance := player_position.distance_to(jam_spot.global_position)

		if distance < best_distance:
			best_source = jam_spot
			best_distance = distance
			best_name = _get_jam_source_display_name(jam_spot, "Jam Spot")

	if best_source == null:
		return {}

	return {
		"source": best_source,
		"type": "jam_spot",
		"name": best_name,
		"distance": best_distance
	}


func _find_best_active_musician(player_position: Vector2) -> Dictionary:
	var best_source: Node = null
	var best_name := "None"
	var best_distance := INF

	var check_radius := leave_radius if current_nearby_jam_type == "musician" else join_radius

	for musician in get_tree().get_nodes_in_group("npc_musician"):
		if not is_instance_valid(musician):
			continue

		if not musician.has_method("is_actively_playing_jam"):
			continue

		if not musician.is_actively_playing_jam():
			continue

		var distance := player_position.distance_to(musician.global_position)

		if distance <= check_radius and distance < best_distance:
			best_source = musician
			best_distance = distance
			best_name = _get_jam_source_display_name(musician, "Musician")

	if best_source == null:
		return {}

	return {
		"source": best_source,
		"type": "musician",
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

		var npc_radius := accompanist_search_radius

		if "auto_accompany_radius" in npc:
			npc_radius = float(npc.auto_accompany_radius)

		var distance := player_position.distance_to(npc.global_position)

		if distance <= npc_radius and distance < best_distance:
			best_npc = npc
			best_distance = distance

	return best_npc


func _find_best_joinable_freeform_leader(player_position: Vector2) -> Node:
	var best_npc: Node = null
	var best_distance := INF

	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if not is_instance_valid(npc):
			continue

		if not npc.has_method("is_joinable_freeform_leader"):
			continue

		if not npc.is_joinable_freeform_leader():
			continue

		var npc_radius := accompanist_search_radius

		if "auto_accompany_radius" in npc:
			npc_radius = float(npc.auto_accompany_radius)

		var distance := player_position.distance_to(npc.global_position)

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


func _clear_freeform_jam() -> void:
	var context_to_clear := active_freeform_jam_context

	if context_to_clear != null and is_instance_valid(context_to_clear):
		if context_to_clear.has_method("stop_all_members"):
			context_to_clear.stop_all_members()

	for member in active_freeform_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.has_method("set_current_jam_context"):
			member.set_current_jam_context(null)

		if member.has_method("set_current_part"):
			member.set_current_part("silent")

	if context_to_clear != null and is_instance_valid(context_to_clear):
		context_to_clear.queue_free()

	active_freeform_jam_context = null
	active_freeform_leader = null
	active_freeform_started_by_npc = false
	active_freeform_members.clear()
