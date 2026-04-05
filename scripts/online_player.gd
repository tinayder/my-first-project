extends CharacterBody2D

const SPEED: float = 200.0
const MAX_HEALTH: int = 100
const MAX_AMMO: int = 10
const SNOWBALL_SCENE: PackedScene = preload("res://scenes/Snowball.tscn")
const REGEN_AMOUNT: int = 2      # Сколько ХП восстанавливать за "тик"
const REGEN_TICK_TIME: float = 1.0 # Частота восстановления (раз в секунду)
const REGEN_DELAY: float = 5.0    # Через сколько секунд после урона начнется реген

# Текстуры команд
const RED_TEXTURE = preload("res://assets/images/hat1.png")
const BLUE_TEXTURE = preload("res://assets/images/hat2.png")

# Синхронизируемые переменные
@export var health: int = MAX_HEALTH
@export var is_dead: bool = false
@export var team: int = -1
@export var nickname: String = ""

@onready var Sound = $sounds

var shoot_sound = preload("res://assets/sounds/shoot.mp3")
var ice_sound = preload("res://assets/sounds/ice.mp3")
var making_sound = preload("res://assets/sounds/making.mp3")

# Локальные переменные
var ammo: int = 10
var is_chatting: bool = false
var is_reloading: bool = false
var can_shoot: bool = true
var snowball_cooldown: float = 0.5
var spawn_red = Vector2(1568, 994)
var spawn_blue = Vector2(-1248, -994)
var Ammo = null
var regen_timer: float = 0.0
var time_since_last_hit: float = 0.0

signal died()

func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
	Ammo = get_parent().get_parent().find_child("CanvasLayer").find_child("ammo")

func _ready() -> void:
	global_position = Vector2(-9999, -9999)
	multiplayer.peer_disconnected.connect(_on_player_disconnected)
	_create_base_appearance()
	add_to_group("players")
	
	if get_parent().get_parent().name == "Lake":
		spawn_red = Vector2(-416, -160)
		spawn_blue = Vector2(1184, 1248)
	else:
		spawn_red = Vector2(1568, 994)
		spawn_blue = Vector2(-1248, -994)
	
	if multiplayer.is_server():
		await get_tree().create_timer(0.2).timeout
		_assign_team()
	else:
		_request_initial_state.rpc_id(1)

# --- СЕТЕВАЯ ЛОГИКА ---

@rpc("any_peer", "reliable")
func _request_initial_state():
	if not multiplayer.is_server(): return
	for p in get_tree().get_nodes_in_group("players"):
		if p.team != -1:
			p._force_sync_all.rpc(p.health, p.is_dead, p.team, p.nickname)

func _on_player_disconnected(id: int) -> void:
	print("Игрок отключился: ", id)
	rpc("remove_player", id)

@rpc("any_peer", "call_local", "reliable")
func _force_sync_all(s_health: int, s_is_dead: bool, s_team: int, s_nickname: String = ""):
	if multiplayer.get_remote_sender_id() != 1 and not multiplayer.is_server(): return
	health = s_health
	is_dead = s_is_dead
	team = s_team
	if s_nickname != "": nickname = s_nickname # Применяем имя
	_update_visuals()

func _assign_team() -> void:
	var players = get_tree().get_nodes_in_group("players")
	var red = 0
	var blue = 0
	for p in players:
		if p != self and p.team != -1:
			if p.team == 0: red += 1
			elif p.team == 1: blue += 1
	team = 0 if red <= blue else 1
	var spawn_pos = spawn_red if team == 0 else spawn_blue
	
	# Синхронизируем команду и телепортируем игрока на его базу
	_force_sync_all.rpc(health, is_dead, team, nickname)
	_teleport.rpc(spawn_pos)

# --- УПРАВЛЕНИЕ ---

func _physics_process(_delta: float) -> void:
	_update_visuals()
	
	if not is_multiplayer_authority() or is_dead: return
	
	if is_reloading or is_chatting:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if direction == Vector2.ZERO:
		var x = int(Input.is_key_pressed(KEY_D)) - int(Input.is_key_pressed(KEY_A))
		var y = int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W))
		direction = Vector2(x, y).normalized()

	velocity = direction * SPEED
	move_and_slide()

	# Поворот за мышкой (Flip)
	$Sprite.look_at(get_global_mouse_position())
	$Sprite.rotation += PI/2

	if Input.is_key_pressed(KEY_E) and ammo < MAX_AMMO:
		_try_collect_snow()
	
	if Input.is_action_just_pressed("mouse_left") and can_shoot and ammo > 0:
		var dir = (get_global_mouse_position() - global_position).normalized()
		ammo -= 1
		Ammo.text = str(ammo) + "/10"
		_spawn_snowball.rpc(dir)
		_start_cooldown()
	
	_check_surface_collision()
	
	if multiplayer.is_server() and not is_dead and health < MAX_HEALTH:
		time_since_last_hit += _delta
		
		# Если прошло достаточно времени без урона
		if time_since_last_hit >= REGEN_DELAY:
			regen_timer += _delta
			if regen_timer >= REGEN_TICK_TIME:
				regen_timer = 0.0
				health = min(health + REGEN_AMOUNT, MAX_HEALTH)
				# Синхронизируем здоровье со всеми
				_force_sync_all.rpc(health, is_dead, team, nickname)

# --- ЛОГИКА ПОВЕРХНОСТЕЙ ---

func _check_surface_collision():
	var field = get_parent().get_parent()
	var ice_layer = field.get_node_or_null("ice")
	if not ice_layer: return
	
	var map_pos = ice_layer.local_to_map(ice_layer.to_local(global_position))
	var ice_tile_id = ice_layer.get_cell_source_id(map_pos)
	
	# Проверяем, наступили ли на лед ИЛИ на воду
	var water_layer = field.get_node_or_null("water")
	var on_water = water_layer and water_layer.get_cell_source_id(map_pos) != -1
	
	if ice_tile_id != -1 or on_water: 
		# Если мы на льду/воде — просим СЕРВЕР убить нас
		if multiplayer.is_server():
			# Если мы и есть сервер — просто ломаем и умираем
			if ice_tile_id != -1: _break_ice.rpc(map_pos)
			take_damage(999, -2)
		else:
			# Если мы клиент — отправляем RPC запрос на сервер
			_request_environment_death.rpc_id(1, map_pos if ice_tile_id != -1 else Vector2i(-1,-1))

# Новый RPC метод для смерти от окружения
@rpc("any_peer", "reliable")
func _request_environment_death(map_pos: Vector2i):
	if not multiplayer.is_server(): return
	
	# Если была передана позиция льда — ломаем его для всех
	if map_pos != Vector2i(-1, -1):
		_break_ice.rpc(map_pos)
	
	# Наносим смертельный урон (сервер имеет право это делать)
	take_damage(999, -2)

@rpc("any_peer", "call_local", "reliable")
func _break_ice(map_pos: Vector2i):
	var field = get_parent().get_parent()
	var ice_layer = field.get_node_or_null("ice")
	if not ice_layer: return
	var s_id = ice_layer.get_cell_source_id(map_pos)
	var a_coords = ice_layer.get_cell_atlas_coords(map_pos)
	var alt_tile = ice_layer.get_cell_alternative_tile(map_pos)
	ice_layer.set_cell(map_pos, -1)
	Sound.stream = ice_sound
	Sound.play()
	if multiplayer.is_server():
		_start_ice_recovery_timer(map_pos, s_id, a_coords, alt_tile)

func _start_ice_recovery_timer(map_pos, s_id, a_coords, alt_tile):
	await get_tree().create_timer(5.0).timeout
	_restore_ice.rpc(map_pos, s_id, a_coords, alt_tile)

@rpc("authority", "call_local", "reliable")
func _restore_ice(map_pos: Vector2i, s_id: int, a_coords: Vector2i, alt_tile: int):
	var field = get_parent().get_parent()
	var ice_layer = field.get_node_or_null("ice")
	if ice_layer: ice_layer.set_cell(map_pos, s_id, a_coords, alt_tile)

# --- СНЕГ И СТРЕЛЬБА ---

func _try_collect_snow():
	var hills = get_parent().get_parent().get_node_or_null("hills")
	if not hills or is_reloading: return
	var local_pos = hills.to_local(global_position)
	var map_pos = hills.local_to_map(local_pos)
	var found_snow = false
	for x in range(-1, 2):
		for y in range(-1, 2):
			if hills.get_cell_tile_data(map_pos + Vector2i(x, y)):
				found_snow = true; break
		if found_snow: break
	if found_snow: _do_reload_snow_local()

func _do_reload_snow_local():
	is_reloading = true
	Sound.stream = making_sound
	Sound.play()
	await get_tree().create_timer(1).timeout
	if not is_dead and is_multiplayer_authority():
		ammo = min(ammo + 1, MAX_AMMO)
		Ammo.text = str(ammo) + "/10"
	is_reloading = false

@rpc("any_peer", "call_local", "reliable")
func _spawn_snowball(dir: Vector2):
	var sb = SNOWBALL_SCENE.instantiate()
	sb.global_position = global_position + dir * 35
	sb.direction = dir
	sb.shooter_id = name.to_int()
	sb.shooter_team = team
	get_parent().add_child(sb)
	Sound.stream = shoot_sound
	Sound.play()

func _start_cooldown():
	can_shoot = false
	await get_tree().create_timer(snowball_cooldown).timeout
	can_shoot = true

# --- УРОН И СМЕРТЬ ---

func take_damage(amount: int, attacker_team: int):
	if not multiplayer.is_server() or is_dead: return
	if attacker_team == team: return 
	
	time_since_last_hit = 0.0 # Сбрасываем таймер покоя при получении урона
	
	health -= amount
	if health <= 0:
		health = 0
		_die()
	else:
		_force_sync_all.rpc(health, is_dead, team, nickname)

func _die():
	is_dead = true
	is_reloading = false
	_force_sync_all.rpc(health, is_dead, team, nickname)
	_sync_collision.rpc(true)
	await get_tree().create_timer(3.0).timeout
	_respawn()

func _respawn():
	var spawn_pos = spawn_red if team == 0 else spawn_blue
	health = MAX_HEALTH
	is_dead = false
	Ammo.text = "10/10"
	_force_sync_all.rpc(health, is_dead, team, nickname)
	_sync_collision.rpc(false)
	_teleport.rpc(spawn_pos)

@rpc("any_peer", "call_local", "reliable")
func _teleport(pos: Vector2):
	global_position = pos
	velocity = Vector2.ZERO
	if is_multiplayer_authority(): ammo = 10

@rpc("any_peer", "call_local", "reliable")
func remove_player(id: int):
	var container = get_parent()
	var player_node = container.get_node_or_null(str(id))
	if player_node:
		player_node.queue_free()
		print("Игрок ", id, " удален локально через RPC")

@rpc("any_peer", "call_local", "reliable")
func _sync_collision(disabled: bool):
	if has_node("CollisionShape2D"): $CollisionShape2D.disabled = disabled
	if disabled: died.emit()

# --- ЧАТ ---

func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or is_dead: return
	if event is InputEventKey and event.pressed and not event.is_echo():
		# Реагируем ТОЛЬКО на Enter или Numpad Enter
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if not is_chatting:
				_start_chatting()
			else:
				# Если мы уже в чате, нажатие Enter отправляет текст
				_stop_chatting_and_send()
		
		if event.is_action_pressed("ui_cancel") and is_chatting: # ESC по умолчанию
			_cancel_chatting()

func _cancel_chatting():
	var chat_input = get_parent().get_parent().find_child("CanvasLayer").find_child("ChatInput", true, false)
	if chat_input:
		chat_input.text = ""
		chat_input.hide()
		chat_input.release_focus()
	is_chatting = false

func _start_chatting():
	var chat_input = get_parent().get_parent().find_child("CanvasLayer").find_child("ChatInput", true, false)
	if chat_input:
		is_chatting = true
		chat_input.show()
		
		# Делаем LineEdit доступным для фокуса
		chat_input.focus_mode = Control.FOCUS_ALL 
		
		# Вызываем захват фокуса в конце текущего кадра (это решает 99% проблем)
		chat_input.call_deferred("grab_focus")
		
		# Очищаем поле от случайного "Enter", который мог туда попасть
		chat_input.text = ""

func _stop_chatting_and_send():
	var chat_input = get_parent().get_parent().find_child("CanvasLayer").find_child("ChatInput", true, false)
	if chat_input:
		var text = chat_input.text.strip_edges()
		if text != "":
			send_bubble_text.rpc(text)
		
		chat_input.text = ""
		chat_input.hide()
		# Отдаем фокус обратно «в никуда», чтобы клавиши снова считывались игроком
		chat_input.release_focus() 
	
	is_chatting = false

# Функция отображения текста над головой (на всех клиентах)
@rpc("any_peer", "call_local", "reliable")
func send_bubble_text(message: String):
	var label = get_node_or_null("ChatLabel")
	if label:
		label.text = message
		label.show()
		await get_tree().create_timer(4.0).timeout
		if label.text == message:
			label.hide()

# --- ВИЗУАЛ ---

func _update_visuals():
	var hb = get_node_or_null("HealthBar")
	var name_label = get_node_or_null("NameLabel")
	var sprite = get_node_or_null("Sprite")
	
	if hb: hb.value = health
	
	if is_multiplayer_authority():
		var status = " [ЛЕПКА...]" if is_reloading else ""
		DisplayServer.window_set_title("Снежки: " + str(ammo) + "/10" + status)
	
	if not sprite: return
	
	if is_dead:
		sprite.modulate = Color.GRAY
		if name_label: name_label.hide()
	else:
		sprite.modulate = Color.WHITE
		if name_label: 
			name_label.show()
			name_label.text = nickname # Чтобы текст всегда соответствовал переменной
		
		# Установка скина и цвета ника по команде
		if team == 0:
			sprite.texture = RED_TEXTURE
			if name_label: name_label.modulate = Color(1, 0.3, 0.3)
		elif team == 1:
			sprite.texture = BLUE_TEXTURE
			if name_label: name_label.modulate = Color(0.3, 0.6, 1)

func _create_base_appearance():
	if not has_node("Sprite"):
		var sprite = Sprite2D.new()
		sprite.name = "Sprite"
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST 
		add_child(sprite)
	
	if not has_node("NameLabel"):
		var nl = Label.new()
		nl.name = "NameLabel"
		add_child(nl)
		_load_name(nl)

	if not has_node("HealthBar"):
		var hb = ProgressBar.new()
		hb.name = "HealthBar"
		hb.show_percentage = false
		hb.add_theme_font_size_override("font_size", 1) 
		hb.add_theme_constant_override("outline_size", 0)
		hb.custom_minimum_size = Vector2(40, 4) 
		hb.size = hb.custom_minimum_size
		hb.position = Vector2(-20, -40)
		hb.max_value = MAX_HEALTH
		hb.value = health
		var bg = StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.6); bg.anti_aliasing = false
		hb.add_theme_stylebox_override("background", bg)
		var fill = StyleBoxFlat.new(); fill.bg_color = Color(0.2, 0.9, 0.3); fill.anti_aliasing = false
		hb.add_theme_stylebox_override("fill", fill)
		add_child(hb)

func _load_name(nl):
	# Только владелец персонажа читает свой файл
	if is_multiplayer_authority():
		var file = FileAccess.open("user://username.txt", FileAccess.READ)
		if file:
			nickname = file.get_as_text().strip_edges()
		else:
			nickname = "Player_" + str(multiplayer.get_unique_id())
		
		# Отправляем свое имя серверу, чтобы он разослал остальным
		_sync_nickname.rpc(nickname)
	
	# Настройка внешнего вида Label
	nl.text = nickname
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var custom_font = load("res://assets/fonts/8bitoperator_jve.ttf")
	if custom_font: nl.add_theme_font_override("font", custom_font)
	nl.add_theme_font_size_override("font_size", 18)
	nl.custom_minimum_size = Vector2(100, 20)
	nl.position = Vector2(-50, -65)

# Этот метод обновит имя у всех игроков
@rpc("any_peer", "call_local", "reliable")
func _sync_nickname(new_name: String):
	nickname = new_name
	if has_node("NameLabel"):
		$NameLabel.text = new_name
