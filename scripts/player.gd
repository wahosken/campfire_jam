extends CharacterBody2D

@export var speed := 180.0

var music_system: Node = null
var guitar_is_playing := false


func _ready() -> void:
	music_system = get_tree().get_first_node_in_group("music_system")


func _physics_process(_delta: float) -> void:
	_handle_movement()
	_handle_guitar_input()


func _handle_movement() -> void:
	var input_vector := Vector2.ZERO

	input_vector.x = Input.get_axis("move_left", "move_right")
	input_vector.y = Input.get_axis("move_up", "move_down")

	input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()


func _handle_guitar_input() -> void:
	if music_system == null:
		return

	if Input.is_action_pressed("interact"):
		if not guitar_is_playing:
			guitar_is_playing = true
			music_system.set_stem_active("guitar", true)
	else:
		if guitar_is_playing:
			guitar_is_playing = false
			music_system.set_stem_active("guitar", false)
