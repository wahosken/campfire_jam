extends Node2D

@onready var music_system: Node = $MusicSystem
@onready var player: CharacterBody2D = $player

@onready var current_instrument_label: Label = $CanvasLayer/UI/HBoxContainer/CurrentInstrumentLabel
@onready var interaction_prompt: Label = $CanvasLayer/UI/HBoxContainer/InteractionPrompt
@onready var current_beat_label: Label = $CanvasLayer/UI/HBoxContainer/CurrentBeatLabel
@onready var current_measure_label: Label = $CanvasLayer/UI/HBoxContainer/CurrentMeasureLabel
@onready var current_loop_position_label: Label = $CanvasLayer/UI/HBoxContainer/CurrentLoopPositionLabel


func _process(_delta: float) -> void:
	_update_music_labels()
	_update_interaction_prompt()
	_update_current_instrument_label()


func _update_music_labels() -> void:
	current_beat_label.text = "Current Beat: " + str(music_system.current_beat)
	current_measure_label.text = "Current Measure: " + str(music_system.current_measure)
	current_loop_position_label.text = "Current Loop Position: " + music_system.get_loop_position_text()


func _update_interaction_prompt() -> void:
	if player.nearby_jam_spot == null:
		interaction_prompt.text = ""
		return

	var spot = player.nearby_jam_spot
	var stem_name: String = spot.stem_name
	var instrument_name: String = spot.instrument_name

	if music_system.is_stem_active(stem_name):
		interaction_prompt.text = "Press E to stop playing " + instrument_name
	else:
		interaction_prompt.text = "Press E to play " + instrument_name


func _update_current_instrument_label() -> void:
	var active_instruments: Array[String] = []

	if music_system.is_stem_active("guitar"):
		active_instruments.append("Guitar")

	if music_system.is_stem_active("bass"):
		active_instruments.append("Bass")

	if music_system.is_stem_active("harmonica"):
		active_instruments.append("Harmonica")

	if active_instruments.is_empty():
		current_instrument_label.text = "Current Instrument: None"
	else:
		current_instrument_label.text = "Current Instrument: " + ", ".join(active_instruments)
