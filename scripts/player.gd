extends CharacterBody2D

@export var speed := 180.0

@onready var interaction_area: Area2D = $InteractionArea
@onready var sprite: ColorRect = $ColorRect

@onready var guitar_audio_source: Node = $PlayerAudioSources/GuitarAudioSource
@onready var bass_audio_source: Node = $PlayerAudioSources/BassAudioSource
@onready var harmonica_audio_source: Node = $PlayerAudioSources/HarmonicaAudioSource
@onready var mandolin_audio_source: Node = $PlayerAudioSources/MandolinAudioSource

@onready var part_label: Label = $PlayerPartLabel

var current_jam_context: Node = null
var current_requested_part := "silent"

var nearby_interactables: Array[Node] = []

var music_system: Node = null
var jam_manager: Node = null

var is_playing_instrument := false
var is_playing_direct_solo := false
var started_in_synced_jam := false

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
	jam_manager = get_tree().get_first_node_in_group("jam_manager")

	_register_player_audio_sources()

	sprite.modulate = NORMAL_COLOR
	sprite.scale = NORMAL_SCALE

	_update_part_label()


func _physics_process(_delta: float) -> void:
	if jam_manager != null and jam_manager.has_method("update_player_jam_proximity"):
		jam_manager.update_player_jam_proximity(global_position)

	_handle_movement()
	_handle_npc_interact_input()
	_handle_instrument_cycle_input()
	_handle_play_instrument_input()


func start_or_update_instrument(requested_part: String) -> void:
	if is_playing_instrument:
		if current_requested_part == requested_part:
			return

		current_requested_part = requested_part

		if is_playing_direct_solo:
			var current_audio_source := get_current_audio_source()

			if current_audio_source != null and current_audio_source.has_method("start_solo_tracks"):
				current_audio_source.start_solo_tracks(true, true)
		else:
			if current_jam_context != null and current_jam_context.has_method("set_member_requested_part"):
				current_jam_context.set_member_requested_part(self, requested_part)

		_update_part_label()
		return

	start_instrument(requested_part)


func start_instrument(requested_part := "rhythm") -> void:
	if is_playing_instrument:
		return

	is_playing_instrument = true
	is_playing_direct_solo = false
	started_in_synced_jam = false

	current_requested_part = requested_part
	current_jam_context = null

	if jam_manager != null and jam_manager.has_method("get_current_nearby_jam_context"):
		current_jam_context = jam_manager.get_current_nearby_jam_context()

	if current_jam_context == null:
		if jam_manager != null and jam_manager.has_method("create_freeform_jam_with_accompanist"):
			current_jam_context = jam_manager.create_freeform_jam_with_accompanist(self, global_position)

	if current_jam_context != null:
		started_in_synced_jam = true

		if current_jam_context.has_method("add_member"):
			current_jam_context.add_member(self)

		if current_jam_context.has_method("set_member_active"):
			current_jam_context.set_member_active(self, true)

		if current_jam_context.has_method("set_member_requested_part"):
			current_jam_context.set_member_requested_part(self, requested_part)
	else:
		is_playing_direct_solo = true

		var current_audio_source := get_current_audio_source()

		if current_audio_source != null and current_audio_source.has_method("start_solo_tracks"):
			current_audio_source.start_solo_tracks(true, true)

	_start_instrument_visuals()
	_update_part_label()


func stop_instrument() -> void:
	if not is_playing_instrument:
		return

	if is_playing_direct_solo:
		var current_audio_source := get_current_audio_source()

		if current_audio_source != null and current_audio_source.has_method("stop_solo_jam"):
			current_audio_source.stop_solo_jam()
	else:
		if current_jam_context != null:
			if current_jam_context.has_method("clear_member_requested_part"):
				current_jam_context.clear_member_requested_part(self)

			if current_jam_context.has_method("set_member_active"):
				current_jam_context.set_member_active(self, false)

		if jam_manager != null:
			if jam_manager.has_method("is_freeform_jam_context"):
				if jam_manager.is_freeform_jam_context(current_jam_context):
					var freeform_started_by_npc := false

					if jam_manager.has_method("is_active_freeform_started_by_npc"):
						freeform_started_by_npc = jam_manager.is_active_freeform_started_by_npc()

					if freeform_started_by_npc:
						if current_jam_context != null and current_jam_context.has_method("refresh_arrangement"):
							current_jam_context.refresh_arrangement()
					else:
						if jam_manager.has_method("end_freeform_jam"):
							jam_manager.end_freeform_jam()

	is_playing_instrument = false
	is_playing_direct_solo = false
	started_in_synced_jam = false

	current_jam_context = null
	current_requested_part = "silent"

	_stop_instrument_visuals()
	_update_part_label()


func cycle_instrument() -> void:
	var was_playing := is_playing_instrument
	var previous_requested_part := current_requested_part
	var previous_direct_solo := is_playing_direct_solo
	var previous_audio_source := get_current_audio_source()

	if was_playing and previous_audio_source != null:
		if previous_audio_source.has_method("stop_solo_jam"):
			previous_audio_source.stop_solo_jam()
		elif previous_audio_source.has_method("stop_all"):
			previous_audio_source.stop_all()

	current_instrument_index += 1

	if current_instrument_index >= instruments.size():
		current_instrument_index = 0

	current_requested_part = previous_requested_part

	if was_playing:
		if previous_direct_solo:
			var new_audio_source := get_current_audio_source()

			if new_audio_source != null and new_audio_source.has_method("start_solo_tracks"):
				new_audio_source.start_solo_tracks(true, true)
		else:
			if current_jam_context != null:
				if current_jam_context.has_method("set_member_requested_part"):
					current_jam_context.set_member_requested_part(self, previous_requested_part)

				if current_jam_context.has_method("set_member_active"):
					current_jam_context.set_member_active(self, true)

				if current_jam_context.has_method("refresh_arrangement"):
					current_jam_context.refresh_arrangement()

	_update_part_label()


func get_current_instrument_id() -> String:
	return instruments[current_instrument_index]["id"]


func get_current_instrument_display_name() -> String:
	return instruments[current_instrument_index]["display_name"]


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


func get_closest_prompt_interactable() -> Node:
	if nearby_interactables.is_empty():
		return null

	var closest_node: Node = null
	var closest_distance := INF

	for node in nearby_interactables:
		if not is_instance_valid(node):
			continue

		if node.is_in_group("jam_spot"):
			continue

		var distance := global_position.distance_to(node.global_position)

		if distance < closest_distance:
			closest_distance = distance
			closest_node = node

	return closest_node


func is_latched_to_synced_jam() -> bool:
	return is_playing_instrument and started_in_synced_jam and not is_playing_direct_solo


func is_latched_to_campfire_jam() -> bool:
	return is_latched_to_synced_jam()


func is_currently_playing_solo_jam() -> bool:
	return is_playing_direct_solo


func get_current_jam_leader_text() -> String:
	if is_playing_direct_solo:
		return "Player"

	return ""


func get_current_active_instruments_text() -> String:
	if is_playing_direct_solo:
		return get_current_instrument_display_name()

	return ""


func get_current_featured_instrument_text() -> String:
	if is_playing_direct_solo:
		return get_current_instrument_display_name()

	return ""


func _register_player_audio_sources() -> void:
	if music_system == null:
		return

	if music_system.has_method("register_audio_source"):
		music_system.register_audio_source("guitar", "player", guitar_audio_source)
		music_system.register_audio_source("bass", "player", bass_audio_source)
		music_system.register_audio_source("harmonica", "player", harmonica_audio_source)
		music_system.register_audio_source("mandolin", "player", mandolin_audio_source)


func _handle_movement() -> void:
	var input_vector := Vector2.ZERO

	input_vector.x = Input.get_axis("move_left", "move_right")
	input_vector.y = Input.get_axis("move_up", "move_down")

	input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()


func _handle_npc_interact_input() -> void:
	if Input.is_action_just_pressed("interact"):
		var closest_interactable := get_closest_interactable()

		if closest_interactable != null and closest_interactable.has_method("interact"):
			closest_interactable.interact()


func _handle_instrument_cycle_input() -> void:
	if Input.is_action_just_pressed("cycle_instrument"):
		cycle_instrument()


func _handle_play_instrument_input() -> void:
	var melody_pressed := Input.is_action_pressed("play_melody")
	var rhythm_pressed := Input.is_action_pressed("play_rhythm")

	if melody_pressed:
		start_or_update_instrument("melody")
	elif rhythm_pressed:
		start_or_update_instrument("rhythm")
	else:
		stop_instrument()


func _update_part_label() -> void:
	if part_label == null:
		return

	var instrument_name := get_current_instrument_display_name()
	var part_text := "silent"

	if is_playing_direct_solo:
		part_text = "both"
	elif is_playing_instrument:
		part_text = current_requested_part
	elif current_jam_context != null and current_jam_context.has_method("get_current_part_for_member"):
		part_text = current_jam_context.get_current_part_for_member(self)

	if part_text == "silent":
		part_label.text = "%s: ----" % instrument_name
	else:
		part_label.text = "%s: %s" % [
			instrument_name,
			part_text.capitalize()
		]


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


func _on_interaction_area_entered(area: Area2D) -> void:
	var possible_interactable := area.get_parent()

	if possible_interactable.is_in_group("interactable") or possible_interactable.is_in_group("npc_musician"):
		if not nearby_interactables.has(possible_interactable):
			nearby_interactables.append(possible_interactable)


func _on_interaction_area_exited(area: Area2D) -> void:
	var possible_interactable := area.get_parent()

	if nearby_interactables.has(possible_interactable):
		nearby_interactables.erase(possible_interactable)
