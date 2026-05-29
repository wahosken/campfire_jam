extends Node2D

@export var unlock_npc_id := ""
@export var activate_once := true

@export var required_song_id := ""
@export var required_instrument_id := ""
@export var required_musician_count := 1

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


func activate() -> void:

	if activate_once and activated:
		return

	activated = true

	update_visuals()

	var unlock_manager := get_tree().get_first_node_in_group("npc_unlock_manager")

	if unlock_manager != null:
		unlock_manager.unlock_npc_by_id(unlock_npc_id)

	print("WorldReaction activated")


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

	if player_in_range == null:
		return false

	if song_id != required_song_id:
		return false

	if not has_required_instrument():
		return false

	if get_player_jam_size() < required_musician_count:
		return false

	activate()

	return true


func try_current_player_jam() -> void:

	if player_in_range == null:
		return

	if not player_in_range.has_method("get_current_playing_song_id"):
		return

	var song_id: String = player_in_range.get_current_playing_song_id()

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


func get_player_jam_size() -> int:

	if player_in_range == null:
		return 0

	# Player alone counts as 1 musician.
	var count := 1

	if not "current_jam_context" in player_in_range:
		return count

	var context: Node = player_in_range.current_jam_context

	if context == null:
		return count

	if not is_instance_valid(context):
		return count

	if context.has_method("get_active_musician_count"):
		return context.get_playing_musician_count()

	return count


func update_label() -> void:
	label.text = label_text
