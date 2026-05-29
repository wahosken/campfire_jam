extends Node2D

@export var unlock_npc_id := ""
@export var activate_once := true

@export var required_song_id := ""
@export var required_instrument_id := ""

@export var broken_visual: NodePath
@export var repaired_visual: NodePath
@export var collision_shape: NodePath

@onready var reaction_area: Area2D = $ReactionArea

var musicians_in_range: Array[Node] = []

var activated := false


func _ready() -> void:
	add_to_group("world_reaction")

	update_visuals()

	reaction_area.body_entered.connect(_on_reaction_area_body_entered)
	reaction_area.body_exited.connect(_on_reaction_area_body_exited)


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

	if musicians_in_range.is_empty():
		return false

	if song_id != required_song_id:
		return false

	if not has_required_instrument():
		return false

	activate()

	return true


func _on_reaction_area_body_entered(body: Node) -> void:

	if not body.is_in_group("musician"):
		return

	if not musicians_in_range.has(body):
		musicians_in_range.append(body)


func _on_reaction_area_body_exited(body: Node) -> void:

	if not body.is_in_group("musician"):
		return

	if musicians_in_range.has(body):
		musicians_in_range.erase(body)


func has_active_music_nearby() -> bool:

	for musician in musicians_in_range:

		if musician == null:
			continue

		if musician.has_method("get_current_playing_song_id"):
			return true

	return false


func has_required_instrument() -> bool:

	if required_instrument_id == "":
		return true

	for musician in musicians_in_range:

		if musician == null:
			continue

		if not is_instance_valid(musician):
			continue

		if not musician.has_method("get_current_instrument_id"):
			continue

		if musician.get_current_instrument_id() == required_instrument_id:
			return true

	return false
