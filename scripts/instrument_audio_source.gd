extends Node2D

@export var instrument_name := "guitar"
@export var owner_type := "npc"

@export var song_01_rhythm_stream: AudioStream
@export var song_01_melody_stream: AudioStream

@export var song_02_rhythm_stream: AudioStream
@export var song_02_melody_stream: AudioStream

@onready var rhythm_player: AudioStreamPlayer2D = $RhythmPlayer
@onready var melody_player: AudioStreamPlayer2D = $MelodyPlayer

const MUTED_DB := -80.0
const FULL_DB := 0.0

var current_song_id := "song_01"

var solo_override := false

var solo_loop_enabled := false

func _ready() -> void:
	if rhythm_player == null:
		push_warning(name + " is missing child AudioStreamPlayer2D: RhythmPlayer")
		return

	if melody_player == null:
		push_warning(name + " is missing child AudioStreamPlayer2D: MelodyPlayer")
		return

	_apply_song_streams()

	_prepare_player(rhythm_player)
	_prepare_player(melody_player)

	set_tracks_audible(false, false)


func _process(_delta: float) -> void:
	if not solo_override:
		return

	if not solo_loop_enabled:
		return

	# Keep both players running during solo mode, even if one is muted.
	# This keeps rhythm/melody aligned when switching parts.
	if rhythm_player != null and rhythm_player.stream != null:
		if not rhythm_player.playing:
			rhythm_player.play(0.0)

	if melody_player != null and melody_player.stream != null:
		if not melody_player.playing:
			melody_player.play(0.0)


func play_synced(from_position := 0.0) -> void:
	solo_override = false
	solo_loop_enabled = false

	var safe_position: float = maxf(from_position, 0.0)

	if rhythm_player != null and rhythm_player.stream != null:
		rhythm_player.stop()
		rhythm_player.play(safe_position)

	if melody_player != null and melody_player.stream != null:
		melody_player.stop()
		melody_player.play(safe_position)


func stop_all() -> void:
	solo_override = false
	solo_loop_enabled = false
	_force_stop_all()


func stop_solo_jam() -> void:
	solo_override = false
	solo_loop_enabled = false
	_force_stop_all()


func adopt_into_synced_jam(rhythm_on: bool, melody_on: bool) -> void:
	solo_override = false
	solo_loop_enabled = false
	_apply_track_volumes(rhythm_on, melody_on)


func restart_synced() -> void:
	solo_override = false
	play_synced(0.0)


func set_tracks_audible(rhythm_on: bool, melody_on: bool) -> void:
	solo_override = false
	_apply_track_volumes(rhythm_on, melody_on)


func set_track_volumes(rhythm_on: bool, melody_on: bool, rhythm_db := FULL_DB, melody_db := FULL_DB) -> void:
	solo_override = false

	if rhythm_player != null:
		rhythm_player.volume_db = rhythm_db if rhythm_on else MUTED_DB

	if melody_player != null:
		melody_player.volume_db = melody_db if melody_on else MUTED_DB


func start_solo_tracks(rhythm_on: bool, melody_on: bool) -> void:
	solo_override = true
	solo_loop_enabled = true

	if rhythm_player != null and rhythm_player.stream != null:
		if not rhythm_player.playing:
			rhythm_player.play(0.0)

	if melody_player != null and melody_player.stream != null:
		if not melody_player.playing:
			melody_player.play(0.0)

	_apply_track_volumes(rhythm_on, melody_on)


func start_solo_jam() -> void:
	start_solo_tracks(true, true)


func get_playback_position() -> float:
	if rhythm_player != null and rhythm_player.playing:
		return rhythm_player.get_playback_position()

	if melody_player != null and melody_player.playing:
		return melody_player.get_playback_position()

	return 0.0


func is_any_track_playing() -> bool:
	if rhythm_player != null and rhythm_player.playing:
		return true

	if melody_player != null and melody_player.playing:
		return true

	return false


func _apply_track_volumes(rhythm_on: bool, melody_on: bool) -> void:
	if rhythm_player != null:
		rhythm_player.volume_db = FULL_DB if rhythm_on else MUTED_DB

	if melody_player != null:
		melody_player.volume_db = FULL_DB if melody_on else MUTED_DB


func _force_stop_all() -> void:
	if rhythm_player != null:
		rhythm_player.stop()
		rhythm_player.volume_db = MUTED_DB

	if melody_player != null:
		melody_player.stop()
		melody_player.volume_db = MUTED_DB


func _prepare_player(player: AudioStreamPlayer2D) -> void:
	if player == null:
		return

	player.volume_db = MUTED_DB
	player.max_distance = 800.0
	player.attenuation = 1.0

	if player.stream != null:
		if "loop" in player.stream:
			player.stream.loop = true


func ensure_synced_playing(from_position := 0.0) -> void:
	solo_override = false

	var safe_position: float = maxf(from_position, 0.0)

	if rhythm_player != null and rhythm_player.stream != null:
		if not rhythm_player.playing:
			rhythm_player.play(safe_position)

	if melody_player != null and melody_player.stream != null:
		if not melody_player.playing:
			melody_player.play(safe_position)


func set_song_id(new_song_id: String) -> void:
	if current_song_id == new_song_id:
		return

	current_song_id = new_song_id
	_apply_song_streams()


func _apply_song_streams() -> void:
	match current_song_id:
		"song_02":
			if rhythm_player != null:
				rhythm_player.stream = song_02_rhythm_stream

			if melody_player != null:
				melody_player.stream = song_02_melody_stream
		_:
			if rhythm_player != null:
				rhythm_player.stream = song_01_rhythm_stream

			if melody_player != null:
				melody_player.stream = song_01_melody_stream
