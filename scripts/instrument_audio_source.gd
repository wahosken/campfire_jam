extends Node2D

@export var instrument_name := "guitar"
@export var owner_type := "npc"

@export var rhythm_stream: AudioStream
@export var melody_stream: AudioStream

@onready var rhythm_player: AudioStreamPlayer2D = $RhythmPlayer
@onready var melody_player: AudioStreamPlayer2D = $MelodyPlayer

const MUTED_DB := -80.0
const FULL_DB := 0.0

var solo_override := false


func _ready() -> void:
	if rhythm_player == null:
		push_warning(name + " is missing child AudioStreamPlayer2D: RhythmPlayer")
		return

	if melody_player == null:
		push_warning(name + " is missing child AudioStreamPlayer2D: MelodyPlayer")
		return

	rhythm_player.stream = rhythm_stream
	melody_player.stream = melody_stream

	_prepare_player(rhythm_player)
	_prepare_player(melody_player)

	set_tracks_audible(false, false)


func play_synced(from_position := 0.0) -> void:
	solo_override = false

	if rhythm_player != null and rhythm_player.stream != null:
		rhythm_player.play(from_position)

	if melody_player != null and melody_player.stream != null:
		melody_player.play(from_position)


func restart_synced() -> void:
	solo_override = false
	play_synced(0.0)


func stop_all() -> void:
	solo_override = false
	_force_stop_all()


func set_tracks_audible(rhythm_on: bool, melody_on: bool) -> void:
	if solo_override:
		return

	if rhythm_player != null:
		rhythm_player.volume_db = FULL_DB if rhythm_on else MUTED_DB

	if melody_player != null:
		melody_player.volume_db = FULL_DB if melody_on else MUTED_DB


func start_solo_tracks(rhythm_on: bool, melody_on: bool) -> void:
	solo_override = true

	if rhythm_player != null and rhythm_player.stream != null:
		rhythm_player.play(0.0)
		rhythm_player.volume_db = FULL_DB if rhythm_on else MUTED_DB

	if melody_player != null and melody_player.stream != null:
		melody_player.play(0.0)
		melody_player.volume_db = FULL_DB if melody_on else MUTED_DB


func get_playback_position() -> float:
	if rhythm_player != null and rhythm_player.playing:
		return rhythm_player.get_playback_position()

	if melody_player != null and melody_player.playing:
		return melody_player.get_playback_position()

	return 0.0

func adopt_into_synced_jam(rhythm_on: bool, melody_on: bool) -> void:
	solo_override = false
	set_tracks_audible(rhythm_on, melody_on)



func start_solo_jam() -> void:
	start_solo_tracks(true, true)


func stop_solo_jam() -> void:
	solo_override = false
	_force_stop_all()


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
