extends CanvasLayer

@onready var label: Label = $PanelContainer/Label

var queue: Array[String] = []

var showing := false


func _ready() -> void:

	hide()

	NotificationManager.notification_requested.connect(_add_notification)


func _add_notification(text: String) -> void:

	queue.append(text)

	if not showing:

		show_next()


func show_next() -> void:

	if queue.is_empty():

		showing = false

		visible = false

		return

	showing = true

	visible = true

	label.text = queue.pop_front()

	await get_tree().create_timer(2.5).timeout

	show_next()
