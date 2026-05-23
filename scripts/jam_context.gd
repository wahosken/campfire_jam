extends Node

signal arrangement_changed

@export var song_id := "song_01"
@export var bpm := 100.0
@export var beats_per_measure := 4
@export var total_measures := 8
@export var debug_logs := false

@export var melody_priority := [
	"guitar",
	"harmonica",
	"mandolin",
	"bass"
]

var registered_members: Array[Node] = []
var active_members: Array[Node] = []

var member_parts := {}
var member_requested_parts := {}

var current_featured_instrument := ""
var current_melody_index := 0

var song_started := false
var beat_index := 0
var current_measure := 1
var beat_timer := 0.0
var seconds_per_beat := 0.0

var forced_melody_member: Node = null
var current_featured_member: Node = null
var featured_member_before_forced_melody: Node = null

var rng := RandomNumberGenerator.new()

var start_position_override := -1.0
var preserve_existing_audio_member: Node = null


func _ready() -> void:
	seconds_per_beat = 60.0 / bpm
	rng.randomize()


func _process(delta: float) -> void:
	if not song_started:
		return

	beat_timer += delta

	while beat_timer >= seconds_per_beat:
		beat_timer -= seconds_per_beat
		_on_beat()


func add_member(member: Node) -> void:
	if member == null:
		return

	if registered_members.has(member):
		return

	registered_members.append(member)
	member_parts[member] = "silent"
	member_requested_parts[member] = "auto"

	if member.has_method("set_current_jam_context"):
		member.set_current_jam_context(self)


func remove_member(member: Node) -> void:
	if member == null:
		return

	if active_members.has(member):
		set_member_active(member, false)

	if registered_members.has(member):
		registered_members.erase(member)

	if member_parts.has(member):
		member_parts.erase(member)

	if member_requested_parts.has(member):
		member_requested_parts.erase(member)

	if member.has_method("set_current_jam_context"):
		member.set_current_jam_context(null)

	if forced_melody_member == member:
		forced_melody_member = null

	if current_featured_member == member:
		current_featured_member = null

	if featured_member_before_forced_melody == member:
		featured_member_before_forced_melody = null

	_update_arrangement()


func start_from_existing_member(member: Node) -> void:
	preserve_existing_audio_member = member

	var audio_source := _get_member_audio_source(member)

	if audio_source != null and audio_source.has_method("get_playback_position"):
		start_position_override = audio_source.get_playback_position()
	else:
		start_position_override = 0.0


func set_member_active(member: Node, should_be_active: bool) -> void:
	if member == null:
		return

	if not registered_members.has(member):
		add_member(member)

	if should_be_active:
		if not active_members.has(member):
			active_members.append(member)

		if not song_started:
			_start_song()
		else:
			_start_member_audio(member)
			_update_arrangement()
	else:
		if active_members.has(member):
			active_members.erase(member)

		_stop_member_audio(member)
		_set_member_part(member, "silent")

		if active_members.is_empty():
			_stop_song()
		else:
			if current_featured_instrument == "" or not _is_instrument_active(current_featured_instrument):
				_choose_first_featured_instrument()

			_update_arrangement()


func start_all_registered_members() -> void:
	for member in registered_members:
		set_member_active(member, true)


func stop_all_members() -> void:
	var members_to_stop := active_members.duplicate()

	for member in members_to_stop:
		set_member_active(member, false)


func set_member_requested_part(member: Node, requested_part: String) -> void:
	if member == null:
		return

	if not registered_members.has(member):
		add_member(member)

	member_requested_parts[member] = requested_part

	if requested_part == "melody":
		if forced_melody_member == null:
			featured_member_before_forced_melody = current_featured_member

		forced_melody_member = member
		current_featured_member = member
		current_featured_instrument = _get_member_instrument_id(member)

	elif forced_melody_member == member:
		forced_melody_member = null
		_restore_featured_member_after_forced_melody()

	_update_arrangement()


func clear_member_requested_part(member: Node) -> void:
	if member == null:
		return

	if member_requested_parts.has(member):
		member_requested_parts[member] = "auto"

	if forced_melody_member == member:
		forced_melody_member = null
		_restore_featured_member_after_forced_melody()

	_update_arrangement()


func get_current_part_for_member(member: Node) -> String:
	if member_parts.has(member):
		return member_parts[member]

	return "silent"


func get_active_instruments_text() -> String:
	var active_ids := _get_active_instrument_ids()

	if active_ids.is_empty():
		return "None"

	var names: Array[String] = []

	for instrument_id in melody_priority:
		if active_ids.has(instrument_id):
			names.append(instrument_id.capitalize())

	return ", ".join(names)


func get_featured_instrument_text() -> String:
	if current_featured_member != null and is_instance_valid(current_featured_member):
		var instrument_id := _get_member_instrument_id(current_featured_member)

		if instrument_id != "":
			return instrument_id.capitalize()

	if current_featured_instrument == "":
		return "None"

	return current_featured_instrument.capitalize()


func get_song_id() -> String:
	return song_id


func is_jam_active() -> bool:
	return song_started and not active_members.is_empty()


func is_active() -> bool:
	return is_jam_active()


func _start_song() -> void:
	song_started = true
	beat_index = 0
	current_measure = 1
	beat_timer = 0.0

	var start_position := 0.0

	if start_position_override >= 0.0:
		start_position = start_position_override
		beat_index = int(start_position / seconds_per_beat)
		beat_timer = fmod(start_position, seconds_per_beat)
		current_measure = int(float(beat_index) / float(beats_per_measure)) + 1

	_play_all_active_members_synced(start_position)
	_choose_first_featured_instrument()
	_update_arrangement()

	start_position_override = -1.0
	preserve_existing_audio_member = null


func _stop_song() -> void:
	song_started = false
	beat_index = 0
	current_measure = 1
	beat_timer = 0.0
	current_featured_instrument = ""
	current_featured_member = null
	forced_melody_member = null
	featured_member_before_forced_melody = null

	for member in registered_members:
		_stop_member_audio(member)
		_set_member_part(member, "silent")

	arrangement_changed.emit()


func _on_beat() -> void:
	beat_index += 1

	var total_beats := beats_per_measure * total_measures

	if beat_index >= total_beats:
		beat_index = 0
		_on_song_loop()

	current_measure = int(float(beat_index) / float(beats_per_measure)) + 1


func _on_song_loop() -> void:
	_restart_all_active_members_synced()
	_advance_featured_instrument()
	_update_arrangement()


func _choose_first_featured_instrument() -> void:
	_choose_random_featured_member(true)


func _advance_featured_instrument() -> void:
	if forced_melody_member != null and active_members.has(forced_melody_member):
		current_featured_member = forced_melody_member
		current_featured_instrument = _get_member_instrument_id(forced_melody_member)
		return

	_choose_random_featured_member(true)


func _choose_random_featured_member(prefer_npc := true) -> void:
	var candidates: Array[Node] = []

	for member in active_members:
		if member == null or not is_instance_valid(member):
			continue

		var instrument_id := _get_member_instrument_id(member)

		if instrument_id == "":
			continue

		candidates.append(member)

	if candidates.is_empty():
		current_featured_member = null
		current_featured_instrument = ""
		return

	if prefer_npc:
		var npc_candidates: Array[Node] = []

		for member in candidates:
			if member.is_in_group("player"):
				continue

			npc_candidates.append(member)

		if not npc_candidates.is_empty():
			candidates = npc_candidates

	if candidates.size() > 1 and current_featured_member != null:
		candidates.erase(current_featured_member)

	var random_index := rng.randi_range(0, candidates.size() - 1)
	current_featured_member = candidates[random_index]
	current_featured_instrument = _get_member_instrument_id(current_featured_member)

	for i in melody_priority.size():
		if melody_priority[i] == current_featured_instrument:
			current_melody_index = i
			return


func _update_arrangement() -> void:
	_mute_all_active_members()
	_clear_member_parts()

	if active_members.is_empty():
		arrangement_changed.emit()
		return

	if active_members.size() == 1:
		var solo_member := active_members[0]

		_set_member_full_arrangement(solo_member)

		arrangement_changed.emit()
		return

	if forced_melody_member != null and active_members.has(forced_melody_member):
		current_featured_member = forced_melody_member
		current_featured_instrument = _get_member_instrument_id(forced_melody_member)
	else:
		if current_featured_member == null or not active_members.has(current_featured_member):
			_choose_random_featured_member(true)

	for member in active_members:
		if member == null or not is_instance_valid(member):
			continue

		if member == current_featured_member:
			_set_member_tracks(member, false, true)
			_set_member_part(member, "melody")
		else:
			_set_member_tracks(member, true, false)
			_set_member_part(member, "rhythm")

	arrangement_changed.emit()


func _restore_featured_member_after_forced_melody() -> void:
	if featured_member_before_forced_melody != null:
		if is_instance_valid(featured_member_before_forced_melody):
			if active_members.has(featured_member_before_forced_melody):
				current_featured_member = featured_member_before_forced_melody
				current_featured_instrument = _get_member_instrument_id(current_featured_member)
				featured_member_before_forced_melody = null
				return

	featured_member_before_forced_melody = null
	_choose_random_featured_member(true)


func _get_active_instrument_ids() -> Array[String]:
	var active_ids: Array[String] = []

	for member in active_members:
		var instrument_id := _get_member_instrument_id(member)

		if instrument_id == "":
			continue

		if not active_ids.has(instrument_id):
			active_ids.append(instrument_id)

	return active_ids


func _is_instrument_active(instrument_id: String) -> bool:
	return _get_active_instrument_ids().has(instrument_id)


func _get_member_instrument_id(member: Node) -> String:
	if member == null:
		return ""

	if member.has_method("get_current_instrument_id"):
		return member.get_current_instrument_id()

	if member.has_method("get_instrument_id"):
		return member.get_instrument_id()

	if "instrument_name" in member:
		return str(member.instrument_name)

	return ""


func _get_member_audio_source(member: Node) -> Node:
	if member == null:
		return null

	if member.has_method("get_current_audio_source"):
		return member.get_current_audio_source()

	if member.has_method("get_jam_audio_source"):
		return member.get_jam_audio_source()

	if "audio_source" in member:
		return member.audio_source

	return null


func _get_member_requested_part(member: Node) -> String:
	if member_requested_parts.has(member):
		return member_requested_parts[member]

	return "auto"


func _play_all_active_members_synced(from_position := 0.0) -> void:
	for member in active_members:
		var audio_source := _get_member_audio_source(member)

		if audio_source == null:
			continue

		if member == preserve_existing_audio_member:
			continue

		if audio_source.has_method("play_synced"):
			audio_source.play_synced(from_position)


func _restart_all_active_members_synced() -> void:
	for member in active_members:
		var audio_source := _get_member_audio_source(member)

		if audio_source != null and audio_source.has_method("restart_synced"):
			audio_source.restart_synced()


func _start_member_audio(member: Node) -> void:
	var audio_source := _get_member_audio_source(member)

	if audio_source == null:
		push_warning("JamContext: No audio source found for member: " + str(member.name))
		return

	if audio_source.has_method("play_synced"):
		audio_source.play_synced(_get_current_song_position())
	else:
		push_warning("JamContext: audio source missing play_synced(): " + str(audio_source.name))


func _stop_member_audio(member: Node) -> void:
	var audio_source := _get_member_audio_source(member)

	if audio_source != null and audio_source.has_method("stop_all"):
		audio_source.stop_all()


func _mute_all_active_members() -> void:
	for member in active_members:
		_set_member_tracks(member, false, false)


func _set_member_tracks(member: Node, rhythm_on: bool, melody_on: bool) -> void:
	var audio_source := _get_member_audio_source(member)

	if audio_source == null:
		push_warning("JamContext: No audio source for track assignment: " + str(member.name))
		return

	_debug_log(
		"Set %s tracks: rhythm=%s melody=%s" % [
			str(member.name),
			str(rhythm_on),
			str(melody_on)
		]
	)

	if audio_source.has_method("set_tracks_audible"):
		audio_source.set_tracks_audible(rhythm_on, melody_on)
	else:
		push_warning("JamContext: audio source missing set_tracks_audible(): " + str(audio_source.name))


func _set_member_part(member: Node, part_name: String) -> void:
	if member == null:
		return

	member_parts[member] = part_name

	if member.has_method("set_current_part"):
		member.set_current_part(part_name)


func _clear_member_parts() -> void:
	for member in registered_members:
		_set_member_part(member, "silent")


func _get_current_song_position() -> float:
	return float(beat_index) * seconds_per_beat + beat_timer


func _set_member_full_arrangement(member: Node) -> void:
	_set_member_tracks(member, true, true)
	_set_member_part(member, "both")
	current_featured_member = member
	current_featured_instrument = _get_member_instrument_id(member)


func _debug_log(message: String) -> void:
	if debug_logs:
		print(message)


func refresh_arrangement() -> void:
	_update_arrangement()
