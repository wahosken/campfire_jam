extends Node

const SAVE_PATH := "user://campfirejam_save.json"

var world_data := WorldSaveData.new()

var character_data := CharacterSaveData.new()


func capture_game_state() -> void:

	var player := get_tree().get_first_node_in_group(
		"player"
	)

	if player != null:

		character_data.unlocked_instruments = \
			player.unlocked_instruments.duplicate()

		character_data.unlocked_songs = \
			player.unlocked_songs.duplicate()

		character_data.collected_items = \
			player.collected_items.duplicate()

	world_data.recruited_npcs.clear()

	for npc in get_tree().get_nodes_in_group(
		"npc_musician"
	):

		if not is_instance_valid(npc):
			continue

		if not npc.is_recruited():
			continue

		if npc.npc_id.is_empty():
			continue

		world_data.recruited_npcs.append(
			npc.npc_id
		)

	# NEW
	world_data.completed_quests.clear()

	if QuestManager != null:
		world_data.completed_quests = \
			QuestManager.completed_quests.duplicate()


func save_game() -> void:

	capture_game_state()

	var save_dict := {

		"world": {
			"recruited_npcs":
				world_data.recruited_npcs,

			"completed_quests":
				world_data.completed_quests
		},

		"character": {
			"unlocked_instruments":
				character_data.unlocked_instruments,

			"unlocked_songs":
				character_data.unlocked_songs,

			"collected_items":
				character_data.collected_items
		}
	}

	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.WRITE
	)

	if file == null:
		return

	file.store_string(
		JSON.stringify(save_dict, "\t")
	)

	file.close()

	print("GAME SAVED")


func debug_print_save() -> void:

	capture_game_state()

	print("NPCS: ", world_data.recruited_npcs)

	print("QUESTS: ", world_data.completed_quests)

	print("INSTRUMENTS: ",
		character_data.unlocked_instruments)

	print("SONGS: ",
		character_data.unlocked_songs)

	print("ITEMS: ",
		character_data.collected_items)


func _input(event):

	if event.is_action_pressed("ui_page_up"):

		debug_print_save()
		save_game()

	if event.is_action_pressed("ui_caps"):
		load_game()


func is_item_collected(item_id: String) -> bool:

	return character_data.collected_items.has(
		item_id
	)


func load_game() -> void:

	if not FileAccess.file_exists(
		SAVE_PATH
	):
		print("NO SAVE FOUND")
		return

	var file := FileAccess.open(
		SAVE_PATH,
		FileAccess.READ
	)

	if file == null:
		return

	var json_text := file.get_as_text()

	file.close()

	var json := JSON.new()

	var error := json.parse(json_text)

	if error != OK:
		print("SAVE PARSE FAILED")
		return

	var data = json.data

	# -------------------------
	# WORLD DATA
	# -------------------------

	if data.has("world"):

		var world = data["world"]

		world_data.completed_quests.clear()

		for quest_id in world.get(
			"completed_quests",
			[]
		):
			world_data.completed_quests.append(
				str(quest_id)
			)

		world_data.recruited_npcs.clear()

		for npc_id in world.get(
			"recruited_npcs",
			[]
		):
			world_data.recruited_npcs.append(
				str(npc_id)
			)

	# -------------------------
	# CHARACTER DATA
	# -------------------------

	if data.has("character"):

		var character = data["character"]

		character_data.unlocked_instruments.clear()

		for instrument in character.get(
			"unlocked_instruments",
			[]
		):
			character_data.unlocked_instruments.append(
				str(instrument)
			)

		character_data.unlocked_songs.clear()

		for song in character.get(
			"unlocked_songs",
			[]
		):
			character_data.unlocked_songs.append(
				str(song)
			)

		character_data.collected_items.clear()

		for item in character.get(
			"collected_items",
			[]
		):
			character_data.collected_items.append(
				str(item)
			)

	# -------------------------
	# DEBUG
	# -------------------------

	print(
		"LOADED QUESTS: ",
		world_data.completed_quests
	)

	print(
		"LOADED NPCS: ",
		world_data.recruited_npcs
	)

	print(
		"LOADED INSTRUMENTS: ",
		character_data.unlocked_instruments
	)

	print(
		"LOADED SONGS: ",
		character_data.unlocked_songs
	)

	print(
		"LOADED ITEMS: ",
		character_data.collected_items
	)

	# -------------------------
	# RESTORE QUESTS
	# -------------------------

	if QuestManager != null:

		QuestManager.restore_completed_quests(
			world_data.completed_quests
		)

	# -------------------------
	# RESTORE PLAYER
	# -------------------------

	var player := get_tree().get_first_node_in_group(
		"player"
	)

	if player != null:

		player.unlocked_instruments = \
			character_data.unlocked_instruments.duplicate()

		player.unlocked_songs = \
			character_data.unlocked_songs.duplicate()

		player.collected_items = \
			character_data.collected_items.duplicate()

		print("PLAYER DATA RESTORED")

	# -------------------------
	# RESTORE WORLD REACTIONS
	# -------------------------

	for reaction in get_tree().get_nodes_in_group(
		"world_reaction"
	):

		if not is_instance_valid(reaction):
			continue

		if reaction.quest_id.is_empty():
			continue

		if not QuestManager.is_quest_complete(
			reaction.quest_id
		):
			continue

		reaction.restore_completed_state()

	# -------------------------
	# RESTORE NPCS
	# -------------------------

	for npc in get_tree().get_nodes_in_group(
		"npc_musician"
	):

		print(
			"NPC:",
			npc.npc_id,
			" Saved:",
			world_data.recruited_npcs
		)

		if not is_instance_valid(npc):
			continue

		if not world_data.recruited_npcs.has(
			npc.npc_id
		):
			continue

		print(
			"RESTORING NPC:",
			npc.npc_id
		)

		npc.restore_recruited_state()

	print("GAME LOADED")

	print(
		"COLLECTIBLES FOUND:",
		get_tree().get_nodes_in_group(
			"collectible"
		).size()
	)

	for collectible in get_tree().get_nodes_in_group(
		"collectible"
	):
		print(
			"RESTORING COLLECTIBLE:",
			collectible.name
		)

		if not is_instance_valid(collectible):
			continue

		if collectible.has_method("restore_state"):
			collectible.restore_state()
