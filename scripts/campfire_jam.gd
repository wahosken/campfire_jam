extends Node2D

@onready var music_system: Node = $MusicSystem
@onready var player: CharacterBody2D = $player

@onready var current_instrument_label: Label = $CanvasLayer/UI/HBoxContainer/CurrentInstrumentLabel
@onready var interaction_prompt: Label = $CanvasLayer/UI/HBoxContainer/InteractionPrompt
@onready var current_beat_label: Label = $CanvasLayer/UI/HBoxContainer/CurrentBeatLabel
@onready var current_measure_label: Label = $CanvasLayer/UI/HBoxContainer/CurrentMeasureLabel
@onready var current_loop_position_label: Label = $CanvasLayer/UI/HBoxContainer/CurrentLoopPositionLabel

var jam_started := false

func _process(_delta: float) -> void:
	_handle_start_jam_input()

	_update_music_labels()
	_update_interaction_prompt()
	_update_current_instrument_label()


func _handle_start_jam_input() -> void:
	if jam_started:
		return

	if Input.is_anything_pressed():
		jam_started = true
		music_system.start_jam_from_user_input()


func _update_music_labels() -> void:
	current_beat_label.text = "Current Beat: " + str(music_system.current_beat)
	current_measure_label.text = "Current Measure: " + str(music_system.current_measure)
	current_loop_position_label.text = "Current Loop Position: " + music_system.get_loop_position_text()


func _update_interaction_prompt() -> void:
	if not jam_started:
		interaction_prompt.text = "Press any key to start jam"
		return

	if Input.is_action_pressed("interact"):
		interaction_prompt.text = "Playing Guitar"
	else:
		interaction_prompt.text = "Hold E to strum Guitar"


func _update_current_instrument_label() -> void:
	if music_system.is_stem_active("guitar"):
		current_instrument_label.text = "You: Guitar | NPCs: Bass, Harmonica"
	else:
		current_instrument_label.text = "You: Not Playing | NPCs: Bass, Harmonica"
