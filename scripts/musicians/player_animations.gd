extends Node

@onready var character_sprite: AnimatedSprite2D = $"../CharacterSprite"
@onready var instrument_sprite: AnimatedSprite2D = $"../InstrumentSprite"

var facing_direction := "down"

func set_facing_direction(direction: String) -> void:
	facing_direction = direction
	_update_character_animation()


func show_instrument(instrument_id: String) -> void:

	instrument_sprite.visible = true

	var animation_name := (
		instrument_id
		+ "_"
		+ facing_direction
	)

	if instrument_sprite.sprite_frames.has_animation(animation_name):
		instrument_sprite.play(animation_name)


func hide_instrument() -> void:
	instrument_sprite.visible = false


func _update_character_animation() -> void:

	var animation_name := facing_direction

	if character_sprite.sprite_frames.has_animation(animation_name):
		character_sprite.play(animation_name)

	if instrument_sprite.visible:

		var current_animation := instrument_sprite.animation

		if current_animation.is_empty():
			return

		var pieces := current_animation.split("_")

		if pieces.is_empty():
			return

		var instrument_id := pieces[0]

		show_instrument(instrument_id)
