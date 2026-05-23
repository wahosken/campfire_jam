extends Node

signal instrument_owner_changed(instrument_name: String, instrument_owner: String)
signal arrangement_changed

@export var bpm := 100.0
@export var beats_per_measure := 4
@export var total_measures := 8

var npc_active_instruments := {
	"guitar": false,
	"bass": false,
	"harmonica": false,
	"mandolin": false
}

var player_active_instruments := {
	"guitar": false,
	"bass": false,
	"harmonica": false,
	"mandolin": false
}

var melody_priority := [
	"guitar",
	"harmonica",
	"mandolin",
	"bass"
]

var audio_sources := {
	"npc": {},
	"player": {}
}

var current_melody_index := 0
var current_featured_instrument := ""

var song_started := false
var beat_index := 0
var current_measure := 1

var beat_timer := 0.0
var seconds_per_beat := 0.0


func _ready() -> void:
	add_to_group("music_system")

	seconds_per_beat = 60.0 / bpm
	_mute_all_stems()


func _process(delta: float) -> void:
	if not song_started:
		return

	beat_timer += delta

	while beat_timer >= seconds_per_beat:
		beat_timer -= seconds_per_beat
		_on_beat()


func _on_beat() -> void:
	beat_index += 1

	var total_beats := beats_per_measure * total_measures

	if beat_index >= total_beats:
		beat_index = 0
		_on_song_loop()

	current_measure = int(float(beat_index) / float(beats_per_measure)) + 1


func _on_song_loop() -> void:
	_restart_all_stems_synced()
	_advance_featured_instrument()
	_update_arrangement()


func register_audio_source(instrument_name: String, owner_type: String, source: Node) -> void:
	if source == null:
		push_warning("Tried to register null audio source for " + owner_type + " " + instrument_name)
		return

	if not audio_sources.has(owner_type):
		audio_sources[owner_type] = {}

	audio_sources[owner_type][instrument_name] = source

	# If the song is already running when a source registers, start it silently in sync.
	if song_started and source.has_method("play_synced"):
		source.play_synced(0.0)
		_update_arrangement()


func unregister_audio_source(instrument_name: String, owner_type: String) -> void:
	if not audio_sources.has(owner_type):
		return

	if audio_sources[owner_type].has(instrument_name):
		var source: Node = audio_sources[owner_type][instrument_name]

		if source != null and source.has_method("stop_all"):
			source.stop_all()

		audio_sources[owner_type].erase(instrument_name)


func _get_audio_source(instrument_name: String, owner_type: String) -> Node:
	if not audio_sources.has(owner_type):
		return null

	if not audio_sources[owner_type].has(instrument_name):
		return null

	return audio_sources[owner_type][instrument_name]


func set_npc_instrument_active(instrument_name: String, is_active: bool) -> void:
	if not npc_active_instruments.has(instrument_name):
		push_warning("Unknown NPC instrument: " + instrument_name)
		return

	var old_owner := get_instrument_owner(instrument_name)

	npc_active_instruments[instrument_name] = is_active

	var new_owner := get_instrument_owner(instrument_name)

	if old_owner != new_owner:
		instrument_owner_changed.emit(instrument_name, new_owner)

	_refresh_song_state()


func set_player_instrument_active(instrument_name: String, is_active: bool) -> void:
	if not player_active_instruments.has(instrument_name):
		push_warning("Unknown player instrument: " + instrument_name)
		return

	var old_owner := get_instrument_owner(instrument_name)

	player_active_instruments[instrument_name] = is_active

	var new_owner := get_instrument_owner(instrument_name)

	if old_owner != new_owner:
		instrument_owner_changed.emit(instrument_name, new_owner)

	_refresh_song_state()


func _refresh_song_state() -> void:
	if _get_active_count() > 0:
		if not song_started:
			_start_song()
		else:
			if current_featured_instrument == "" or not is_instrument_active(current_featured_instrument):
				_choose_first_featured_instrument()

			_update_arrangement()
	else:
		_stop_song()


func _start_song() -> void:
	song_started = true
	beat_index = 0
	current_measure = 1
	beat_timer = 0.0

	_play_all_stems_synced()
	_choose_first_featured_instrument()
	_update_arrangement()


func _stop_song() -> void:
	song_started = false
	beat_index = 0
	current_measure = 1
	beat_timer = 0.0
	current_featured_instrument = ""

	_stop_all_stems()
	arrangement_changed.emit()


func _choose_first_featured_instrument() -> void:
	for i in melody_priority.size():
		var instrument_name: String = melody_priority[i]

		if is_instrument_active(instrument_name):
			current_melody_index = i
			current_featured_instrument = instrument_name
			return

	current_featured_instrument = ""


func _advance_featured_instrument() -> void:
	if _get_active_count() == 0:
		current_featured_instrument = ""
		return

	for step in melody_priority.size():
		current_melody_index = (current_melody_index + 1) % melody_priority.size()
		var candidate: String = melody_priority[current_melody_index]

		if is_instrument_active(candidate):
			current_featured_instrument = candidate
			return


func _update_arrangement() -> void:
	var active_count := _get_active_count()

	_mute_all_stems()

	if active_count == 0:
		arrangement_changed.emit()
		return

	if active_count == 1:
		var solo_instrument := _get_first_active_instrument()

		if is_same_instrument_duet(solo_instrument):
			# Player and NPC both have same instrument, and no other instruments are active.
			# Let both play: player melody, NPC rhythm.
			_set_source_tracks(solo_instrument, "player", false, true)
			_set_source_tracks(solo_instrument, "npc", true, false)
		elif player_active_instruments[solo_instrument]:
			_set_source_tracks(solo_instrument, "player", true, true)
		else:
			_set_source_tracks(solo_instrument, "npc", true, true)

		arrangement_changed.emit()
		return

	if current_featured_instrument == "" or not is_instrument_active(current_featured_instrument):
		_choose_first_featured_instrument()

	for instrument_name in melody_priority:
		if not is_instrument_active(instrument_name):
			continue

		var player_is_active: bool = player_active_instruments[instrument_name]
		var npc_is_active: bool = npc_active_instruments[instrument_name]

		if instrument_name == current_featured_instrument:
			if player_is_active:
				# Player gets melody priority.
				_set_source_tracks(instrument_name, "player", false, true)

				if npc_is_active:
					# Same-instrument NPC backs player with rhythm.
					_set_source_tracks(instrument_name, "npc", true, false)
			else:
				# No player on this instrument, so NPC takes melody.
				_set_source_tracks(instrument_name, "npc", false, true)
		else:
			if player_is_active:
				# Player is active, but this instrument is not featured.
				# Player owns the audible rhythm unless NPC-only.
				_set_source_tracks(instrument_name, "player", true, false)
			elif npc_is_active:
				_set_source_tracks(instrument_name, "npc", true, false)

	arrangement_changed.emit()


func is_instrument_active(instrument_name: String) -> bool:
	if not npc_active_instruments.has(instrument_name):
		return false

	return npc_active_instruments[instrument_name] or player_active_instruments[instrument_name]


func get_instrument_owner(instrument_name: String) -> String:
	if not npc_active_instruments.has(instrument_name):
		return "none"

	if player_active_instruments[instrument_name]:
		return "player"

	if npc_active_instruments[instrument_name]:
		return "npc"

	return "none"


func _get_active_count() -> int:
	var count := 0

	for instrument_name in melody_priority:
		if is_instrument_active(instrument_name):
			count += 1

	return count


func _get_first_active_instrument() -> String:
	for instrument_name in melody_priority:
		if is_instrument_active(instrument_name):
			return instrument_name

	return ""


func _play_all_stems_synced() -> void:
	for owner_type in audio_sources.keys():
		for instrument_name in audio_sources[owner_type].keys():
			var source: Node = audio_sources[owner_type][instrument_name]

			if source != null and source.has_method("play_synced"):
				source.play_synced(0.0)


func _restart_all_stems_synced() -> void:
	for owner_type in audio_sources.keys():
		for instrument_name in audio_sources[owner_type].keys():
			var source: Node = audio_sources[owner_type][instrument_name]

			if source != null and source.has_method("restart_synced"):
				source.restart_synced()


func _stop_all_stems() -> void:
	for owner_type in audio_sources.keys():
		for instrument_name in audio_sources[owner_type].keys():
			var source: Node = audio_sources[owner_type][instrument_name]

			if source != null and source.has_method("stop_all"):
				source.stop_all()


func _mute_all_stems() -> void:
	for owner_type in audio_sources.keys():
		for instrument_name in audio_sources[owner_type].keys():
			var source: Node = audio_sources[owner_type][instrument_name]

			if source != null and source.has_method("set_tracks_audible"):
				source.set_tracks_audible(false, false)


func _set_source_tracks(instrument_name: String, owner_type: String, rhythm_on: bool, melody_on: bool) -> void:
	var source := _get_audio_source(instrument_name, owner_type)

	if source == null:
		return

	if source.has_method("set_tracks_audible"):
		source.set_tracks_audible(rhythm_on, melody_on)


func is_same_instrument_duet(instrument_name: String) -> bool:
	if not npc_active_instruments.has(instrument_name):
		return false

	if not npc_active_instruments[instrument_name]:
		return false

	if not player_active_instruments[instrument_name]:
		return false

	return _get_active_count() == 1


func should_same_instrument_npc_play_rhythm(instrument_name: String) -> bool:
	if not npc_active_instruments.has(instrument_name):
		return false

	if not npc_active_instruments[instrument_name]:
		return false

	if not player_active_instruments[instrument_name]:
		return false

	if current_featured_instrument != instrument_name:
		return false

	return _get_active_count() > 1


func get_current_beat_in_measure() -> int:
	return int(beat_index % beats_per_measure) + 1


func get_loop_position_text() -> String:
	return "Measure %d / %d | Beat %d / %d | Featured: %s" % [
		current_measure,
		total_measures,
		get_current_beat_in_measure(),
		beats_per_measure,
		current_featured_instrument.capitalize() if current_featured_instrument != "" else "None"
	]


func is_song_started() -> bool:
	return song_started


func get_featured_instrument() -> String:
	return current_featured_instrument
