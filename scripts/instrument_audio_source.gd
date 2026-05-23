extends Node2D

@export var instrument_name := "guitar"
@export var owner_type := "npc"

@export var rhythm_stream: AudioStream
@export var melody_stream: AudioStream

@onready var rhythm_player: AudioStreamPlayer2D = $RhythmPlayer
@onready var melody_player: AudioStreamPlayer2D = $MelodyPlayer

const MUTED_DB := -80.0
const FULL_DB := 0.0


func _ready() -> void:
	rhythm_player.stream = rhythm_stream
	melody_player.stream = melody_stream

	_prepare_player(rhythm_player)
	_prepare_player(melody_player)

	set_tracks_audible(false, false)


func set_streams(new_instrument_name: String, new_rhythm_stream: AudioStream, new_melody_stream: AudioStream) -> void:
	instrument_name = new_instrument_name
	rhythm_stream = new_rhythm_stream
	melody_stream = new_melody_stream

	rhythm_player.stream = rhythm_stream
	melody_player.stream = melody_stream

	_prepare_player(rhythm_player)
	_prepare_player(melody_player)

	set_tracks_audible(false, false)


func play_synced(from_position := 0.0) -> void:
	if rhythm_player.stream != null:
		rhythm_player.play(from_position)

	if melody_player.stream != null:
		melody_player.play(from_position)


func restart_synced() -> void:
	play_synced(0.0)


func stop_all() -> void:
	rhythm_player.stop()
	melody_player.stop()

	set_tracks_audible(false, false)


func set_tracks_audible(rhythm_on: bool, melody_on: bool) -> void:
	rhythm_player.volume_db = FULL_DB if rhythm_on else MUTED_DB
	melody_player.volume_db = FULL_DB if melody_on else MUTED_DB


func _prepare_player(player: AudioStreamPlayer2D) -> void:
	player.volume_db = MUTED_DB
	player.max_distance = 800.0
	player.attenuation = 1.0

	if player.stream != null:
		if "loop" in player.stream:
			player.stream.loop = true
