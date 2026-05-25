extends Control

@onready var current_instrument_label: Label = $HBoxContainer/CurrentInstrumentLabel
@onready var selected_song_label: Label = $HBoxContainer/SelectedSongLabel
@onready var nearby_jam_label: Label = $HBoxContainer/NearbyJamLabel
@onready var active_instruments_label: Label = $HBoxContainer/ActiveInstrumentsLabel
@onready var featured_instrument_label: Label = $HBoxContainer/FeaturedInstrumentLabel
@onready var interact_prompt_label: Label = $HBoxContainer/InteractPromptLabel

var player: Node = null
var music_system: Node = null
var jam_manager: Node = null


func setup_ui(player_ref: Node, music_system_ref: Node) -> void:
	player = player_ref
	music_system = music_system_ref
	jam_manager = get_tree().get_first_node_in_group("jam_manager")

	update_ui()


func update_ui() -> void:
	if jam_manager == null:
		jam_manager = get_tree().get_first_node_in_group("jam_manager")

	_update_equipped_label()
	_update_selected_song_label()
	_update_nearby_jam_label()
	_update_active_instruments_label()
	_update_featured_instrument_label()
	_update_interact_prompt()


func _update_equipped_label() -> void:
	if current_instrument_label == null:
		return

	if player == null:
		current_instrument_label.text = "Equipped: ----"
		return

	if player.has_method("get_current_instrument_display_name"):
		current_instrument_label.text = "Equipped: %s" % player.get_current_instrument_display_name()
	else:
		current_instrument_label.text = "Equipped: ----"


func _update_nearby_jam_label() -> void:
	if nearby_jam_label == null:
		return

	if _player_is_direct_solo():
		nearby_jam_label.text = "Current Jam: Player Solo"
		return

	if jam_manager == null:
		nearby_jam_label.text = "Current Jam: None"
		return

	var jam_source: Node = null
	var jam_type := "none"
	var jam_name := "None"

	if jam_manager.has_method("get_current_nearby_jam_source"):
		jam_source = jam_manager.get_current_nearby_jam_source()

	if jam_manager.has_method("get_current_nearby_jam_type"):
		jam_type = jam_manager.get_current_nearby_jam_type()

	if jam_manager.has_method("get_current_nearby_jam_name"):
		jam_name = jam_manager.get_current_nearby_jam_name()

	if jam_source == null:
		nearby_jam_label.text = "Current Jam: None"
		return

	match jam_type:
		"jam_spot":
			nearby_jam_label.text = "Current Jam: %s" % jam_name
		"player_freeform":
			nearby_jam_label.text = "Current Jam: Player-led Jam"
		"npc_freeform":
			nearby_jam_label.text = "Current Jam: %s's Jam" % jam_name
		"musician":
			nearby_jam_label.text = "Nearby Musician: %s" % jam_name
		_:
			nearby_jam_label.text = "Current Jam: %s" % jam_name


func _update_active_instruments_label() -> void:
	if active_instruments_label == null:
		return

	var active_text := _get_current_active_instruments_text()
	active_instruments_label.text = "Active: %s" % active_text


func _update_featured_instrument_label() -> void:
	if featured_instrument_label == null:
		return

	var featured_text := _get_current_featured_instrument_text()
	featured_instrument_label.text = "Featured: %s" % featured_text


func _update_interact_prompt() -> void:
	if interact_prompt_label == null:
		return

	if player == null:
		interact_prompt_label.visible = false
		return

	var closest_interactable: Node = null

	if player.has_method("get_closest_prompt_interactable"):
		closest_interactable = player.get_closest_prompt_interactable()
	elif player.has_method("get_closest_interactable"):
		closest_interactable = player.get_closest_interactable()

	if closest_interactable == null:
		interact_prompt_label.visible = false
		return

	interact_prompt_label.visible = true

	var interact_name := "Interact"

	if closest_interactable.has_method("get_display_name"):
		interact_name = closest_interactable.get_display_name()
	elif "display_name" in closest_interactable:
		interact_name = str(closest_interactable.display_name)
	elif closest_interactable.name != "":
		interact_name = closest_interactable.name

	interact_prompt_label.text = "Interact: %s" % interact_name


func _get_current_active_instruments_text() -> String:
	var jam_context := _get_current_jam_context()

	if jam_context != null and jam_context.has_method("get_active_instruments_text"):
		return jam_context.get_active_instruments_text()

	if _player_is_direct_solo():
		if player.has_method("get_current_active_instruments_text"):
			return player.get_current_active_instruments_text()

	if jam_manager != null and jam_manager.has_method("get_current_jam_active_instruments_text"):
		return jam_manager.get_current_jam_active_instruments_text()

	return "None"


func _get_current_featured_instrument_text() -> String:
	var jam_context := _get_current_jam_context()

	if jam_context != null and jam_context.has_method("get_featured_instrument_text"):
		return jam_context.get_featured_instrument_text()

	if _player_is_direct_solo():
		if player.has_method("get_current_featured_instrument_text"):
			return player.get_current_featured_instrument_text()

	if jam_manager != null and jam_manager.has_method("get_current_jam_featured_instrument_text"):
		return jam_manager.get_current_jam_featured_instrument_text()

	return "None"


func _get_current_jam_context() -> Node:
	if jam_manager == null:
		return null

	if jam_manager.has_method("get_current_nearby_jam_context"):
		return jam_manager.get_current_nearby_jam_context()

	return null


func _player_is_direct_solo() -> bool:
	if player == null:
		return false

	if player.has_method("is_currently_playing_solo_jam"):
		return player.is_currently_playing_solo_jam()

	return false


func _update_selected_song_label() -> void:
	if selected_song_label == null:
		return

	if player == null:
		selected_song_label.text = "Song: ----"
		return

	var song_id := "song_01"

	if player.has_method("get_selected_song_id"):
		song_id = player.get_selected_song_id()

	var song_name := song_id

	var song_library: Node = get_node_or_null("/root/SongLibrary")

	if song_library != null and song_library.has_method("get_song_display_name"):
		song_name = song_library.get_song_display_name(song_id)

	selected_song_label.text = "Song: %s" % song_name
