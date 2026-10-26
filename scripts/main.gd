extends Node2D
## 搜打撤循环：进图 -> 搜索容器 / 清场 -> 限时内从撤离点离开 -> 回休息处。
##
## 规则：
##   - 贵重品只记估值，装备先放进 6 格背包，两者都要成功撤离才结算；
##   - 清场后撤离点（顶墙的门）开启，走进去结算；
##   - 死亡 / 倒计时归零 / 主动放弃：背包清空，身上的武器与护甲一起丢失；
##   - 撤离或死亡后自动回到休息处，仓库在那边。

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

## 一局的时间预算，超时视为死亡。
const RUN_TIME := 150.0

## 背包只装装备，格子满了必须丢一件才能捡新的。
const BAG_SIZE := 6

## 贵重品：直接折算成撤离时的金币。
const VALUE_TABLE := [
	{"id": "coins", "value": 5, "tex": "coin_anim_f0", "weight": 50},
	{"id": "potion", "value": 15, "tex": "flask_big_red", "weight": 28},
	{"id": "relic", "value": 30, "tex": "flask_big_blue", "weight": 15},
	{"id": "idol", "value": 60, "tex": "skull", "weight": 7},
]

## 装备掉落：越深的 RAID 越容易掉高阶货。
const GEAR_TABLE := [
	{"kind": "weapon", "id": "knight_sword", "weight": 32},
	{"kind": "armor", "id": "leather", "weight": 28},
	{"kind": "weapon", "id": "katana", "weight": 18},
	{"kind": "armor", "id": "chain", "weight": 14},
	{"kind": "weapon", "id": "golden_sword", "weight": 4},
	{"kind": "armor", "id": "plate", "weight": 4},
]

@onready var dungeon: Dungeon = $Dungeon
@onready var actors: Node2D = $Actors
@onready var hud: GameHud = $HUD

var player: Player
var raid := 1
var loot_value := 0
var loot_count := 0
## 背包内容：[{kind, id, name, tex, bonus, bonus_text}]
var bag: Array[Dictionary] = []
var bag_open := false
var time_left := RUN_TIME
## playing / cleared / extracting / dead / ended
var state := "playing"
var enemies_alive := 0
## 测试与截图模式可以关掉自动回城。
var auto_return := true

var _last_hp := 0
var _hint := ""
var _full_warn := 0.0


func _ready() -> void:
	player = PLAYER_SCENE.instantiate() as Player
	actors.add_child(player)
	player.health_changed.connect(_on_health_changed)
	player.died.connect(_on_player_died)
	hud.bag_drop.connect(drop_bag_item)
	_start_run()
	if "--shot" in OS.get_cmdline_user_args():
		_capture_after_delay()
	if "--demo" in OS.get_cmdline_user_args():
		_demo_shots()
	if "--diag" in OS.get_cmdline_user_args():
		_diagnose()


func _process(delta: float) -> void:
	_full_warn = maxf(0.0, _full_warn - delta)
	if Input.is_action_just_pressed("menu"):
		_return_to_menu()
		return
	if state == "dead" or state == "ended":
		if Input.is_action_just_pressed("restart"):
			_start_run()
		return
	if state == "extracting":
		return
	if player == null or player.dead:
		return

	if Input.is_action_just_pressed("bag") and (state == "playing" or state == "cleared"):
		_toggle_bag()
		return
	if bag_open:
		# 背包开着时玩家不能动，但倒计时继续走。
		_tick_timer(delta)
		return

	if state == "playing" or state == "cleared":
		_tick_timer(delta)
		if state == "dead":
			return

	for loot in get_tree().get_nodes_in_group("loot"):
		if loot.global_position.distance_to(player.global_position) < 26.0:
			var item: Dictionary = loot.get_meta("item", {})
			if item.is_empty():
				continue
			if not _collect_item(item):
				if _full_warn <= 0.0:
					hud.message("BAG FULL — TAB TO DROP SOMETHING", 1.4)
					_full_warn = 1.6
				continue
			loot.remove_from_group("loot")
			loot.queue_free()

	var can_search := dungeon.can_search(player.global_position)
	if can_search and Input.is_action_just_pressed("interact"):
		_search()

	if state == "cleared" and dungeon.at_door(player.global_position):
		_extract()
		return

	if state == "extracting":
		_set_hint("EXTRACTING…")
	elif state == "cleared":
		_set_hint("EXIT OPEN — WALK INTO THE DOOR TO EXTRACT")
	elif can_search:
		_set_hint("E — SEARCH")
	else:
		_set_hint("WASD MOVE   SPACE ATTACK   SHIFT DASH   E SEARCH   TAB BAG   ESC ABANDON")


func _tick_timer(delta: float) -> void:
	time_left = maxf(0.0, time_left - delta)
	hud.set_timer(time_left)
	if time_left <= 0.0:
		_fail("TIME UP")


func _start_run() -> void:
	raid = Meta.raids + 1
	loot_value = 0
	loot_count = 0
	bag.clear()
	bag_open = false
	time_left = RUN_TIME
	state = "playing"
	player.control_enabled = true
	hud.close_bag()
	hud.hide_end()
	hud.set_loot(loot_count, loot_value)
	hud.set_bag(0, BAG_SIZE)
	hud.set_timer(time_left)
	hud.set_coins(Meta.gold)
	hud.fade_to(0.0, 0.45)
	_build_room()


func _build_room() -> void:
	_clear_actors()
	dungeon.generate(randi(), raid)
	player.reset(dungeon.spawn_point())
	_update_camera_limits()
	_spawn_enemies()
	state = "playing"
	hud.set_raid(raid)
	hud.set_enemies(enemies_alive)
	hud.message("SEARCH · FIGHT · EXTRACT", 2.0)
	_set_hint("WASD MOVE   SPACE ATTACK   SHIFT DASH   E SEARCH   TAB BAG   ESC ABANDON")


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
	var count: int = mini(4 + raid, 10)
	enemies_alive = count
	var pool: Array[String] = ["goblin", "goblin", "skelet"]
	if raid >= 2:
		pool.append_array(["skelet", "chort"])
	if raid >= 3:
		pool.append("chort")
	if raid % 3 == 0:
		pool.append("ogre")

	for i in count:
		var kind: String = pool.pick_random()
		var enemy := ENEMY_SCENE.instantiate() as Enemy
		enemy.kind = kind
		enemy.tier = raid
		enemy.player = player
		actors.add_child(enemy)
		# 前两只保证在视野附近，剩下的散落在房间各处。
		var min_distance := 110.0 if i < 2 else 150.0
		enemy.global_position = dungeon.random_floor_point(min_distance, 2)
		enemy.died.connect(_on_enemy_died)


func _on_enemy_died(enemy: Node) -> void:
	enemies_alive -= 1
	hud.set_enemies(enemies_alive)
	var roll := randf()
	if roll < 0.55:
		_spawn_item(enemy.global_position, _roll_valuable())
	elif roll < 0.84:
		_spawn_item(enemy.global_position, _roll_gear())
	if enemies_alive <= 0 and state == "playing":
		_room_cleared()


func _room_cleared() -> void:
	state = "cleared"
	dungeon.open_door()
	hud.message("AREA CLEAR — REACH THE EXIT", 2.6)


# ---------------------------------------------------------------- 搜索 / 战利品

func _search() -> void:
	var result := dungeon.search(player.global_position)
	if not bool(result.found):
		return
	var gold_gain := 0
	var gear_gain := 0
	var dropped := 0
	var at: Vector2 = result.pos
	for i in int(result.rolls):
		var item := _roll_loot_item()
		if item.kind == "valuable":
			gold_gain += int(item.value)
			_stow(item, at)
		elif _stow(item, at):
			gear_gain += 1
		else:
			dropped += 1
	var parts: Array[String] = []
	if gold_gain > 0:
		parts.append("+%d G" % gold_gain)
	if gear_gain > 0:
		parts.append("+%d GEAR" % gear_gain)
	if dropped > 0:
		parts.append("%d ON FLOOR (BAG FULL)" % dropped)
	if parts.is_empty():
		parts.append("EMPTY")
	hud.message("   ·   ".join(PackedStringArray(parts)), 1.4)


## 贵重品直接入账；装备优先放背包，放不下就掉在脚边。
func _stow(item: Dictionary, at: Vector2) -> bool:
	if item.kind == "valuable":
		loot_value += int(item.value)
		loot_count += 1
		hud.set_loot(loot_count, loot_value)
		hud.pulse_loot()
		return true
	if bag.size() < BAG_SIZE:
		bag.append(item)
		hud.set_bag(bag.size(), BAG_SIZE)
		hud.pulse_loot()
		return true
	_spawn_item(at + Vector2(randf_range(-16.0, 16.0), 4.0), item)
	return false


func _collect_item(item: Dictionary) -> bool:
	if item.kind == "valuable":
		loot_value += int(item.value)
		loot_count += 1
		hud.set_loot(loot_count, loot_value)
		hud.pulse_loot()
		return true
	if bag.size() >= BAG_SIZE:
		return false
	bag.append(item)
	hud.set_bag(bag.size(), BAG_SIZE)
	hud.pulse_loot()
	return true


func _spawn_item(at: Vector2, item: Dictionary) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = Game.tex(str(item.tex))
	sprite.position = at + Vector2(randf_range(-10.0, 10.0), -10.0)
	sprite.z_index = 5
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.set_meta("item", item)
	sprite.add_to_group("loot")
	actors.add_child(sprite)
	var base_y := sprite.position.y
	var tween := sprite.create_tween().set_loops()
	tween.tween_property(sprite, "position:y", base_y - 4.0, 0.45)
	tween.tween_property(sprite, "position:y", base_y, 0.45)


func _roll_loot_item() -> Dictionary:
	if randf() < 0.58:
		return _roll_valuable()
	return _roll_gear()


func _roll_valuable() -> Dictionary:
	var total := 0
	for entry in VALUE_TABLE:
		total += int(entry.weight)
	var roll := randi_range(1, total)
	for entry in VALUE_TABLE:
		roll -= int(entry.weight)
		if roll <= 0:
			return {
				"kind": "valuable",
				"id": str(entry.id),
				"name": str(entry.id).to_upper(),
				"value": int(entry.value),
				"tex": str(entry.tex),
			}
	return {"kind": "valuable", "id": "coins", "name": "COINS", "value": 5, "tex": "coin_anim_f0"}


func _roll_gear() -> Dictionary:
	var weights: Array[int] = []
	var total := 0
	for entry in GEAR_TABLE:
		var weight := int(entry.weight)
		# 高阶装备随 RAID 提升出现率。
		if Meta.gear_bonus(str(entry.kind), str(entry.id)) >= 2:
			weight += (raid - 1) * 4
		weights.append(weight)
		total += weight
	var roll := randi_range(1, total)
	for i in GEAR_TABLE.size():
		roll -= weights[i]
		if roll <= 0:
			return _make_gear_item(str(GEAR_TABLE[i].kind), str(GEAR_TABLE[i].id))
	return _make_gear_item("weapon", "knight_sword")


func _make_gear_item(kind: String, id: String) -> Dictionary:
	var bonus := Meta.gear_bonus(kind, id)
	return {
		"kind": kind,
		"id": id,
		"name": Meta.gear_title(kind, id),
		"tex": Meta.gear_texture(kind, id),
		"bonus": bonus,
		"bonus_text": "+%d %s" % [bonus, "DMG" if kind == "weapon" else "HP"],
	}


# ---------------------------------------------------------------- 背包

## 测试与事件用的入口：放得下就进背包。
func add_gear_to_bag(kind: String, id: String) -> bool:
	if bag.size() >= BAG_SIZE:
		return false
	bag.append(_make_gear_item(kind, id))
	hud.set_bag(bag.size(), BAG_SIZE)
	hud.pulse_loot()
	return true


func drop_bag_item(index: int) -> void:
	if index < 0 or index >= bag.size():
		return
	var item := bag[index]
	bag.remove_at(index)
	hud.set_bag(bag.size(), BAG_SIZE)
	hud.open_bag(bag)
	hud.message("DROPPED %s" % str(item.name), 1.0)


func _toggle_bag() -> void:
	bag_open = not bag_open
	player.control_enabled = not bag_open
	if bag_open:
		hud.open_bag(bag)
	else:
		hud.close_bag()


# ---------------------------------------------------------------- 撤离 / 失败

func _extract() -> void:
	if state != "cleared":
		return
	state = "extracting"
	if bag_open:
		bag_open = false
		hud.close_bag()
	player.control_enabled = false
	_set_hint("")
	var gained := loot_value
	var gear: Array = bag.duplicate()
	var stored := bag.size()
	var punished := _penalties_enabled()
	if punished:
		Meta.finish_extraction(gained, gear)
		bag.clear()
		hud.set_bag(0, BAG_SIZE)
		hud.set_loot(0, 0)
	hud.set_coins(Meta.gold)
	hud.fade_to(0.55, 0.25)
	await get_tree().create_timer(0.35).timeout
	if state != "extracting":
		return
	hud.message("EXTRACTED  +%d G" % gained, 2.0)
	var tail := "RETURNING TO CAMP…" if punished else "ESC CAMP"
	hud.show_end("EXTRACTED",
		"+%d G   ·   %d GEAR STORED\n%s" % [gained, stored, tail],
		Color("#8fd18a"))
	hud.fade_to(0.0, 0.4)
	state = "ended"
	if auto_return and punished:
		await get_tree().create_timer(2.0).timeout
		if state == "ended":
			get_tree().change_scene_to_file("res://scenes/hub.tscn")


func _fail(reason: String) -> void:
	if state == "dead" or state == "ended" or state == "extracting":
		return
	state = "dead"
	if bag_open:
		bag_open = false
		hud.close_bag()
	player.control_enabled = false
	var lost := loot_value
	var lost_gear := bag.size()
	var punished := _penalties_enabled()
	if punished:
		Meta.lose_gear()
		bag.clear()
		hud.set_bag(0, BAG_SIZE)
		Meta.record_result("%s   ·   %d G LOST   ·   %d GEAR LOST" % [reason, lost, lost_gear])
	hud.message("", 0.0)
	hud.set_enemies(-1)
	hud.set_timer(0.0)
	_set_hint("")
	var subtitle: String
	if punished:
		subtitle = "%d G LOST   ·   %d GEAR LOST   ·   EQUIPMENT LOST\nRETURNING TO CAMP…" % [lost, lost_gear]
	else:
		subtitle = "%d G   ·   %d GEAR   ·   DEMO — NO PENALTIES\nR RETRY      ESC CAMP" % [lost, lost_gear]
	await get_tree().create_timer(0.6).timeout
	if state != "dead":
		return
	hud.show_end(reason, subtitle, Color("#e0453c"))
	if auto_return and punished:
		await get_tree().create_timer(2.0).timeout
		if state == "dead":
			get_tree().change_scene_to_file("res://scenes/hub.tscn")


func _penalties_enabled() -> bool:
	var args := OS.get_cmdline_user_args()
	for flag in ["--demo", "--shot", "--diag"]:
		if flag in args:
			return false
	return true


func _on_health_changed(hp: int, max_hp: int) -> void:
	hud.set_health(hp, max_hp)
	if hp < _last_hp:
		hud.flash_damage()
	_last_hp = hp


func _on_player_died() -> void:
	_fail("YOU DIED")


func _return_to_menu() -> void:
	# 撤离前按 ESC 视为放弃：背包与装备全部丢失。
	if _penalties_enabled() and (state == "playing" or state == "cleared" or state == "extracting"):
		Meta.lose_gear()
		Meta.record_result("ABANDONED   ·   LOOT AND GEAR LOST")
	Meta.save_data()
	get_tree().change_scene_to_file("res://scenes/hub.tscn")


func _set_hint(text: String) -> void:
	if text == _hint:
		return
	_hint = text
	hud.set_hint(text)


# ---------------------------------------------------------------- 截图 / 诊断

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

	# 背包面板：放几件装备进去再打开。
	add_gear_to_bag("weapon", "katana")
	add_gear_to_bag("armor", "chain")
	add_gear_to_bag("weapon", "golden_sword")
	_toggle_bag()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("shot_bag.png")
	_toggle_bag()
	await get_tree().create_timer(0.2).timeout

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
