extends Node
## 菜单冒烟测试：角色格、商店购买、升级是否真的作用到玩家。
## 运行：godot --headless --path . res://tests/menu_test.tscn

var failures := 0
var _saved_gold := 0
var _saved_levels := {}


func _ready() -> void:
	_saved_gold = Meta.gold
	for key in Meta.UPGRADES:
		_saved_levels[key] = Meta.upgrade_level(key)

	var menu = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame

	check(menu._hero_slots.size() == 4, "四个角色格")
	check(menu._hero_slots[0].button_pressed, "默认选中骑士")
	check(menu._hero_slots[1].button_pressed == false, "锁定角色默认未选中")

	menu._on_hero_pressed(1)
	await get_tree().process_frame
	check(menu.selected_hero == 0, "点击锁定角色不会切换选择")

	Meta.gold = 100
	menu._refresh_shop()
	check(Meta.buy("vitality"), "金币足够时购买成功")
	check(Meta.upgrade_level("vitality") == 1, "升级等级 +1")
	check(Meta.gold == 70, "金币被扣除（剩 %d）" % Meta.gold)

	menu._open_shop()
	check(menu._shop_panel.visible, "打开商店面板")
	menu._close_shop()
	check(menu._shop_panel.visible == false, "关闭商店面板")

	var main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.2).timeout
	check(main.player.max_hp == 8, "生命升级作用到玩家（%d）" % main.player.max_hp)

	main.queue_free()
	menu.queue_free()
	await get_tree().process_frame

	Meta.gold = _saved_gold
	for key in _saved_levels:
		Meta._levels[key] = _saved_levels[key]
	Meta.save_data()

	print("---- %d failure(s) ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		print("FAIL  ", message)
