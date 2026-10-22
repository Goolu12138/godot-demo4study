extends Node
## 无头冒烟测试：驱动主场景跑一遍核心循环。
## 运行：godot --headless --path . res://tests/smoke_test.tscn

var main: Node
var failures := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(0.25).timeout
	await _run()
	print("---- %d failure(s) ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	check(main.enemies_alive == 5, "首层生成 5 个敌人（实际 %d）" % main.enemies_alive)
	check(get_tree().get_nodes_in_group("enemies").size() == 5, "敌人已加入 enemies 组")

	var enemy: Node = get_tree().get_nodes_in_group("enemies")[0]
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
	check(main.enemies_alive == 4, "击杀敌人后计数减少（%d）" % main.enemies_alive)

	main.player.global_position = main.dungeon.chest_position()
	Input.action_press("interact")
	await get_tree().process_frame
	Input.action_release("interact")
	await get_tree().process_frame
	check(main.dungeon.is_chest_open(), "按 E 打开宝箱")
	check(main.coins == 3, "宝箱产出 3 枚金币（%d）" % main.coins)

	for leftover in get_tree().get_nodes_in_group("enemies"):
		leftover.take_damage(99, Vector2.ZERO)
	await get_tree().create_timer(0.1).timeout
	check(main.state == "cleared", "清场后进入 cleared 状态（%s）" % main.state)
	check(main.dungeon.is_door_open(), "清场后门打开")

	main.player.global_position = main.dungeon.door_point() + Vector2(0, 30)
	await get_tree().create_timer(0.8).timeout
	check(main.depth == 2, "走进门进入下一层（B%d）" % main.depth)
	check(main.enemies_alive == 6, "第二层敌人更多（%d）" % main.enemies_alive)

	main.player.invuln = 0.0
	main.player.take_damage(99, Vector2.ZERO)
	await get_tree().create_timer(0.1).timeout
	check(main.state == "dead", "血量归零后进入 dead 状态")
	check(main.player.dead, "玩家死亡标记")

	main._start_run()
	await get_tree().create_timer(0.2).timeout
	check(main.depth == 1, "重开后回到 B1")
	check(main.player.hp == main.player.max_hp, "重开后满血")
	check(main.state == "playing", "重开后恢复 playing")


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		print("FAIL  ", message)
