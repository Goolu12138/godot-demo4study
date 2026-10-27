extends Node
## 休息处测试：角色格、商店开关、永久升级、装备购买/仓库/换装与属性生效。
## 运行：godot --headless --path . res://tests/menu_test.tscn

var failures := 0
var _saved := {}


func _ready() -> void:
	_snapshot()
	Loc.language = "en"
	Meta.gold = 500
	Meta.selected_hero = "knight_m"
	Meta.weapon = Meta.DEFAULT_WEAPON
	Meta.armor = Meta.DEFAULT_ARMOR
	Meta.owned_weapons = []
	Meta.owned_armors = []
	Meta.last_result = ""
	for key in Meta.UPGRADES:
		Meta._levels[key] = 0

	var menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame

	check(menu._hero_slots.size() == 4, "四个角色格")
	check(menu.ui_only == false, "菜单处于标题模式")
	check(menu._main_box.get_child_count() == 3, "标题有进入大厅 / 设置 / 退出三个按钮")
	check(menu._hero_slots[0].button_pressed, "默认选中骑士")
	check(menu._hero_slots[1].button_pressed == false, "锁定角色默认未选中")

	menu._on_hero_pressed(1)
	await get_tree().process_frame
	check(menu.selected_hero == 0, "点击锁定角色不会切换选择")

	# 永久升级
	Meta.gold = 100
	menu._refresh_shop()
	check(Meta.buy("vitality"), "金币足够时购买升级成功")
	check(Meta.upgrade_level("vitality") == 1, "升级等级 +1")
	check(Meta.gold == 70, "金币被扣除（剩 %d）" % Meta.gold)

	# 商店买装备：先入库，比身上强就自动换上
	Meta.gold = 200
	check(Meta.buy_gear("weapon", "knight_sword"), "买得起就购买武器")
	check(Meta.weapon == "knight_sword", "更强的武器自动装备（%s）" % Meta.weapon)
	check(Meta.owned_count("weapon", "knight_sword") == 1, "武器进入仓库")
	check(Meta.gold == 80, "武器扣款正确（剩 %d）" % Meta.gold)
	check(not Meta.buy_gear("weapon", "knight_sword"), "不能重复购买同一件")

	Meta.gold = 400
	check(Meta.buy_gear("weapon", "katana"), "可以购买更高档武器")
	check(Meta.gold == 100, "升级扣款正确（剩 %d）" % Meta.gold)
	check(not Meta.buy_gear("weapon", "rusty_sword"), "不能买默认武器")

	Meta.gold = 500
	check(Meta.buy_gear("armor", "leather"), "可以购买护甲")
	check(Meta.armor == "leather", "护甲已装备（%s）" % Meta.armor)

	# 仓库：换回已拥有的低档武器，不需要再花钱
	check(Meta.equip_gear("weapon", "knight_sword"), "仓库里换装备成功")
	check(Meta.weapon == "knight_sword", "换上 KNIGHT SWORD（%s）" % Meta.weapon)
	check(Meta.gold == 400, "换装不扣钱（剩 %d）" % Meta.gold)
	check(Meta.equip_gear("weapon", "katana"), "再换回 KATANA")
	check(not Meta.equip_gear("weapon", "golden_sword"), "没进货的装备不能装备")

	# 出售：默认装备与身上最后一件不能卖，其余按买入价一半回收
	check(not Meta.sell_gear("weapon", "rusty_sword"), "默认武器不能出售")
	check(not Meta.sell_gear("weapon", "katana"), "身上最后一件武器不能出售")
	var sell_price := Meta.gear_sell_price("weapon", "knight_sword")
	check(sell_price == 60, "出售价是买入价的一半（%d）" % sell_price)
	var gold_before_sell := Meta.gold
	check(Meta.sell_gear("weapon", "knight_sword"), "仓库里的备用武器可以出售")
	check(Meta.owned_count("weapon", "knight_sword") == 0, "出售后仓库数量减少")
	check(Meta.gold == gold_before_sell + sell_price, "出售获得金币（%d）" % Meta.gold)

	# 仓库容量：默认 100，可付费扩容，满仓拒绝新装备
	Meta.stash_capacity = Meta.STASH_BASE_CAPACITY
	check(Meta.stash_capacity == 100, "仓库默认 100 格")
	Meta.gold = 1000
	var stash_cost := Meta.next_stash_cost()
	check(Meta.upgrade_stash(), "金币足够时扩建仓库")
	check(Meta.stash_capacity == 120, "仓库扩容 +20 格（%d）" % Meta.stash_capacity)
	check(Meta.gold == 1000 - stash_cost, "仓库扩容扣款正确（剩 %d）" % Meta.gold)
	Meta.stash_capacity = Meta.stash_used()
	check(not Meta.buy_gear("weapon", "golden_sword"), "仓库满时不能再买装备")
	Meta.stash_capacity = 120

	# 面板开关
	menu._refresh_shop()
	menu._open_shop()
	check(menu._shop_panel.visible, "打开商店面板")
	menu._close_shop()
	check(menu._shop_panel.visible == false, "关闭商店面板")

	menu._open_stash()
	check(menu._stash_panel.visible, "打开仓库面板")
	check(menu._stash_box.get_child_count() > 0, "仓库列出装备")
	menu._close_stash()
	check(menu._stash_panel.visible == false, "关闭仓库面板")

	# 设置：音量滑块 + 中英文词条
	menu._open_settings()
	check(menu._settings_panel.visible, "打开设置面板")
	check(menu._quit_button == null, "标题菜单的设置里不重复放退出按钮")
	check(menu._volume_slider != null, "设置里有音量滑块")
	menu._volume_slider.value = 35.0 if Meta.volume != 35 else 34.0
	menu._volume_slider.value = 35.0
	await get_tree().process_frame
	check(Meta.volume == 35, "音量写入设置（%d）" % Meta.volume)
	check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.35)) < 0.2, "音量作用到 Master 总线")
	Loc.language = "zh"
	check(Loc.t("settings_title") == "设置", "中文词条可用")
	check(Loc.t("menu_title") == "地牢撤离", "中文标题可用")
	Loc.language = "en"
	check(Loc.t("settings_title") == "SETTINGS", "英文词条可用")
	menu._close_settings()
	check(menu._settings_panel.visible == false, "关闭设置面板")

	# 大厅 UI 层：只构建面板，供可走动的 hall 复用
	var hall_ui = load("res://scenes/hall_ui.tscn").instantiate()
	add_child(hall_ui)
	await get_tree().process_frame
	check(hall_ui.ui_only, "hall_ui 处于纯 UI 模式")
	check(hall_ui._shop_panel != null and hall_ui._stash_panel != null, "大厅 UI 内置仓库与商店面板")
	hall_ui.open_shop("upgrades")
	check(hall_ui._shop_panel.visible and hall_ui._shop_scope == "upgrades", "铁匠面板只展示升级")
	hall_ui.close_all()
	hall_ui.queue_free()

	# 装备与升级作用到玩家
	var main = load("res://scenes/main.tscn").instantiate()
	main.auto_return = false
	add_child(main)
	await get_tree().create_timer(0.2).timeout
	check(main.player.max_hp == 10, "生命升级 + 护甲作用到玩家（%d）" % main.player.max_hp)
	check(main.player.damage == 3, "武器伤害作用到玩家（%d）" % main.player.damage)
	check(main.bag.is_empty(), "进图时背包为空")

	main.queue_free()
	menu.queue_free()
	await get_tree().process_frame

	_restore()
	print("---- %d failure(s) ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _snapshot() -> void:
	_saved = {
		"gold": Meta.gold,
		"raids": Meta.raids,
		"best_haul": Meta.best_haul,
		"hero": Meta.selected_hero,
		"weapon": Meta.weapon,
		"armor": Meta.armor,
		"levels": Meta._levels.duplicate(),
		"weapons": Meta.owned_weapons.duplicate(),
		"armors": Meta.owned_armors.duplicate(),
		"last_result": Meta.last_result,
		"volume": Meta.volume,
		"language": Meta.language,
		"stash_capacity": Meta.stash_capacity,
	}


func _restore() -> void:
	Meta.gold = int(_saved.gold)
	Meta.raids = int(_saved.raids)
	Meta.best_haul = int(_saved.best_haul)
	Meta.selected_hero = str(_saved.hero)
	Meta.weapon = str(_saved.weapon)
	Meta.armor = str(_saved.armor)
	Meta._levels = _saved.levels
	Meta.owned_weapons = _saved.weapons
	Meta.owned_armors = _saved.armors
	Meta.last_result = str(_saved.last_result)
	Meta.volume = int(_saved.volume)
	Meta.language = str(_saved.language)
	Meta.stash_capacity = int(_saved.stash_capacity)
	Meta.apply_audio()
	Meta.save_data()


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		print("FAIL  ", message)
