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

var npc_active_instruments := {
	"guitar": false,
	"bass": false,
	"harmonica": false
}

var player_active_instrument := ""


func _ready() -> void:
	add_to_group("music_system")

	_set_stem_active("guitar", false)
	_set_stem_active("bass", false)
	_set_stem_active("harmonica", false)


func _process(_delta: float) -> void:
	if not song_playing:
		return

	_update_timing()
	_stop_song_if_everyone_stopped()


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


func npc_toggle_instrument(instrument_id: String) -> void:
	if not npc_active_instruments.has(instrument_id):
		push_warning("Unknown NPC instrument: " + instrument_id)
		return

	var currently_active: bool = npc_active_instruments[instrument_id]
	set_npc_instrument_active(instrument_id, not currently_active)


func set_npc_instrument_active(instrument_id: String, active: bool) -> void:
	if not npc_active_instruments.has(instrument_id):
		push_warning("Unknown NPC instrument: " + instrument_id)
		return

	npc_active_instruments[instrument_id] = active

	var player_is_playing_this_instrument: bool = player_active_instrument == instrument_id

	if active:
		if not song_playing:
			start_song()

		if player_is_playing_this_instrument:
			_set_matching_npcs_visual_playing(instrument_id, false)
		else:
			_set_matching_npcs_visual_playing(instrument_id, true)

		_set_stem_active(instrument_id, true)
	else:
		_set_matching_npcs_visual_playing(instrument_id, false)

		if player_is_playing_this_instrument:
			_set_stem_active(instrument_id, true)
		else:
			_set_stem_active(instrument_id, false)

	_stop_song_if_everyone_stopped()


func player_take_over_instrument(instrument_id: String) -> void:
	if not active_stems.has(instrument_id):
		push_warning("Unknown player instrument: " + instrument_id)
		return

	player_active_instrument = instrument_id

	if not song_playing:
		start_song()

	_set_matching_npcs_visual_playing(instrument_id, false)
	_set_stem_active(instrument_id, true)


func player_release_instrument(instrument_id: String) -> void:
	if player_active_instrument != instrument_id:
		return

	player_active_instrument = ""

	var matching_npc_was_active: bool = npc_active_instruments[instrument_id]

	if matching_npc_was_active:
		_set_matching_npcs_visual_playing(instrument_id, true)
		_set_stem_active(instrument_id, true)
	else:
		_set_matching_npcs_visual_playing(instrument_id, false)
		_set_stem_active(instrument_id, false)

	_stop_song_if_everyone_stopped()


func _is_any_other_npc_playing(excluded_instrument_id: String) -> bool:
	for instrument_id: String in npc_active_instruments.keys():
		if instrument_id == excluded_instrument_id:
			continue

		if npc_active_instruments[instrument_id]:
			return true

	return false


func _stop_song_if_everyone_stopped() -> void:
	if player_active_instrument != "":
		return

	for instrument_id: String in npc_active_instruments.keys():
		if npc_active_instruments[instrument_id]:
			return

	stop_song()


func _set_stem_active(stem_name: String, active: bool) -> void:
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


func is_stem_active(stem_name: String) -> bool:
	if not active_stems.has(stem_name):
		return false

	return active_stems[stem_name]


func _set_matching_npcs_visual_playing(instrument_id: String, playing: bool) -> void:
	var npcs: Array[Node] = get_tree().get_nodes_in_group("npc_musician")

	for npc: Node in npcs:
		if not npc.has_method("get_instrument_id"):
			continue

		if not npc.has_method("set_visual_playing"):
			continue

		var npc_instrument_id: String = npc.get_instrument_id()

		if npc_instrument_id == instrument_id:
			npc.set_visual_playing(playing)


func _update_timing() -> void:
	if guitar_stem == null:
		return

	var playback_position: float = guitar_stem.get_playback_position()

	var seconds_per_beat: float = 60.0 / bpm
	var total_beats: int = beats_per_measure * total_measures
	var loop_length_seconds: float = seconds_per_beat * float(total_beats)

	current_loop_position = fmod(playback_position, loop_length_seconds)

	var beat_index: int = int(current_loop_position / seconds_per_beat)

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
