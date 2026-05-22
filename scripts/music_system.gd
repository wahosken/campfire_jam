extends Node

@export var bpm := 100.0
@export var beats_per_measure := 4
@export var total_measures := 8

@onready var guitar_stem: AudioStreamPlayer = $GuitarStem
@onready var bass_stem: AudioStreamPlayer = $BassStem
@onready var harmonica_stem: AudioStreamPlayer = $HarmonicaStem

var song_playing := false

var current_beat := 1
var current_measure := 1
var current_loop_position := 0.0

var active_stems := {
	"guitar": false,
	"bass": false,
	"harmonica": false
}


func _ready() -> void:
	add_to_group("music_system")

	set_stem_active("guitar", false)
	set_stem_active("bass", false)
	set_stem_active("harmonica", false)


func _process(_delta: float) -> void:
	if not song_playing:
		return

	_update_timing()
	_check_if_all_players_stopped()


func start_song() -> void:
	if song_playing:
		return

	song_playing = true
	current_beat = 1
	current_measure = 1
	current_loop_position = 0.0

	if guitar_stem != null:
		guitar_stem.play(0.0)

	if bass_stem != null:
		bass_stem.play(0.0)

	if harmonica_stem != null:
		harmonica_stem.play(0.0)

	_apply_all_stem_volumes()


func stop_song() -> void:
	song_playing = false

	if guitar_stem != null:
		guitar_stem.stop()

	if bass_stem != null:
		bass_stem.stop()

	if harmonica_stem != null:
		harmonica_stem.stop()

	current_beat = 1
	current_measure = 1
	current_loop_position = 0.0


func start_jam_from_user_input() -> void:
	start_song()


func set_stem_active(stem_name: String, active: bool) -> void:
	if not active_stems.has(stem_name):
		push_warning("Unknown stem name: " + stem_name)
		return

	active_stems[stem_name] = active

	if active and not song_playing:
		start_song()

	match stem_name:
		"guitar":
			_set_player_muted(guitar_stem, not active)
		"bass":
			_set_player_muted(bass_stem, not active)
		"harmonica":
			_set_player_muted(harmonica_stem, not active)


func _apply_all_stem_volumes() -> void:
	_set_player_muted(guitar_stem, not active_stems["guitar"])
	_set_player_muted(bass_stem, not active_stems["bass"])
	_set_player_muted(harmonica_stem, not active_stems["harmonica"])


func _set_player_muted(player: AudioStreamPlayer, muted: bool) -> void:
	if player == null:
		return

	if muted:
		player.volume_db = -80.0
	else:
		player.volume_db = 0.0


func _check_if_all_players_stopped() -> void:
	for stem_name in active_stems.keys():
		if active_stems[stem_name]:
			return

	stop_song()


func is_stem_active(stem_name: String) -> bool:
	if not active_stems.has(stem_name):
		return false

	return active_stems[stem_name]


func _update_timing() -> void:
	if guitar_stem == null:
		return

	var playback_position := guitar_stem.get_playback_position()

	var seconds_per_beat := 60.0 / bpm
	var total_beats := beats_per_measure * total_measures
	var loop_length_seconds := seconds_per_beat * total_beats

	current_loop_position = fmod(playback_position, loop_length_seconds)

	var beat_index := int(current_loop_position / seconds_per_beat)

	current_beat = beat_index % beats_per_measure + 1
	current_measure = int(float(beat_index) / float(beats_per_measure)) + 1


func get_loop_position_text() -> String:
	return "Measure %d / Beat %d" % [current_measure, current_beat]


func get_current_measure_text() -> String:
	return "Measure: %d" % current_measure


func get_current_beat_text() -> String:
	return "Beat: %d" % current_beat


func get_current_loop_position_text() -> String:
	return "Loop: %.2f" % current_loop_position
