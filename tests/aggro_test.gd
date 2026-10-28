extends Node
## 仇恨测试：生成不主动 / 接近才发现 / 超距脱战 / 断视线脱战 / 回出生点待机 / 受击立刻仇恨。
## 运行：godot --headless --path . res://tests/aggro_test.tscn

var main: Node
var failures := 0
var _saved := {}


## 只实现敌人会用到的那几个成员，用来在空场景里单独驱动一只怪。
class FakePlayer extends Node2D:
	var dead := false
	var hp := 6

	func take_damage(amount: int, _from: Vector2) -> void:
		hp -= amount


func _ready() -> void:
	_snapshot()
	Loc.language = "en"
	Meta.gold = 0
	Meta.raids = 0
	Meta.weapon = Meta.DEFAULT_WEAPON
	Meta.armor = Meta.DEFAULT_ARMOR
	Meta.stash.clear()

	main = load("res://scenes/main.tscn").instantiate()
	main.auto_return = false
	add_child(main)
	await get_tree().create_timer(0.25).timeout

	await _run_spawn()
	await _run_packs()
	await _run_attack_slow()
	await _run_map_noise()
	await _run_states()
	await _run_hearing()
	await _run_disengage()

	_restore()
	print("---- %d failure(s) ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## 真实地图：怪物生成后应该待在原地，不能一出生就扑向玩家。
func _run_spawn() -> void:
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() == 15, "首局生成 15 只敌人（实际 %d）" % enemies.size())

	var all_idle := true
	var nearest := 9999.0
	for enemy in enemies:
		all_idle = all_idle and int(enemy.state) == Enemy.State.IDLE
		nearest = minf(nearest, enemy.global_position.distance_to(main.player.global_position))
	check(all_idle, "生成后全部处于待机，不会立刻冲上来")
	check(nearest > Enemy.DETECT_RADIUS,
		"离玩家最近的怪在 %.0f 像素外，大于发现半径 %.0f" % [nearest, Enemy.DETECT_RADIUS])

	var spots: Array[Vector2] = []
	for enemy in enemies:
		spots.append(enemy.global_position)
	await get_tree().create_timer(0.6).timeout
	var stayed := true
	for i in enemies.size():
		if not is_instance_valid(enemies[i]):
			continue
		stayed = stayed and enemies[i].global_position.distance_to(spots[i]) < 0.5
	check(stayed, "0.6 秒内待机敌人原地不动")


## 群落：同一群里应该混有多种怪物，而不是清一色。
func _run_packs() -> void:
	var by_pack := {}
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var id: int = enemy.pack_id
		if id < 0:
			continue
		if not by_pack.has(id):
			by_pack[id] = []
		by_pack[id].append(str(enemy.kind))

	check(by_pack.size() >= 2, "至少刷出 2 个群落（%d）" % by_pack.size())

	var pure := 0
	var largest := 0
	for id in by_pack:
		var kinds: Array = by_pack[id]
		var distinct := {}
		for kind in kinds:
			distinct[kind] = true
		largest = maxi(largest, kinds.size())
		if kinds.size() >= 2 and distinct.size() < 2:
			pure += 1
	check(pure == 0, "每个群落都混了多种怪（纯种群落 %d 个）" % pure)
	check(largest >= 3, "群落有 3 只以上的规模（最大 %d）" % largest)


## 挥剑硬直：攻击冷却期间移速掉到 60%，边退边砍不再比怪快。
func _run_attack_slow() -> void:
	var player: Player = main.player
	Input.action_press("move_right")
	await get_tree().create_timer(0.4).timeout
	var normal: float = player.velocity.length()
	Input.action_release("move_right")
	await get_tree().create_timer(0.25).timeout

	player._start_attack()
	Input.action_press("move_right")
	await get_tree().create_timer(0.25).timeout
	var slowed: float = player.velocity.length()
	Input.action_release("move_right")

	check(normal > 80.0, "正常跑动保持全速（%.0f）" % normal)
	check(slowed < normal * 0.75, "挥剑硬直期间移速明显下降（%.0f -> %.0f）" % [normal, slowed])


## 真实地图：挥剑 / 开门产生的噪音应该把附近的怪引过来。
func _run_map_noise() -> void:
	var enemy: Node = get_tree().get_nodes_in_group("enemies")[0]
	enemy.global_position = main.player.global_position + Vector2(150, 0)
	enemy.set_home(enemy.global_position)
	await get_tree().physics_frame
	await get_tree().create_timer(0.15).timeout
	check(int(enemy.state) == Enemy.State.IDLE,
		"150 像素外（超出 104 发现半径）保持待机（state=%d）" % enemy.state)

	main.player._start_attack()
	await get_tree().create_timer(0.15).timeout
	check(int(enemy.state) == Enemy.State.INVESTIGATE,
		"挥剑声把 150 像素外的怪引过来查看（state=%d）" % enemy.state)

	# 开门单独拿一只新怪测，避免上一步的仇恨干扰。
	var guard: Enemy = load("res://scenes/enemy.tscn").instantiate()
	guard.kind = "goblin"
	guard.tier = 1
	guard.player = main.player
	main.actors.add_child(guard)
	guard.global_position = main.dungeon.door_position(0) + Vector2(0, 60)
	guard.set_home(guard.global_position)
	await get_tree().physics_frame
	check(int(guard.state) == Enemy.State.IDLE, "门边 60 像素的守卫初始待机")

	main._operate_switch(0)
	await get_tree().create_timer(0.85).timeout
	check(int(guard.state) == Enemy.State.INVESTIGATE,
		"开门声把门边的怪惊动（state=%d）" % guard.state)


## 空场景：逐个验证发现 / 脱战 / 回家 / 受击仇恨。
func _run_states() -> void:
	# 换成干净场景，避免真实地图上的墙干扰视线判定。
	main.queue_free()
	await get_tree().process_frame
	await get_tree().physics_frame

	var world := Node2D.new()
	add_child(world)
	var hero := FakePlayer.new()
	hero.global_position = Vector2(0, 400)
	world.add_child(hero)

	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.kind = "goblin"
	enemy.tier = 1
	enemy.player = hero
	world.add_child(enemy)
	enemy.global_position = Vector2.ZERO
	enemy.set_home(Vector2.ZERO)
	await get_tree().physics_frame

	# 1. 玩家在远处：保持待机，也不移动。
	await get_tree().create_timer(0.5).timeout
	check(int(enemy.state) == Enemy.State.IDLE, "400 像素外不会发现玩家（state=%d）" % enemy.state)
	check(enemy.global_position.distance_to(Vector2.ZERO) < 0.5, "待机时不移动")

	# 2. 玩家走进发现半径：短暂警戒后开始追。
	hero.global_position = Vector2(60, 0)
	await get_tree().create_timer(0.4).timeout
	check(int(enemy.state) == Enemy.State.CHASE, "玩家进入 104 像素内后开始追击（state=%d）" % enemy.state)
	check(enemy.global_position.distance_to(hero.global_position) < 60.0,
		"追击时会靠近玩家（%.1f）" % enemy.global_position.distance_to(hero.global_position))

	# 3. 玩家跑远：超距 1.2 秒后脱战，回出生点恢复待机。
	hero.global_position = Vector2(600, 0)
	await get_tree().create_timer(1.4).timeout
	check(int(enemy.state) == Enemy.State.RETURN, "玩家跑出 224 像素 1.2 秒后脱战（state=%d）" % enemy.state)
	await get_tree().create_timer(2.0).timeout
	check(int(enemy.state) == Enemy.State.IDLE, "回到出生点后恢复待机（state=%d）" % enemy.state)
	check(enemy.global_position.distance_to(Vector2.ZERO) < 12.0,
		"回到出生点附近（%.1f）" % enemy.global_position.distance_to(Vector2.ZERO))

	# 4. 待机时挨打：立刻进入追击，不用等发现半径。
	enemy.take_damage(1, Vector2(80, 0))
	check(int(enemy.state) == Enemy.State.CHASE, "挨打后立刻进入追击（state=%d）" % enemy.state)
	await get_tree().create_timer(3.2).timeout
	check(int(enemy.state) == Enemy.State.IDLE, "玩家仍在远处，再次脱战回待机（state=%d）" % enemy.state)

	# 5. 视线被墙挡住：2.5 秒没有视线也会脱战（关门 / 卡柱子）。
	#    先在 60 像素内被它发现，再把玩家拉到 200（仍在 224 的脱战距离内），
	#    这样只有“断视线”这一条能把它甩掉。
	#    它刚回巢，先等 3 秒冷静期过去，否则不会重新发现玩家。
	await get_tree().create_timer(3.1).timeout
	hero.global_position = Vector2(60, 0)
	await get_tree().create_timer(0.4).timeout
	check(int(enemy.state) == Enemy.State.CHASE, "再次被发现（state=%d）" % enemy.state)

	hero.global_position = Vector2(200, 0)
	await get_tree().physics_frame
	var wall := StaticBody2D.new()
	wall.collision_layer = 4
	wall.collision_mask = 0
	var block := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(8, 160)
	block.shape = rect
	wall.add_child(block)
	wall.global_position = Vector2(120, 0)
	world.add_child(wall)
	await get_tree().physics_frame
	check(int(enemy.state) == Enemy.State.CHASE, "玩家进入 200 像素仍算追击中（state=%d）" % enemy.state)

	await get_tree().create_timer(2.9).timeout
	check(int(enemy.state) != Enemy.State.CHASE,
		"视线被挡 2.5 秒后脱战（state=%d）" % enemy.state)

	world.queue_free()


## 听觉：噪音范围判定、循声查看、查看途中发现玩家、同伴喊话。
func _run_hearing() -> void:
	var world := Node2D.new()
	add_child(world)
	var hero := FakePlayer.new()
	hero.global_position = Vector2(3000, 3000)
	world.add_child(hero)
	var listener := _spawn_enemy(world, Vector2.ZERO, hero)
	await get_tree().physics_frame

	Game.emit_noise(Vector2(2000, 0), 190.0, "test")
	await get_tree().create_timer(0.2).timeout
	check(int(listener.state) == Enemy.State.IDLE, "噪音范围外保持待机（state=%d）" % listener.state)

	var point := Vector2(90, 0)
	Game.emit_noise(point, 190.0, "test")
	await get_tree().create_timer(0.15).timeout
	check(int(listener.state) == Enemy.State.INVESTIGATE, "听到噪音去查看（state=%d）" % listener.state)
	var before := listener.global_position.distance_to(point)
	await get_tree().create_timer(0.5).timeout
	var after := listener.global_position.distance_to(point)
	check(after < before - 1.0, "会朝声源走过去（%.1f -> %.1f）" % [before, after])

	hero.global_position = listener.global_position + Vector2(50, 0)
	await get_tree().create_timer(0.4).timeout
	check(int(listener.state) == Enemy.State.CHASE,
		"查看途中撞见玩家，直接转追击（state=%d）" % listener.state)

	world.queue_free()
	await get_tree().process_frame

	# 喊话：seer 看见玩家 -> ally 在喊话半径（130）内；
	# far 离 seer 200（够不到），但离 ally 只有 110 —— 如果喊话会连锁，它就会被拉进来。
	var world2 := Node2D.new()
	add_child(world2)
	var hero2 := FakePlayer.new()
	hero2.global_position = Vector2(60, 0)
	world2.add_child(hero2)
	var seer := _spawn_enemy(world2, Vector2.ZERO, hero2)
	var ally := _spawn_enemy(world2, Vector2(0, 90), hero2)
	var far_away := _spawn_enemy(world2, Vector2(0, 200), hero2)
	await get_tree().physics_frame
	check(int(ally.state) == Enemy.State.IDLE, "同伴初始待机")

	await get_tree().create_timer(0.45).timeout
	check(int(seer.state) == Enemy.State.CHASE, "发现玩家的怪进入追击（state=%d）" % seer.state)
	check(int(ally.state) == Enemy.State.CHASE, "附近同伴被喊进战斗（state=%d）" % ally.state)
	check(int(far_away.state) == Enemy.State.IDLE,
		"被喊来的同伴不会再传话（state=%d）" % far_away.state)

	world2.queue_free()


## 极限距离拉扯：贴脸不脱战、退开才脱战、回巢回血、冷静期内不重仇恨。
func _run_disengage() -> void:
	var world := Node2D.new()
	add_child(world)
	var hero := FakePlayer.new()
	hero.global_position = Vector2(6000, 6000)
	world.add_child(hero)
	var enemy := _spawn_enemy(world, Vector2.ZERO, hero)
	await get_tree().physics_frame

	# 把它拖到牵引半径（320）之外，玩家贴脸站着：不该转身回家。
	enemy.global_position = Vector2(400, 0)
	enemy.set_home(Vector2.ZERO)
	hero.global_position = Vector2(440, 0)
	enemy.state = Enemy.State.CHASE
	await get_tree().create_timer(1.7).timeout
	check(int(enemy.state) == Enemy.State.CHASE,
		"贴脸时超出牵引半径也不脱战（state=%d）" % enemy.state)

	# 玩家退开：正常脱战。
	hero.global_position = Vector2(2000, 0)
	await get_tree().create_timer(1.5).timeout
	check(int(enemy.state) == Enemy.State.RETURN,
		"玩家退开后脱战（state=%d）" % enemy.state)

	# 带伤回家：把锚点挪到脚边，验证到家回血。
	enemy.hp = 1
	enemy.set_home(enemy.global_position + Vector2(-40, 0))
	await get_tree().create_timer(1.6).timeout
	check(int(enemy.state) == Enemy.State.IDLE, "走到锚点后恢复待机（state=%d）" % enemy.state)
	check(enemy.hp == enemy.max_hp, "回巢回满血（%d/%d）" % [enemy.hp, enemy.max_hp])

	# 冷静期内站在发现半径里也不会重新仇恨。
	hero.global_position = enemy.global_position + Vector2(80, 0)
	await get_tree().create_timer(0.6).timeout
	check(int(enemy.state) == Enemy.State.IDLE,
		"冷静期内不会重新仇恨（state=%d）" % enemy.state)

	# 冷静期过后恢复正常发现。
	await get_tree().create_timer(3.0).timeout
	check(int(enemy.state) != Enemy.State.IDLE,
		"冷静期结束后重新发现玩家（state=%d）" % enemy.state)

	world.queue_free()


func _spawn_enemy(world: Node2D, at: Vector2, hero: Node) -> Enemy:
	var enemy: Enemy = load("res://scenes/enemy.tscn").instantiate()
	enemy.kind = "goblin"
	enemy.tier = 1
	enemy.player = hero
	world.add_child(enemy)
	enemy.global_position = at
	enemy.set_home(at)
	return enemy


func _snapshot() -> void:
	_saved = {
		"gold": Meta.gold,
		"raids": Meta.raids,
		"best_haul": Meta.best_haul,
		"weapon": Meta.weapon,
		"armor": Meta.armor,
		"levels": Meta._levels.duplicate(),
		"stash": Meta.stash.items.duplicate(true),
		"backpack": Meta.backpack,
		"owned_backpacks": Meta.owned_backpacks.duplicate(),
		"last_result": Meta.last_result,
	}


func _restore() -> void:
	Meta.gold = int(_saved.gold)
	Meta.raids = int(_saved.raids)
	Meta.best_haul = int(_saved.best_haul)
	Meta.weapon = str(_saved.weapon)
	Meta.armor = str(_saved.armor)
	Meta._levels = _saved.levels
	Meta.stash.set_items(_saved.stash)
	Meta.backpack = str(_saved.backpack)
	Meta.owned_backpacks.clear()
	for id in _saved.owned_backpacks:
		Meta.owned_backpacks.append(str(id))
	Meta.last_result = str(_saved.last_result)
	Meta.save_data()


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		print("FAIL  ", message)
