extends Node2D

@export var debug_npc_state := false

@export var instrument_name := "bass"
@export var display_name := ""

@export var can_auto_accompany_player := true
@export var auto_accompany_radius := 300.0

@export var primary_song_id := "song_01"

@export var follow_speed := 120.0
@export var follow_min_distance := 56.0
@export var follow_max_distance := 96.0

@onready var interaction_area: Area2D = $InteractionArea
@onready var sprite: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var audio_source: Node = $InstrumentAudioSource


enum BehaviorState {
	IDLE,
	SCHEDULED,
	LISTENING,
	JAMMING,
	FOLLOWING_PLAYER,
	TRAVELING
}


enum FreeformMode {
	NONE,
	AUTO,
	MANUAL
}


enum MusicControlMode {
	NONE,
	JAM_SPOT,
	FREEFORM_AUTO,
	FREEFORM_MANUAL,
	SCHEDULE
}


var behavior_state := BehaviorState.IDLE
var freeform_mode := FreeformMode.NONE
var music_control_mode := MusicControlMode.NONE

var proximity_blocked_until_reset := false
var interaction_temporarily_disabled := false

var jam_manager: Node = null

var current_jam_spot: Node = null
var current_jam_context: Node = null

var npc_enabled := true
var wants_to_play := false
var wants_rhythm := false
var wants_melody := false

var current_part := "silent"

var following_player := false
var follow_target: Node = null

var instrument_visual_tween: Tween = null

const IDLE_COLOR := Color(1, 1, 1, 1)
const PLAYING_COLOR := Color(1.25, 1.1, 0.75, 1)

const NORMAL_SCALE := Vector2(1, 1)
const PLAYING_SCALE := Vector2(1.08, 0.94)


# ------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------

func _ready() -> void:
	add_to_group("npc_musician")
	add_to_group("interactable")

	jam_manager = get_tree().get_first_node_in_group("jam_manager")

	if display_name == "":
		display_name = instrument_name.capitalize()

	if audio_source != null:
		audio_source.instrument_name = instrument_name
		audio_source.owner_type = "npc"

	_set_visual_idle()
	_update_label()


func _process(delta: float) -> void:
	_update_follow_player(delta)


# ------------------------------------------------------------
# Interaction
# ------------------------------------------------------------

# Basic interact only opens the prompt.
# NPC music should only start/stop through NPCDialoguePrompt.
func interact() -> void:
	if interaction_temporarily_disabled:
		return

	var dialogue_prompt: Node = get_tree().get_first_node_in_group("npc_dialogue_prompt")

	if dialogue_prompt != null and dialogue_prompt.has_method("open_for_npc"):
		dialogue_prompt.open_for_npc(self)


func start_music() -> void:
	# Deprecated safety wrapper.
	# NPC music should start through NPCDialoguePrompt -> toggle_play_song_request().
	pass


func stop_music() -> void:
	# Deprecated safety wrapper.
	# NPC music should stop through NPCDialoguePrompt -> toggle_play_song_request().
	pass


func set_interaction_enabled(is_enabled: bool) -> void:
	# Do NOT disable Area2D monitoring/monitorable.
	# JamSpots may use this area for overlap detection.
	interaction_temporarily_disabled = not is_enabled


func disable_interaction_temporarily() -> void:
	set_interaction_enabled(false)


func enable_interaction() -> void:
	set_interaction_enabled(true)


func is_interaction_temporarily_disabled() -> bool:
	return interaction_temporarily_disabled


# ------------------------------------------------------------
# Prompt music controls
# ------------------------------------------------------------

# Called only by NPCDialoguePrompt.
# Priority:
# 1. Active JamSpot: sit out / rejoin JamSpot.
# 2. Manual freeform: stop/uncommit.
# 3. Auto freeform: promote to manual.
# 4. Nearby jam: join existing jam.
# 5. No jam nearby: start own primary song.
func toggle_play_song_request() -> void:
	_debug_state("toggle_play_song_request START")

	if _handle_active_jam_spot_toggle():
		return

	if _handle_manual_freeform_toggle():
		return

	if _handle_auto_freeform_promotion():
		return

	if _try_join_nearby_jam_from_prompt():
		return

	_start_own_manual_freeform_from_prompt()


func _handle_active_jam_spot_toggle() -> bool:
	if current_jam_spot == null:
		return false

	if not is_instance_valid(current_jam_spot):
		return false

	if not current_jam_spot.has_method("is_jam_active"):
		return false

	if not current_jam_spot.is_jam_active():
		return false

	if npc_enabled:
		set_npc_enabled(false)
	else:
		npc_enabled = true

		freeform_mode = FreeformMode.NONE
		music_control_mode = MusicControlMode.NONE
		proximity_blocked_until_reset = false

		wants_to_play = true
		wants_rhythm = true
		wants_melody = true

		if current_jam_spot.has_method("refresh_npc_activity"):
			current_jam_spot.refresh_npc_activity(self)

	return true


func _handle_manual_freeform_toggle() -> bool:
	if freeform_mode != FreeformMode.MANUAL:
		return false

	if jam_manager != null and jam_manager.has_method("toggle_manual_npc_off"):
		jam_manager.toggle_manual_npc_off(self)
	elif jam_manager != null and jam_manager.has_method("stop_manual_freeform_for_npc"):
		jam_manager.stop_manual_freeform_for_npc(self)
	else:
		stop_freeform_immediately()

	return true


func _handle_auto_freeform_promotion() -> bool:
	if freeform_mode != FreeformMode.AUTO:
		return false

	if jam_manager != null and jam_manager.has_method("promote_auto_npc_to_manual"):
		jam_manager.promote_auto_npc_to_manual(self)
	else:
		start_manual_freeform()

	return true


func _try_join_nearby_jam_from_prompt() -> bool:
	if jam_manager == null:
		return false

	if not jam_manager.has_method("try_add_manual_npc_to_nearby_jam"):
		return false

	return jam_manager.try_add_manual_npc_to_nearby_jam(self)


func _start_own_manual_freeform_from_prompt() -> void:
	freeform_mode = FreeformMode.MANUAL
	music_control_mode = MusicControlMode.FREEFORM_MANUAL
	reset_auto_block()

	var started_with_manager := false

	if jam_manager != null and jam_manager.has_method("start_manual_freeform_npc"):
		started_with_manager = jam_manager.start_manual_freeform_npc(self)

	if not started_with_manager:
		set_requested_parts(true, true)
		set_actual_playing(true)


# ------------------------------------------------------------
# Freeform control
# ------------------------------------------------------------

# Called by JamManager when this NPC auto-joins a freeform jam.
func start_auto_freeform() -> void:
	if not can_use_freeform_logic():
		return

	freeform_mode = FreeformMode.AUTO
	music_control_mode = MusicControlMode.FREEFORM_AUTO

	reset_auto_block()
	_request_both_parts_from_current_context_or_start_solo()


# Called by JamManager when this NPC is committed/indefinite.
func start_manual_freeform() -> void:
	if not can_use_freeform_logic():
		return

	freeform_mode = FreeformMode.MANUAL
	music_control_mode = MusicControlMode.FREEFORM_MANUAL

	reset_auto_block()
	_request_both_parts_from_current_context_or_start_solo()


# Internal control method used by JamManager.
# This is allowed to stop music, but should not be called by raw interact.
func stop_freeform_immediately() -> void:
	if current_jam_context != null and is_instance_valid(current_jam_context):
		if current_jam_context.has_method("clear_member_requested_part"):
			current_jam_context.clear_member_requested_part(self)

		if current_jam_context.has_method("set_member_active"):
			current_jam_context.set_member_active(self, false)

	_stop_current_audio_source()

	freeform_mode = FreeformMode.NONE

	if music_control_mode == MusicControlMode.FREEFORM_AUTO \
		or music_control_mode == MusicControlMode.FREEFORM_MANUAL:
		music_control_mode = MusicControlMode.NONE

	current_jam_context = null

	_clear_playing_state()


func is_auto_freeform() -> bool:
	return freeform_mode == FreeformMode.AUTO


func is_manual_freeform() -> bool:
	return freeform_mode == FreeformMode.MANUAL


func block_auto_until_reset() -> void:
	proximity_blocked_until_reset = true


func reset_auto_block() -> void:
	proximity_blocked_until_reset = false


func is_proximity_blocked() -> bool:
	return proximity_blocked_until_reset


func is_available_for_player_accompaniment() -> bool:
	if not can_use_freeform_logic():
		return false

	if proximity_blocked_until_reset:
		return false

	if not can_auto_accompany_player:
		return false

	if wants_to_play:
		return false

	if current_jam_context != null:
		if music_control_mode == MusicControlMode.JAM_SPOT:
			return false

		if music_control_mode == MusicControlMode.FREEFORM_AUTO:
			return false

		if music_control_mode == MusicControlMode.FREEFORM_MANUAL:
			return false

	return true


func can_use_freeform_logic() -> bool:
	return not is_controlled_by_active_jam_spot()


# ------------------------------------------------------------
# JamSpot control
# ------------------------------------------------------------

func begin_jam_spot_control(jam_spot: Node, jam_context: Node) -> void:
	_debug_state("begin_jam_spot_control from " + str(jam_spot))

	current_jam_spot = jam_spot
	current_jam_context = jam_context

	# If this NPC was previously playing solo/freeform,
	# make sure the JamContext can control its rhythm/melody volumes immediately.
	var source: Node = get_current_audio_source()

	if source != null and source.has_method("force_jam_control"):
		source.force_jam_control()

	freeform_mode = FreeformMode.NONE
	music_control_mode = MusicControlMode.JAM_SPOT

	reset_auto_block()

	wants_to_play = true
	wants_rhythm = true
	wants_melody = true

	# Do not visually claim "both" here.
	# JamContext should resolve the actual part and call set_current_part().
	current_part = "silent"

	if current_jam_context != null:
		if current_jam_context.has_method("set_member_requested_parts"):
			current_jam_context.set_member_requested_parts(self, true, true)
		elif current_jam_context.has_method("set_member_requested_part"):
			current_jam_context.set_member_requested_part(self, "both")

	_update_visual_from_current_part()
	_update_label()


func end_jam_spot_control(jam_spot: Node) -> void:
	_debug_state("end_jam_spot_control from " + str(jam_spot))

	if current_jam_spot != jam_spot:
		return

	if current_jam_context != null and is_instance_valid(current_jam_context):
		if current_jam_context.has_method("clear_member_requested_part"):
			current_jam_context.clear_member_requested_part(self)

		if current_jam_context.has_method("set_member_active"):
			current_jam_context.set_member_active(self, false)

	_stop_current_audio_source()

	if music_control_mode == MusicControlMode.JAM_SPOT:
		music_control_mode = MusicControlMode.NONE

	current_jam_context = null
	current_jam_spot = null

	_clear_playing_state()


func is_in_jam_spot() -> bool:
	return current_jam_spot != null


func is_controlled_by_jam_spot() -> bool:
	return music_control_mode == MusicControlMode.JAM_SPOT


func is_controlled_by_active_jam_spot() -> bool:
	if music_control_mode != MusicControlMode.JAM_SPOT:
		return false

	if current_jam_spot == null:
		return false

	if not is_instance_valid(current_jam_spot):
		return false

	if not current_jam_spot.has_method("is_jam_active"):
		return false

	return current_jam_spot.is_jam_active()


# ------------------------------------------------------------
# Playing state and JamContext requests
# ------------------------------------------------------------

func set_npc_enabled(is_enabled: bool) -> void:
	_debug_state("set_npc_enabled -> " + str(is_enabled))

	npc_enabled = is_enabled

	# If inside an active JamSpot, JamSpot decides the actual music state.
	if current_jam_spot != null and is_instance_valid(current_jam_spot):
		if current_jam_spot.has_method("is_jam_active") and current_jam_spot.is_jam_active():
			if current_jam_spot.has_method("refresh_npc_activity"):
				current_jam_spot.refresh_npc_activity(self)

			return

	# Outside active JamSpot, this is a direct NPC play state.
	set_actual_playing(npc_enabled)


func is_npc_enabled() -> bool:
	return npc_enabled


# Internal control method used by JamSpot/JamManager.
func set_actual_playing(is_playing: bool) -> void:
	_debug_state("set_actual_playing -> " + str(is_playing))

	if wants_to_play == is_playing:
		return

	wants_to_play = is_playing

	if wants_to_play:
		_start_actual_music()
	else:
		_stop_actual_music()


func set_requested_parts(rhythm: bool, melody: bool) -> void:
	wants_rhythm = rhythm
	wants_melody = melody

	# If we are inside a JamContext, do not decide our own visible part.
	# JamContext will call set_current_part() with the actual resolved part.
	if current_jam_context != null:
		if current_jam_context.has_method("set_member_requested_parts"):
			current_jam_context.set_member_requested_parts(self, wants_rhythm, wants_melody)
		elif current_jam_context.has_method("set_member_requested_part"):
			current_jam_context.set_member_requested_part(self, get_requested_part_from_flags(wants_rhythm, wants_melody))

		return

	# Only solo/uncontexted NPCs set their own actual part directly.
	current_part = get_requested_part_from_flags(wants_rhythm, wants_melody)

	_update_visual_from_current_part()
	_update_label()


func get_requested_part_from_flags(rhythm: bool, melody: bool) -> String:
	if rhythm and melody:
		return "both"
	elif melody:
		return "melody"
	elif rhythm:
		return "rhythm"

	return "silent"


func _start_actual_music() -> void:
	if current_part == "silent":
		set_requested_parts(true, true)

	if current_jam_context != null:
		behavior_state = BehaviorState.JAMMING

		if current_jam_context.has_method("add_member"):
			current_jam_context.add_member(self)

		if current_jam_context.has_method("set_member_requested_parts"):
			current_jam_context.set_member_requested_parts(self, wants_rhythm, wants_melody)
		elif current_jam_context.has_method("set_member_requested_part"):
			current_jam_context.set_member_requested_part(self, current_part)

		if current_jam_context.has_method("set_member_active"):
			current_jam_context.set_member_active(self, true)
	else:
		behavior_state = BehaviorState.JAMMING
		current_part = get_requested_part_from_flags(wants_rhythm, wants_melody)

		if audio_source != null and audio_source.has_method("start_solo_tracks"):
			audio_source.start_solo_tracks(wants_rhythm, wants_melody)

	_update_visual_from_current_part()
	_update_label()


func _stop_actual_music() -> void:
	if current_jam_context != null and is_instance_valid(current_jam_context):
		if current_jam_context.has_method("clear_member_requested_part"):
			current_jam_context.clear_member_requested_part(self)

		if current_jam_context.has_method("set_member_active"):
			current_jam_context.set_member_active(self, false)

	_stop_current_audio_source()
	_clear_playing_state()


func set_current_part(part_name: String) -> void:
	current_part = part_name

	match part_name:
		"both":
			wants_rhythm = true
			wants_melody = true
		"melody":
			wants_rhythm = false
			wants_melody = true
		"rhythm":
			wants_rhythm = true
			wants_melody = false
		_:
			wants_rhythm = false
			wants_melody = false

	_update_visual_from_current_part()
	_update_label()


func prepare_for_jam_context_transfer() -> void:
	current_part = "silent"
	wants_rhythm = false
	wants_melody = false

	_update_visual_from_current_part()
	_update_label()


func reset_temporary_music_state_for_jam_join() -> void:
	npc_enabled = true

	freeform_mode = FreeformMode.NONE
	music_control_mode = MusicControlMode.NONE
	proximity_blocked_until_reset = false

	wants_to_play = false
	wants_rhythm = false
	wants_melody = false
	current_part = "silent"

	_update_visual_from_current_part()
	_update_label()


func _clear_playing_state() -> void:
	wants_to_play = false
	wants_rhythm = false
	wants_melody = false
	current_part = "silent"
	behavior_state = BehaviorState.IDLE

	_update_visual_from_current_part()
	_update_label()


func _stop_current_audio_source() -> void:
	var source: Node = get_current_audio_source()

	if source == null:
		return

	if source.has_method("stop_all"):
		source.stop_all()
	elif source.has_method("stop_solo_jam"):
		source.stop_solo_jam()


func _request_both_parts_from_current_context_or_start_solo() -> void:
	wants_to_play = true
	wants_rhythm = true
	wants_melody = true

	if current_jam_context != null:
		if current_jam_context.has_method("set_member_requested_parts"):
			current_jam_context.set_member_requested_parts(self, true, true)
		elif current_jam_context.has_method("set_member_requested_part"):
			current_jam_context.set_member_requested_part(self, "both")

		current_part = "silent"
		_update_visual_from_current_part()
		_update_label()
		return

	set_requested_parts(true, true)
	set_actual_playing(true)


# ------------------------------------------------------------
# Context setters
# ------------------------------------------------------------

func set_current_jam_spot(jam_spot: Node) -> void:
	current_jam_spot = jam_spot


func set_current_jam_context(jam_context: Node) -> void:
	current_jam_context = jam_context


func set_music_control_mode(new_mode: MusicControlMode) -> void:
	music_control_mode = new_mode


func clear_music_control_mode() -> void:
	music_control_mode = MusicControlMode.NONE


# ------------------------------------------------------------
# Following
# ------------------------------------------------------------

func toggle_follow_player() -> void:
	if following_player:
		stop_following_player()
	else:
		start_following_player()


func start_following_player() -> void:
	var player: Node = get_tree().get_first_node_in_group("player")

	if player == null:
		return

	follow_target = player
	following_player = true
	_update_label()


func stop_following_player() -> void:
	following_player = false
	follow_target = null
	_update_label()


func is_following_player() -> bool:
	return following_player


func _update_follow_player(delta: float) -> void:
	if not following_player:
		return

	if follow_target == null or not is_instance_valid(follow_target):
		following_player = false
		_update_label()
		return

	if not follow_target is Node2D:
		return

	var distance: float = global_position.distance_to(follow_target.global_position)

	if distance <= follow_min_distance:
		return

	if distance <= follow_max_distance:
		return

	var direction: Vector2 = global_position.direction_to(follow_target.global_position)
	global_position += direction * follow_speed * delta


# ------------------------------------------------------------
# Queries
# ------------------------------------------------------------

func is_actively_playing_jam() -> bool:
	return wants_to_play or current_part != "silent"


func get_display_name() -> String:
	return display_name


func get_instrument_display_name() -> String:
	return display_name


func get_instrument_id() -> String:
	return instrument_name


func get_current_instrument_id() -> String:
	return instrument_name


func get_jam_audio_source() -> Node:
	return audio_source


func get_current_audio_source() -> Node:
	return audio_source


func get_current_part() -> String:
	return current_part


func get_wants_rhythm() -> bool:
	return wants_rhythm


func get_wants_melody() -> bool:
	return wants_melody


func get_behavior_state() -> BehaviorState:
	return behavior_state


func get_primary_song_id() -> String:
	return primary_song_id


# ------------------------------------------------------------
# Label and visuals
# ------------------------------------------------------------

func _update_label() -> void:
	if label == null:
		return

	var mode_text := ""

	if freeform_mode == FreeformMode.MANUAL:
		mode_text += " [ON]"

	if following_player:
		mode_text += " [FOLLOW]"

	if current_part == "waiting":
		label.text = "%s%s: Waiting" % [
			display_name,
			mode_text
		]
		return

	if current_part == "silent":
		label.text = "%s%s: ----" % [
			display_name,
			mode_text
		]
		return

	var db_text := ""

	if current_part == "rhythm" or current_part == "both":
		var rhythm_db := 0.0

		if current_jam_context != null and current_jam_context.has_method("get_rhythm_db_for_member"):
			rhythm_db = current_jam_context.get_rhythm_db_for_member(self)

		if rhythm_db < 0.0:
			db_text = " %.0fdB" % rhythm_db

	label.text = "%s%s: %s%s" % [
		display_name,
		mode_text,
		current_part.capitalize(),
		db_text
	]


func _update_visual_from_current_part() -> void:
	if current_part == "silent":
		_set_visual_idle()
	else:
		_set_visual_playing()


func _set_visual_playing() -> void:
	if sprite:
		sprite.modulate = PLAYING_COLOR

	if instrument_visual_tween:
		return

	if sprite:
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


func _set_visual_idle() -> void:
	if instrument_visual_tween:
		instrument_visual_tween.kill()
		instrument_visual_tween = null

	if sprite:
		sprite.modulate = IDLE_COLOR
		sprite.scale = NORMAL_SCALE


# ------------------------------------------------------------
# Debug
# ------------------------------------------------------------

func _debug_state(message: String) -> void:
	if debug_npc_state:
		print("[%s] %s | enabled=%s mode=%s freeform=%s jamspot=%s context=%s part=%s wants=%s" % [
			name,
			message,
			str(npc_enabled),
			str(music_control_mode),
			str(freeform_mode),
			str(current_jam_spot),
			str(current_jam_context),
			str(current_part),
			str(wants_to_play)
		])
