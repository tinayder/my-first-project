# player_camera.gd
extends Camera2D

@export var follow_speed: float = 5.0
var target_player: CharacterBody2D = null

func _ready():
	print("Камера инициализирована")
	
	# Ищем локального игрока
	_find_local_player()
	
	# Если не нашли сразу, проверяем каждую секунду
	if not target_player:
		_check_for_player_timer()

func _find_local_player():
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.is_multiplayer_authority():
			target_player = player
			print("Найден локальный игрок для камеры: ", player.name)
			global_position = player.global_position
			break

func _check_for_player_timer():
	# Проверяем каждую секунду пока не найдем игрока
	while not target_player:
		await get_tree().create_timer(1.0).timeout
		_find_local_player()

func _process(delta: float):
	if target_player and is_instance_valid(target_player):
		# Плавное следование за игроком
		var target_pos = target_player.global_position
		global_position = global_position.lerp(target_pos, follow_speed * delta)
		
		# Ограничиваем камеру пределами карты (опционально)
		_limit_camera_to_map()

func _limit_camera_to_map():
	# Если есть TileMapLayer, ограничиваем камеру
	var tilemap = get_parent().get_node_or_null("TileMapLayer")
	if tilemap:
		var used_rect = tilemap.get_used_rect()
		var tile_size = Vector2(64, 64)  # Укажи размер твоих тайлов
		
		var map_rect = Rect2(
			used_rect.position * tile_size,
			used_rect.size * tile_size
		)
		
		# Устанавливаем лимиты камеры
		limit_left = map_rect.position.x
		limit_top = map_rect.position.y
		limit_right = map_rect.end.x
		limit_bottom = map_rect.end.y
		
		# Смещаем лимиты на пол-экрана чтобы игрок не уходил к краю
		var viewport_size = get_viewport().get_visible_rect().size / zoom
		limit_left += viewport_size.x / 2
		limit_right -= viewport_size.x / 2
		limit_top += viewport_size.y / 2
		limit_bottom -= viewport_size.y / 2
