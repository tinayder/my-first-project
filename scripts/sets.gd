extends Control

@onready var exit_button = $BACK
@onready var save_button = $VBoxContainer/SAVE
@onready var bg = $background

func _ready():
	bg.play()
	var file = FileAccess.open("user://username.txt", FileAccess.READ)
	if file:
		$VBoxContainer/Username.text = file.get_as_text()
		file.close()
	exit_button.pressed.connect(_on_exit_button_pressed)
	save_button.pressed.connect(_on_save_button_pressed)

func _on_exit_button_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_save_button_pressed():
	var file = FileAccess.open("user://username.txt", FileAccess.WRITE)
	if file:
		file.store_string($VBoxContainer/Username.text)
		file.close()
