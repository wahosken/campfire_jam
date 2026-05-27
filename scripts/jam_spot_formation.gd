extends Node

@export var min_radius := 125.0
@export var max_radius := 150.0
@export var start_angle_degrees := -90.0

var jam_spot: Node2D = null
var members: Array[Node] = []
var assigned_slots := {}


func set_jam_spot(source_jam_spot: Node2D) -> void:
	jam_spot = source_jam_spot
	_rebuild_assignments()


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

	_rebuild_assignments()
	apply_targets_to_members()


func clear() -> void:
	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		if member.has_method("clear_jam_formation_target"):
			member.clear_jam_formation_target()

	members.clear()
	assigned_slots.clear()


func _rebuild_assignments() -> void:
	assigned_slots.clear()

	for i in range(members.size()):
		assigned_slots[members[i]] = i


func apply_targets_to_members() -> void:
	if jam_spot == null or not is_instance_valid(jam_spot):
		return

	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		var target_position: Vector2 = get_assigned_target_for_member(member)

		if member.has_method("set_jam_formation_target"):
			member.set_jam_formation_target(target_position)


func get_assigned_target_for_member(member: Node) -> Vector2:
	if jam_spot == null or not is_instance_valid(jam_spot):
		if member != null and member is Node2D:
			return member.global_position

		return Vector2.ZERO

	if not assigned_slots.has(member):
		if member != null and member is Node2D:
			return member.global_position

		return jam_spot.global_position

	var slot_index: int = int(assigned_slots[member])

	return get_slot_position(
		jam_spot.global_position,
		slot_index,
		members.size()
	)


func get_slot_position(
	center_position: Vector2,
	follower_index: int,
	follower_count: int
) -> Vector2:
	if follower_count <= 0:
		return center_position

	var radius: float = get_radius_for_count(follower_count)
	var angle: float = get_angle_for_index(follower_index, follower_count)

	return center_position + Vector2.RIGHT.rotated(angle) * radius


func get_radius_for_count(follower_count: int) -> float:
	if follower_count <= 1:
		return min_radius

	var t: float = clamp(float(follower_count - 1) / 5.0, 0.0, 1.0)

	return lerp(min_radius, max_radius, t)


func get_angle_for_index(follower_index: int, follower_count: int) -> float:
	if follower_count <= 0:
		return deg_to_rad(start_angle_degrees)

	var angle_step: float = TAU / float(follower_count)
	var start_angle: float = deg_to_rad(start_angle_degrees)

	return start_angle + angle_step * float(follower_index)
