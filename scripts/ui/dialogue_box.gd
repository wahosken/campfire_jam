extends CanvasLayer

@onready var speaker_label: Label = $MarginContainer/Panel/VBoxContainer/SpeakerLabel
@onready var dialogue_label: Label = $MarginContainer/Panel/VBoxContainer/DialogueLabel

func _ready() -> void:
	hide()

func show_line(line, speaker = null):

	if speaker != null:
		speaker_label.text = speaker.display_name
	else:
		speaker_label.text = "NO SPEAKER"

	dialogue_label.text = line.text

	show()

func _unhandled_input(event):

	if not visible:
		return

	if event.is_action_pressed("ui_accept") \
	or event.is_action_pressed("interact"):

		get_viewport().set_input_as_handled()
		DialogueManager.advance()
