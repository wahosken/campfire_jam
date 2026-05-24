extends Node2D

@export var instrument_name := "bass"
@export var display_name := ""

@export var starting_jam_spot_path: NodePath

@export var can_auto_accompany_player := true
@export var auto_accompany_radius := 300.0

@onready var interaction_area: Area2D = $InteractionArea
@onready var sprite: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var audio_source: Node = $InstrumentAudioSource

var jam_manager: Node = null

var current_jam_spot: Node = null
var current_jam_context: Node = null

# Remembered NPC toggle.
# This is what the player changes by interacting with the NPC.
# Jam spots should use this to know whether this NPC should play when the spot is active.
var npc_enabled := true

# Actual/resolved playing state.
# This should only be true when the NPC is currently supposed to be playing.
var wants_to_play := false

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

	_register_with_starting_jam_spot()


func interact() -> void:
	# If this NPC belongs to a jam spot, interacting with the NPC should
	# only toggle that NPC's remembered enabled state.
	# The jam spot decides whether enabled NPCs are actually playing.
	if current_jam_spot != null:
		set_npc_enabled(not npc_enabled)
		return

	# Freeform NPCs still behave like before.
	if wants_to_play:
		stop_music()
	else:
		start_music()


func start_music() -> void:
	# For jam spot NPCs, this means "enable this NPC."
	# It does not necessarily mean "play immediately" unless the jam spot is active.
	if current_jam_spot != null:
		set_npc_enabled(true)
		return

	set_actual_playing(true)


func stop_music() -> void:
	# For jam spot NPCs, this means "disable this NPC."
	# It should be remembered even after the jam spot turns off/on.
	if current_jam_spot != null:
		set_npc_enabled(false)
		return

	set_actual_playing(false)


func set_npc_enabled(is_enabled: bool) -> void:
	if npc_enabled == is_enabled:
		return

	npc_enabled = is_enabled

	# Let the jam spot re-check:
	# should_play = jam_spot_active AND npc_enabled
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


func _start_actual_music() -> void:
	if current_jam_context != null and current_jam_context.has_method("set_member_active"):
		current_jam_context.set_member_active(self, true)
	else:
		current_part = "both"

		if audio_source != null and audio_source.has_method("start_solo_tracks"):
			audio_source.start_solo_tracks(true, true)

	_update_visual_from_current_part()
	_update_label()


func _stop_actual_music() -> void:
	if current_jam_spot == null:
		if jam_manager != null and jam_manager.has_method("end_freeform_jam_if_leader"):
			if jam_manager.has_method("is_freeform_jam_context"):
				if jam_manager.is_freeform_jam_context(current_jam_context):
					jam_manager.end_freeform_jam_if_leader(self)
					current_part = "silent"
					_update_visual_from_current_part()
					_update_label()
					return

	if current_jam_context != null and current_jam_context.has_method("set_member_active"):
		current_jam_context.set_member_active(self, false)
	else:
		if audio_source != null and audio_source.has_method("stop_solo_jam"):
			audio_source.stop_solo_jam()

	current_part = "silent"
	_update_visual_from_current_part()
	_update_label()


func set_current_jam_spot(jam_spot: Node) -> void:
	current_jam_spot = jam_spot


func set_current_jam_context(jam_context: Node) -> void:
	current_jam_context = jam_context


func set_current_part(part_name: String) -> void:
	current_part = part_name
	_update_visual_from_current_part()
	_update_label()


func is_in_jam_spot() -> bool:
	return current_jam_spot != null


func is_available_for_player_accompaniment() -> bool:
	if not can_auto_accompany_player:
		return false

	if is_in_jam_spot():
		return false

	if wants_to_play:
		return false

	if current_jam_context != null:
		return false

	return true


func is_joinable_freeform_leader() -> bool:
	if is_in_jam_spot():
		return false

	if current_jam_context != null:
		return false

	return wants_to_play


func prepare_for_jam_context_transfer() -> void:
	current_part = "silent"
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


func _register_with_starting_jam_spot() -> void:
	if starting_jam_spot_path == NodePath(""):
		return

	var jam_spot := get_node_or_null(starting_jam_spot_path)

	if jam_spot != null and jam_spot.has_method("register_npc"):
		jam_spot.register_npc(self)


func _update_label() -> void:
	if label == null:
		return

	if current_part == "silent":
		label.text = "%s: ----" % display_name
	else:
		label.text = "%s: %s" % [
			display_name,
			current_part.capitalize()
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
