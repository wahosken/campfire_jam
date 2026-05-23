extends Node

signal arrangement_changed
signal instrument_owner_changed(instrument_name: String, instrument_owner: String)

@export var bpm := 100.0
@export var beats_per_measure := 4
@export var total_measures := 8

var player_is_near_active_jam := false
var current_song_id := "song_01"
var jam_enabled := true

var audio_sources := {
	"npc": {},
	"player": {}
}


func _ready() -> void:
	add_to_group("music_system")


func set_current_song_id(new_song_id: String) -> void:
	current_song_id = new_song_id


func get_current_song_id() -> String:
	return current_song_id


func set_player_near_active_jam(is_near_jam: bool) -> void:
	player_is_near_active_jam = is_near_jam


func is_player_near_active_jam() -> bool:
	return player_is_near_active_jam


func set_jam_enabled(is_enabled: bool) -> void:
	jam_enabled = is_enabled


func is_jam_enabled() -> bool:
	return jam_enabled


func register_audio_source(instrument_name: String, owner_type: String, source: Node) -> void:
	if source == null:
		push_warning("Tried to register null audio source for " + owner_type + " " + instrument_name)
		return

	if not audio_sources.has(owner_type):
		audio_sources[owner_type] = {}

	audio_sources[owner_type][instrument_name] = source


func unregister_audio_source(instrument_name: String, owner_type: String) -> void:
	if not audio_sources.has(owner_type):
		return

	if audio_sources[owner_type].has(instrument_name):
		audio_sources[owner_type].erase(instrument_name)


func get_active_instruments_text() -> String:
	return "None"


func get_featured_instrument_text() -> String:
	return "None"


func get_arrangement_debug_text() -> String:
	return "MusicSystem is now a compatibility shell. JamContext owns arrangements."


func is_song_started() -> bool:
	return false


func get_featured_instrument() -> String:
	return ""


# Legacy compatibility.
# These are intentionally no-ops now that JamContext owns arrangements.
func set_npc_jam_enabled(_is_enabled: bool) -> void:
	pass


func set_npc_instrument_active(_instrument_name: String, _is_active: bool) -> void:
	pass


func set_player_instrument_active(_instrument_name: String, _is_active: bool) -> void:
	pass


func get_instrument_owner(_instrument_name: String) -> String:
	return "none"


func get_current_part(_instrument_name: String) -> String:
	return "silent"


func get_current_owner_part(_owner_type: String, _instrument_name: String) -> String:
	return "silent"


func is_instrument_active(_instrument_name: String) -> bool:
	return false


func is_player_instrument_active_in_campfire(_instrument_name: String) -> bool:
	return false


func update_player_jam_area(_player_position: Vector2) -> void:
	pass
