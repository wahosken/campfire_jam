extends Node

@export var base_radius := 48.0
@export var radius_per_extra_member := 6.0
@export var max_radius := 96.0

@export var start_angle_degrees := -90.0
@export var debug_logs := false

var leader: Node2D = null
var members: Array[Node2D] = []
var assigned_slots := {}


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
	clear_targets_from_members()

	leader = null
	members.clear()
	assigned_slots.clear()


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
	return get_slot_position(leader.global_position, slot_index, members.size())


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
	var angle_step := TAU / float(follower_count)
	var start_angle := deg_to_rad(start_angle_degrees)
	var angle := start_angle + angle_step * float(follower_index)

	return leader_position + Vector2.RIGHT.rotated(angle) * radius


func get_radius_for_count(follower_count: int) -> float:
	if follower_count <= 1:
		return base_radius

	var radius := base_radius + float(follower_count - 1) * radius_per_extra_member
	return min(radius, max_radius)


func apply_targets_to_members() -> void:
	if leader == null or not is_instance_valid(leader):
		return

	for member in members:
		if member == null or not is_instance_valid(member):
			continue

		var target_position := get_assigned_target_for_member(member)

		if member.has_method("set_jam_formation_target"):
			member.set_jam_formation_target(target_position)


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


# ------------------------------------------------------------
# Assignment internals
# ------------------------------------------------------------

func _rebuild_slot_assignments() -> void:
	assigned_slots.clear()

	for i in members.size():
		var member: Node2D = members[i]
		assigned_slots[member] = i

	debug_print_assignments()
