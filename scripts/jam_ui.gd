extends Control

@onready var current_instrument_label: Label = $HBoxContainer/CurrentInstrumentLabel
@onready var interaction_prompt: Label = $HBoxContainer/InteractionPrompt

var player: CharacterBody2D = null
var music_system: Node = null
var jam_started := false


func setup_ui(player_reference: CharacterBody2D, music_system_reference: Node) -> void:
	player = player_reference
	music_system = music_system_reference


func set_jam_started(value: bool) -> void:
	jam_started = value


func update_ui() -> void:
	_update_current_instrument_label()
	_update_interaction_prompt()


func _update_current_instrument_label() -> void:
	if player == null:
		current_instrument_label.text = "Instrument: None"
		return

	if player.has_method("get_current_instrument_display_name"):
		current_instrument_label.text = "Instrument: " + player.get_current_instrument_display_name()
	else:
		current_instrument_label.text = "Instrument: Unknown"


func _update_interaction_prompt() -> void:

	if player == null:
		interaction_prompt.text = ""
		return

	var closest_npc: Node = player.get_closest_npc()

	if closest_npc != null:
		interaction_prompt.text = "Press E to interact"
	else:
		interaction_prompt.text = ""
