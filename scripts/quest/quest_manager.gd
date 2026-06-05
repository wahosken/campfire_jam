extends Node

@export var quests: Array[QuestData] = [
	preload("res://quests/repair_bridge.tres"),
	preload("res://quests/find_lost_bass.tres"),
	preload("res://quests/find_the_flask.tres"),
	preload("res://quests/play_fountain_song.tres")
]

var completed_quests: Array[String] = []

func complete_quest(quest_id: String) -> void:

	if quest_id.is_empty():
		return

	if completed_quests.has(quest_id):
		return

	completed_quests.append(quest_id)

	NotificationManager.show_notification("Task Complete")

	SaveManager.create_autosave()

	_activate_jamspots_for_quest(quest_id)


func is_quest_complete(quest_id: String) -> bool:

	if quest_id.is_empty():
		return true

	return completed_quests.has(quest_id)


func _activate_jamspots_for_quest(quest_id: String) -> void:

	for jamspot in get_tree().get_nodes_in_group("jam_spot"):

		if jamspot == null:
			continue

		if not is_instance_valid(jamspot):
			continue

		if not "required_quest_id" in jamspot:
			continue

			if jamspot.required_quest_id != quest_id:
				continue

		if jamspot.has_method("start_jam"):
			jamspot.start_jam()


func get_quest(quest_id: String) -> QuestData:

	for quest in quests:

		if quest == null:
			continue

		if quest.quest_id == quest_id:
			return quest

	return null


func restore_completed_quests(quest_ids: Array[String]) -> void:

	completed_quests.clear()

	for quest_id in quest_ids:

		if completed_quests.has(quest_id):
			continue

		completed_quests.append(quest_id)

		_activate_jamspots_for_quest(
			quest_id
		)

	for reaction in get_tree().get_nodes_in_group("world_reaction"):

		if reaction == null:
			continue

		if not is_instance_valid(reaction):
			continue

		if not QuestManager.is_quest_complete(reaction.quest_id):
			continue

		reaction.restore_completed_state()
