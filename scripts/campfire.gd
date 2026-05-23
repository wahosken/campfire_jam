extends Node2D

@export var start_on_game_start := true
@export var wait_for_input_on_web := true

@onready var interaction_area: Area2D = $InteractionArea
@onready var label: Label = $Label
@onready var sprite: CanvasItem = $ColorRect

var music_system: Node = null
var jam_is_on := false
var has_started_once := false

const FIRE_ON_COLOR := Color(1.25, 0.85, 0.45, 1)
const FIRE_OFF_COLOR := Color(0.35, 0.35, 0.35, 1)


func _ready() -> void:
	add_to_group("interactable")

	music_system = get_tree().get_first_node_in_group("music_system")

	_update_visuals()

	if start_on_game_start:
		if OS.has_feature("web") and wait_for_input_on_web:
			label.text = "Campfire: Click/Tap to Start"
		else:
			call_deferred("turn_jam_on")


func _input(event: InputEvent) -> void:
	if has_started_once:
		return

	if not start_on_game_start:
		return

	if not OS.has_feature("web"):
		return

	if not wait_for_input_on_web:
		return

	if _is_audio_unlock_input(event):
		has_started_once = true
		turn_jam_on()


func interact() -> void:
	if jam_is_on:
		turn_jam_off()
	else:
		turn_jam_on()


func turn_jam_on() -> void:
	jam_is_on = true

	if music_system != null and music_system.has_method("set_npc_jam_enabled"):
		music_system.set_npc_jam_enabled(true)

	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if npc.has_method("start_music"):
			npc.start_music()

	_update_visuals()


func turn_jam_off() -> void:
	jam_is_on = false

	for npc in get_tree().get_nodes_in_group("npc_musician"):
		if npc.has_method("stop_music"):
			npc.stop_music()

	if music_system != null and music_system.has_method("set_npc_jam_enabled"):
		music_system.set_npc_jam_enabled(false)

	_update_visuals()


func _update_visuals() -> void:
	if label != null:
		if jam_is_on:
			label.text = "Campfire: On"
		else:
			label.text = "Campfire: Off"

	if sprite != null:
		sprite.modulate = FIRE_ON_COLOR if jam_is_on else FIRE_OFF_COLOR


func _is_audio_unlock_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed:
		return true

	if event is InputEventScreenTouch and event.pressed:
		return true

	if event is InputEventKey and event.pressed:
		return true

	if event is InputEventJoypadButton and event.pressed:
		return true

	return false
