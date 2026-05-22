extends Node

@export var bpm: float = 100.0
@export var beats_per_measure: int = 4
@export var loop_measures: int = 8

@export var guitar_stem: AudioStream
@export var bass_stem: AudioStream
@export var harmonica_stem: AudioStream

var song_playing := false
var song_time := 0.0

var seconds_per_beat := 0.0
var seconds_per_measure := 0.0
var loop_length_seconds := 0.0

var current_beat := 1
var current_measure := 1

var stem_players := {}
var active_stems := {
	"guitar": false,
	"bass": true,
	"harmonica": true
}


func _ready() -> void:
	seconds_per_beat = 60.0 / bpm
	seconds_per_measure = seconds_per_beat * beats_per_measure
	loop_length_seconds = seconds_per_measure * loop_measures

	_create_audio_players()


func _process(delta: float) -> void:
	if not song_playing:
		return

	song_time += delta

	if song_time >= loop_length_seconds:
		song_time = fmod(song_time, loop_length_seconds)
		_restart_active_stems()

	_update_timing_values()


func _create_audio_players() -> void:
	var guitar_player := AudioStreamPlayer.new()
	var bass_player := AudioStreamPlayer.new()
	var harmonica_player := AudioStreamPlayer.new()

	guitar_player.name = "GuitarPlayer"
	bass_player.name = "BassPlayer"
	harmonica_player.name = "HarmonicaPlayer"

	add_child(guitar_player)
	add_child(bass_player)
	add_child(harmonica_player)

	guitar_player.stream = guitar_stem
	bass_player.stream = bass_stem
	harmonica_player.stream = harmonica_stem

	stem_players["guitar"] = guitar_player
	stem_players["bass"] = bass_player
	stem_players["harmonica"] = harmonica_player


func start_song() -> void:
	song_playing = true
	song_time = 0.0
	current_beat = 1
	current_measure = 1

	_restart_active_stems()


func stop_song() -> void:
	song_playing = false
	song_time = 0.0
	current_beat = 1
	current_measure = 1

	for stem_name in stem_players.keys():
		stem_players[stem_name].stop()


func toggle_stem(stem_name: String) -> void:
	if not active_stems.has(stem_name):
		print("Unknown stem: ", stem_name)
		return

	var new_state: bool = not active_stems[stem_name]
	set_stem_active(stem_name, new_state)


func set_stem_active(stem_name: String, enabled: bool) -> void:
	if not stem_players.has(stem_name):
		print("No player for stem: ", stem_name)
		return

	var player: AudioStreamPlayer = stem_players[stem_name]

	if player.stream == null:
		print(stem_name, " has no audio stream assigned.")
		return

	active_stems[stem_name] = enabled

	if not song_playing:
		return

	if enabled:
		player.play(song_time)
	else:
		player.stop()


func is_stem_active(stem_name: String) -> bool:
	if not active_stems.has(stem_name):
		return false

	return active_stems[stem_name]


func _restart_active_stems() -> void:
	for stem_name in active_stems.keys():
		if active_stems[stem_name]:
			var player: AudioStreamPlayer = stem_players[stem_name]
			if player.stream != null:
				player.stop()
				player.play(0.0)


func _update_timing_values() -> void:
	var total_beats := int(song_time / seconds_per_beat)

	current_beat = total_beats % beats_per_measure + 1
	current_measure = int(song_time / seconds_per_measure) + 1


func get_loop_position_text() -> String:
	return str(snapped(song_time, 0.01)) + "s / " + str(snapped(loop_length_seconds, 0.01)) + "s"


func start_jam_from_user_input() -> void:
	if song_playing:
		return

	start_song()
