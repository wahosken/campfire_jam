extends Node2D

@onready var music_system: Node = $MusicSystem
@onready var player: CharacterBody2D = $player
@onready var jam_ui: Control = $CanvasLayer/UI

@onready var start_gate: CanvasLayer = $StartGate
@onready var jam_manager: Node = $JamManager


func _ready() -> void:
	jam_ui.setup_ui(player, music_system)
	start_gate.game_started.connect(_on_game_started)


func _process(_delta: float) -> void:
	jam_ui.update_ui()



func _on_game_started() -> void:
	print("Game officially started.")

	if jam_manager != null and jam_manager.has_method("on_game_started"):
		jam_manager.on_game_started()

	for jam_spot in get_tree().get_nodes_in_group("jam_spot"):
		if jam_spot.has_method("on_game_started"):
			jam_spot.on_game_started()
