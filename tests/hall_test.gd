extends Node
## 休息大厅测试：角色可移动、三个 NPC 面板、出击确认、ESC 设置。
## 运行：godot --headless --path . res://tests/hall_test.tscn

var failures := 0


func _ready() -> void:
	Loc.language = "en"
	var hall = load("res://scenes/hall.tscn").instantiate()
	add_child(hall)
	await get_tree().create_timer(0.3).timeout

	check(hall.player != null, "大厅里有玩家角色")
	check(hall.player.combat_enabled == false, "大厅里只走路不挥刀")
	check(hall.npcs.size() == 4, "三个 NPC + 一个仓库箱子（%d）" % hall.npcs.size())
	check(hall.npcs[0].role == "shop" and hall.npcs[1].role == "abilities", "商人与教官")
	check(hall.npcs[2].role == "stash" and hall.npcs[2].texture_name != "", "仓库是一个大箱子")
	check(hall.npcs[3].role == "stash" and hall.npcs[3].texture_name == "", "军需官站在仓库旁")
	check(hall.ui != null and hall.confirm != null, "大厅 UI 与确认弹窗就绪")

	var start_x: float = hall.player.global_position.x
	Input.action_press("move_right")
	await get_tree().create_timer(0.3).timeout
	Input.action_release("move_right")
	check(hall.player.global_position.x > start_x + 2.0, "角色可以在大厅走动")

	hall._talk(hall.npcs[0])
	check(hall.ui._shop_panel.visible, "商人打开商店")
	check(hall.ui._shop_scope == "gear", "商人只展示装备")
	check(hall.ui._shop_title.text == "SHOP", "商人面板标题是 SHOP")
	hall.ui.close_all()
	await get_tree().create_timer(0.1).timeout
	check(hall.player.control_enabled, "关闭商店后恢复操作")

	hall._talk(hall.npcs[1])
	check(hall.ui._shop_panel.visible and hall.ui._shop_scope == "upgrades", "教官打开能力面板")
	check(hall.ui._shop_title.text == "ABILITIES", "教官面板标题是 ABILITIES")
	hall.ui.close_all()
	await get_tree().create_timer(0.1).timeout

	hall._talk(hall.npcs[2])
	check(hall.ui._stash_panel.visible, "大箱子打开仓库")
	hall.ui.close_all()
	await get_tree().create_timer(0.1).timeout

	hall._talk(hall.npcs[3])
	check(hall.ui._stash_panel.visible, "军需官也能打开仓库")
	hall.ui.close_all()
	await get_tree().create_timer(0.1).timeout

	# ESC：没有面板时打开设置，再按一次关闭
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	hall._unhandled_input(escape)
	check(hall.ui._settings_panel.visible, "Esc 打开设置")
	check(hall.ui._quit_button != null, "大厅设置里有退出游戏选项")
	hall._unhandled_input(escape)
	check(not hall.ui.any_open(), "再按 Esc 关闭设置")

	hall._ask_deploy()
	check(hall.confirm.is_open(), "靠近大门弹出出击确认")
	hall.confirm.cancel()
	await get_tree().create_timer(0.1).timeout
	check(not hall.confirm.is_open(), "取消出击后关闭确认")
	check(hall.player.control_enabled, "取消出击后恢复操作")

	hall.queue_free()
	await get_tree().process_frame
	print("---- %d failure(s) ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		print("FAIL  ", message)
