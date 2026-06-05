extends Node

var current_sequence = null
var current_index := 0

var current_speaker: Node = null

var dialogue_box = null

var dialogue_active := false


func get_dialogue_box():

	if dialogue_box == null: dialogue_box = get_tree().get_first_node_in_group("dialogue_box")

	return dialogue_box


func start_dialogue(sequence, speaker = null) -> void:

	current_speaker = speaker

	dialogue_active = true

	current_sequence = sequence
	current_index = 0

	show_current_line()


func show_current_line() -> void:

	if current_sequence == null:
		end_dialogue()
		return

	if current_index >= current_sequence.lines.size():
		end_dialogue()
		return

	var box = get_dialogue_box()

	box.show_line(current_sequence.lines[current_index],current_speaker)


func advance() -> void:

	if not dialogue_active:
		return

	current_index += 1
	show_current_line()


func end_dialogue() -> void:

	if current_speaker != null:
		if current_speaker.has_method("advance_after_dialogue"):
			current_speaker.advance_after_dialogue()

	dialogue_active = false

	current_sequence = null
	current_index = 0

	var box = get_dialogue_box()

	if box != null: box.hide()


func is_dialogue_active() -> bool:
	return dialogue_active
