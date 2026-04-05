extends Control

@onready var start_button = $Buttons/PLAY
@onready var settings_button = $Buttons/SETS
@onready var exit_button = $Buttons/QUIT
@onready var bg = $background

func save_text(content: String, path: String = "user://username.txt"):
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(content)
		file.close()

func _ready():
	bg.play()
	var file = FileAccess.open("user://username.txt", FileAccess.READ)
	if !file:
		save_text("Anonymus")
		file.close()
	start_button.pressed.connect(_on_start_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)

func _on_start_button_pressed():
	$Sound.play()
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_settings_button_pressed():
	$Sound.play()
	get_tree().change_scene_to_file("res://scenes/sets.tscn")

func _on_exit_button_pressed():
	print("Выходим из игры")
	get_tree().quit()
