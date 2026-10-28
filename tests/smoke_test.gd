extends Node
## 搜打撤冒烟测试：搜索 -> 背包 -> 清场 -> 撤离结算 -> 死亡/超时惩罚。
## 运行：godot --headless --path . res://tests/smoke_test.tscn

var main: Node
var failures := 0
var _saved := {}


func _ready() -> void:
	_snapshot()
	# 结果文案是本地化的，测试固定英文，避免受存档里的语言设置影响。
	Loc.language = "en"
	Meta.gold = 0
	Meta.raids = 0
	Meta.best_haul = 0
	Meta.weapon = Meta.DEFAULT_WEAPON
	Meta.armor = Meta.DEFAULT_ARMOR
	Meta.stash.clear()
	Meta.backpack = Meta.DEFAULT_BACKPACK
	Meta.owned_backpacks = [Meta.DEFAULT_BACKPACK]
	Meta.last_result = ""

	main = load("res://scenes/main.tscn").instantiate()
	main.auto_return = false
	add_child(main)
	await get_tree().create_timer(0.25).timeout
	await _run()
	_restore()
	print("---- %d failure(s) ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	# Esc 二次确认：先暂停并弹窗，取消后恢复
	main._request_abandon()
	check(get_tree().paused, "按 Esc 先暂停并弹出确认")
	check(main._confirm.is_open(), "确认弹窗已显示")
	main._on_abandon_cancelled()
	check(not get_tree().paused, "取消后恢复游戏")
	check(not main._confirm.is_open(), "取消后关闭弹窗")

	check(main.state == "playing", "开局处于 playing")
	check(main.enemies_alive == 8, "首局生成 8 个敌人（实际 %d）" % main.enemies_alive)
	check(get_tree().get_nodes_in_group("enemies").size() == 8, "敌人已加入 enemies 组")
	check(main.time_left > 140.0, "倒计时已启动（%.0f）" % main.time_left)
	check(main.bag.items.is_empty(), "开局背包为空")
	check(main.bag.cols == 30 and main.bag.rows == 20, "初级背包是 30×20")
	check(main.hud._bag_max == 600, "背包容量按格计算（%d）" % main.hud._bag_max)

	var enemy: Node = get_tree().get_nodes_in_group("enemies")[0]
	# 出生点周围 96px 内不会生成障碍物，先把它放到这段空地上再测追逐，避免柱子挡路导致偶发失败。
	enemy.global_position = main.player.global_position + Vector2(72, 0)
	await get_tree().physics_frame
	var before: float = enemy.global_position.distance_to(main.player.global_position)
	await get_tree().create_timer(0.5).timeout
	var after: float = enemy.global_position.distance_to(main.player.global_position)
	check(after < before - 1.0, "敌人会朝玩家靠近（%.1f -> %.1f）" % [before, after])

	var hp_before: int = main.player.hp
	main.player.invuln = 0.0
	main.player.take_damage(1, enemy.global_position)
	check(main.player.hp == hp_before - 1, "玩家受击扣血")
	check(main.player.invuln > 0.0, "受击后进入无敌帧")

	enemy.take_damage(99, main.player.global_position)
	await get_tree().process_frame
	check(main.enemies_alive == 7, "击杀敌人后计数减少（%d）" % main.enemies_alive)

	# 搜索：贵重品记估值，装备进背包，都不写存档
	main.player.global_position = main.dungeon.chest_position()
	check(main.dungeon.can_search(main.player.global_position), "靠近宝箱可以搜索")
	var loot_before: int = main.loot_value
	var bag_before: int = main.bag.items.size()
	var left_before: int = main.dungeon.searchable_left()
	main._search()
	await get_tree().process_frame
	check(main.dungeon.is_chest_open(), "按 E 搜开宝箱")
	check(main.loot_value > loot_before or main.bag.items.size() > bag_before, "宝箱产出战利品")
	check(main.dungeon.searchable_left() == left_before - 1, "容器搜过后从可搜索列表移除，不能重复搜索")
	check(Meta.gold == 0, "搜索不写存档，金币仍为 0")

	# 地面掉落：贵重品自动入账，装备进背包
	var before_pickup: int = main.loot_value
	main._spawn_item(main.player.global_position,
		{"kind": "valuable", "id": "test", "name": "TEST", "value": 7, "tex": "coin_anim_f0"})
	await get_tree().create_timer(0.1).timeout
	check(main.loot_value == before_pickup + 7, "走过贵重品自动拾取（%d）" % main.loot_value)

	var bag_before_gear: int = main.bag.items.size()
	main._spawn_item(main.player.global_position, main._make_gear_item("armor", "leather"))
	await get_tree().create_timer(0.1).timeout
	check(main.bag.items.size() == bag_before_gear + 1, "走过装备会进背包（%d）" % main.bag.items.size())

	# 背包容量：30×20 格，用 2×3 武器铺满；满了之后不能再拿，必须丢东西
	main.bag.clear()
	for i in 90:
		main.bag.auto_place(Meta.make_gear_item("weapon", "knight_sword"))
	check(main.bag.items.size() == 90, "2×3 武器能放 90 件（%d）" % main.bag.items.size())
	check(main.bag.used_cells() == 540, "已占用 540/600 格")
	check(not main.add_gear_to_bag("weapon", "katana"), "剩余 2 行放不下 2×3，拒绝新装备")

	main._toggle_bag()
	check(main.bag_open, "TAB 打开背包")
	check(main.hud.is_bag_open(), "背包面板已显示")
	check(not main.player.control_enabled, "背包打开时锁定操作")

	# 拖放：把第一件物品拖到第二件上，两件占用格相同，应交换位置。
	var view: GridInventoryView = main.hud.bag_view
	var first_old := Vector2i(int(main.bag.items[0].x), int(main.bag.items[0].y))
	var second_old := Vector2i(int(main.bag.items[1].x), int(main.bag.items[1].y))
	var first_size := Vector2(int(main.bag.items[0].w), int(main.bag.items[0].h))
	var second_size := Vector2(int(main.bag.items[1].w), int(main.bag.items[1].h))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = (Vector2(first_old) + first_size * 0.5) * view.cell
	var motion := InputEventMouseMotion.new()
	motion.position = (Vector2(second_old) + second_size * 0.5) * view.cell
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = motion.position
	view._gui_input(press)
	view._gui_input(motion)
	view._gui_input(release)
	check(Vector2i(int(main.bag.items[0].x), int(main.bag.items[0].y)) == second_old,
		"左键拖动背包物品到空位 / 另一件物品上")
	check(Vector2i(int(main.bag.items[1].x), int(main.bag.items[1].y)) == first_old,
		"拖到占位物品上会交换位置")

	# 右键物品只弹菜单，不再直接丢弃。
	var right_click := InputEventMouseButton.new()
	right_click.button_index = MOUSE_BUTTON_RIGHT
	right_click.pressed = true
	right_click.position = (Vector2(second_old) + first_size * 0.5) * view.cell
	view._gui_input(right_click)
	check(main.hud._bag_menu != null and main.hud._bag_menu.visible and main.hud._bag_menu_index == 0,
		"右键背包物品会弹出丢弃选项")
	check(main.hud._bag_menu.get_item_text(0) == Loc.t("discard"), "丢弃菜单文案已本地化")
	main.hud._bag_menu.id_pressed.emit(0)
	check(main.bag.items.size() == 89, "从右键菜单丢弃一件后少一件（%d）" % main.bag.items.size())

	# 左键单击不再丢弃，只是选中 / 等待拖动。
	var click_item: Dictionary = main.bag.items[0]
	var click_pos := (Vector2(int(click_item.x), int(click_item.y)) \
		+ Vector2(int(click_item.w), int(click_item.h)) * 0.5) * view.cell
	var click_press := InputEventMouseButton.new()
	click_press.button_index = MOUSE_BUTTON_LEFT
	click_press.pressed = true
	click_press.position = click_pos
	var click_release := InputEventMouseButton.new()
	click_release.button_index = MOUSE_BUTTON_LEFT
	click_release.pressed = false
	click_release.position = click_pos
	view._gui_input(click_press)
	view._gui_input(click_release)
	check(main.bag.items.size() == 89, "左键单击背包物品不再直接丢弃")
	main.hud._on_bag_item_hovered(0)
	check("×" in main.hud.bag_hint.text, "悬停背包物品显示体积（%s）" % main.hud.bag_hint.text)
	check(main.add_gear_to_bag("weapon", "katana"), "空出 2×3 后可以捡起新装备")
	main._toggle_bag()
	check(not main.bag_open and main.player.control_enabled, "关闭背包恢复操作")

	# 准备撤离：背包里放指定装备，确保仓库断言稳定
	main.bag.clear()
	main.add_gear_to_bag("weapon", "katana")
	main.add_gear_to_bag("armor", "chain")

	# 开关交互：0.5 秒内门还没切换，结束后打开；再交互一次关上
	main.player.invuln = 99.0
	main.player.global_position = main.dungeon._switches[0].pos
	main._operate_switch(0)
	check(not main.dungeon.is_passage_door_open(0), "交互 0.5 秒内门还没有打开")
	await get_tree().create_timer(0.7).timeout
	check(main.dungeon.is_passage_door_open(0), "交互 0.5 秒后门打开")
	main._operate_switch(0)
	await get_tree().create_timer(0.7).timeout
	check(not main.dungeon.is_passage_door_open(0), "再次交互把门关上")

	# 撤离点只在倒计时 7:00 后开始刷新，且是陆续刷新的
	check(not main.dungeon.has_extraction_ladder(), "开局没有撤离点")
	main.time_left = 421.0
	main._update_extraction_spawns(0.1)
	check(not main.dungeon.has_extraction_ladder(), "7:00 之前不刷新撤离点")
	main.time_left = 419.0
	main._update_extraction_spawns(0.1)
	check(main.dungeon.has_extraction_ladder(), "倒计时到 7:00 后开始刷新撤离点")

	# 不要求清怪：整张大地图可以自由穿行，直接去撤离梯
	main.player.invuln = 99.0
	var haul: int = main.loot_value
	main.player.global_position = main.dungeon.extraction_point()
	await get_tree().create_timer(0.2).timeout
	check(main._confirm.is_open() and main._confirm_mode == "extract", "撤离梯弹出确认")
	check(get_tree().paused, "撤离确认时暂停游戏")
	main._confirm.cancel()
	await get_tree().create_timer(0.1).timeout
	check(main.state == "playing" and not get_tree().paused, "取消撤离后继续游戏")

	main.player.global_position = main.dungeon.extraction_point() + Vector2(0, -90)
	await get_tree().create_timer(0.2).timeout
	main.player.global_position = main.dungeon.extraction_point()
	await get_tree().create_timer(0.2).timeout
	check(main._confirm.is_open(), "走开再靠近会再次弹撤离确认")
	main._on_abandon_confirmed()
	await get_tree().create_timer(1.0).timeout
	check(main.state == "ended", "确认撤离后结束本局（%s）" % main.state)
	check(Meta.gold == main.loot_value, "撤离后贵重品入账（%d / %d）" % [Meta.gold, main.loot_value])
	check(main.loot_value >= haul, "撤离时携带的贵重品没有丢失（%d）" % main.loot_value)
	check(main.bag.items.is_empty(), "撤离后背包清空")
	check(Meta.raids == 1, "撤离次数 +1（%d）" % Meta.raids)
	check(Meta.best_haul >= haul, "记录最佳收益（%d）" % Meta.best_haul)
	check(Meta.owned_count("weapon", "katana") == 1, "撤离后武器进仓库")
	check(Meta.owned_count("armor", "chain") == 1, "撤离后护甲进仓库")
	check(Meta.last_result.begins_with("EXTRACTED"), "休息处会显示撤离结果")

	# 新一局：状态清零
	main._start_run()
	await get_tree().create_timer(0.2).timeout
	check(main.state == "playing", "可以再开一局")
	check(main.loot_value == 0 and main.loot_count == 0, "新局贵重品清零")
	check(main.bag.items.is_empty(), "新局背包清空")
	check(main.raid == 2, "第二局 RAID 递增（%d）" % main.raid)
	check(main.enemies_alive == 10, "第二局敌人更多（%d）" % main.enemies_alive)

	# 死亡：背包清空 + 身上装备从仓库消失
	check(Meta.equip_gear("weapon", "katana"), "从仓库装备 KATANA")
	check(Meta.equip_gear("armor", "chain"), "从仓库装备 CHAIN")
	check(main.add_gear_to_bag("armor", "leather"), "死亡前背包里有一件装备")
	var banked: int = Meta.gold
	main.player.invuln = 0.0
	main.player.take_damage(99, Vector2.ZERO)
	await get_tree().create_timer(0.1).timeout
	check(main.state == "dead", "血量归零后进入 dead 状态")
	check(Meta.gold == banked, "死亡不结算贵重品")
	check(main.bag.items.is_empty(), "死亡后背包清空")
	check(Meta.weapon == Meta.DEFAULT_WEAPON, "死亡丢失武器")
	check(Meta.armor == Meta.DEFAULT_ARMOR, "死亡丢失护甲")
	check(Meta.owned_count("weapon", "katana") == 0, "仓库里的 KATANA 也消失")
	check(Meta.owned_count("armor", "chain") == 0, "仓库里的 CHAIN 也消失")
	check(Meta.last_result.begins_with("YOU DIED"), "休息处会显示死亡结果")

	# 超时：同样判定失败
	main._start_run()
	await get_tree().create_timer(0.2).timeout
	main.time_left = 0.02
	await get_tree().create_timer(0.15).timeout
	check(main.state == "dead", "倒计时归零判定失败（%s）" % main.state)


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
