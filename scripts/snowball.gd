extends Area2D

var speed: float = 600.0
var direction: Vector2 = Vector2.RIGHT
var damage: int = 30
var lifetime: float = 0.75
var shooter_id: int = -1
var shooter_team: int = -1 # Важно: получаем от игрока при спавне

func _ready() -> void:
	# Удаление через время
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
	
	# Подключаем сигнал столкновения
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta

func _on_body_entered(body: Node) -> void:
	if body.name == str(shooter_id): return
	$Sound.play()
	# Попадание в игрока ИЛИ в Иглу
	if body.has_method("take_damage"):
		if body.is_in_group("players") and body.team == shooter_team:
			visible = false # Скрываем объект (например, пулю)
			set_deferred("monitoring", false) # Отключаем коллизии, чтобы не срабатывало повторно
			await $Sound.finished
			queue_free()
			return
			
		# Просим сервер нанести урон
		if shooter_id == multiplayer.get_unique_id():
			_request_damage.rpc_id(1, body.get_path(), damage, shooter_team)
		visible = false # Скрываем объект (например, пулю)
		set_deferred("monitoring", false) # Отключаем коллизии, чтобы не срабатывало повторно
		await $Sound.finished
		queue_free()
		return
	visible = false # Скрываем объект (например, пулю)
	set_deferred("monitoring", false) # Отключаем коллизии, чтобы не срабатывало повторно
	await $Sound.finished
	queue_free()

@rpc("any_peer", "call_local", "reliable")
func _request_damage(target_path: NodePath, dmg: int, s_team: int):
	if not multiplayer.is_server(): return
	var target = get_node_or_null(target_path)
	if target and target.has_method("take_damage"):
		target.take_damage(dmg, s_team)
