extends Node
class_name NPCDialogueController

@export var dialogue_data: NPCDialogueData

@export var progression_state := NPCProgressionState.INTRO

const EVENT_RECRUITMENT := "recruitment"

enum NPCProgressionState {
	INTRO,
	TASK_GIVEN,
	TASK_COMPLETE,
	RECRUITED
}

var pending_dialogue_events: Array[String] = []


func get_npc() -> Node:
	return get_parent()


func initialize(start_locked: bool) -> void:

	if start_locked:
		progression_state = NPCProgressionState.INTRO
	else:
		progression_state = NPCProgressionState.RECRUITED


func get_current_dialogue() -> DialogueSequence:

	if dialogue_data == null:
		return null

	# One-time dialogue events take priority.
	if has_pending_dialogue_events():

		var event_id := pop_next_dialogue_event()

		match event_id:

			EVENT_RECRUITMENT:
				return dialogue_data.recruited_dialogue

			_:
				pass

	match progression_state:

		NPCProgressionState.INTRO:
			return dialogue_data.intro_dialogue

		NPCProgressionState.TASK_GIVEN:
			return dialogue_data.task_dialogue

		NPCProgressionState.TASK_COMPLETE:
			return dialogue_data.completion_dialogue

		NPCProgressionState.RECRUITED:
			return dialogue_data.recruited_dialogue

		_:
			return dialogue_data.intro_dialogue


func queue_dialogue_event(event_id: String) -> void:

	if event_id.is_empty():
		return

	pending_dialogue_events.push_back(event_id)


func has_pending_dialogue_events() -> bool:
	return pending_dialogue_events.size() > 0


func pop_next_dialogue_event() -> String:

	if pending_dialogue_events.is_empty():
		return ""

	return pending_dialogue_events.pop_front()


func begin_task() -> void:

	set_progression_state(
		NPCProgressionState.TASK_GIVEN
	)


func complete_task() -> void:

	set_progression_state(
		NPCProgressionState.TASK_COMPLETE
	)


func recruit() -> void:
	set_progression_state(
		NPCProgressionState.RECRUITED
	)


func unlock_npc() -> void:

	progression_state = NPCProgressionState.RECRUITED

	queue_dialogue_event(EVENT_RECRUITMENT)

	var npc := get_npc()

	if npc != null:
		if npc.has_method("enable_interaction"):
			npc.enable_interaction()

		if npc.has_method("_update_label"):
			npc._update_label()


func lock_npc() -> void:

	progression_state = NPCProgressionState.INTRO

	var npc := get_npc()

	if npc != null:

		if npc.has_method("stop_following_player"):
			npc.stop_following_player()

		if npc.has_method("stop_freeform_immediately"):
			npc.stop_freeform_immediately()

		if npc.has_method("_update_label"):
			npc._update_label()


func is_locked() -> bool:
	return progression_state == NPCProgressionState.INTRO


func is_recruited() -> bool:
	return progression_state == NPCProgressionState.RECRUITED


func restore_recruited_state() -> void:

	progression_state = NPCProgressionState.RECRUITED

	pending_dialogue_events.clear()

	var npc := get_npc()

	if npc != null:

		if npc.has_method("_update_label"):
			npc._update_label()


func set_progression_state(new_state: NPCProgressionState) -> void:

	if progression_state == new_state:
		return

	progression_state = new_state

	var npc := get_npc()

	if npc != null:
		if npc.has_method("_update_label"):
			npc._update_label()
