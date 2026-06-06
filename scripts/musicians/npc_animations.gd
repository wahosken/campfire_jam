extends Node

@onready var character_sprite: AnimatedSprite2D = $"../CharacterSprite"
@onready var instrument_sprite: AnimatedSprite2D = $"../InstrumentSprite"

var facing_direction := "down"

func set_facing_direction(direction: String) -> void:
	facing_direction = direction
	_update_visuals()


func show_instrument() -> void:
	instrument_sprite.visible = true
	_update_visuals()


func hide_instrument() -> void:
	instrument_sprite.visible = false


func _update_visuals() -> void:

	if character_sprite.sprite_frames.has_animation(facing_direction):
		character_sprite.play(facing_direction)

	if instrument_sprite.visible:
		if instrument_sprite.sprite_frames.has_animation(facing_direction):
			instrument_sprite.play(facing_direction)
