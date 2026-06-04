extends Node2D

enum JamRequirement {
	ANY,
	FREEFORM,
	JAMSPOT,
	SPECIFIC_JAMSPOT
}

@export var target_npc: Node
@export var unlock_npc_id := ""
@export var activate_once := true

@export var required_song_id := ""
@export var required_instrument_id := ""
@export var required_npc_id := ""
@export var required_musician_count := 1

@export var jam_requirement := JamRequirement.ANY

@export var required_jamspot: Node

@export var broken_visual: NodePath
@export var repaired_visual: NodePath
@export var collision_shape: NodePath

@export var label_text:= ""

@onready var reaction_area: Area2D = $ReactionArea

@onready var label: Label = $Label

@export var quest_id := ""

var player_in_range: Node = null

var activated := false

var check_timer := 0.0

func _ready() -> void:
	add_to_group("world_reaction")

	update_label()
	update_visuals()

	reaction_area.body_entered.connect(_on_reaction_area_body_entered)
	reaction_area.body_exited.connect(_on_reaction_area_body_exited)

func _process(delta: float) -> void:

	if activated:
		return

	check_timer += delta

	if check_timer < 0.25:
		return

	check_timer = 0.0

	try_current_player_jam()


func restore_completed_state() -> void:

	activated = true

	update_visuals()

	if target_npc != null:

		if target_npc.has_method("restore_recruited_state"): target_npc.restore_recruited_state()


func _startup_refresh() -> void:

	var player := get_tree().get_first_node_in_group("player")

	if player == null:
		return

	if not player.has_method("get_current_playing_song_id"):
		return

	var song_id: String = player.get_current_playing_song_id()

	try_activate(song_id)


func activate() -> void:

	if activate_once and activated:
		return

	activated = true

	update_visuals()

	if target_npc != null:

		if target_npc.has_method("unlock_npc"):
			target_npc.unlock_npc()


func update_visuals() -> void:

	var broken := get_node_or_null(broken_visual)
	var repaired := get_node_or_null(repaired_visual)

	if broken:
		broken.visible = not activated

	if repaired:
		repaired.visible = activated

	var shape := get_node_or_null(collision_shape)

	if shape:
		shape.set_deferred("disabled", activated)


func try_activate(song_id: String) -> bool:

	# Only enforce song requirements if one is specified.
	if required_song_id != "":
		if song_id != required_song_id:
			return false

	if not has_required_instrument():
		return false

	if not has_required_npc():
		return false

	if not satisfies_jam_requirement():
		return false

	var musician_count := 0

	if jam_requirement == JamRequirement.JAMSPOT \
	or jam_requirement == JamRequirement.SPECIFIC_JAMSPOT:

		musician_count = get_jamspot_musician_count()
	else:
		musician_count = get_player_jam_size()

	if musician_count < required_musician_count:
		return false

	activate()

	return true


func try_current_player_jam() -> void:

	# JamSpot objectives evaluate continuously.
	if jam_requirement == JamRequirement.JAMSPOT \
	or jam_requirement == JamRequirement.SPECIFIC_JAMSPOT:

		try_activate("")
		return

	var player: Node = player_in_range

	if player == null:
		return

	if "is_playing_instrument" in player:
		if not player.is_playing_instrument:
			return

	if not player.has_method("get_current_playing_song_id"):
		return

	var song_id: String = player.get_current_playing_song_id()

	try_activate(song_id)


func _on_reaction_area_body_entered(body: Node) -> void:

	if body.is_in_group("player"):

		player_in_range = body

		try_current_player_jam()


func _on_reaction_area_body_exited(body: Node) -> void:

	if body == player_in_range:
		player_in_range = null


func has_required_instrument() -> bool:

	if required_instrument_id == "":
		return true

	# Check player
	var player := get_tree().get_first_node_in_group("player")

	if player != null:

		if player.has_method("get_current_instrument_id"):

			if player.get_current_instrument_id() == required_instrument_id:

				if "is_playing_instrument" in player:
					if player.is_playing_instrument:
						return true

	for npc in get_tree().get_nodes_in_group("npc_musician"):

		if not is_instance_valid(npc):
			continue

		if not npc.has_method("get_current_instrument_id"):
			continue

		if npc.get_current_instrument_id() != required_instrument_id:
			continue

		if npc.has_method("is_actively_playing_jam"):
			if npc.is_actively_playing_jam():
				return true

	return false


func has_required_npc() -> bool:

	if required_npc_id == "":
		return true

	for npc in get_tree().get_nodes_in_group("npc_musician"):

		if not is_instance_valid(npc):
			continue

		if npc.npc_id != required_npc_id:
			continue

		if npc.is_actively_playing_jam():
			return true

	return false


func satisfies_jam_requirement() -> bool:

	match jam_requirement:

		JamRequirement.ANY:
			return true

		JamRequirement.FREEFORM:

			var player := get_tree().get_first_node_in_group("player")

			if player == null:
				return false

			if not "current_jam_context" in player:
				return false

			var context = player.current_jam_context

			if context == null:
				return false

			return true

		JamRequirement.JAMSPOT:

			for jamspot in get_tree().get_nodes_in_group("jam_spot"):

				if jamspot == null:
					continue

				if not jamspot.has_method("is_jam_active"):
					continue

				if not jamspot.is_jam_active():
					continue

				var jam_context: Node = jamspot.get_jam_context()

				if jam_context == null:
					continue

				if jam_context.has_method("get_playing_musician_count"):
					if jam_context.get_playing_musician_count() > 0:
						return true

			return false

		JamRequirement.SPECIFIC_JAMSPOT:

			if required_jamspot == null:
				return false

			if not required_jamspot.has_method("is_jam_active"):
				return false

			return required_jamspot.is_jam_active()

	return false


func get_jamspot_musician_count() -> int:

	# SPECIFIC JAMSPOT
	if jam_requirement == JamRequirement.SPECIFIC_JAMSPOT:

		if required_jamspot == null:
			return 0

		if not required_jamspot.has_method("get_jam_context"):
			return 0

		var context: Node = required_jamspot.get_jam_context()

		if context == null:
			return 0

		if context.has_method("get_playing_musician_count"):
			return context.get_playing_musician_count()

		return 0

	# ANY JAMSPOT
	var highest_count := 0

	for jamspot in get_tree().get_nodes_in_group("jam_spot"):

		if not jamspot.has_method("get_jam_context"):
			continue

		var context: Node = jamspot.get_jam_context()

		if context == null:
			continue

		if context.has_method("get_playing_musician_count"):

			highest_count = max(
				highest_count,
				context.get_playing_musician_count()
			)

	return highest_count


func get_player_jam_size() -> int:

	if player_in_range == null:
		return 0

	var context: Node = player_in_range.current_jam_context

	if context == null:
		return 1

	if not is_instance_valid(context):
		return 1

	if context.has_method("get_playing_musician_count"):
		var count: int = context.get_playing_musician_count()

		return count

	if context.has_method("get_active_musician_count"):
		var count: int = context.get_active_musician_count()

		return count

	return 1


func update_label() -> void:
	label.text = label_text
