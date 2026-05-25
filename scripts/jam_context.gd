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
var member_rhythm_db := {}

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


# ------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------

func _ready() -> void:
	apply_song_id(song_id)
	rng.randomize()


func _process(delta: float) -> void:
	if not song_started:
		return

	beat_timer += delta

	while beat_timer >= seconds_per_beat:
		beat_timer -= seconds_per_beat
		_on_beat()


# ------------------------------------------------------------
# Member registration and activity
# ------------------------------------------------------------

func add_member(member: Node) -> void:
	if member == null:
		return

	if registered_members.has(member):
		return

	registered_members.append(member)
	member_parts[member] = "silent"
	member_requested_parts[member] = "auto"
	member_rhythm_db[member] = 0.0

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

	if member_rhythm_db.has(member):
		member_rhythm_db.erase(member)

	if member.has_method("set_current_jam_context"):
		member.set_current_jam_context(null)

	if forced_melody_member == member:
		forced_melody_member = null

	if current_featured_member == member:
		current_featured_member = null

	if featured_member_before_forced_melody == member:
		featured_member_before_forced_melody = null

	_update_arrangement()


func set_member_active(member: Node, should_be_active: bool) -> void:
	if member == null:
		return

	if not registered_members.has(member):
		add_member(member)

	if should_be_active:
		_activate_member(member)
	else:
		_deactivate_member(member)


func _activate_member(member: Node) -> void:
	if not active_members.has(member):
		active_members.append(member)

	if not song_started:
		_start_song()
	else:
		_start_member_audio(member)
		_update_arrangement()


func _deactivate_member(member: Node) -> void:
	if active_members.has(member):
		active_members.erase(member)

	_stop_member_audio(member)
	_set_member_part(member, "silent")

	if member_rhythm_db.has(member):
		member_rhythm_db[member] = 0.0

	if forced_melody_member == member:
		forced_melody_member = null
		_restore_featured_member_after_forced_melody()

	if current_featured_member == member:
		current_featured_member = null
		current_featured_instrument = ""

	if active_members.is_empty():
		_stop_song()
	else:
		if current_featured_member == null:
			_choose_random_featured_member(true)

		_update_arrangement()


# Used when a member leaves a synced jam but should keep their own audio going.
# Do not stop the member's audio here; the member decides what to do next.
func detach_member_preserve_audio(member: Node) -> void:
	if member == null:
		return

	if active_members.has(member):
		active_members.erase(member)

	if member_parts.has(member):
		member_parts[member] = "silent"

	if member_requested_parts.has(member):
		member_requested_parts[member] = "auto"

	if member_rhythm_db.has(member):
		member_rhythm_db[member] = 0.0

	if forced_melody_member == member:
		forced_melody_member = null
		_restore_featured_member_after_forced_melody()

	if current_featured_member == member:
		current_featured_member = null
		current_featured_instrument = ""
		_choose_random_featured_member(true)

	if member.has_method("set_current_jam_context"):
		member.set_current_jam_context(null)

	if member.has_method("set_current_part"):
		member.set_current_part("silent")

	if active_members.is_empty():
		_reset_transport_state()
		current_featured_instrument = ""
		current_featured_member = null
		forced_melody_member = null
		featured_member_before_forced_melody = null
	else:
		_update_arrangement()

	arrangement_changed.emit()


func start_all_registered_members() -> void:
	for member in registered_members:
		set_member_active(member, true)


func stop_all_members() -> void:
	var members_to_stop: Array[Node] = active_members.duplicate()

	for member in members_to_stop:
		set_member_active(member, false)


# ------------------------------------------------------------
# Member requests and visible parts
# ------------------------------------------------------------

func set_member_requested_parts(member: Node, rhythm: bool, melody: bool) -> void:
	var requested_part: String = _get_requested_part_from_flags(rhythm, melody)
	set_member_requested_part(member, requested_part)


func set_member_requested_part(member: Node, requested_part: String) -> void:
	if member == null:
		return

	if not registered_members.has(member):
		add_member(member)

	if not _is_valid_requested_part(requested_part):
		requested_part = "auto"

	member_requested_parts[member] = requested_part
	_update_forced_melody_member(member, requested_part)
	_update_arrangement()


func clear_member_requested_part(member: Node) -> void:
	if member == null:
		return

	if member_requested_parts.has(member):
		member_requested_parts[member] = "auto"

	if forced_melody_member == member:
		forced_melody_member = null
		_restore_featured_member_after_forced_melody()

		if current_featured_member == null or current_featured_member.is_in_group("player"):
			_choose_random_featured_member(true)

	_update_arrangement()


func _update_forced_melody_member(member: Node, requested_part: String) -> void:
	var should_force_melody := false

	if member.is_in_group("player"):
		should_force_melody = requested_part == "melody" or requested_part == "both"

	if should_force_melody:
		if forced_melody_member == null:
			featured_member_before_forced_melody = current_featured_member

		forced_melody_member = member
		current_featured_member = member
		current_featured_instrument = _get_member_instrument_id(member)
	elif forced_melody_member == member:
		forced_melody_member = null
		_restore_featured_member_after_forced_melody()

		if current_featured_member == null or current_featured_member.is_in_group("player"):
			_choose_random_featured_member(true)

	if forced_melody_member == null:
		if current_featured_member == null or current_featured_member.is_in_group("player"):
			_choose_random_featured_member(true)


func get_current_part_for_member(member: Node) -> String:
	if member_parts.has(member):
		return member_parts[member]

	return "silent"


func get_rhythm_db_for_member(member: Node) -> float:
	if member_rhythm_db.has(member):
		return float(member_rhythm_db[member])

	return 0.0


# ------------------------------------------------------------
# Song transport
# ------------------------------------------------------------

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
	_choose_random_featured_member(true)
	_update_arrangement()

	start_position_override = -1.0
	preserve_existing_audio_member = null


func _stop_song() -> void:
	_reset_transport_state()

	current_featured_instrument = ""
	current_featured_member = null
	forced_melody_member = null
	featured_member_before_forced_melody = null

	for member in registered_members:
		_stop_member_audio(member)
		_set_member_part(member, "silent")

	arrangement_changed.emit()


func _reset_transport_state() -> void:
	song_started = false
	beat_index = 0
	current_measure = 1
	beat_timer = 0.0


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


func _get_current_song_position() -> float:
	return float(beat_index) * seconds_per_beat + beat_timer


func is_jam_active() -> bool:
	return song_started and not active_members.is_empty()


func is_active() -> bool:
	return is_jam_active()


# ------------------------------------------------------------
# Song and sync helpers
# ------------------------------------------------------------

func apply_song_id(new_song_id: String) -> void:
	song_id = new_song_id

	if Engine.has_singleton("SongLibrary"):
		pass

	if typeof(SongLibrary) != TYPE_NIL:
		var song_data: Dictionary = SongLibrary.get_song(song_id)

		if song_data.has("bpm"):
			bpm = float(song_data["bpm"])

		if song_data.has("beats_per_measure"):
			beats_per_measure = int(song_data["beats_per_measure"])

		if song_data.has("total_measures"):
			total_measures = int(song_data["total_measures"])

	seconds_per_beat = 60.0 / bpm


func start_from_existing_member(member: Node) -> void:
	preserve_existing_audio_member = member

	var audio_source: Node = _get_member_audio_source(member)

	if audio_source != null and audio_source.has_method("get_playback_position"):
		start_position_override = audio_source.get_playback_position()
	else:
		start_position_override = 0.0


func _get_best_live_sync_position(excluded_member: Node = null) -> float:
	for member in active_members:
		if member == null or not is_instance_valid(member):
			continue

		if member == excluded_member:
			continue

		var audio_source: Node = _get_member_audio_source(member)

		if audio_source == null:
			continue

		if audio_source.has_method("get_playback_position"):
			return audio_source.get_playback_position()

	return _get_current_song_position()


func _set_member_audio_song(member: Node) -> void:
	var audio_source: Node = _get_member_audio_source(member)

	if audio_source == null:
		return

	if audio_source.has_method("set_song_id"):
		audio_source.set_song_id(song_id)


# ------------------------------------------------------------
# Arrangement
# ------------------------------------------------------------

func refresh_arrangement() -> void:
	_update_arrangement()


func _update_arrangement() -> void:
	_mute_all_active_members()
	_clear_member_parts()

	if active_members.is_empty():
		arrangement_changed.emit()
		return

	if active_members.size() == 1:
		var solo_member: Node = active_members[0]
		_set_solo_member_arrangement(solo_member)

		arrangement_changed.emit()
		return

	_select_featured_member_for_arrangement()

	var rhythm_counts: Dictionary = _get_rhythm_counts_by_instrument()

	for member in active_members:
		_apply_arrangement_to_member(member, rhythm_counts)

	arrangement_changed.emit()


func _select_featured_member_for_arrangement() -> void:
	if forced_melody_member != null and active_members.has(forced_melody_member):
		current_featured_member = forced_melody_member
		current_featured_instrument = _get_member_instrument_id(forced_melody_member)
		return

	if current_featured_member == null or not active_members.has(current_featured_member) or current_featured_member.is_in_group("player"):
		_choose_random_featured_member(true)

	if current_featured_member != null:
		var featured_requested_part: String = _get_member_requested_part(current_featured_member)

		if featured_requested_part == "silent":
			_choose_random_featured_member(true)

	if current_featured_member == null:
		_choose_random_featured_member(true)


func _apply_arrangement_to_member(member: Node, rhythm_counts: Dictionary) -> void:
	if member == null or not is_instance_valid(member):
		return

	var requested_part: String = _get_member_requested_part(member)

	if requested_part == "silent":
		_set_member_tracks_with_volume(member, false, false)
		_set_member_part(member, "silent")
		return

	var is_player: bool = member.is_in_group("player")
	var is_featured: bool = member == current_featured_member

	var rhythm_on := false
	var melody_on := false

	if is_player:
		rhythm_on = requested_part == "rhythm" or requested_part == "both"
		melody_on = is_featured and (requested_part == "melody" or requested_part == "both")
	else:
		if is_featured:
			rhythm_on = false
			melody_on = true
		else:
			rhythm_on = true
			melody_on = false

	var rhythm_db: float = _get_rhythm_volume_for_member(member, rhythm_counts)

	_set_member_tracks_with_volume(member, rhythm_on, melody_on, rhythm_db, 0.0)

	if rhythm_on and melody_on:
		_set_member_part(member, "both")
	elif melody_on:
		_set_member_part(member, "melody")
	elif rhythm_on:
		_set_member_part(member, "rhythm")
	else:
		_set_member_part(member, "silent")


func _set_solo_member_arrangement(member: Node) -> void:
	var requested_part: String = _get_member_requested_part(member)

	if requested_part == "silent":
		_set_member_tracks(member, false, false)
		_set_member_part(member, "silent")
		return

	if member.is_in_group("player"):
		match requested_part:
			"rhythm":
				_set_member_tracks(member, true, false)
				_set_member_part(member, "rhythm")
			"melody":
				_set_member_tracks(member, false, true)
				_set_member_part(member, "melody")
			"both":
				_set_member_tracks(member, true, true)
				_set_member_part(member, "both")
			_:
				_set_member_tracks(member, true, true)
				_set_member_part(member, "both")
	else:
		_set_member_tracks(member, true, true)
		_set_member_part(member, "both")

	current_featured_member = member
	current_featured_instrument = _get_member_instrument_id(member)


func _advance_featured_instrument() -> void:
	if forced_melody_member != null and active_members.has(forced_melody_member):
		current_featured_member = forced_melody_member
		current_featured_instrument = _get_member_instrument_id(forced_melody_member)
		return

	_choose_random_featured_member(true)


func _choose_random_featured_member(_prefer_npc := true) -> void:
	var candidates: Array[Node] = []

	for member in active_members:
		if member == null or not is_instance_valid(member):
			continue

		if member.is_in_group("player"):
			continue

		var requested_part: String = _get_member_requested_part(member)

		if requested_part == "silent":
			continue

		var instrument_id: String = _get_member_instrument_id(member)

		if instrument_id == "":
			continue

		candidates.append(member)

	if candidates.is_empty():
		current_featured_member = null
		current_featured_instrument = ""
		return

	if candidates.size() > 1 and current_featured_member != null:
		candidates.erase(current_featured_member)

	var random_index: int = rng.randi_range(0, candidates.size() - 1)
	current_featured_member = candidates[random_index]
	current_featured_instrument = _get_member_instrument_id(current_featured_member)

	for i in melody_priority.size():
		if melody_priority[i] == current_featured_instrument:
			current_melody_index = i
			return


func _restore_featured_member_after_forced_melody() -> void:
	if featured_member_before_forced_melody != null:
		if is_instance_valid(featured_member_before_forced_melody):
			if active_members.has(featured_member_before_forced_melody) and not featured_member_before_forced_melody.is_in_group("player"):
				current_featured_member = featured_member_before_forced_melody
				current_featured_instrument = _get_member_instrument_id(current_featured_member)
				featured_member_before_forced_melody = null
				return

	featured_member_before_forced_melody = null
	_choose_random_featured_member(true)


# ------------------------------------------------------------
# Audio control
# ------------------------------------------------------------

func _play_all_active_members_synced(from_position := 0.0) -> void:
	for member in active_members:
		var audio_source: Node = _get_member_audio_source(member)

		if audio_source == null:
			continue

		if member == preserve_existing_audio_member:
			continue

		if audio_source.has_method("set_song_id"):
			audio_source.set_song_id(song_id)

		if audio_source.has_method("play_synced"):
			audio_source.play_synced(from_position)


func _restart_all_active_members_synced() -> void:
	for member in active_members:
		var audio_source: Node = _get_member_audio_source(member)

		if audio_source == null:
			continue

		if audio_source.has_method("set_song_id"):
			audio_source.set_song_id(song_id)

		if audio_source.has_method("restart_synced"):
			audio_source.restart_synced()


func _start_member_audio(member: Node) -> void:
	var audio_source: Node = _get_member_audio_source(member)

	if audio_source == null:
		push_warning("JamContext: No audio source found for member: " + str(member.name))
		return

	if audio_source.has_method("set_song_id"):
		audio_source.set_song_id(song_id)

	var sync_position: float = _get_best_live_sync_position(member)

	if audio_source.has_method("play_synced"):
		audio_source.play_synced(sync_position)
	else:
		push_warning("JamContext: audio source missing play_synced(): " + str(audio_source.name))


func _stop_member_audio(member: Node) -> void:
	var audio_source: Node = _get_member_audio_source(member)

	if audio_source != null and audio_source.has_method("stop_all"):
		audio_source.stop_all()


func _mute_all_active_members() -> void:
	for member in active_members:
		_set_member_tracks(member, false, false)


func _set_member_tracks(member: Node, rhythm_on: bool, melody_on: bool) -> void:
	var audio_source: Node = _get_member_audio_source(member)

	if audio_source == null:
		push_warning("JamContext: No audio source for track assignment: " + str(member.name))
		return

	if audio_source.has_method("force_jam_control"):
		audio_source.force_jam_control()

	if audio_source.has_method("set_tracks_audible"):
		audio_source.set_tracks_audible(rhythm_on, melody_on)
	else:
		push_warning("JamContext: audio source missing set_tracks_audible(): " + str(audio_source.name))

	member_rhythm_db[member] = 0.0


func _set_member_tracks_with_volume(
	member: Node,
	rhythm_on: bool,
	melody_on: bool,
	rhythm_db := 0.0,
	melody_db := 0.0
) -> void:
	var audio_source: Node = _get_member_audio_source(member)

	if audio_source == null:
		push_warning("JamContext: No audio source for track assignment: " + str(member.name))
		return

	if audio_source.has_method("force_jam_control"):
		audio_source.force_jam_control()

	member_rhythm_db[member] = rhythm_db if rhythm_on else 0.0

	if audio_source.has_method("set_track_volumes"):
		audio_source.set_track_volumes(rhythm_on, melody_on, rhythm_db, melody_db)
	elif audio_source.has_method("set_tracks_audible"):
		audio_source.set_tracks_audible(rhythm_on, melody_on)
	else:
		push_warning("JamContext: audio source missing track control method: " + str(audio_source.name))


# ------------------------------------------------------------
# Part helpers
# ------------------------------------------------------------

# JamContext is the authority for what each member is actually playing.
# It may update member visuals/labels only if this is still that member's current context.
func _set_member_part(member: Node, part_name: String) -> void:
	if member == null:
		return

	if not is_instance_valid(member):
		return

	member_parts[member] = part_name

	# Only the member's current JamContext should control its visible/actual part.
	# This prevents old/stale contexts from setting a transferred NPC to "silent".
	if "current_jam_context" in member:
		if member.current_jam_context != null and member.current_jam_context != self:
			return

	if member.has_method("set_current_part"):
		member.set_current_part(part_name)


func _clear_member_parts() -> void:
	for member in active_members:
		_set_member_part(member, "silent")


func _get_rhythm_counts_by_instrument() -> Dictionary:
	var counts := {}

	for member in active_members:
		if member == null or not is_instance_valid(member):
			continue

		var requested_part: String = _get_member_requested_part(member)

		if requested_part == "silent":
			continue

		var is_player: bool = member.is_in_group("player")
		var is_featured: bool = member == current_featured_member

		var rhythm_on := false

		if is_player:
			rhythm_on = requested_part == "rhythm" or requested_part == "both"
		else:
			rhythm_on = not is_featured

		if not rhythm_on:
			continue

		var instrument_id: String = _get_member_instrument_id(member)

		if instrument_id == "":
			continue

		if not counts.has(instrument_id):
			counts[instrument_id] = 0

		counts[instrument_id] += 1

	return counts


func _get_rhythm_volume_for_member(member: Node, rhythm_counts: Dictionary) -> float:
	var instrument_id: String = _get_member_instrument_id(member)

	if instrument_id == "":
		return 0.0

	if not rhythm_counts.has(instrument_id):
		return 0.0

	var count: int = int(rhythm_counts[instrument_id])

	if count <= 1:
		return 0.0

	match count:
		2:
			return -4.0
		3:
			return -7.0
		_:
			return -10.0


# ------------------------------------------------------------
# Query helpers
# ------------------------------------------------------------

func get_active_instruments_text() -> String:
	var active_ids: Array[String] = _get_active_instrument_ids()

	if active_ids.is_empty():
		return "None"

	var names: Array[String] = []

	for instrument_id in melody_priority:
		if active_ids.has(instrument_id):
			names.append(instrument_id.capitalize())

	return ", ".join(names)


func get_featured_instrument_text() -> String:
	if current_featured_member != null and is_instance_valid(current_featured_member):
		var instrument_id: String = _get_member_instrument_id(current_featured_member)

		if instrument_id != "":
			return instrument_id.capitalize()

	if current_featured_instrument == "":
		return "None"

	return current_featured_instrument.capitalize()


func get_song_id() -> String:
	return song_id


func _get_active_instrument_ids() -> Array[String]:
	var active_ids: Array[String] = []

	for member in active_members:
		var instrument_id: String = _get_member_instrument_id(member)

		if instrument_id == "":
			continue

		if not active_ids.has(instrument_id):
			active_ids.append(instrument_id)

	return active_ids


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


func _get_requested_part_from_flags(rhythm: bool, melody: bool) -> String:
	if rhythm and melody:
		return "both"
	elif melody:
		return "melody"
	elif rhythm:
		return "rhythm"

	return "silent"


func _is_valid_requested_part(requested_part: String) -> bool:
	return requested_part == "auto" \
		or requested_part == "silent" \
		or requested_part == "rhythm" \
		or requested_part == "melody" \
		or requested_part == "both"


# ------------------------------------------------------------
# Debug
# ------------------------------------------------------------

func _debug_log(message: String) -> void:
	if debug_logs:
		print(message)
