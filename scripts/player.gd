extends CharacterBody2D

@export var debug_player_music := false
@export var speed := 180.0
@export var jam_attach_grace_time := 0.15

@onready var interaction_area: Area2D = $InteractionArea
@onready var sprite: ColorRect = $ColorRect
@onready var part_label: Label = $PlayerPartLabel

@onready var guitar_audio_source: Node = $PlayerAudioSources/GuitarAudioSource
@onready var bass_audio_source: Node = $PlayerAudioSources/BassAudioSource
@onready var harmonica_audio_source: Node = $PlayerAudioSources/HarmonicaAudioSource
@onready var mandolin_audio_source: Node = $PlayerAudioSources/MandolinAudioSource

const NORMAL_COLOR := Color(1, 1, 1, 1)
const PLAYING_COLOR := Color(1.25, 1.1, 0.75, 1)

const NORMAL_SCALE := Vector2(1, 1)
const PLAYING_SCALE := Vector2(1.08, 0.94)

var npc_dialogue_prompt: Node = null

var music_system: Node = null
var jam_manager: Node = null

var current_jam_context: Node = null

var current_requested_part := "silent"
var current_actual_part := "silent"

var wants_rhythm := false
var wants_melody := false

var is_playing_instrument := false
var is_playing_direct_solo := false
var started_in_synced_jam := false

var jam_attach_grace_timer := 0.0

var nearby_interactables: Array[Node] = []

var instrument_visual_tween: Tween = null
var current_instrument_index := 0

var selected_song_id := "song_01"
var current_playing_song_id := "song_01"

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


# ------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------

func _ready() -> void:
	add_to_group("player")

	npc_dialogue_prompt = get_tree().get_first_node_in_group("npc_dialogue_prompt")

	interaction_area.area_entered.connect(_on_interaction_area_entered)
	interaction_area.area_exited.connect(_on_interaction_area_exited)

	music_system = get_tree().get_first_node_in_group("music_system")
	jam_manager = get_tree().get_first_node_in_group("jam_manager")

	_register_player_audio_sources()

	sprite.modulate = NORMAL_COLOR
	sprite.scale = NORMAL_SCALE

	_update_part_label()


func _physics_process(delta: float) -> void:
	if jam_attach_grace_timer > 0.0:
		jam_attach_grace_timer -= delta

	if jam_manager != null and jam_manager.has_method("update_player_jam_proximity"):
		jam_manager.update_player_jam_proximity(global_position)

	_check_for_jam_transition_while_playing()

	if _is_npc_dialogue_prompt_open():
		if is_playing_instrument:
			stop_instrument()

		velocity = Vector2.ZERO
		move_and_slide()
		return

	_handle_movement()
	_handle_npc_interact_input()
	_handle_instrument_cycle_input()
	_handle_song_cycle_input()
	_handle_play_instrument_input()


# ------------------------------------------------------------
# Instrument start / stop
# ------------------------------------------------------------

func start_or_update_instrument_parts(rhythm: bool, melody: bool) -> void:
	var requested_part: String = get_requested_part_from_flags(rhythm, melody)

	if requested_part == "silent":
		stop_instrument()
		return

	if is_playing_instrument:
		if wants_rhythm == rhythm and wants_melody == melody:
			return

		wants_rhythm = rhythm
		wants_melody = melody
		current_requested_part = requested_part

		if is_playing_direct_solo:
			current_actual_part = requested_part

			var current_audio_source: Node = get_current_audio_source()

			if current_audio_source != null:
				if current_audio_source.has_method("set_song_id"):
					current_audio_source.set_song_id(selected_song_id)

				if current_audio_source.has_method("start_solo_tracks"):
					current_audio_source.start_solo_tracks(wants_rhythm, wants_melody)
		else:
			if current_jam_context != null and is_instance_valid(current_jam_context):
				if current_jam_context.has_method("set_member_requested_parts"):
					current_jam_context.set_member_requested_parts(self, wants_rhythm, wants_melody)
				elif current_jam_context.has_method("set_member_requested_part"):
					current_jam_context.set_member_requested_part(self, current_requested_part)

		_update_part_label()
		return

	start_instrument_parts(rhythm, melody)


func start_instrument_parts(rhythm := true, melody := false) -> void:
	if is_playing_instrument:
		return

	if current_jam_context != null and not is_instance_valid(current_jam_context):
		current_jam_context = null

	is_playing_instrument = true
	is_playing_direct_solo = false
	started_in_synced_jam = false

	wants_rhythm = rhythm
	wants_melody = melody
	current_requested_part = get_requested_part_from_flags(wants_rhythm, wants_melody)
	current_actual_part = "silent"
	current_jam_context = null

	if jam_manager != null and jam_manager.has_method("get_current_nearby_jam_context"):
		current_jam_context = jam_manager.get_current_nearby_jam_context()

	if current_jam_context != null:
		_join_current_jam_context()
	else:
		_start_direct_solo()

	_start_instrument_visuals()
	_update_part_label()


func stop_instrument() -> void:
	if not is_playing_instrument:
		return

	var previous_jam_context: Node = current_jam_context
	var current_audio_source: Node = get_current_audio_source()

	# Remove player from current JamContext, if any.
	if current_jam_context != null and is_instance_valid(current_jam_context):
		if current_jam_context.has_method("clear_member_requested_part"):
			current_jam_context.clear_member_requested_part(self)

		if current_jam_context.has_method("set_member_active"):
			current_jam_context.set_member_active(self, false)

	# Let JamManager clean up freeform group ownership if this was a freeform context.
	if jam_manager != null and jam_manager.has_method("handle_player_stopped_playing"):
		jam_manager.handle_player_stopped_playing(previous_jam_context)

	# Stop the player's actual audio source.
	if current_audio_source != null:
		if current_audio_source.has_method("stop_all"):
			current_audio_source.stop_all()
		elif current_audio_source.has_method("stop_solo_jam"):
			current_audio_source.stop_solo_jam()

	is_playing_instrument = false
	is_playing_direct_solo = false
	started_in_synced_jam = false

	current_jam_context = null

	wants_rhythm = false
	wants_melody = false
	current_requested_part = "silent"
	current_actual_part = "silent"

	_stop_instrument_visuals()
	_update_part_label()


func _join_current_jam_context() -> void:
	current_playing_song_id = _get_song_id_from_context(current_jam_context)

	started_in_synced_jam = true
	is_playing_direct_solo = false
	jam_attach_grace_timer = jam_attach_grace_time

	if current_jam_context.has_method("add_member"):
		current_jam_context.add_member(self)

	if current_jam_context.has_method("set_member_requested_parts"):
		current_jam_context.set_member_requested_parts(self, wants_rhythm, wants_melody)
	elif current_jam_context.has_method("set_member_requested_part"):
		current_jam_context.set_member_requested_part(self, current_requested_part)

	if current_jam_context.has_method("set_member_active"):
		current_jam_context.set_member_active(self, true)


func _start_direct_solo() -> void:
	is_playing_direct_solo = true
	current_actual_part = current_requested_part
	current_playing_song_id = selected_song_id

	var current_audio_source: Node = get_current_audio_source()

	if current_audio_source == null:
		return

	if current_audio_source.has_method("set_song_id"):
		current_audio_source.set_song_id(current_playing_song_id)

	if current_audio_source.has_method("start_solo_tracks"):
		current_audio_source.start_solo_tracks(wants_rhythm, wants_melody)


# ------------------------------------------------------------
# Jam transition / carried solo
# ------------------------------------------------------------


func _check_for_jam_transition_while_playing() -> void:
	if not is_playing_instrument:
		return

	if jam_manager == null:
		return

	# Direct solo is sacred. While soloing, the player keeps their current song.
	# JamManager may recruit nearby NPCs if the player is not inside an actual JamSpot.
	if is_playing_direct_solo:
		if jam_manager.has_method("try_auto_attach_npc_to_player"):
			jam_manager.try_auto_attach_npc_to_player(self, global_position)

		return

	if current_jam_context == null:
		return

	if not is_instance_valid(current_jam_context):
		detach_from_current_jam_to_carried_solo()
		return

	var valid_nearby_context: Node = null

	if jam_manager.has_method("get_current_nearby_jam_context"):
		valid_nearby_context = jam_manager.get_current_nearby_jam_context()

	# If the current context is still valid, stay latched.
	if valid_nearby_context == current_jam_context:
		return

	# If the player is already playing and walks into a different context,
	# do NOT switch songs/contexts. Detach into carried solo and preserve
	# the current carried song until the player releases play.
	detach_from_current_jam_to_carried_solo()


func detach_from_current_jam_to_carried_solo() -> void:
	if not is_playing_instrument:
		return

	var previous_context: Node = current_jam_context
	var saved_rhythm := wants_rhythm
	var saved_melody := wants_melody
	var saved_requested_part := current_requested_part

	# Important:
	# Carry the song from the jam being left.
	# Do not use selected_song_id here.
	# Keep the exact song the player is currently carrying.
	# Do not replace it with the context song when detaching.
	var saved_song_id := current_playing_song_id

	if previous_context != null and is_instance_valid(previous_context):
		if previous_context.has_method("detach_member_preserve_audio"):
			previous_context.detach_member_preserve_audio(self)
		else:
			if previous_context.has_method("clear_member_requested_part"):
				previous_context.clear_member_requested_part(self)

			if previous_context.has_method("set_member_active"):
				previous_context.set_member_active(self, false)

	if jam_manager != null and jam_manager.has_method("remove_player_from_freeform_members"):
		jam_manager.remove_player_from_freeform_members(self, previous_context)

	current_jam_context = null
	is_playing_direct_solo = true
	started_in_synced_jam = false

	wants_rhythm = saved_rhythm
	wants_melody = saved_melody
	current_requested_part = saved_requested_part
	current_actual_part = current_requested_part
	current_playing_song_id = saved_song_id

	var current_audio_source: Node = get_current_audio_source()

	if current_audio_source != null:
		if current_audio_source.has_method("set_song_id"):
			current_audio_source.set_song_id(current_playing_song_id)

		if current_audio_source.has_method("start_solo_tracks"):
			current_audio_source.start_solo_tracks(wants_rhythm, wants_melody)

	_start_instrument_visuals()
	_update_part_label()


func return_to_carried_solo_from_freeform() -> void:
	detach_from_current_jam_to_carried_solo()


func mark_as_freeform_jam_context(jam_context: Node) -> void:
	current_jam_context = jam_context
	is_playing_direct_solo = false
	started_in_synced_jam = true
	current_actual_part = "silent"
	jam_attach_grace_timer = jam_attach_grace_time

	_update_part_label()


# ------------------------------------------------------------
# Context setters called by JamContext / JamManager
# ------------------------------------------------------------

func set_current_jam_context(jam_context: Node) -> void:
	current_jam_context = jam_context

	if current_jam_context == null:
		current_actual_part = "silent"

	_update_part_label()


func set_current_part(part_name: String) -> void:
	current_actual_part = part_name
	_update_part_label()


# ------------------------------------------------------------
# Input handling
# ------------------------------------------------------------

func _handle_movement() -> void:
	if _is_npc_dialogue_prompt_open():
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var input_vector := Vector2.ZERO

	input_vector.x = Input.get_axis("move_left", "move_right")
	input_vector.y = Input.get_axis("move_up", "move_down")

	input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()


func _handle_npc_interact_input() -> void:
	if not Input.is_action_just_pressed("interact"):
		return

	if _is_npc_dialogue_prompt_open():
		return

	var closest_interactable: Node = get_closest_interactable()

	if closest_interactable == null:
		return

	# NPCs never execute direct interact behavior from the player.
	# They only open NPCDialoguePrompt.
	if closest_interactable.is_in_group("npc_musician"):
		_open_npc_prompt(closest_interactable)
		return

	# JamSpot interaction proxies and other non-NPC interactables can still use interact().
	if closest_interactable.has_method("interact"):
		closest_interactable.interact()


func _handle_instrument_cycle_input() -> void:
	if Input.is_action_just_pressed("cycle_instrument"):
		cycle_instrument()


func _handle_song_cycle_input() -> void:
	if Input.is_action_just_pressed("cycle_song"):
		cycle_song()


func _handle_play_instrument_input() -> void:
	var melody_pressed := Input.is_action_pressed("play_melody")
	var rhythm_pressed := Input.is_action_pressed("play_rhythm")

	if melody_pressed or rhythm_pressed:
		start_or_update_instrument_parts(rhythm_pressed, melody_pressed)
		return

	if is_playing_instrument:
		stop_instrument()


# ------------------------------------------------------------
# Instrument / song selection
# ------------------------------------------------------------

func cycle_instrument() -> void:
	var was_playing := is_playing_instrument
	var was_direct_solo := is_playing_direct_solo
	var previous_audio_source: Node = get_current_audio_source()

	var saved_rhythm := wants_rhythm
	var saved_melody := wants_melody
	var saved_requested_part := current_requested_part
	var saved_actual_part := current_actual_part
	var saved_context: Node = current_jam_context
	var saved_song_id := current_playing_song_id

	var playback_position := 0.0

	if was_playing and previous_audio_source != null:
		if previous_audio_source.has_method("get_playback_position"):
			playback_position = previous_audio_source.get_playback_position()

		if previous_audio_source.has_method("stop_all"):
			previous_audio_source.stop_all()
		elif previous_audio_source.has_method("stop_solo_jam"):
			previous_audio_source.stop_solo_jam()

	current_instrument_index += 1

	if current_instrument_index >= instruments.size():
		current_instrument_index = 0

	wants_rhythm = saved_rhythm
	wants_melody = saved_melody
	current_requested_part = saved_requested_part
	current_actual_part = saved_actual_part
	current_jam_context = saved_context
	current_playing_song_id = saved_song_id

	if was_playing:
		var new_audio_source: Node = get_current_audio_source()

		if new_audio_source != null:
			if new_audio_source.has_method("set_song_id"):
				new_audio_source.set_song_id(current_playing_song_id)

			if was_direct_solo:
				is_playing_direct_solo = true
				started_in_synced_jam = false
				current_actual_part = current_requested_part

				if new_audio_source.has_method("play_synced"):
					new_audio_source.play_synced(playback_position)

				if new_audio_source.has_method("set_track_volumes"):
					new_audio_source.set_track_volumes(wants_rhythm, wants_melody)
				elif new_audio_source.has_method("set_tracks_audible"):
					new_audio_source.set_tracks_audible(wants_rhythm, wants_melody)
				elif new_audio_source.has_method("start_solo_tracks"):
					new_audio_source.start_solo_tracks(wants_rhythm, wants_melody)
			else:
				is_playing_direct_solo = false
				started_in_synced_jam = true

				if current_jam_context != null and is_instance_valid(current_jam_context):
					if current_jam_context.has_method("set_member_requested_parts"):
						current_jam_context.set_member_requested_parts(self, wants_rhythm, wants_melody)
					elif current_jam_context.has_method("set_member_requested_part"):
						current_jam_context.set_member_requested_part(self, current_requested_part)

					if current_jam_context.has_method("set_member_active"):
						current_jam_context.set_member_active(self, true)

					if new_audio_source.has_method("play_synced"):
						new_audio_source.play_synced(playback_position)

					if current_jam_context.has_method("refresh_arrangement"):
						current_jam_context.refresh_arrangement()

	_start_instrument_visuals()
	_update_part_label()


func cycle_song() -> void:
	# Song selection only affects the next fresh start from silence.
	# It should not change the song while the player is already playing/carrying a jam.
	if is_playing_instrument:
		return

	if selected_song_id == "song_01":
		selected_song_id = "song_02"
	else:
		selected_song_id = "song_01"

	current_playing_song_id = selected_song_id

	print("Selected Song: ", selected_song_id)

	_update_part_label()


func _get_song_id_from_context(jam_context: Node) -> String:
	if jam_context != null and is_instance_valid(jam_context):
		if jam_context.has_method("get_song_id"):
			return jam_context.get_song_id()

		if "song_id" in jam_context:
			return str(jam_context.song_id)

	return selected_song_id


# ------------------------------------------------------------
# Interaction tracking
# ------------------------------------------------------------

func clear_nearby_interactables() -> void:
	nearby_interactables.clear()


func refresh_nearby_interactables() -> void:
	nearby_interactables.clear()

	if interaction_area == null:
		return

	for area in interaction_area.get_overlapping_areas():
		var possible_interactable: Node = _resolve_interactable_from_area(area)

		if possible_interactable == null:
			continue

		_add_nearby_interactable(possible_interactable)

	for body in interaction_area.get_overlapping_bodies():
		if body == null or not is_instance_valid(body):
			continue

		if body.is_in_group("interactable") or body.is_in_group("npc_musician"):
			_add_nearby_interactable(body)


func get_closest_npc() -> Node:
	var closest: Node = get_closest_interactable()

	if closest != null and closest.is_in_group("npc_musician"):
		return closest

	return null


func get_closest_interactable() -> Node:
	_clean_nearby_interactables()

	if nearby_interactables.is_empty():
		return null

	var closest_node: Node = null
	var closest_distance := INF

	for node in nearby_interactables:
		if node == null or not is_instance_valid(node):
			continue

		if node.has_method("is_interaction_temporarily_disabled"):
			if node.is_interaction_temporarily_disabled():
				continue

		if not node is Node2D:
			continue

		var distance := global_position.distance_to(node.global_position)

		if distance < closest_distance:
			closest_distance = distance
			closest_node = node

	return closest_node


func get_closest_prompt_interactable() -> Node:
	_clean_nearby_interactables()

	if nearby_interactables.is_empty():
		return null

	var closest_node: Node = null
	var closest_distance := INF

	for node in nearby_interactables:
		if node == null or not is_instance_valid(node):
			continue

		if node.is_in_group("jam_spot"):
			continue

		if node.has_method("is_interaction_temporarily_disabled"):
			if node.is_interaction_temporarily_disabled():
				continue

		if not node is Node2D:
			continue

		var distance := global_position.distance_to(node.global_position)

		if distance < closest_distance:
			closest_distance = distance
			closest_node = node

	return closest_node


func _open_npc_prompt(npc: Node) -> void:
	if npc == null:
		return

	if is_playing_instrument:
		stop_instrument()

	if npc_dialogue_prompt == null:
		npc_dialogue_prompt = get_tree().get_first_node_in_group("npc_dialogue_prompt")

	if npc_dialogue_prompt != null and npc_dialogue_prompt.has_method("open_for_npc"):
		npc_dialogue_prompt.open_for_npc(npc)


func _on_interaction_area_entered(area: Area2D) -> void:
	var possible_interactable: Node = _resolve_interactable_from_area(area)

	if possible_interactable == null:
		return

	_add_nearby_interactable(possible_interactable)


func _on_interaction_area_exited(area: Area2D) -> void:
	var possible_interactable: Node = _resolve_interactable_from_area(area)

	if possible_interactable == null:
		return

	if nearby_interactables.has(possible_interactable):
		nearby_interactables.erase(possible_interactable)


func _resolve_interactable_from_area(area: Area2D) -> Node:
	if area == null or not is_instance_valid(area):
		return null

	# JamSpot interaction proxy areas are interactable themselves.
	if area.is_in_group("interactable"):
		return area

	var parent: Node = area.get_parent()

	if parent == null or not is_instance_valid(parent):
		return null

	if parent.is_in_group("interactable") or parent.is_in_group("npc_musician"):
		return parent

	return null


func _add_nearby_interactable(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return

	if node.has_method("is_interaction_temporarily_disabled"):
		if node.is_interaction_temporarily_disabled():
			return

	if not node.is_in_group("interactable") and not node.is_in_group("npc_musician"):
		return

	if not nearby_interactables.has(node):
		nearby_interactables.append(node)


func _clean_nearby_interactables() -> void:
	for node in nearby_interactables.duplicate():
		if node == null or not is_instance_valid(node):
			nearby_interactables.erase(node)
			continue

		if node.has_method("is_interaction_temporarily_disabled"):
			if node.is_interaction_temporarily_disabled():
				nearby_interactables.erase(node)


func _is_npc_dialogue_prompt_open() -> bool:
	if npc_dialogue_prompt == null:
		npc_dialogue_prompt = get_tree().get_first_node_in_group("npc_dialogue_prompt")

	if npc_dialogue_prompt == null:
		return false

	if "visible" in npc_dialogue_prompt:
		return npc_dialogue_prompt.visible

	return false


# ------------------------------------------------------------
# Queries for JamContext / UI
# ------------------------------------------------------------

func get_requested_part_from_flags(rhythm: bool, melody: bool) -> String:
	if rhythm and melody:
		return "both"
	elif melody:
		return "melody"
	elif rhythm:
		return "rhythm"

	return "silent"


func get_wants_rhythm() -> bool:
	return wants_rhythm


func get_wants_melody() -> bool:
	return wants_melody


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


func is_latched_to_synced_jam() -> bool:
	return is_playing_instrument and started_in_synced_jam and not is_playing_direct_solo


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


func get_selected_song_id() -> String:
	return selected_song_id


func get_current_playing_song_id() -> String:
	if is_playing_instrument:
		return current_playing_song_id

	return selected_song_id


# ------------------------------------------------------------
# Audio source registration
# ------------------------------------------------------------

func _register_player_audio_sources() -> void:
	if music_system == null:
		return

	if music_system.has_method("register_audio_source"):
		music_system.register_audio_source("guitar", "player", guitar_audio_source)
		music_system.register_audio_source("bass", "player", bass_audio_source)
		music_system.register_audio_source("harmonica", "player", harmonica_audio_source)
		music_system.register_audio_source("mandolin", "player", mandolin_audio_source)


# ------------------------------------------------------------
# Label and visuals
# ------------------------------------------------------------

func _update_part_label() -> void:
	if part_label == null:
		return

	var instrument_name := get_current_instrument_display_name()
	var part_text := "silent"

	if is_playing_direct_solo:
		part_text = current_requested_part
	elif current_actual_part != "silent":
		part_text = current_actual_part
	elif current_jam_context != null and is_instance_valid(current_jam_context) and current_jam_context.has_method("get_current_part_for_member"):
		part_text = current_jam_context.get_current_part_for_member(self)
	elif is_playing_instrument:
		part_text = current_requested_part

	if part_text == "waiting":
		part_label.text = "%s: Waiting" % instrument_name
		return

	if part_text == "silent":
		part_label.text = "%s: ----" % instrument_name
		return

	var db_text := ""

	if part_text == "rhythm" or part_text == "both":
		var rhythm_db := 0.0

		if current_jam_context != null and is_instance_valid(current_jam_context):
			if current_jam_context.has_method("get_rhythm_db_for_member"):
				rhythm_db = current_jam_context.get_rhythm_db_for_member(self)

		if rhythm_db < 0.0:
			db_text = " %.0fdB" % rhythm_db

	part_label.text = "%s: %s%s" % [
		instrument_name,
		part_text.capitalize(),
		db_text
	]


func _start_instrument_visuals() -> void:
	if instrument_visual_tween:
		instrument_visual_tween.kill()
		instrument_visual_tween = null

	if sprite == null:
		return

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

	if sprite != null:
		sprite.modulate = NORMAL_COLOR
		sprite.scale = NORMAL_SCALE


# ------------------------------------------------------------
# Debug
# ------------------------------------------------------------

func _debug_player_music(message: String) -> void:
	if not debug_player_music:
		return

	print("[PLAYER] %s | playing=%s direct_solo=%s synced=%s context=%s req=%s actual=%s wants_rhythm=%s wants_melody=%s play_melody=%s play_rhythm=%s" % [
		message,
		str(is_playing_instrument),
		str(is_playing_direct_solo),
		str(started_in_synced_jam),
		str(current_jam_context),
		str(current_requested_part),
		str(current_actual_part),
		str(wants_rhythm),
		str(wants_melody),
		str(Input.is_action_pressed("play_melody")),
		str(Input.is_action_pressed("play_rhythm"))
	])
