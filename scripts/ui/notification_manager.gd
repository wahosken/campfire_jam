extends Node

signal notification_requested(text)

func show_notification(text: String) -> void:

	notification_requested.emit(text)
