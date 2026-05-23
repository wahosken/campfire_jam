extends Node2D

@onready var music_system: Node = $MusicSystem
@onready var player: CharacterBody2D = $player
@onready var jam_ui: Control = $CanvasLayer/UI


func _ready() -> void:
	jam_ui.setup_ui(player, music_system)


func _process(_delta: float) -> void:
	jam_ui.update_ui()
