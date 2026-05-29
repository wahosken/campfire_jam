extends Node

var unlocked_npc_ids: Dictionary = {}


func _ready() -> void:
	add_to_group("npc_unlock_manager")


func get_npc_by_id(id: String) -> Node:

	print("Searching for NPC id: ", id)

	for npc in get_tree().get_nodes_in_group("npc_musician"):

		print("Checking NPC: ", npc.name, " unlock_id=", npc.get_unlock_id())

		if npc.get_unlock_id() == id:
			print("MATCH FOUND")
			return npc

	print("NO MATCH FOUND")

	return null


func unlock_npc_by_id(id: String) -> bool:

	print("unlock_npc_by_id: ", id)

	if id == "":
		print("Empty unlock id")
		return false

	if unlocked_npc_ids.has(id):
		print("Already unlocked")
		return true

	unlocked_npc_ids[id] = true

	var npc: Node = get_npc_by_id(id)

	if npc != null:

		if npc.has_method("unlock_npc"):
			npc.unlock_npc()

		print("Unlocked NPC: ", id)

		return true

	print("Failed to find NPC: ", id)

	return false


func is_npc_unlocked(id: String) -> bool:
	return unlocked_npc_ids.has(id)


func lock_npc_by_id(id: String) -> bool:

	unlocked_npc_ids.erase(id)

	for npc in get_tree().get_nodes_in_group("npc_musician"):

		if npc.get_unlock_id() == id:

			if npc.has_method("lock_npc"):
				npc.lock_npc()

			return true

	return false
