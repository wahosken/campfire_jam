extends Node2D

@export var stem_name := "bass"

@export var start_playing := false
@export var playing_color := Color(1.0, 0.9, 0.15)
@export var idle_color := Color(0.12, 0.12, 0.12)
@export var bounce_amount := 4.0
@export var squish_amount := 0.08
@export var pulse_speed := 8.0

@onready var visual: ColorRect = $ColorRect

var is_playing := false
var base_position := Vector2.ZERO
var base_scale := Vector2.ONE
var anim_time := 0.0
var music_system: Node = null


func _ready() -> void:
	music_system = get_tree().get_first_node_in_group("music_system")

	base_position = visual.position
	base_scale = visual.scale

	if start_playing:
		start_music()
	else:
		stop_music()


func _process(delta: float) -> void:
	if is_playing:
		anim_time += delta * pulse_speed

		var bounce := sin(anim_time) * bounce_amount
		var squish := sin(anim_time) * squish_amount

		visual.position = base_position + Vector2(0, bounce)
		visual.scale = Vector2(
			base_scale.x + squish,
			base_scale.y - squish
		)
	else:
		visual.position = visual.position.lerp(base_position, delta * 12.0)
		visual.scale = visual.scale.lerp(base_scale, delta * 12.0)


func interact() -> void:
	if is_playing:
		stop_music()
	else:
		start_music()


func start_music() -> void:
	is_playing = true
	anim_time = 0.0
	visual.color = playing_color

	if music_system != null:
		music_system.set_stem_active(stem_name, true)


func stop_music() -> void:
	is_playing = false
	visual.color = idle_color

	if music_system != null:
		music_system.set_stem_active(stem_name, false)
