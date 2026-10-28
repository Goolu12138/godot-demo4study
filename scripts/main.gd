extends Node2D
## 搜打撤循环：在一张由三间房拼接的大地图里搜索，在限时内找到随机刷新的撤离梯离开。
##
## 规则：
##   - 所有战利品都放进格子背包（贵重品 / 武器 / 护甲体积不同），都要成功撤离才结算；
##   - 三间房用门连接，门可以开关，不要求清怪；
##   - 怪物的种类与位置每局随机，可以打也可以绕；
##   - 死亡 / 倒计时归零 / 主动放弃：背包清空，身上的非默认武器与护甲一起丢失；
##   - 撤离或死亡后自动回到休息处，仓库在那边。

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")
const CONFIRM_SCENE := preload("res://scenes/confirm_dialog.tscn")

## 一局的时间预算，超时视为死亡。
const RUN_TIME := 900.0
## 倒计时剩 7:00 时开始刷新撤离点，之后每隔 15~25 秒刷一个。
const EXTRACTION_START_TIME := 7.0 * 60.0
const EXTRACTION_SPAWN_MIN := 15.0
const EXTRACTION_SPAWN_MAX := 25.0

## 贵重品：撤离时折算成金币；体积各不相同，一样占用背包格子。
const VALUE_TABLE := [
	{"id": "coins", "value": 5, "tex": "coin_anim_f0", "weight": 50, "w": 1, "h": 1},
	{"id": "potion", "value": 15, "tex": "flask_big_red", "weight": 28, "w": 2, "h": 2},
	{"id": "relic", "value": 30, "tex": "flask_big_blue", "weight": 15, "w": 3, "h": 1},
	{"id": "idol", "value": 60, "tex": "skull", "weight": 7, "w": 3, "h": 2},
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
## 格子背包：容量由 Meta.backpack 决定。
var bag: GridInventory = null
var bag_open := false
var time_left := RUN_TIME
## playing / moving / extracting / dead / ended
var state := "playing"
var enemies_alive := 0
## 测试与截图模式可以关掉自动回城。
var auto_return := true

var _last_hp := 0
var _hint := ""
var _full_warn := 0.0
var _confirm: CanvasLayer
var _confirm_mode := ""
var _switch_busy := false
var _extraction_spawn_cd := 0.0
var _extraction_spawned := 0
## 撤离梯前需要先离开再靠近才会再次弹确认，避免取消后立刻又弹。
var _extract_armed := true
## 换图后短暂忽略门判定，避免刚出生就被身后的门弹回去。
var _door_grace := 0.0


func _ready() -> void:
	_confirm = CONFIRM_SCENE.instantiate()
	add_child(_confirm)
	_confirm.confirmed.connect(_on_abandon_confirmed)
	_confirm.cancelled.connect(_on_abandon_cancelled)

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
	if "--abandon-shot" in OS.get_cmdline_user_args():
		_capture_abandon()
	if "--map-shot" in OS.get_cmdline_user_args():
		_capture_map()
	if "--extract-shot" in OS.get_cmdline_user_args():
		_capture_extract()
	if "--ladder-shot" in OS.get_cmdline_user_args():
		_capture_ladder()


func _process(delta: float) -> void:
	_full_warn = maxf(0.0, _full_warn - delta)
	_door_grace = maxf(0.0, _door_grace - delta)
	if Input.is_action_just_pressed("menu"):
		_request_abandon()
		return
	if state == "dead" or state == "ended":
		if Input.is_action_just_pressed("restart"):
			_start_run()
		return
	if state == "moving" or state == "extracting":
		return
	if player == null or player.dead:
		return


	if Input.is_action_just_pressed("bag") and state == "playing" and not _switch_busy:
		_toggle_bag()
		return
	if bag_open:
		# 背包开着时玩家不能动，但倒计时继续走。
		_tick_timer(delta)
		return

	if state == "playing":
		_tick_timer(delta)
		if state == "dead":
			return
		_update_extraction_spawns(delta)

	for loot in get_tree().get_nodes_in_group("loot"):
		if loot.global_position.distance_to(player.global_position) < 26.0:
			var item: Dictionary = loot.get_meta("item", {})
			if item.is_empty():
				continue
			if not _collect_item(item):
				if _full_warn <= 0.0:
					hud.message(Loc.t("bag_full"), 1.4)
					_full_warn = 1.6
				continue
			loot.remove_from_group("loot")
			loot.queue_free()

	var switch_index := dungeon.switch_near(player.global_position)
	var can_search := dungeon.can_search(player.global_position)
	if Input.is_action_just_pressed("interact") and not _switch_busy:
		if switch_index >= 0:
			_operate_switch(switch_index)
		elif can_search:
			_search()

	# 撤离点取消确认后，需要先走开再靠近，避免站在梯子上反复弹窗。
	if state == "playing" and not _extract_armed \
			and dungeon.extraction_distance(player.global_position) > 46.0:
		_extract_armed = true

	if state == "playing" and _door_grace <= 0.0 and dungeon.extraction_hit(player.global_position):
		if _extract_armed:
			_request_extract()
			return

	if switch_index >= 0:
		_set_hint(Loc.t("hint_switch"))
	elif can_search:
		_set_hint(Loc.t("hint_search"))
	elif dungeon.has_extraction_ladder():
		_set_hint(Loc.t("hint_extract_room"))
	else:
		_set_hint(Loc.t("hint_world"))


## 拉开关需要 0.5 秒：期间锁住玩家操作，结束后才真正切换门和碰撞。
func _operate_switch(door_index: int) -> void:
	if _switch_busy or state != "playing":
		return
	var will_open := not dungeon.is_passage_door_open(door_index)
	if not will_open and dungeon.door_position(door_index).distance_to(player.global_position) < 26.0:
		hud.message(Loc.t("door_blocked"), 1.2)
		return
	_switch_busy = true
	player.control_enabled = false
	hud.message(Loc.t("switch_opening") if will_open else Loc.t("switch_closing"), 0.7)
	await get_tree().create_timer(0.5).timeout
	if state == "playing":
		dungeon.toggle_door(door_index)
		hud.message(Loc.t("switch_opened") if will_open else Loc.t("switch_closed"), 0.9)
	if player != null and not player.dead:
		player.control_enabled = true
	_switch_busy = false


func _tick_timer(delta: float) -> void:
	time_left = maxf(0.0, time_left - delta)
	hud.set_timer(time_left)
	if time_left <= 0.0:
		_fail(Loc.t("reason_timeup"))


## 倒计时到 7:00 后开始刷新撤离点，每隔一段时间刷一个，最多 5 个。
func _update_extraction_spawns(delta: float) -> void:
	if time_left > EXTRACTION_START_TIME:
		return
	if _extraction_spawned >= Dungeon.MAX_EXTRACTION_LADDERS:
		return
	_extraction_spawn_cd -= delta
	if _extraction_spawn_cd > 0.0:
		return
	if dungeon.spawn_extraction_ladder():
		_extraction_spawned += 1
		hud.message(Loc.t("extraction_spawned"), 1.6)
		_extraction_spawn_cd = randf_range(EXTRACTION_SPAWN_MIN, EXTRACTION_SPAWN_MAX)
	else:
		_extraction_spawn_cd = 5.0


func _start_run() -> void:
	raid = Meta.raids + 1
	loot_value = 0
	loot_count = 0
	_extraction_spawn_cd = 0.0
	_extraction_spawned = 0
	bag = GridInventory.new(Meta.bag_cols(), Meta.bag_rows())
	bag_open = false
	time_left = RUN_TIME
	state = "playing"
	player.control_enabled = true
	hud.close_bag()
	hud.hide_end()
	hud.set_loot(loot_count, loot_value)
	hud.set_bag(0, bag.capacity_cells())
	hud.set_timer(time_left)
	hud.set_coins(Meta.gold)
	hud.fade_to(0.0, 0.45)
	_build_room()


func _build_room() -> void:
	_clear_actors()
	dungeon.build_world()
	player.reset(dungeon.spawn_point())
	_update_camera_limits()
	_spawn_enemies()
	state = "playing"
	player.control_enabled = true
	_door_grace = 0.7
	_extract_armed = true
	hud.set_raid(raid)
	hud.set_enemies(enemies_alive)
	hud.message(Loc.t("msg_start"), 2.2)
	_set_hint(Loc.t("hint_world"))


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
	var count: int = mini(6 + raid * 2, 20)
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
		if _stow(item, at):
			if item.kind == "valuable":
				gold_gain += int(item.value)
			else:
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


## 所有战利品都先找格子；放不下就掉在脚边（贵重品也一样）。
func _stow(item: Dictionary, at: Vector2) -> bool:
	if not bag.auto_place(item):
		_spawn_item(at + Vector2(randf_range(-16.0, 16.0), 4.0), item)
		return false
	if item.kind == "valuable":
		loot_value += int(item.value)
		loot_count += 1
		hud.set_loot(loot_count, loot_value)
	hud.set_bag(bag.used_cells(), bag.capacity_cells())
	hud.pulse_loot()
	return true


func _collect_item(item: Dictionary) -> bool:
	if not bag.auto_place(item):
		return false
	if item.kind == "valuable":
		loot_value += int(item.value)
		loot_count += 1
		hud.set_loot(loot_count, loot_value)
	hud.set_bag(bag.used_cells(), bag.capacity_cells())
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
				"w": int(entry.w),
				"h": int(entry.h),
			}
	return {"kind": "valuable", "id": "coins", "name": "COINS", "value": 5, "tex": "coin_anim_f0", "w": 1, "h": 1}


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
	return Meta.make_gear_item(kind, id)


# ---------------------------------------------------------------- 背包

## 测试与事件用的入口：放得下就进背包。
func add_gear_to_bag(kind: String, id: String) -> bool:
	var item := Meta.make_gear_item(kind, id)
	if item.is_empty() or not bag.auto_place(item):
		return false
	hud.set_bag(bag.used_cells(), bag.capacity_cells())
	hud.pulse_loot()
	return true


func drop_bag_item(index: int) -> void:
	if index < 0 or index >= bag.items.size():
		return
	var item := bag.remove_at(index)
	if item.is_empty():
		return
	hud.set_bag(bag.used_cells(), bag.capacity_cells())
	hud.open_bag(bag, _bag_tier_name())
	var label := str(item.get("name", item.get("id", "?")))
	if str(item.get("kind", "")) != "valuable":
		label = Loc.gear_name(str(item.get("id", "")))
	hud.message(Loc.t("msg_dropped") % label, 1.0)


func _toggle_bag() -> void:
	bag_open = not bag_open
	player.control_enabled = not bag_open
	if bag_open:
		hud.open_bag(bag, _bag_tier_name())
	else:
		hud.close_bag()


func _bag_tier_name() -> String:
	return Loc.t("pack_" + Meta.backpack)


# ---------------------------------------------------------------- 撤离 / 失败

func _extract() -> void:
	if state != "playing":
		return
	state = "extracting"
	if bag_open:
		bag_open = false
		hud.close_bag()
	player.control_enabled = false
	_set_hint("")
	var gained := loot_value
	var gear: Array = []
	for item in bag.items:
		if str(item.get("kind", "")) != "valuable":
			gear.append(item)
	var stored := gear.size()
	var punished := _penalties_enabled()
	if punished:
		stored = Meta.finish_extraction(gained, gear)
		bag.clear()
		hud.set_bag(0, bag.capacity_cells())
		hud.set_loot(0, 0)
	hud.set_coins(Meta.gold)
	hud.fade_to(0.55, 0.25)
	await get_tree().create_timer(0.35).timeout
	if state != "extracting":
		return
	hud.message(Loc.t("msg_extracted") % gained, 2.0)
	var tail := Loc.t("returning_camp") if punished else Loc.t("esc_camp")
	hud.show_end(Loc.t("end_extracted"),
		Loc.t("end_extracted_sub") % [gained, stored, tail],
		Color("#8fd18a"))
	hud.fade_to(0.0, 0.4)
	state = "ended"
	if auto_return and punished:
		await get_tree().create_timer(2.0).timeout
		if state == "ended":
			get_tree().change_scene_to_file("res://scenes/hall.tscn")


func _fail(reason: String) -> void:
	if state == "dead" or state == "ended" or state == "extracting":
		return
	state = "dead"
	if bag_open:
		bag_open = false
		hud.close_bag()
	player.control_enabled = false
	var lost := loot_value
	var lost_gear := bag.items.size()
	var punished := _penalties_enabled()
	if punished:
		Meta.lose_gear()
		bag.clear()
		hud.set_bag(0, bag.capacity_cells())
		Meta.record_result(Loc.t("result_lost") % [reason, lost, lost_gear])
	hud.message("", 0.0)
	hud.set_enemies(-1)
	hud.set_timer(0.0)
	_set_hint("")
	var subtitle: String
	if punished:
		subtitle = Loc.t("end_lost_sub") % [lost, lost_gear, Loc.t("returning_camp")]
	else:
		subtitle = Loc.t("end_demo_sub") % [lost, lost_gear]
	await get_tree().create_timer(0.6).timeout
	if state != "dead":
		return
	hud.show_end(reason, subtitle, Color("#e0453c"))
	if auto_return and punished:
		await get_tree().create_timer(2.0).timeout
		if state == "dead":
			get_tree().change_scene_to_file("res://scenes/hall.tscn")


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
	_fail(Loc.t("reason_died"))


# ---------------------------------------------------------------- 主动放弃（Esc）

## Esc 不再直接回大厅：先暂停游戏并弹二次确认。
func _request_abandon() -> void:
	if _confirm == null or _confirm.is_open():
		return
	if state == "dead" or state == "ended":
		_leave_to_hall()
		return
	if bag_open:
		_toggle_bag()
		return
	if state != "playing" and state != "extracting":
		return
	_confirm_mode = "abandon"
	get_tree().paused = true
	_confirm.ask(Loc.t("abandon_title"), Loc.t("abandon_body"),
		Loc.t("abandon_yes"), Loc.t("abandon_no"))


## 走到撤离梯：先确认，确认后才结算。
func _request_extract() -> void:
	if _confirm == null or _confirm.is_open() or state != "playing":
		return
	if bag_open:
		_toggle_bag()
		return
	_confirm_mode = "extract"
	get_tree().paused = true
	_confirm.ask(Loc.t("extract_title"), Loc.t("extract_body"),
		Loc.t("extract_yes"), Loc.t("extract_no"))


func _on_abandon_confirmed() -> void:
	get_tree().paused = false
	if _confirm_mode == "extract":
		if _confirm != null:
			_confirm.close()
		_confirm_mode = ""
		_extract()
		return
	if _penalties_enabled() and (state == "playing" or state == "extracting"):
		Meta.lose_gear()
		Meta.record_result(Loc.t("result_abandoned"))
	Meta.save_data()
	_leave_to_hall()


func _on_abandon_cancelled() -> void:
	get_tree().paused = false
	if _confirm != null:
		_confirm.close()
	if _confirm_mode == "extract":
		_extract_armed = false
	_confirm_mode = ""


func _leave_to_hall() -> void:
	get_tree().paused = false
	Meta.save_data()
	get_tree().change_scene_to_file("res://scenes/hall.tscn")


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


## 调试用：截撤离梯特写。
func _capture_ladder() -> void:
	player.invuln = 99.0
	if not dungeon.has_extraction_ladder():
		dungeon.spawn_extraction_ladder()
	await get_tree().create_timer(0.4).timeout
	player.global_position = dungeon.extraction_point() + Vector2(0, 40)
	player.camera.reset_smoothing()
	await get_tree().create_timer(0.4).timeout
	await _save_shot("shot_ladder.png")
	get_tree().quit()


## 调试用：截撤离确认弹窗。
func _capture_extract() -> void:
	player.invuln = 99.0
	if not dungeon.has_extraction_ladder():
		dungeon.spawn_extraction_ladder()
	await get_tree().create_timer(0.4).timeout
	player.global_position = dungeon.extraction_point()
	await get_tree().create_timer(0.5).timeout
	await _save_shot("shot_extract.png")
	get_tree().paused = false
	get_tree().quit()


## 调试用：把整张 120x24 的大地图缩到一屏（map_world.png）。
func _capture_map() -> void:
	player.invuln = 99.0
	await get_tree().create_timer(0.3).timeout
	player.global_position = dungeon.room_pixel_size() * 0.5
	player.camera.zoom = Vector2(0.32, 0.32)
	player.camera.reset_smoothing()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("map_world.png")
	get_tree().quit()


func _capture_abandon() -> void:
	await get_tree().create_timer(0.6).timeout
	_request_abandon()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("shot_abandon.png")
	get_tree().paused = false
	get_tree().quit()


func _demo_shots() -> void:
	player.invuln = 99.0
	if not dungeon.has_extraction_ladder():
		dungeon.spawn_extraction_ladder()
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

	player.global_position = dungeon.extraction_point() + Vector2(0, 44)
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
	player.global_position = dungeon.extraction_point() + Vector2(0, 44)
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
