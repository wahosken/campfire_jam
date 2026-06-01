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
@export var required_musician_count := 1

@export var jam_requirement := JamRequirement.ANY

@export var required_jamspot: Node

@export var broken_visual: NodePath
@export var repaired_visual: NodePath
@export var collision_shape: NodePath

@export var label_text:= ""

@onready var reaction_area: Area2D = $ReactionArea

@onready var label: Label = $Label

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

		if target_npc.has_method("complete_task"):
			target_npc.complete_task()

#	var unlock_manager := get_tree().get_first_node_in_group("npc_unlock_manager")

#	if unlock_manager != null:
#		unlock_manager.unlock_npc_by_id(unlock_npc_id)


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

	print(
		"REACTION CHECK | ",
		name,
		" | song=",
		song_id
	)

	# Only enforce song requirements if one is specified.
	if required_song_id != "":
		if song_id != required_song_id:
			return false

	if not has_required_instrument():
		return false

	if not satisfies_jam_requirement():
		return false

	var musician_count := 0

	if jam_requirement == JamRequirement.JAMSPOT \
	or jam_requirement == JamRequirement.SPECIFIC_JAMSPOT:

		musician_count = get_jamspot_musician_count()
	else:
		musician_count = get_player_jam_size()

	print(
		"FINAL MUSICIAN COUNT = ",
		musician_count
	)

	if musician_count < required_musician_count:
		return false

	activate()

	return true


func try_current_player_jam() -> void:

	# JamSpot objectives should evaluate continuously.
	if jam_requirement == JamRequirement.JAMSPOT \
	or jam_requirement == JamRequirement.SPECIFIC_JAMSPOT:

		try_activate("")
		return

	var player: Node = player_in_range

	if player == null:
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

	if player_in_range == null:
		return false

	if not player_in_range.has_method("get_current_instrument_id"):
		return false

	return player_in_range.get_current_instrument_id() == required_instrument_id


func satisfies_jam_requirement() -> bool:

	match jam_requirement:

		JamRequirement.ANY:
			return true

		JamRequirement.FREEFORM:

			var jam_manager := get_tree().get_first_node_in_group("jam_manager")

			if jam_manager == null:
				return false

			var context: Node = jam_manager.get_current_nearby_jam_context()

			return context != null and "Freeform" in str(context)

		JamRequirement.JAMSPOT:

			if required_jamspot == null:
				return false

			if not required_jamspot.has_method("is_jam_active"):
				return false

			return required_jamspot.is_jam_active()

		JamRequirement.SPECIFIC_JAMSPOT:

			if required_jamspot == null:
				return false

			if not required_jamspot.has_method("is_jam_active"):
				return false

			return required_jamspot.is_jam_active()

	return false


func get_jamspot_musician_count() -> int:

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


func get_player_jam_size() -> int:

	if player_in_range == null:
		return 0

	var context: Node = player_in_range.current_jam_context

	if context == null:
		return 1

	if not is_instance_valid(context):
		return 1

	if context.has_method("get_playing_musician_count"):
		return context.get_playing_musician_count()

	if context.has_method("get_active_musician_count"):
		return context.get_active_musician_count()

	return 1


func update_label() -> void:
	label.text = label_text
