extends Control

@onready var exit_button = $BACK
@onready var host_button = $All/LocalMenu/Create/HOST
@onready var join_button = $All/LocalMenu/Join/JOIN
@onready var bg = $background

func _ready():
	bg.play()
	exit_button.pressed.connect(_on_exit_button_pressed)
	host_button.pressed.connect(_on_host_button_pressed)
	join_button.pressed.connect(_on_join_button_pressed)
	$All/LocalMenu/Create/OptionButton.item_selected.connect(_on_map_changed)
	$All/LocalMenu/Create/OptionButton.select(0)
	
	# Подключаем сигнал успешного подключения
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_map_changed(ind):
	if ind == 0:
		$All/LocalMenu/Create/porthost.text = "PORT: 7777"
	else:
		$All/LocalMenu/Create/porthost.text = "PORT: 9999"

func _on_host_button_pressed():
	$Sound.play()
	var port = 7777
	if $All/LocalMenu/Create/OptionButton.selected == 1:
		port = 9999
	Handler.start_server(port)
	print("Created the SERVER")
	await get_tree().create_timer(0.1).timeout
	if $All/LocalMenu/Create/OptionButton.selected == 0:
		get_tree().change_scene_to_file("res://scenes/Field.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Lake.tscn")

func _on_join_button_pressed():
	$Sound.play()
	if $All/LocalMenu/Join/ip.text:
		var ip = $All/LocalMenu/Join/ip.text
		var port = $All/LocalMenu/Join/portjoin.text.to_int()
		Handler.start_client(ip, port)
		print("Connected to the SERVER")
		# Сцена меняется автоматически по сигналу connected_to_server

# Сигнал при успешном подключении к серверу
func _on_connected_to_server():
	print("Successfully connected to server")
	var port = $All/LocalMenu/Join/portjoin.text.to_int()
	if port == 7777:
		get_tree().change_scene_to_file("res://scenes/Field.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Lake.tscn")

# Сигнал при отключении от сервера
func _on_server_disconnected():
	print("Disconnected from server")
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_exit_button_pressed():
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
