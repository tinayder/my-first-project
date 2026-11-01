extends Camera2D

@export var follow_speed: float = 5.0
var target_player: CharacterBody2D = null

func _ready():
	print("Camera is intialized")
	
	# searching for a local player
	_find_local_player()
	
	# if we didn't find him, we search him every second
	if not target_player:
		_check_for_player_timer()

func _find_local_player():
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		if player.is_multiplayer_authority():
			target_player = player
			print("Local player for the camera: ", player.name)
			global_position = player.global_position
			break

func _check_for_player_timer():
	while not target_player:
		await get_tree().create_timer(1.0).timeout
		_find_local_player()

func _process(delta: float):
	if target_player and is_instance_valid(target_player):
		# camera moves to the player
		var target_pos = target_player.global_position
		global_position = global_position.lerp(target_pos, follow_speed * delta)
		
		# to do not let the camera go behind the map
		_limit_camera_to_map()

func _limit_camera_to_map():
	var tilemap = get_parent().get_node_or_null("TileMapLayer")
	if tilemap:
		var used_rect = tilemap.get_used_rect()
		var tile_size = Vector2(64, 64)
		
		var map_rect = Rect2(
			used_rect.position * tile_size,
			used_rect.size * tile_size
		)
		
		limit_left = map_rect.position.x
		limit_top = map_rect.position.y
		limit_right = map_rect.end.x
		limit_bottom = map_rect.end.y
		
		var viewport_size = get_viewport().get_visible_rect().size / zoom
		limit_left += viewport_size.x / 2
		limit_right -= viewport_size.x / 2
		limit_top += viewport_size.y / 2
		limit_bottom -= viewport_size.y / 2
