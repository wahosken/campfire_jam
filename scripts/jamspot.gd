extends Area2D

@export var instrument_name := "Guitar"
@export var stem_name := "guitar"

@onready var label: Label = $Label
@onready var visual: ColorRect = $ColorRect

var player_nearby := false
var music_system: Node = null


func _ready() -> void:
	label.text = instrument_name

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	music_system = get_tree().get_first_node_in_group("music_system")


func _process(_delta: float) -> void:
	if music_system == null:
		return

	if music_system.is_stem_active(stem_name):
		visual.color = Color(0.9, 0.7, 0.25)
	else:
		visual.color = Color(0.25, 0.25, 0.25)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = true
		body.set_nearby_jam_spot(self)


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_nearby = false
		body.clear_nearby_jam_spot(self)


func interact() -> void:
	if music_system == null:
		print("No music system found.")
		return

	music_system.toggle_stem(stem_name)
	print("Toggled ", instrument_name)
