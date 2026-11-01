extends StaticBody2D

@export var red_texture: Texture2D = preload("res://assets/images/base1.png")
@export var blue_texture: Texture2D = preload("res://assets/images/base2.png")
@export var team: int = 0 # 0 is red, 1 is blue
@export var health: int = 500
var max_health: int = 500

@onready var sprite = $Sprite2D
@onready var Winner = get_parent().find_child("CanvasLayer").find_child("Winner")

func _ready():
	Winner.text = ""
	add_to_group("igloos")
	_update_style()
	$HealthBar.max_value = max_health
	$HealthBar.value = health
	
	# if client, asking for hp of the igloo
	if not multiplayer.is_server():
		_request_initial_hp.rpc_id(1)

# request for current hp
@rpc("any_peer", "reliable")
func _request_initial_hp():
	if multiplayer.is_server():
		# sending 
		_sync_hp.rpc_id(multiplayer.get_remote_sender_id(), health)

# syncing
@rpc("authority", "call_local", "reliable")
func _sync_hp(new_hp: int):
	health = new_hp
	if $HealthBar:
		$HealthBar.value = health
	_check_destruction()

func take_damage(amount: int, attacker_team: int):
	if not multiplayer.is_server() or health <= 0: return
	if attacker_team == team: return 
	
	health -= amount
	_sync_hp.rpc(health)

func _check_destruction():
	if health <= 0:
		modulate.a = 0.3
		process_mode = PROCESS_MODE_DISABLED
		if team == 0:
			Winner.text = "BLUE TEAM WINS!"
			Winner.modulate = Color.BLUE
		else:
			Winner.text = "RED TEAM WINS!"
			Winner.modulate = Color.RED
		
func _update_style():
	if team == 0:
		sprite.texture = red_texture
	else:
		sprite.texture = blue_texture

	if health <= 0:
		modulate.a = 0.3
	if not has_node("HealthBar"):
		var hb = ProgressBar.new()
		hb.name = "HealthBar"
		hb.show_percentage = false
		hb.add_theme_font_size_override("font_size", 1) 
		hb.add_theme_constant_override("outline_size", 0)
		hb.custom_minimum_size = Vector2(40, 4) 
		hb.size = hb.custom_minimum_size
		hb.position = Vector2(-20, -40)
		hb.max_value = max_health
		hb.value = health

		var bg = StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.6)
		bg.anti_aliasing = false
		hb.add_theme_stylebox_override("background", bg)
		
		var fill = StyleBoxFlat.new()
		fill.bg_color = Color(0.2, 0.9, 0.3)
		fill.anti_aliasing = false
		hb.add_theme_stylebox_override("fill", fill)
		
		add_child(hb)
