extends CharacterBody2D

@export var speed := 180.0

@onready var interaction_area: Area2D = $InteractionArea
@onready var sprite: ColorRect = $ColorRect

@onready var guitar_audio_source: Node = $PlayerAudioSources/GuitarAudioSource
@onready var bass_audio_source: Node = $PlayerAudioSources/BassAudioSource
@onready var harmonica_audio_source: Node = $PlayerAudioSources/HarmonicaAudioSource
@onready var mandolin_audio_source: Node = $PlayerAudioSources/MandolinAudioSource

@onready var part_label: Label = $PlayerPartLabel

var nearby_interactables: Array[Node] = []
var music_system: Node = null

var is_playing_instrument := false
var instrument_visual_tween: Tween = null

var is_playing_solo_jam := false
var started_in_campfire_jam := false

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
	},
	{
		"id": "mandolin",
		"display_name": "Mandolin"
	}
]

const NORMAL_COLOR := Color(1, 1, 1, 1)
const PLAYING_COLOR := Color(1.25, 1.1, 0.75, 1)

const NORMAL_SCALE := Vector2(1, 1)
const PLAYING_SCALE := Vector2(1.08, 0.94)


func _ready() -> void:
	add_to_group("player")

	interaction_area.area_entered.connect(_on_interaction_area_entered)
	interaction_area.area_exited.connect(_on_interaction_area_exited)

	music_system = get_tree().get_first_node_in_group("music_system")

	_register_player_audio_sources()

	sprite.modulate = NORMAL_COLOR
	sprite.scale = NORMAL_SCALE

	_update_part_label()

	if music_system != null:
		music_system.arrangement_changed.connect(_on_arrangement_changed)

	print("Selected Instrument: ", get_current_instrument_display_name())


func _physics_process(_delta: float) -> void:
	if music_system != null and music_system.has_method("update_player_jam_area"):
		music_system.update_player_jam_area(global_position)
	
	_handle_movement()
	_handle_npc_interact_input()
	_handle_instrument_cycle_input()
	_handle_play_instrument_input()


func _on_arrangement_changed() -> void:
	_update_part_label()


func _update_part_label() -> void:
	if part_label == null:
		return

	var instrument_name := get_current_instrument_display_name()
	var part_text := "silent"

	if is_playing_solo_jam:
		part_text = "both"
	elif music_system != null and music_system.has_method("get_current_owner_part"):
		part_text = music_system.get_current_owner_part("player", get_current_instrument_id())

	if part_text == "silent":
		part_label.text = "%s: ----" % instrument_name
	else:
		part_label.text = "%s: %s" % [
			instrument_name,
			part_text.capitalize()
		]


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


func _handle_play_instrument_input() -> void:
	if Input.is_action_pressed("play_instrument"):
		start_instrument()
	else:
		stop_instrument()


func _register_player_audio_sources() -> void:
	if music_system == null:
		push_warning("Player could not find music_system group.")
		return

	music_system.register_audio_source("guitar", "player", guitar_audio_source)
	music_system.register_audio_source("bass", "player", bass_audio_source)
	music_system.register_audio_source("harmonica", "player", harmonica_audio_source)
	music_system.register_audio_source("mandolin", "player", mandolin_audio_source)


func cycle_instrument() -> void:
	var was_playing := is_playing_instrument

	if was_playing:
		stop_instrument()

	current_instrument_index += 1

	if current_instrument_index >= instruments.size():
		current_instrument_index = 0

	_update_part_label()

	if was_playing:
		start_instrument()


func start_instrument() -> void:
	if is_playing_instrument:
		return

	is_playing_instrument = true

	var instrument_id := get_current_instrument_id()
	started_in_campfire_jam = false
	is_playing_solo_jam = false

	if music_system != null and music_system.has_method("is_player_joined_to_campfire_jam"):
		started_in_campfire_jam = music_system.is_player_joined_to_campfire_jam()

	if started_in_campfire_jam:
		if music_system != null:
			music_system.set_player_instrument_active(instrument_id, true)
	else:
		is_playing_solo_jam = true

		var current_audio_source := get_current_audio_source()

		if current_audio_source != null and current_audio_source.has_method("start_solo_jam"):
			current_audio_source.start_solo_jam()

	_start_instrument_visuals()
	_update_part_label()


func stop_instrument() -> void:
	if not is_playing_instrument:
		return

	var instrument_id := get_current_instrument_id()

	if is_playing_solo_jam:
		var current_audio_source := get_current_audio_source()

		if current_audio_source != null and current_audio_source.has_method("stop_solo_jam"):
			current_audio_source.stop_solo_jam()
	else:
		if music_system != null:
			music_system.set_player_instrument_active(instrument_id, false)

	is_playing_instrument = false
	is_playing_solo_jam = false
	started_in_campfire_jam = false

	_stop_instrument_visuals()
	_update_part_label()


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
	return get_closest_interactable()


func get_closest_interactable() -> Node:
	if nearby_interactables.is_empty():
		return null

	var closest_node: Node = null
	var closest_distance := INF

	for node in nearby_interactables:
		if not is_instance_valid(node):
			continue

		var distance := global_position.distance_to(node.global_position)

		if distance < closest_distance:
			closest_distance = distance
			closest_node = node

	return closest_node


func _on_interaction_area_entered(area: Area2D) -> void:
	var possible_interactable := area.get_parent()

	if possible_interactable.is_in_group("interactable") or possible_interactable.is_in_group("npc_musician"):
		if not nearby_interactables.has(possible_interactable):
			nearby_interactables.append(possible_interactable)


func _on_interaction_area_exited(area: Area2D) -> void:
	var possible_interactable := area.get_parent()

	if nearby_interactables.has(possible_interactable):
		nearby_interactables.erase(possible_interactable)


func get_current_audio_source() -> Node:
	var instrument_id := get_current_instrument_id()

	match instrument_id:
		"guitar":
			return guitar_audio_source
		"bass":
			return bass_audio_source
		"harmonica":
			return harmonica_audio_source
		"mandolin":
			return mandolin_audio_source
		_:
			return null

func is_latched_to_campfire_jam() -> bool:
	return is_playing_instrument and started_in_campfire_jam and not is_playing_solo_jam
