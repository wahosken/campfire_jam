extends Node

@export var base_radius := 48.0
@export var radius_per_extra_member := 6.0

@export var loose_min_radius := 75.0
@export var loose_max_radius := 100.0

@export var precise_min_radius := 125.0
@export var precise_max_radius := 150.0

@export var start_angle_degrees := -90.0
@export var debug_logs := false

@export var use_blocked_slot_fallback := true
@export var world_collision_mask := 1

@export var angle_probe_step_degrees := 20.0
@export var max_angle_probe_steps := 4

@export var radius_probe_step := 16.0
@export var max_radius_probe_steps := 2

@export var slot_clearance_radius := 12.0

var leader: Node2D = null
var members: Array[Node2D] = []
var assigned_slots := {}

var use_precise_slots := false


# ------------------------------------------------------------
# Public API
# ------------------------------------------------------------

func set_leader(new_leader: Node) -> void:
	if new_leader != null and not new_leader is Node2D:
		return

	if leader == new_leader:
		return

	leader = new_leader
	_rebuild_slot_assignments()


func set_members(new_members: Array[Node]) -> void:
	var cleaned_members: Array[Node2D] = []

	for member in new_members:
		if member == null or not is_instance_valid(member):
			continue

		if not member is Node2D:
			continue

		if member == leader:
			continue

		if not cleaned_members.has(member):
			cleaned_members.append(member)

	if _members_match_current_members(cleaned_members):
		return

	members = cleaned_members
	_rebuild_slot_assignments()


func _members_match_current_members(new_members: Array[Node2D]) -> bool:
	if new_members.size() != members.size():
		return false

	for i in new_members.size():
		if new_members[i] != members[i]:
			return false

	return true


func add_member(member: Node) -> void:
	if member == null or not is_instance_valid(member):
		return

	if not member is Node2D:
		return

	if member == leader:
		return

	if members.has(member):
		return

	members.append(member)
	_rebuild_slot_assignments()


func remove_member(member: Node) -> void:
	if member == null:
		return

	if members.has(member):
		members.erase(member)

	if assigned_slots.has(member):
		assigned_slots.erase(member)

	_rebuild_slot_assignments()


func clear() -> void:
	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		if member.has_method("set_precise_jam_formation"):
			member.set_precise_jam_formation(false)

		if member.has_method("clear_jam_formation_target"):
			member.clear_jam_formation_target()

	members.clear()
	assigned_slots.clear()
	leader = null


func get_assigned_target_for_member(member: Node) -> Vector2:
	if leader == null or not is_instance_valid(leader):
		if member != null and member is Node2D:
			return member.global_position

		return Vector2.ZERO

	if not assigned_slots.has(member):
		if member != null and member is Node2D:
			return member.global_position

		return leader.global_position

	var slot_index: int = int(assigned_slots[member])

	if member != null and member is Node2D:
		return get_valid_slot_position(
			leader.global_position,
			slot_index,
			members.size(),
			member.global_position
		)

	return get_valid_slot_position(
		leader.global_position,
		slot_index,
		members.size(),
		leader.global_position
	)


func get_all_assigned_targets() -> Dictionary:
	var targets := {}

	if leader == null or not is_instance_valid(leader):
		return targets

	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		targets[member] = get_assigned_target_for_member(member)

	return targets


func debug_print_assignments() -> void:
	if not debug_logs:
		return

	print("JamFormation assignments:")

	if leader == null or not is_instance_valid(leader):
		print("  Leader: none")
	else:
		print("  Leader: %s at %s" % [leader.name, leader.global_position])

	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		var slot_index := -1

		if assigned_slots.has(member):
			slot_index = int(assigned_slots[member])

		print("  %s -> slot %s target %s" % [
			member.name,
			slot_index,
			get_assigned_target_for_member(member)
		])


# ------------------------------------------------------------
# Slot math
# ------------------------------------------------------------

func get_slot_positions(leader_position: Vector2, follower_count: int) -> Array[Vector2]:
	var positions: Array[Vector2] = []

	if follower_count <= 0:
		return positions

	var radius := get_radius_for_count(follower_count)
	var angle_step := TAU / float(follower_count)
	var start_angle := deg_to_rad(start_angle_degrees)

	for i in follower_count:
		var angle := start_angle + angle_step * float(i)
		var direction := Vector2.RIGHT.rotated(angle)
		var slot_position := leader_position + direction * radius

		positions.append(slot_position)

	return positions


func get_slot_position(
	leader_position: Vector2,
	follower_index: int,
	follower_count: int
) -> Vector2:
	if follower_count <= 0:
		return leader_position

	var radius := get_radius_for_count(follower_count)
	var angle := get_angle_for_index(follower_index, follower_count)

	return leader_position + Vector2.RIGHT.rotated(angle) * radius


func get_radius_for_count(follower_count: int) -> float:
	var min_radius: float = loose_min_radius
	var max_radius: float = loose_max_radius

	if use_precise_slots:
		min_radius = precise_min_radius
		max_radius = precise_max_radius

	if follower_count <= 1:
		return min_radius

	var t: float = clamp(float(follower_count - 1) / 5.0, 0.0, 1.0)

	return lerp(min_radius, max_radius, t)


func apply_targets_to_members() -> void:
	if leader == null or not is_instance_valid(leader):
		return

	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		var target_position: Vector2 = get_assigned_target_for_member(member)

		if member.has_method("set_jam_formation_target"):
			member.set_jam_formation_target(target_position)

		if member.has_method("set_precise_jam_formation"):
			member.set_precise_jam_formation(use_precise_slots)


func clear_targets_from_members() -> void:
	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		if member.has_method("clear_jam_formation_target"):
			member.clear_jam_formation_target()



func debug_print_slots(leader_position: Vector2, follower_count: int) -> void:
	if not debug_logs:
		return

	var positions := get_slot_positions(leader_position, follower_count)

	print("JamFormation slots for %s followers:" % follower_count)

	for i in positions.size():
		print("  Slot %s: %s" % [i, positions[i]])


func get_valid_slot_position(
	leader_position: Vector2,
	follower_index: int,
	follower_count: int,
	fallback_position: Vector2
) -> Vector2:
	var ideal_radius: float = get_radius_for_count(follower_count)
	var ideal_angle: float = get_angle_for_index(follower_index, follower_count)

	var ideal_position: Vector2 = leader_position + Vector2.RIGHT.rotated(ideal_angle) * ideal_radius

	if not use_blocked_slot_fallback:
		return ideal_position

	if _is_world_position_valid(ideal_position):
		return ideal_position

	# Try nearby angles at the same radius.
	for step in range(1, max_angle_probe_steps + 1):
		var angle_offset: float = deg_to_rad(angle_probe_step_degrees * float(step))

		var positive_angle_position: Vector2 = leader_position + Vector2.RIGHT.rotated(ideal_angle + angle_offset) * ideal_radius

		if _is_world_position_valid(positive_angle_position):
			return positive_angle_position

		var negative_angle_position: Vector2 = leader_position + Vector2.RIGHT.rotated(ideal_angle - angle_offset) * ideal_radius

		if _is_world_position_valid(negative_angle_position):
			return negative_angle_position

	# Try smaller/larger radii with the same angle probes.
	for radius_step in range(1, max_radius_probe_steps + 1):
		var smaller_radius: float = maxf(8.0, ideal_radius - radius_probe_step * float(radius_step))
		var larger_radius: float = ideal_radius + radius_probe_step * float(radius_step)

		var smaller_position: Vector2 = _find_valid_position_at_radius(
			leader_position,
			ideal_angle,
			smaller_radius
		)

		if _is_world_position_valid(smaller_position):
			return smaller_position

		var larger_position: Vector2 = _find_valid_position_at_radius(
			leader_position,
			ideal_angle,
			larger_radius
		)

		if _is_world_position_valid(larger_position):
			return larger_position

	# If every tested slot is blocked, keep the NPC where they already are.
	return fallback_position


func get_angle_for_index(follower_index: int, follower_count: int) -> float:
	if follower_count <= 0:
		return deg_to_rad(start_angle_degrees)

	var angle_step := TAU / float(follower_count)
	var start_angle := deg_to_rad(start_angle_degrees)

	return start_angle + angle_step * float(follower_index)


func _find_valid_position_at_radius(
	leader_position: Vector2,
	ideal_angle: float,
	radius: float
) -> Vector2:
	var ideal_position := leader_position + Vector2.RIGHT.rotated(ideal_angle) * radius

	if _is_world_position_valid(ideal_position):
		return ideal_position

	for step in range(1, max_angle_probe_steps + 1):
		var angle_offset := deg_to_rad(angle_probe_step_degrees * float(step))

		var positive_angle_position := leader_position + Vector2.RIGHT.rotated(ideal_angle + angle_offset) * radius

		if _is_world_position_valid(positive_angle_position):
			return positive_angle_position

		var negative_angle_position := leader_position + Vector2.RIGHT.rotated(ideal_angle - angle_offset) * radius

		if _is_world_position_valid(negative_angle_position):
			return negative_angle_position

	return ideal_position


func _is_world_position_valid(world_position: Vector2) -> bool:
	var world_2d := get_viewport().world_2d

	if world_2d == null:
		return true

	var space_state := world_2d.direct_space_state

	var shape := CircleShape2D.new()
	shape.radius = slot_clearance_radius

	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, world_position)
	query.collision_mask = world_collision_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var results := space_state.intersect_shape(query, 1)

	return results.is_empty()


func set_precise_slots(is_precise: bool) -> void:
	use_precise_slots = is_precise


# ------------------------------------------------------------
# Assignment internals
# ------------------------------------------------------------

func _rebuild_slot_assignments() -> void:
	assigned_slots.clear()

	for i in members.size():
		var member: Node2D = members[i]
		assigned_slots[member] = i

	debug_print_assignments()
