extends Node

const CHARACTER_FOLDER := "user://characters/"
const WORLD_FOLDER := "user://worlds/"
const PROFILE_PATH := "user://profile.json"
const AUTOSAVE_FOLDER := "user://autosaves/"

const AUTOSAVE_COOLDOWN := 5.0

var last_autosave_time := 0.0

var is_loading_game := false

var world_data := WorldSaveData.new()

var character_data := CharacterSaveData.new()

var current_character_id := ""

var current_world_id := ""


func _ready() -> void:

	DirAccess.make_dir_absolute(CHARACTER_FOLDER)

	DirAccess.make_dir_absolute(WORLD_FOLDER)

	DirAccess.make_dir_absolute(AUTOSAVE_FOLDER)

	ensure_profile_exists()


func get_timestamp_string() -> String:

	var datetime := \
		Time.get_datetime_dict_from_system()

	return (
		"%04d-%02d-%02d_%02d-%02d-%02d"
		% [
			datetime.year,
			datetime.month,
			datetime.day,
			datetime.hour,
			datetime.minute,
			datetime.second
		]
	)


func get_character_path(character_id: String) -> String:

	return CHARACTER_FOLDER + character_id + ".json"


func get_world_path(world_id: String) -> String:

	return WORLD_FOLDER + world_id + ".json"


func get_world_autosave_folder(world_id: String) -> String:

	return (AUTOSAVE_FOLDER + world_id + "/")


func create_autosave_snapshot() -> void:

	var folder := \
		get_world_autosave_folder(
			current_world_id
		)

	DirAccess.make_dir_absolute(
		folder
	)

	var autosave_path := (
		folder +
		"autosave_" +
		get_timestamp_string() +
		".json"
	)

	var data := {

		"world_id":
			current_world_id,

		"world_name":
			build_world_snapshot().get(
				"world_name",
				""
			),

		"character_id":
			current_character_id,

		"character_name":
			build_character_snapshot().get(
				"character_name",
				""
			),

		"created_at":
			int(
				Time.get_unix_time_from_system()
			),

		"display_timestamp":
			get_timestamp_string(),

		"world_data":
			build_world_snapshot(),

		"character_data":
			build_character_snapshot()
	}

	var file := FileAccess.open(
		autosave_path,
		FileAccess.WRITE
	)

	if file == null:
		return

	file.store_string(
		JSON.stringify(
			data,
			"\t"
		)
	)

	file.close()

	print(
		"AUTOSAVE SNAPSHOT:",
		autosave_path
	)

	prune_old_autosaves(
		folder
	)

func ensure_profile_exists() -> void:

	if FileAccess.file_exists(PROFILE_PATH):
		return

	var profile := {"last_world_id": ""}

	var file := FileAccess.open(PROFILE_PATH,FileAccess.WRITE)

	if file == null:
		return

	file.store_string(JSON.stringify(profile,"\t"))

	file.close()


func create_character(character_name: String) -> String:

	var id := ("character_" + get_timestamp_string())


	var character_dict := {

		"version": 0.1,

		"character_id": id,
		"character_name": character_name,

		"created_at": int(
			Time.get_unix_time_from_system()
		),

		"last_played": int(
			Time.get_unix_time_from_system()
		),

		"unlocked_instruments": [
			"guitar"
		],

		"unlocked_songs": [
			"song_01"
		],

		"collected_items": []
	}

	var file := FileAccess.open(get_character_path(id),FileAccess.WRITE)

	if file == null:
		return ""

	file.store_string(JSON.stringify(character_dict,"\t"))

	file.close()

	return id


func create_world(world_name: String) -> String:

	var id := ("world_" + get_timestamp_string())

	var current_time := int(Time.get_unix_time_from_system())

	var world_dict := {

		"version": 1,

		"world_id": id,

		"world_name": world_name,

		"created_at": current_time,

		"last_played": current_time,

		"last_character_id": current_character_id,

		"recruited_npcs": [],

		"completed_quests": []
	}

	var file := FileAccess.open(
		get_world_path(id),
		FileAccess.WRITE
	)

	if file == null:
		return ""

	file.store_string(
		JSON.stringify(
			world_dict,
			"\t"
		)
	)

	file.close()

	print(
		"WORLD CREATED:",
		id
	)

	return id


func capture_game_state() -> void:

	var player := get_tree().get_first_node_in_group(
		"player"
	)

	if player != null:

		print(
			"CAPTURE INSTRUMENTS:",
			player.unlocked_instruments
		)

		print(
			"CAPTURE SONGS:",
			player.unlocked_songs
		)

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

	save_character_file()

	save_world_file()

	print("GAME SAVED")


func create_autosave() -> void:

	if is_loading_game:
		return

	if current_world_id.is_empty():
		return

	var current_time := Time.get_unix_time_from_system()

	if current_time - last_autosave_time < AUTOSAVE_COOLDOWN:

		print("AUTOSAVE SKIPPED (COOLDOWN)")

		return

	last_autosave_time = current_time

	save_game()

	create_autosave_snapshot()

	print("AUTOSAVE CREATED")


func prune_old_autosaves(folder: String) -> void:

	var files: Array[String] = []

	var dir := DirAccess.open(folder)

	if dir == null:
		return

	dir.list_dir_begin()

	var file_name := dir.get_next()

	while file_name != "":

		if file_name.ends_with(".json"):

			files.append(file_name)

		file_name = dir.get_next()

	dir.list_dir_end()

	files.sort()

	while files.size() > 3:

		var oldest: String = files.pop_front()

		DirAccess.remove_absolute(folder + oldest)

		print("REMOVED AUTOSAVE:",oldest)


func save_character_file() -> void:

	capture_game_state()

	if current_character_id.is_empty():
		return

	var path := get_character_path(current_character_id)

	var data := {}

	if FileAccess.file_exists(path):

		var read_file := FileAccess.open(path,FileAccess.READ)

		if read_file != null:

			var json := JSON.new()

			if json.parse(read_file.get_as_text()) == OK:

				data = json.data

			read_file.close()

	data["last_played"] = int(Time.get_unix_time_from_system())

	data["unlocked_instruments"] = character_data.unlocked_instruments

	data["unlocked_songs"] = character_data.unlocked_songs

	data["collected_items"] = character_data.collected_items

	var write_file := FileAccess.open(path,FileAccess.WRITE)

	if write_file == null:
		return

	write_file.store_string(JSON.stringify(data,"\t"))

	write_file.close()

	print("CHARACTER SAVED:",current_character_id)


func save_world_file() -> void:

	capture_game_state()

	if current_world_id.is_empty():
		return

	var path := get_world_path(
		current_world_id
	)

	var data := get_world_data(
		current_world_id
	)

	if data.is_empty():
		return

	data["last_played"] = int(Time.get_unix_time_from_system())

	data["recruited_npcs"] = \
		world_data.recruited_npcs

	data["completed_quests"] = \
		world_data.completed_quests

	var file := FileAccess.open(
		path,
		FileAccess.WRITE
	)

	if file == null:
		return

	file.store_string(
		JSON.stringify(
			data,
			"\t"
		)
	)

	file.close()

	print(
		"WORLD SAVED:",
		current_world_id
	)


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

	is_loading_game = true

	print("LOAD_GAME CALLED")

	if not load_world_file():

		print(
			"WORLD LOAD FAILED"
		)

		return

	if not load_character_file():

		print(
			"CHARACTER LOAD FAILED"
		)

		return

	print(
		"LOADED QUESTS:",
		world_data.completed_quests
	)

	print(
		"LOADED NPCS:",
		world_data.recruited_npcs
	)

	print(
		"LOADED INSTRUMENTS:",
		character_data.unlocked_instruments
	)

	print(
		"LOADED SONGS:",
		character_data.unlocked_songs
	)

	print(
		"LOADED ITEMS:",
		character_data.collected_items
	)

	restore_loaded_state()

	is_loading_game = false

	print("GAME LOADED")


func restore_loaded_state() -> void:

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

	# -------------------------
	# RESTORE COLLECTIBLES
	# -------------------------

	print(
		"COLLECTIBLES FOUND:",
		get_tree().get_nodes_in_group(
			"collectible"
		).size()
	)

	for collectible in get_tree().get_nodes_in_group(
		"collectible"
	):

		if not is_instance_valid(collectible):
			continue

		if collectible.has_method(
			"restore_state"
		):
			collectible.restore_state()


func load_character_file() -> bool:

	if current_character_id.is_empty():
		return false

	var path := get_character_path(
		current_character_id
	)

	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		return false

	var json_text := file.get_as_text()

	file.close()

	var json := JSON.new()

	if json.parse(json_text) != OK:
		return false

	var data = json.data

	character_data.unlocked_instruments.clear()

	for instrument in data.get(
		"unlocked_instruments",
		[]
	):
		character_data.unlocked_instruments.append(
			str(instrument)
		)

	character_data.unlocked_songs.clear()

	for song in data.get(
		"unlocked_songs",
		[]
	):
		character_data.unlocked_songs.append(
			str(song)
		)

	character_data.collected_items.clear()

	for item in data.get(
		"collected_items",
		[]
	):
		character_data.collected_items.append(
			str(item)
		)

	print(
		"CHARACTER LOADED:",
		current_character_id
	)

	return true


func load_world_file() -> bool:

	if current_world_id.is_empty():
		return false

	var data := get_world_data(
		current_world_id
	)

	if data.is_empty():
		return false

	world_data.completed_quests.clear()

	for quest_id in data.get(
		"completed_quests",
		[]
	):
		world_data.completed_quests.append(
			str(quest_id)
		)

	world_data.recruited_npcs.clear()

	for npc_id in data.get(
		"recruited_npcs",
		[]
	):
		world_data.recruited_npcs.append(
			str(npc_id)
		)

	print(
		"WORLD LOADED:",
		current_world_id
	)

	return true


func save_profile() -> void:

	print("SAVE_PROFILE CALLED")

	var profile := {
		"last_world_id": current_world_id
	}

	var file := FileAccess.open(
		PROFILE_PATH,
		FileAccess.WRITE
	)

	if file == null:
		return

	file.store_string(
		JSON.stringify(
			profile,
			"\t"
		)
	)

	file.close()


func load_profile() -> void:

	if not FileAccess.file_exists(
		PROFILE_PATH
	):
		return

	var file := FileAccess.open(
		PROFILE_PATH,
		FileAccess.READ
	)

	if file == null:
		return

	var json_text := file.get_as_text()

	file.close()

	var json := JSON.new()

	if json.parse(json_text) != OK:
		return

	var data = json.data

	current_world_id = str(
		data.get(
			"last_world_id",
			""
		)
	)



func get_world_data(
	world_id: String
) -> Dictionary:

	var path := get_world_path(
		world_id
	)

	if not FileAccess.file_exists(
		path
	):
		return {}

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		return {}

	var json_text := file.get_as_text()

	file.close()

	var json := JSON.new()

	if json.parse(json_text) != OK:
		return {}

	return json.data


func set_world_last_character(
	world_id: String,
	character_id: String
) -> void:

	var data := get_world_data(
		world_id
	)

	if data.is_empty():
		return

	data["last_character_id"] = \
		character_id

	data["last_played"] = int(
		Time.get_unix_time_from_system()
	)

	var file := FileAccess.open(
		get_world_path(world_id),
		FileAccess.WRITE
	)

	if file == null:
		return

	file.store_string(
		JSON.stringify(
			data,
			"\t"
		)
	)

	file.close()

	print(
		"WORLD UPDATED:",
		world_id,
		" Character:",
		character_id
	)


func continue_game() -> bool:

	load_profile()

	if current_world_id.is_empty():
		return false

	var world_dict: Dictionary = \
		get_world_data(
			current_world_id
		)

	if world_dict.is_empty():
		return false

	current_character_id = str(
		world_dict.get(
			"last_character_id",
			""
		)
	)

	print(
		"CONTINUE GAME"
	)

	print(
		"WORLD:",
		current_world_id
	)

	print(
		"CHARACTER:",
		current_character_id
	)

	return true


func start_game(
	world_id: String,
	character_id: String
) -> bool:

	current_world_id = world_id

	current_character_id = character_id

	set_world_last_character(
		world_id,
		character_id
	)

	save_profile()

	return true


func build_character_snapshot() -> Dictionary:

	var path := get_character_path(
		current_character_id
	)

	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		return {}

	var json := JSON.new()

	if json.parse(
		file.get_as_text()
	) != OK:

		file.close()

		return {}

	var data = json.data

	file.close()

	return data


func build_world_snapshot() -> Dictionary:

	var path := get_world_path(
		current_world_id
	)

	if not FileAccess.file_exists(path):
		return {}

	var file := FileAccess.open(
		path,
		FileAccess.READ
	)

	if file == null:
		return {}

	var json := JSON.new()

	if json.parse(
		file.get_as_text()
	) != OK:

		file.close()

		return {}

	var data = json.data

	file.close()

	return data
