extends Node
## 三间房拼成一张大世界：地板固定、通道连通、出生点/宝箱/撤离门可达、石柱有碰撞。

const EXPECTED_FLOORS := 2034
const EXPECTED_OBSTACLES := 18

var failures := 0


func _ready() -> void:
	var dungeon := Dungeon.new()
	dungeon.room = Vector2i(120, 24)
	add_child(dungeon)
	dungeon.build_world()
	_check_world(dungeon)

	var again := Dungeon.new()
	again.room = Vector2i(120, 24)
	add_child(again)
	again.build_world()
	check(dungeon._floor == again._floor, "重建后整张地图完全一致（固定地图）")
	check(dungeon._obstacle_cells == again._obstacle_cells, "重建后石柱位置一致")
	dungeon.queue_free()
	again.queue_free()

	var hall := Dungeon.new()
	hall.room = Vector2i(30, 12)
	add_child(hall)
	hall.build_hall()
	check(hall._floor.size() == 28 * 9, "大厅保持矩形（%d 格）" % hall._floor.size())
	check(hall.get_node_or_null("ObstaclesBody") == null, "大厅不生成障碍物")
	check(_reachable(hall, Vector2i(2, 6), Vector2i(int(hall.door_point().x / 16), 2)), "大厅出生点能走到大门")
	hall.queue_free()

	await get_tree().process_frame
	print("---- %d failure(s) ----" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_world(dungeon) -> void:
	var spawn_cell: Vector2i = dungeon._spawn_cell
	check(dungeon._floor.size() == EXPECTED_FLOORS,
		"大地图地板格数固定（%d）" % dungeon._floor.size())
	check(dungeon._is_floor(spawn_cell), "出生点是地板")

	check(not dungeon.has_extraction_ladder(), "开局没有撤离点")
	check(dungeon.spawn_extraction_ladder(), "能刷新出撤离梯")
	check(dungeon.extraction_count() == 1, "刷新后有一个撤离梯")

	var ladder_cell: Vector2i = dungeon.extraction_cell()
	check(dungeon._is_floor(ladder_cell), "撤离梯在地板上")
	check(_reachable(dungeon, spawn_cell, ladder_cell), "从出生点能走到撤离梯")
	check(not dungeon._obstacle_cells.has(ladder_cell), "撤离梯不和石柱重叠")
	var overlaps_item := false
	for entry in dungeon._searchables:
		if Vector2i(int(entry.pos.x / 16), int(entry.pos.y / 16)) == ladder_cell:
			overlaps_item = true
	if overlaps_item:
		check(false, "撤离梯不和宝箱/木箱重叠")
	else:
		check(true, "撤离梯不和宝箱/木箱重叠")

	for i in 4:
		dungeon.spawn_extraction_ladder()
	check(dungeon.extraction_count() == 5, "最多刷出 5 个撤离梯（%d）" % dungeon.extraction_count())
	check(not dungeon.spawn_extraction_ladder(), "超过 5 个后不再刷新")
	var cells := {}
	for ladder in dungeon._extraction_ladders:
		cells[ladder.cell] = true
	check(cells.size() == 5, "5 个撤离梯位置互不重复")

	# 三间房之间的通道必须能走通
	for cell in [Vector2i(39, 11), Vector2i(40, 12), Vector2i(79, 11), Vector2i(80, 12)]:
		check(dungeon._is_floor(cell), "房间通道是地板 %s" % str(cell))

	var chests: Array = []
	for entry in dungeon._searchables:
		if entry.kind == "chest":
			chests.append(entry)
	check(chests.size() == 3, "三间房各有一个宝箱（%d）" % chests.size())
	for entry in chests:
		var cell := Vector2i(int(entry.pos.x / 16), int(entry.pos.y / 16))
		check(dungeon._is_floor(cell), "宝箱在地板上 %s" % str(cell))
		check(_reachable(dungeon, spawn_cell, cell), "宝箱可达 %s" % str(cell))

	check(dungeon._passage_doors.size() == 2, "两间房之间各有一扇木门")
	check(dungeon._switches.size() == 4, "每扇门两侧各一个开关")
	var door0: Dictionary = dungeon._passage_doors[0]
	var shape0: CollisionShape2D = door0.shape
	check(not bool(door0.open) and not shape0.disabled, "初始门关闭且有实体碰撞")
	check(dungeon.switch_near(dungeon._switches[0].pos) == 0, "开关能对应到木门")
	dungeon.toggle_door(0)
	check(bool(dungeon._passage_doors[0].open) and shape0.disabled, "开门后碰撞关闭，可以通过")
	dungeon.toggle_door(0)
	check(not bool(dungeon._passage_doors[0].open) and not shape0.disabled, "关门后碰撞恢复，不能通过")

	check(dungeon._obstacle_cells.size() == EXPECTED_OBSTACLES,
		"固定 18 根石柱（%d）" % dungeon._obstacle_cells.size())
	var obstacle_body: Node = dungeon.get_node_or_null("ObstaclesBody")
	check(obstacle_body != null and obstacle_body.get_child_count() == dungeon._obstacle_cells.size(),
		"每个石柱都有碰撞体")
	for cell in dungeon._obstacle_cells:
		check(dungeon._is_floor(cell), "石柱在地板上 %s" % str(cell))


func _reachable(dungeon, from: Vector2i, to: Vector2i) -> bool:
	var queue: Array[Vector2i] = [from]
	var seen := {from: true}
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		if cell == to:
			return true
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if seen.has(next) or not dungeon._is_floor(next):
				continue
			if dungeon._obstacle_cells.has(next):
				continue
			seen[next] = true
			queue.append(next)
	return false


func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS  ", message)
	else:
		failures += 1
		print("FAIL  ", message)
