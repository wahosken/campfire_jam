extends Node

@export var min_radius := 125.0
@export var max_radius := 150.0
@export var start_angle_degrees := -90.0

var jam_spot: Node2D = null
var members: Array[Node] = []


func set_jam_spot(source_jam_spot: Node2D) -> void:
	jam_spot = source_jam_spot


func set_members(new_members: Array[Node]) -> void:
	members.clear()

	for member in new_members:
		if member == null or not is_instance_valid(member):
			continue

		if not member.is_in_group("musician"):
			continue

		if not member is Node2D:
			continue

		members.append(member)

	apply_targets_to_members()


func clear() -> void:
	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		if member.has_method("clear_jam_formation_target"):
			member.clear_jam_formation_target()

	members.clear()


func apply_targets_to_members() -> void:
	if jam_spot == null or not is_instance_valid(jam_spot):
		return

	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		var target_position: Vector2 = jam_spot.get_field_position_for_npc(member, members)

		if member.has_method("set_jam_formation_target"):
			member.set_jam_formation_target(target_position)


func get_radius_for_count(follower_count: int) -> float:
	if follower_count <= 1:
		return min_radius

	var t: float = clamp(float(follower_count - 1) / 5.0, 0.0, 1.0)

	return lerp(min_radius, max_radius, t)
