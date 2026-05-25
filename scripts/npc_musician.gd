extends Node2D

@export var instrument_name := "bass"
@export var display_name := ""

@export var can_auto_accompany_player := true
@export var auto_accompany_radius := 300.0

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

var music_control_mode := MusicControlMode.NONE

var behavior_state := BehaviorState.IDLE
var freeform_mode := FreeformMode.NONE
var proximity_blocked_until_reset := false

var jam_manager: Node = null

var current_jam_spot: Node = null
var current_jam_context: Node = null

var npc_enabled := true
var wants_to_play := false

var wants_rhythm := false
var wants_melody := false

var current_part := "silent"

var instrument_visual_tween: Tween = null

const IDLE_COLOR := Color(1, 1, 1, 1)
const PLAYING_COLOR := Color(1.25, 1.1, 0.75, 1)

const NORMAL_SCALE := Vector2(1, 1)
const PLAYING_SCALE := Vector2(1.08, 0.94)


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


func interact() -> void:
	if is_controlled_by_active_jam_spot():
		set_npc_enabled(not npc_enabled)
		return

	# AUTO follower becomes MANUAL / indefinite.
	# This means the player has intentionally invited/locked this NPC into the jam.
	if freeform_mode == FreeformMode.AUTO:
		if jam_manager != null and jam_manager.has_method("promote_auto_npc_to_manual"):
			jam_manager.promote_auto_npc_to_manual(self)
		else:
			start_manual_freeform()

		return

	# MANUAL NPC toggles off.
	# JamManager decides whether they fully stop or fall back into AUTO
	# because another manual/freeform leader is still active nearby.
	if freeform_mode == FreeformMode.MANUAL:
		if jam_manager != null and jam_manager.has_method("toggle_manual_npc_off"):
			jam_manager.toggle_manual_npc_off(self)
		elif jam_manager != null and jam_manager.has_method("stop_manual_freeform_for_npc"):
			jam_manager.stop_manual_freeform_for_npc(self)
		else:
			stop_freeform_immediately()

		return

	# Idle NPC starts an indefinite/manual freeform jam.
	freeform_mode = FreeformMode.MANUAL
	music_control_mode = MusicControlMode.FREEFORM_MANUAL
	reset_auto_block()

	var started_with_manager := false

	if jam_manager != null and jam_manager.has_method("start_manual_freeform_npc"):
		started_with_manager = jam_manager.start_manual_freeform_npc(self)

	if not started_with_manager:
		set_requested_parts(true, true)
		set_actual_playing(true)


func start_music() -> void:
	if current_jam_spot != null:
		set_npc_enabled(true)
		return

	freeform_mode = FreeformMode.MANUAL
	set_requested_parts(true, true)
	set_actual_playing(true)


func stop_music() -> void:
	if current_jam_spot != null:
		set_npc_enabled(false)
		return

	stop_freeform_immediately()


func start_auto_freeform() -> void:
	if not can_use_freeform_logic():
		return

	freeform_mode = FreeformMode.AUTO
	music_control_mode = MusicControlMode.FREEFORM_AUTO

	set_requested_parts(true, true)
	set_actual_playing(true)


func start_manual_freeform() -> void:
	if not can_use_freeform_logic():
		return

	freeform_mode = FreeformMode.MANUAL
	music_control_mode = MusicControlMode.FREEFORM_MANUAL

	reset_auto_block()
	set_requested_parts(true, true)
	set_actual_playing(true)


func stop_freeform_immediately() -> void:
	if freeform_mode == FreeformMode.AUTO or freeform_mode == FreeformMode.MANUAL:
		music_control_mode = MusicControlMode.NONE

	freeform_mode = FreeformMode.NONE
	set_actual_playing(false)

	var source: Node = get_current_audio_source()

	if source != null and source.has_method("stop_all"):
		source.stop_all()

	wants_rhythm = false
	wants_melody = false
	current_part = "silent"
	behavior_state = BehaviorState.IDLE

	_update_visual_from_current_part()
	_update_label()


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

	# Only block freeform if another non-inactive context is actually controlling this NPC.
	# Being inside an inactive JamSpot should not count.
	if current_jam_context != null:
		if music_control_mode == MusicControlMode.JAM_SPOT:
			return false

		if music_control_mode == MusicControlMode.FREEFORM_AUTO:
			return false

		if music_control_mode == MusicControlMode.FREEFORM_MANUAL:
			return false

	return true


func set_npc_enabled(is_enabled: bool) -> void:
	if npc_enabled == is_enabled:
		return

	npc_enabled = is_enabled

	if current_jam_spot != null and current_jam_spot.has_method("refresh_npc_activity"):
		current_jam_spot.refresh_npc_activity(self)
	else:
		set_actual_playing(npc_enabled)


func is_npc_enabled() -> bool:
	return npc_enabled


func set_actual_playing(is_playing: bool) -> void:
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
	current_part = get_requested_part_from_flags(wants_rhythm, wants_melody)

	if current_jam_context != null:
		if current_jam_context.has_method("set_member_requested_parts"):
			current_jam_context.set_member_requested_parts(self, wants_rhythm, wants_melody)
		elif current_jam_context.has_method("set_member_requested_part"):
			current_jam_context.set_member_requested_part(self, current_part)

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
	if current_jam_context != null:
		if current_jam_context.has_method("clear_member_requested_part"):
			current_jam_context.clear_member_requested_part(self)

		if current_jam_context.has_method("set_member_active"):
			current_jam_context.set_member_active(self, false)
	else:
		if audio_source != null and audio_source.has_method("stop_solo_jam"):
			audio_source.stop_solo_jam()

	wants_rhythm = false
	wants_melody = false
	current_part = "silent"
	behavior_state = BehaviorState.IDLE

	_update_visual_from_current_part()
	_update_label()


func set_current_jam_spot(jam_spot: Node) -> void:
	current_jam_spot = jam_spot


func set_current_jam_context(jam_context: Node) -> void:
	current_jam_context = jam_context


func begin_jam_spot_control(jam_spot: Node, jam_context: Node) -> void:
	current_jam_spot = jam_spot
	current_jam_context = jam_context

	freeform_mode = FreeformMode.NONE
	music_control_mode = MusicControlMode.JAM_SPOT

	reset_auto_block()
	set_requested_parts(true, true)


func end_jam_spot_control(jam_spot: Node) -> void:
	if current_jam_spot != jam_spot:
		return

	if current_jam_context != null:
		if current_jam_context.has_method("set_member_active"):
			current_jam_context.set_member_active(self, false)

	if music_control_mode == MusicControlMode.JAM_SPOT:
		music_control_mode = MusicControlMode.NONE

	current_jam_context = null
	current_part = "silent"
	wants_to_play = false
	wants_rhythm = false
	wants_melody = false

	_update_visual_from_current_part()
	_update_label()


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


func is_in_jam_spot() -> bool:
	return current_jam_spot != null


func prepare_for_jam_context_transfer() -> void:
	current_part = "silent"
	wants_rhythm = false
	wants_melody = false

	_update_visual_from_current_part()
	_update_label()


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


func _update_label() -> void:
	if label == null:
		return

	var mode_text := ""

	if freeform_mode == FreeformMode.MANUAL:
		mode_text = " [ON]"

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


func set_music_control_mode(new_mode: MusicControlMode) -> void:
	music_control_mode = new_mode


func clear_music_control_mode() -> void:
	music_control_mode = MusicControlMode.NONE


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


func can_use_freeform_logic() -> bool:
	if is_controlled_by_active_jam_spot():
		return false

	return true
