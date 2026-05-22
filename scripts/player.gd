extends CharacterBody2D

@export var speed := 180.0

@onready var interaction_area: Area2D = $InteractionArea
@onready var sprite: ColorRect = $ColorRect

var nearby_npcs: Array[Node] = []
var music_system: Node = null

var is_playing_instrument := false
var instrument_visual_tween: Tween = null

var current_instrument_index := 0

var instruments := [
	{
		"id": "guitar",
		"display_name": "Guitar"
	},
	{
		"id": "bass",
		"display_name": "Bass"
	},
	{
		"id": "harmonica",
		"display_name": "Harmonica"
	}
]

const NORMAL_COLOR := Color(1, 1, 1, 1)
const PLAYING_COLOR := Color(1.25, 1.1, 0.75, 1)

const NORMAL_SCALE := Vector2(1, 1)
const PLAYING_SCALE := Vector2(1.08, 0.94)


func _ready() -> void:
	interaction_area.area_entered.connect(_on_interaction_area_entered)
	interaction_area.area_exited.connect(_on_interaction_area_exited)

	music_system = get_tree().get_first_node_in_group("music_system")

	sprite.modulate = NORMAL_COLOR
	sprite.scale = NORMAL_SCALE


func _physics_process(_delta: float) -> void:
	_handle_movement()
	_handle_npc_interact_input()
	_handle_instrument_cycle_input()
	_handle_play_instrument_input()


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


func _handle_instrument_cycle_input() -> void:
	if Input.is_action_just_pressed("cycle_instrument"):
		cycle_instrument()


func cycle_instrument() -> void:
	var was_playing := is_playing_instrument

	if was_playing:
		stop_instrument()

	current_instrument_index += 1

	if current_instrument_index >= instruments.size():
		current_instrument_index = 0

	print("Selected Instrument: ", get_current_instrument_display_name())

	if was_playing:
		start_instrument()


func _handle_play_instrument_input() -> void:
	if Input.is_action_pressed("play_instrument"):
		start_instrument()
	else:
		stop_instrument()


func start_instrument() -> void:
	if is_playing_instrument:
		return

	is_playing_instrument = true

	var instrument_id: String = get_current_instrument_id()

	if music_system != null:
		music_system.player_take_over_instrument(instrument_id)

	_start_instrument_visuals()


func stop_instrument() -> void:
	if not is_playing_instrument:
		return

	is_playing_instrument = false

	var instrument_id: String = get_current_instrument_id()

	if music_system != null:
		music_system.player_release_instrument(instrument_id)

	_stop_instrument_visuals()


func get_current_instrument_id() -> String:
	return instruments[current_instrument_index]["id"]


func get_current_instrument_display_name() -> String:
	return instruments[current_instrument_index]["display_name"]


func _start_instrument_visuals() -> void:
	if instrument_visual_tween:
		instrument_visual_tween.kill()

	sprite.modulate = PLAYING_COLOR
	sprite.scale = NORMAL_SCALE

	instrument_visual_tween = create_tween()
	instrument_visual_tween.set_loops()

	instrument_visual_tween.tween_property(
		sprite,
		"scale",
		PLAYING_SCALE,
		0.12
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	instrument_visual_tween.tween_property(
		sprite,
		"scale",
		NORMAL_SCALE,
		0.12
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _stop_instrument_visuals() -> void:
	if instrument_visual_tween:
		instrument_visual_tween.kill()
		instrument_visual_tween = null

	sprite.modulate = NORMAL_COLOR
	sprite.scale = NORMAL_SCALE


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
