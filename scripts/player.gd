extends CharacterBody2D

@export var speed := 180.0

@onready var interaction_area: Area2D = $InteractionArea

var nearby_npcs: Array[Node] = []
var guitar_is_playing := false
var music_system: Node = null


func _ready() -> void:
	interaction_area.area_entered.connect(_on_interaction_area_entered)
	interaction_area.area_exited.connect(_on_interaction_area_exited)

	music_system = get_tree().get_first_node_in_group("music_system")


func _physics_process(_delta: float) -> void:
	_handle_movement()
	_handle_npc_interact_input()
	_handle_guitar_input()


func _handle_movement() -> void:
	var input_vector := Vector2.ZERO

	input_vector.x = Input.get_axis("move_left", "move_right")
	input_vector.y = Input.get_axis("move_up", "move_down")

	input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()


func _handle_npc_interact_input() -> void:
	if Input.is_action_just_pressed("interact"):
		var closest_npc := get_closest_npc()

		if closest_npc != null:
			closest_npc.interact()


func _handle_guitar_input() -> void:
	if music_system == null:
		return

	if Input.is_action_pressed("play_instrument"):
		start_guitar()
	else:
		stop_guitar()


func start_guitar() -> void:
	if guitar_is_playing:
		return

	guitar_is_playing = true
	music_system.set_stem_active("guitar", true)


func stop_guitar() -> void:
	if not guitar_is_playing:
		return

	guitar_is_playing = false

	if music_system != null:
		music_system.set_stem_active("guitar", false)


func get_closest_npc() -> Node:
	if nearby_npcs.is_empty():
		return null

	var closest_npc: Node = null
	var closest_distance := INF

	for npc in nearby_npcs:
		if not is_instance_valid(npc):
			continue

		var distance := global_position.distance_to(npc.global_position)

		if distance < closest_distance:
			closest_distance = distance
			closest_npc = npc

	return closest_npc


func _on_interaction_area_entered(area: Area2D) -> void:
	var possible_npc := area.get_parent()

	if possible_npc.is_in_group("npc_musician"):
		if not nearby_npcs.has(possible_npc):
			nearby_npcs.append(possible_npc)


func _on_interaction_area_exited(area: Area2D) -> void:
	var possible_npc := area.get_parent()

	if nearby_npcs.has(possible_npc):
		nearby_npcs.erase(possible_npc)
