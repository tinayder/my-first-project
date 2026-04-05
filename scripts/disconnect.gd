extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Button.pressed.connect(_on_disconnected)

func _on_disconnected():
	$Sound.play()
	if !multiplayer.is_server():
		Handler.stop_multiplayer()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")
