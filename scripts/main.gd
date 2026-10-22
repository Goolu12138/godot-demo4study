extends Node2D
## 游戏循环：生成房间 -> 清怪 -> 开门 -> 下一层。玩家死亡后按 R 重开。

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const COIN_FRAMES := ["coin_anim_f0", "coin_anim_f1", "coin_anim_f2", "coin_anim_f3"]

@onready var dungeon: Dungeon = $Dungeon
@onready var actors: Node2D = $Actors
@onready var hud: GameHud = $HUD

var player: Player
var depth := 1
var coins := 0
var state := "playing"  # playing / cleared / transition / dead
var enemies_alive := 0
var _last_hp := 0


func _ready() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	actors.add_child(player)
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	_start_run()
	if "--shot" in OS.get_cmdline_user_args():
		_capture_after_delay()
	if "--demo" in OS.get_cmdline_user_args():
		_demo_shots()
	if "--diag" in OS.get_cmdline_user_args():
		_diagnose()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("menu"):
		_return_to_menu()
		return
	if state == "dead":
		if Input.is_action_just_pressed("restart"):
			_start_run()
		return
	if player == null or player.dead:
		return

	for coin in get_tree().get_nodes_in_group("coins"):
		if coin.global_position.distance_to(player.global_position) < 26.0:
			coin.remove_from_group("coins")
			coins += 1
			Meta.add_gold(1)
			hud.set_coins(coins)
			coin.queue_free()

	if Input.is_action_just_pressed("interact") and dungeon.can_open_chest(player.global_position):
		dungeon.open_chest()
		player.heal(2)
		hud.message("+2 HP", 1.0)
		for i in 3:
			_spawn_coin(dungeon.chest_position() + Vector2(randf_range(-12.0, 12.0), 0.0))

	if state == "cleared" and dungeon.at_door(player.global_position):
		_next_room()


func _start_run() -> void:
	depth = 1
	coins = 0
	state = "playing"
	hud.set_coins(coins)
	hud.hide_death()
	hud.fade_to(0.0, 0.45)
	_build_room()


func _build_room() -> void:
	_clear_actors()
	dungeon.generate(randi(), depth)
	player.reset(dungeon.spawn_point())
	_update_camera_limits()
	_spawn_enemies()
	state = "playing"
	hud.set_depth(depth)
	hud.set_enemies(enemies_alive)
	hud.message("CLEAR THE ROOM", 1.6)


func _clear_actors() -> void:
	for child in actors.get_children():
		if child == player:
			continue
		actors.remove_child(child)
		child.queue_free()


func _update_camera_limits() -> void:
	var size := dungeon.room_pixel_size()
	var camera := player.camera
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)
	camera.reset_smoothing()


func _spawn_enemies() -> void:
	var count: int = mini(4 + depth, 10)
	enemies_alive = count
	var pool: Array[String] = ["goblin", "goblin", "skelet"]
	if depth >= 2:
		pool.append_array(["skelet", "chort"])
	if depth >= 3:
		pool.append("chort")
	if depth % 4 == 0:
		pool.append("ogre")

	for i in count:
		var kind: String = pool.pick_random()
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		enemy.kind = kind
		enemy.tier = depth
		enemy.player = player
		actors.add_child(enemy)
		# 前两只保证在视野附近，剩下的散落在房间各处。
		var min_distance := 110.0 if i < 2 else 150.0
		enemy.global_position = dungeon.random_floor_point(min_distance, 2)
		enemy.died.connect(_on_enemy_died)


func _on_enemy_died(enemy: Node) -> void:
	enemies_alive -= 1
	hud.set_enemies(enemies_alive)
	_spawn_coin(enemy.global_position)
	if enemies_alive <= 0 and state == "playing":
		_room_cleared()


func _room_cleared() -> void:
	state = "cleared"
	dungeon.open_door()
	hud.message("ROOM CLEARED - FIND THE DOOR", 2.6)


func _next_room() -> void:
	state = "transition"
	hud.fade_to(1.0, 0.22)
	await get_tree().create_timer(0.28).timeout
	depth += 1
	_build_room()
	hud.fade_to(0.0, 0.3)


func _spawn_coin(at: Vector2) -> void:
	var coin := AnimatedSprite2D.new()
	coin.sprite_frames = Game.simple_frames(COIN_FRAMES, 8.0, true)
	coin.play("default")
	coin.position = at + Vector2(0.0, -10.0)
	coin.z_index = 5
	coin.add_to_group("coins")
	actors.add_child(coin)
	var base_y := coin.position.y
	var tween := coin.create_tween()
	tween.tween_property(coin, "position:y", base_y - 7.0, 0.16)
	tween.tween_property(coin, "position:y", base_y, 0.16)


func _on_health_changed(hp: int, max_hp: int) -> void:
	hud.set_health(hp, max_hp)
	if hp < _last_hp:
		hud.flash_damage()
	_last_hp = hp


func _on_player_died() -> void:
	state = "dead"
	Meta.save_data()
	hud.message("", 0.0)
	hud.set_enemies(-1)
	await get_tree().create_timer(0.75).timeout
	if state == "dead":
		hud.show_death()


func _return_to_menu() -> void:
	Meta.save_data()
	get_tree().change_scene_to_file("res://scenes/menu.tscn")


func _capture_after_delay() -> void:
	await get_tree().create_timer(1.0).timeout
	await _save_shot("shot.png")
	get_tree().quit()


func _demo_shots() -> void:
	player.invuln = 99.0
	await get_tree().create_timer(0.5).timeout
	# 走到房间上方，检查顶墙、旗帜、石柱与门的整体观感。
	player.global_position = Vector2(96.0, 52.0)
	await get_tree().create_timer(0.5).timeout
	await _save_shot("shot_room.png")

	player.global_position = dungeon.door_point() + Vector2(0, 44)
	await get_tree().create_timer(0.5).timeout
	await _save_shot("shot_door_closed.png")

	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.size() > 0:
		var target: Node2D = enemies[0]
		player.global_position = target.global_position + Vector2(-30, 0)
		player.facing = Vector2.RIGHT
		await get_tree().create_timer(0.25).timeout
		Input.action_press("attack")
		await get_tree().process_frame
		Input.action_release("attack")
		await get_tree().create_timer(0.05).timeout
		await _save_shot("shot_combat.png")

	for enemy in get_tree().get_nodes_in_group("enemies"):
		enemy.take_damage(99, Vector2.ZERO)
	await get_tree().create_timer(0.5).timeout
	player.global_position = dungeon.door_point() + Vector2(0, 44)
	await get_tree().create_timer(0.45).timeout
	await _save_shot("shot_door.png")

	player.invuln = 0.0
	player.take_damage(99, Vector2.ZERO)
	await get_tree().create_timer(1.2).timeout
	await _save_shot("shot_death.png")
	get_tree().quit()


func _save_shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := "res://screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/" + file_name
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("saved ", path, " ", image.get_size())


func _diagnose() -> void:
	await get_tree().process_frame
	print("window=", DisplayServer.window_get_size(), " viewport=", get_viewport().get_visible_rect().size,
		" content_scale=", get_window().content_scale_size, " mode=", get_window().content_scale_mode,
		" aspect=", get_window().content_scale_aspect, " cam_zoom=", player.camera.zoom)
	print("player=", player.global_position, " room=", dungeon.room_pixel_size())
	for enemy in get_tree().get_nodes_in_group("enemies"):
		print("enemy kind=", enemy.kind, " pos=", enemy.global_position, " visible=", enemy.visible,
			" frames_idle=", enemy.sprite.sprite_frames.get_frame_count("idle"))
	for child in dungeon.get_children():
		print("dungeon child ", child.name, " ", child.get_class())
	get_tree().quit()
