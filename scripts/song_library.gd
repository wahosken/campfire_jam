extends Node

var songs := {
	"song_01": {
		"display_name": "Song 1",
		"bpm": 100.0,
		"beats_per_measure": 4,
		"total_measures": 8,
		"key": "Unknown"
	},
	"song_02": {
		"display_name": "Song 2",
		"bpm": 90.0,
		"beats_per_measure": 6,
		"total_measures": 8,
		"key": "Unknown"
	}
}


func get_song(song_id: String) -> Dictionary:
	if songs.has(song_id):
		return songs[song_id]

	return songs["song_01"]


func get_song_display_name(song_id: String) -> String:
	var song_data: Dictionary = get_song(song_id)

	if song_data.has("display_name"):
		return str(song_data["display_name"])

	return song_id


func get_all_song_ids() -> Array[String]:
	var ids: Array[String] = []

	for song_id in songs.keys():
		ids.append(str(song_id))

	return ids
