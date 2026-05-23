extends Control


@onready var instrument_label: Label = $HBoxContainer/CurrentInstrumentLabel
@onready var featured_instrument_label: Label = $HBoxContainer/FeaturedInstrumentLabel
@onready var active_instruments_label: Label = $HBoxContainer/ActiveInstrumentsLabel
@onready var interact_prompt_label: Label = $HBoxContainer/InteractPromptLabel

var player: Node = null
var music_system: Node = null


func setup_ui(player_ref: Node, music_system_ref: Node) -> void:
	player = player_ref
	music_system = music_system_ref
	update_ui()


func update_ui() -> void:
	_update_player_instrument_label()
	_update_interact_prompt()
	_update_music_debug_labels()


func _update_player_instrument_label() -> void:
	if instrument_label == null:
		return

	if player == null:
		instrument_label.text = "Equipped: ----"
		return

	if player.has_method("get_current_instrument_display_name"):
		instrument_label.text = "Equipped: %s" % player.get_current_instrument_display_name()
	else:
		instrument_label.text = "Equipped: ----"


func _update_interact_prompt() -> void:
	if interact_prompt_label == null:
		return

	if player == null:
		interact_prompt_label.visible = false
		return

	if not player.has_method("get_closest_npc"):
		interact_prompt_label.visible = false
		return

	var closest_npc: Node = player.get_closest_npc()

	if closest_npc == null:
		interact_prompt_label.visible = false
		return

	interact_prompt_label.visible = true

	var npc_name := "NPC"

	if "display_name" in closest_npc:
		npc_name = closest_npc.display_name

	interact_prompt_label.text = "Press Interact: %s" % npc_name


func _update_music_debug_labels() -> void:
	if music_system == null:
		if featured_instrument_label != null:
			featured_instrument_label.text = "Featured: None"

		if active_instruments_label != null:
			active_instruments_label.text = "Active: None"

		return

	if featured_instrument_label != null:
		if music_system.has_method("get_featured_instrument_text"):
			featured_instrument_label.text = "Featured: %s" % music_system.get_featured_instrument_text()
		else:
			featured_instrument_label.text = "Featured: None"

	if active_instruments_label != null:
		if music_system.has_method("get_active_instruments_text"):
			active_instruments_label.text = "Active: %s" % music_system.get_active_instruments_text()
		else:
			active_instruments_label.text = "Active: None"
