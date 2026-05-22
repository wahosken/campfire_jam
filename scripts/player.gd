extends CharacterBody2D

@export var speed := 180.0

var nearby_jam_spot: Node = null


func _physics_process(_delta: float) -> void:
	var input_vector := Vector2.ZERO

	input_vector.x = Input.get_axis("move_left", "move_right")
	input_vector.y = Input.get_axis("move_up", "move_down")

	input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()

	if Input.is_action_just_pressed("interact"):
		if nearby_jam_spot != null:
			nearby_jam_spot.interact()


func set_nearby_jam_spot(spot: Node) -> void:
	nearby_jam_spot = spot


func clear_nearby_jam_spot(spot: Node) -> void:
	if nearby_jam_spot == spot:
		nearby_jam_spot = null
