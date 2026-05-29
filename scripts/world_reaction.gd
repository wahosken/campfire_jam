extends Node2D

@export var unlock_npc_id := ""
@export var activate_once := true

@export var broken_visual: NodePath
@export var repaired_visual: NodePath
@export var collision_shape: NodePath

var activated := false


func _ready() -> void:
	update_visuals()


func activate() -> void:

	if activate_once and activated:
		return

	activated = true

	update_visuals()

	var unlock_manager := get_tree().get_first_node_in_group("npc_unlock_manager")

	if unlock_manager != null:
		unlock_manager.unlock_npc_by_id(unlock_npc_id)

	print("WorldReaction activated")


func _process(_delta: float) -> void:

	if Input.is_action_just_pressed("ui_page_down"):
		activate()


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
