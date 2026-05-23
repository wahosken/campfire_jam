extends Node2D

@export var instrument_name := "bass"
@export var display_name := ""

@onready var interaction_area: Area2D = $InteractionArea
@onready var sprite: ColorRect = $ColorRect
@onready var label: Label = $Label
@onready var audio_source: Node = $InstrumentAudioSource

var music_system: Node = null
var wants_to_play := false

const IDLE_COLOR := Color(1, 1, 1, 1)
const PLAYING_COLOR := Color(1.25, 1.1, 0.75, 1)


func _ready() -> void:
	add_to_group("npc_musician")
	add_to_group("interactable")

	music_system = get_tree().get_first_node_in_group("music_system")

	if display_name == "":
		display_name = instrument_name.capitalize()

	if audio_source != null:
		audio_source.instrument_name = instrument_name
		audio_source.owner_type = "npc"

	if music_system != null:
		music_system.register_audio_source(instrument_name, "npc", audio_source)
		music_system.instrument_owner_changed.connect(_on_instrument_owner_changed)
		music_system.arrangement_changed.connect(_on_arrangement_changed)
	else:
		push_warning("NPC could not find music_system group.")

	_set_visual_idle()
	_update_label()


func interact() -> void:
	if wants_to_play:
		stop_music()
	else:
		start_music()


func start_music() -> void:
	if wants_to_play:
		return

	wants_to_play = true

	if music_system != null:
		music_system.set_npc_instrument_active(instrument_name, true)
	else:
		push_warning("NPC could not find music_system group.")

	_update_visual_from_owner()
	_update_label()


func stop_music() -> void:
	if not wants_to_play:
		return

	wants_to_play = false

	if music_system != null:
		music_system.set_npc_instrument_active(instrument_name, false)
	else:
		push_warning("NPC could not find music_system group.")

	_set_visual_idle()
	_update_label()


func _on_instrument_owner_changed(changed_instrument_name: String, _instrument_owner: String) -> void:
	if changed_instrument_name != instrument_name:
		return

	_update_visual_from_owner()
	_update_label()


func _on_arrangement_changed() -> void:
	_update_visual_from_owner()
	_update_label()


func _update_visual_from_owner() -> void:
	if not wants_to_play:
		_set_visual_idle()
		return

	if music_system == null:
		_set_visual_idle()
		return

	if music_system.is_same_instrument_duet(instrument_name):
		_set_visual_playing()
		return

	if music_system.should_same_instrument_npc_play_rhythm(instrument_name):
		_set_visual_playing()
		return

	var instrument_owner: String = music_system.get_instrument_owner(instrument_name)

	if instrument_owner == "npc":
		_set_visual_playing()
	else:
		_set_visual_idle()


func _update_label() -> void:
	if label == null:
		return

	var part_text := "silent"

	if music_system != null and music_system.has_method("get_current_owner_part"):
		part_text = music_system.get_current_owner_part("npc", instrument_name)

	if part_text == "silent":
		label.text = "%s: ----" % display_name
	else:
		label.text = "%s: %s" % [
			display_name,
			part_text.capitalize()
		]


func _set_visual_playing() -> void:
	if sprite:
		sprite.modulate = PLAYING_COLOR


func _set_visual_idle() -> void:
	if sprite:
		sprite.modulate = IDLE_COLOR

func is_actively_playing_jam() -> bool:
	return wants_to_play
