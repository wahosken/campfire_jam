extends Node2D

@onready var music_system: Node = $MusicSystem
@onready var player: CharacterBody2D = $player
@onready var jam_ui: Control = $CanvasLayer/UI

var last_printed_beat := -1
var last_printed_measure := -1
var last_printed_loop_position := ""


func _ready() -> void:
	jam_ui.setup_ui(player, music_system)


func _process(_delta: float) -> void:
	jam_ui.update_ui()
	_print_music_debug_to_console()


func _print_music_debug_to_console() -> void:
	if not music_system.song_started:
		return

	var current_beat: int = int(music_system.beat_index % music_system.beats_per_measure) + 1
	var current_measure: int = int(music_system.current_measure)
	var loop_position_text: String = str(music_system.get_loop_position_text())

	var beat_changed: bool = current_beat != last_printed_beat
	var measure_changed: bool = current_measure != last_printed_measure
	var loop_position_changed: bool = loop_position_text != last_printed_loop_position

	if not beat_changed and not measure_changed and not loop_position_changed:
		return

	last_printed_beat = current_beat
	last_printed_measure = current_measure
	last_printed_loop_position = loop_position_text

	print(
		"Beat: ",
		current_beat,
		" | Measure: ",
		current_measure,
		" | Loop Position: ",
		loop_position_text
	)
