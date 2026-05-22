extends Control

# -------------------------
# Song Settings
# -------------------------

@export var bpm: float = 100.0
@export var beats_per_measure: int = 4
@export var loop_measures: int = 8

# Later, replace these with your real placeholder stem paths.
@export var guitar_stem: AudioStream
@export var bass_stem: AudioStream
@export var harmonica_stem: AudioStream

# -------------------------
# UI References
# -------------------------

@onready var song_toggle: CheckButton = $"CanvasLayer/VBoxContainer/Start_Stop Song"
@onready var guitar_toggle: CheckButton = $"CanvasLayer/VBoxContainer/Toggle Guitar"
@onready var bass_toggle: CheckButton = $"CanvasLayer/VBoxContainer/Toggle Bass"
@onready var harmonica_toggle: CheckButton = $"CanvasLayer/VBoxContainer/Toggle Harmonica"

@onready var beat_label: Label = $"CanvasLayer/VBoxContainer/Current Beat"
@onready var measure_label: Label = $"CanvasLayer/VBoxContainer/Current Measure"
@onready var loop_label: Label = $"CanvasLayer/VBoxContainer/Current Loop Position"

# -------------------------
# Audio Players
# -------------------------

var guitar_player: AudioStreamPlayer
var bass_player: AudioStreamPlayer
var harmonica_player: AudioStreamPlayer

# -------------------------
# Timing
# -------------------------

var song_playing := false
var song_time := 0.0

var seconds_per_beat := 0.0
var seconds_per_measure := 0.0
var loop_length_seconds := 0.0

var current_beat := 1
var current_measure := 1
var previous_beat := -1
var previous_measure := -1


func _ready() -> void:
	seconds_per_beat = 60.0 / bpm
	seconds_per_measure = seconds_per_beat * beats_per_measure
	loop_length_seconds = seconds_per_measure * loop_measures

	_create_audio_players()
	_connect_buttons()
	_update_ui()


func _process(delta: float) -> void:
	if not song_playing:
		return

	song_time += delta

	if song_time >= loop_length_seconds:
		song_time = fmod(song_time, loop_length_seconds)
		_restart_active_stems()

	_update_timing_values()
	_update_ui()


func _create_audio_players() -> void:
	guitar_player = AudioStreamPlayer.new()
	bass_player = AudioStreamPlayer.new()
	harmonica_player = AudioStreamPlayer.new()

	guitar_player.name = "GuitarPlayer"
	bass_player.name = "BassPlayer"
	harmonica_player.name = "HarmonicaPlayer"

	add_child(guitar_player)
	add_child(bass_player)
	add_child(harmonica_player)

	guitar_player.stream = guitar_stem
	bass_player.stream = bass_stem
	harmonica_player.stream = harmonica_stem


func _connect_buttons() -> void:
	song_toggle.toggled.connect(_on_song_toggled)
	guitar_toggle.toggled.connect(_on_guitar_toggled)
	bass_toggle.toggled.connect(_on_bass_toggled)
	harmonica_toggle.toggled.connect(_on_harmonica_toggled)


func _on_song_toggled(enabled: bool) -> void:
	if enabled:
		start_song()
	else:
		stop_song()


func start_song() -> void:
	song_playing = true
	song_time = 0.0
	current_beat = 1
	current_measure = 1
	previous_beat = -1
	previous_measure = -1

	_start_active_stems()
	_update_ui()


func stop_song() -> void:
	song_playing = false
	song_time = 0.0

	guitar_player.stop()
	bass_player.stop()
	harmonica_player.stop()

	current_beat = 1
	current_measure = 1
	previous_beat = -1
	previous_measure = -1

	_update_ui()


func _on_guitar_toggled(enabled: bool) -> void:
	_handle_stem_toggle(guitar_player, enabled)


func _on_bass_toggled(enabled: bool) -> void:
	_handle_stem_toggle(bass_player, enabled)


func _on_harmonica_toggled(enabled: bool) -> void:
	_handle_stem_toggle(harmonica_player, enabled)


func _handle_stem_toggle(player: AudioStreamPlayer, enabled: bool) -> void:
	if player.stream == null:
		print(player.name, " has no audio stream assigned yet.")
		return

	if not song_playing:
		return

	if enabled:
		player.play(song_time)
	else:
		player.stop()


func _start_active_stems() -> void:
	if guitar_toggle.button_pressed:
		_play_from_song_time(guitar_player)

	if bass_toggle.button_pressed:
		_play_from_song_time(bass_player)

	if harmonica_toggle.button_pressed:
		_play_from_song_time(harmonica_player)


func _restart_active_stems() -> void:
	if guitar_toggle.button_pressed:
		_restart_player(guitar_player)

	if bass_toggle.button_pressed:
		_restart_player(bass_player)

	if harmonica_toggle.button_pressed:
		_restart_player(harmonica_player)


func _play_from_song_time(player: AudioStreamPlayer) -> void:
	if player.stream == null:
		print(player.name, " has no audio stream assigned yet.")
		return

	player.play(song_time)


func _restart_player(player: AudioStreamPlayer) -> void:
	if player.stream == null:
		return

	player.stop()
	player.play(0.0)


func _update_timing_values() -> void:
	var total_beats := int(song_time / seconds_per_beat)

	current_beat = total_beats % beats_per_measure + 1
	current_measure = int(song_time / seconds_per_measure) + 1

	if current_beat != previous_beat:
		previous_beat = current_beat
		print("Beat: ", current_beat)

	if current_measure != previous_measure:
		previous_measure = current_measure
		print("Measure: ", current_measure)


func _update_ui() -> void:
	beat_label.text = "Current Beat: " + str(current_beat)
	measure_label.text = "Current Measure: " + str(current_measure)
	loop_label.text = "Current Loop Position: " + str(snapped(song_time, 0.01)) + "s / " + str(snapped(loop_length_seconds, 0.01)) + "s"
