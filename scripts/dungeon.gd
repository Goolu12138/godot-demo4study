extends Node2D
class_name Dungeon
## 一次出击是一张由三间房拼接成的大地图（40x24 * 3 = 120x24），
## 房间之间用开放通道相连，可以来回走。怪物位置/种类随机。

const CELL := 16
const TOP_WALL_ROWS := 2
const SEARCH_RANGE := 30.0

const ROOM_SIZE := Vector2i(40, 24)
const WORLD_SIZE := Vector2i(120, 24)
const ROOM_COUNT := 3

## 三间房的固定地板/宝箱/木箱/石柱，坐标相对各自房间；拼接时逐间偏移 40 格。
const MAPS := [
	{
		"name": "entrance",
		"floors": [[1, 2, 38, 21]],
		"chest": Vector2i(20, 5),
		"crates": [Vector2i(6, 5), Vector2i(33, 5), Vector2i(9, 18),
			Vector2i(30, 17), Vector2i(16, 12), Vector2i(24, 12)],
		"obstacles": [Vector2i(8, 8), Vector2i(14, 11), Vector2i(25, 11),
			Vector2i(31, 8), Vector2i(18, 17), Vector2i(28, 16)],
	},
	{
		"name": "t_hall",
		"floors": [[1, 2, 38, 11], [13, 13, 14, 10]],
		"chest": Vector2i(20, 7),
		"crates": [Vector2i(5, 4), Vector2i(34, 4), Vector2i(16, 18),
			Vector2i(23, 18), Vector2i(16, 14), Vector2i(23, 14)],
		"obstacles": [Vector2i(7, 6), Vector2i(32, 6), Vector2i(18, 16),
			Vector2i(25, 16), Vector2i(15, 10), Vector2i(24, 10)],
	},
	{
		"name": "l_chamber",
		"floors": [[1, 2, 22, 21], [22, 10, 17, 13]],
		"chest": Vector2i(5, 4),
		"crates": [Vector2i(4, 14), Vector2i(18, 18), Vector2i(26, 14),
			Vector2i(34, 12), Vector2i(28, 19), Vector2i(35, 20)],
		"obstacles": [Vector2i(7, 7), Vector2i(12, 12), Vector2i(19, 16),
			Vector2i(27, 13), Vector2i(32, 18), Vector2i(34, 16)],
	},
]

## 房间之间的开放通道：x 位置（两格宽）、起始 y、高度。
const PASSAGES := [{"x": 39, "y": 11, "h": 2}, {"x": 79, "y": 11, "h": 2}]

var room := WORLD_SIZE
var floor_layer: TileMapLayer
var wall_layer: TileMapLayer
var door_sprite: Sprite2D
var chest_sprite: AnimatedSprite2D

var _rng := RandomNumberGenerator.new()
var _spawn := Vector2.ZERO
var _spawn_cell := Vector2i.ZERO
var _door_pos := Vector2.ZERO
var _chest_pos := Vector2.ZERO
var _chest_open := false
var _door_open := true
var _occupied: Dictionary = {}
var _obstacle_cells: Array[Vector2i] = []
var _searchables: Array[Dictionary] = []
var _floor: Dictionary = {}
## 房间之间的木门：{sprite, pos, open, shape}
var _passage_doors: Array[Dictionary] = []
## 门边的开关：{sprite, pos, door}
var _switches: Array[Dictionary] = []
## 随任务时间陆续刷新的撤离梯
const MAX_EXTRACTION_LADDERS := 5
var _extraction_ladders: Array[Dictionary] = []


## 出击：把三间固定房间横向拼成一张 120x24 的大地图。
func build_world() -> void:
	_reset()
	room = WORLD_SIZE
	_rng.randomize()

	for index in MAPS.size():
		_load_rects(MAPS[index].floors, Vector2i(index * ROOM_SIZE.x, 0))
	for passage in PASSAGES:
		_carve_passage(int(passage.x), int(passage.y), int(passage.h))

	_build_layers()
	_paint_floor()
	_paint_walls()
	_build_collision()
	_place_passage_doors()

	_spawn_cell = Vector2i(3, 12)
	_spawn = _cell_center(_spawn_cell)
	_mark_core_cells()

	for index in MAPS.size():
		var offset := Vector2i(index * ROOM_SIZE.x, 0)
		_place_chest_at(MAPS[index].chest + offset)
		for cell in MAPS[index].crates:
			_place_crate_at(cell + offset)
		_place_obstacles_at(MAPS[index].obstacles, offset)


## 休息大厅：固定矩形，只有一扇顶门。
func build_hall() -> void:
	_reset()
	room = Vector2i(30, 12)
	_load_rects([[1, 2, 28, 9]], Vector2i.ZERO)
	_build_layers()
	_paint_floor()
	_paint_walls()
	_build_collision()

	_spawn_cell = Vector2i(2, 6)
	_spawn = _cell_center(_spawn_cell)
	_place_hall_door(14)
	_mark_core_cells()


func _reset() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	floor_layer = null
	wall_layer = null
	door_sprite = null
	chest_sprite = null
	_searchables.clear()
	_floor.clear()
	_occupied.clear()
	_obstacle_cells.clear()
	_passage_doors.clear()
	_switches.clear()
	_extraction_ladders.clear()
	_chest_open = false
	_door_open = true


func _load_rects(rects: Array, offset: Vector2i) -> void:
	for rect in rects:
		var x0 := int(rect[0]) + offset.x
		var y0 := int(rect[1]) + offset.y
		var w := int(rect[2])
		var h := int(rect[3])
		for y in range(y0, y0 + h):
			for x in range(x0, x0 + w):
				_floor[Vector2i(x, y)] = true


func _carve_passage(x0: int, y0: int, height: int) -> void:
	for x in [x0, x0 + 1]:
		for y in range(y0, y0 + height):
			_floor[Vector2i(x, y)] = true


func _is_floor(cell: Vector2i) -> bool:
	return _floor.has(cell)


# ---------------------------------------------------------------- 瓦片

func _build_layers() -> void:
	floor_layer = TileMapLayer.new()
	floor_layer.name = "Floor"
	floor_layer.tile_set = Game.tileset()
	floor_layer.z_index = -20
	add_child(floor_layer)

	wall_layer = TileMapLayer.new()
	wall_layer.name = "Walls"
	wall_layer.tile_set = Game.tileset()
	wall_layer.z_index = -10
	add_child(wall_layer)


func _paint_floor() -> void:
	for cell in _floor.keys():
		var variant := 1
		if (cell.x * 37 + cell.y * 17) % 23 == 0:
			variant = 2 + (cell.x + cell.y) % 7
		floor_layer.set_cell(cell, 0, Game.tile_coord("floor_%d" % variant))


func _paint_walls() -> void:
	for y in room.y:
		for x in room.x:
			var cell := Vector2i(x, y)
			if _is_floor(cell):
				continue
			var tile := "wall_mid"
			if y == 0:
				if x == 0:
					tile = "wall_top_left"
				elif x == room.x - 1:
					tile = "wall_top_right"
				else:
					tile = "wall_top_mid"
					var roll := (x * 13 + y * 7) % 10
					if roll == 0:
						tile = "wall_banner_red"
					elif roll == 1:
						tile = "wall_banner_blue"
			wall_layer.set_cell(cell, 0, Game.tile_coord(tile))


# ---------------------------------------------------------------- 碰撞

func _build_collision() -> void:
	var body := StaticBody2D.new()
	body.name = "WallsBody"
	body.collision_layer = 4
	body.collision_mask = 0
	add_child(body)

	for y in room.y:
		var x := 0
		while x < room.x:
			if _is_floor(Vector2i(x, y)):
				x += 1
				continue
			var start := x
			while x < room.x and not _is_floor(Vector2i(x, y)):
				x += 1
			var stop := x
			_add_wall_rect(body, Vector2((start + stop) * 0.5 * CELL, y * CELL + CELL * 0.5),
				Vector2((stop - start) * CELL, CELL))


func _add_wall_rect(body: StaticBody2D, center: Vector2, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = center
	body.add_child(shape)


# ---------------------------------------------------------------- 门 / 宝箱 / 障碍

## 房间之间的木门：默认关着，带实体碰撞；门边有开关，交互后打开/关闭。
func _place_passage_doors() -> void:
	var body := StaticBody2D.new()
	body.name = "DoorBodies"
	body.collision_layer = 4
	body.collision_mask = 0
	add_child(body)

	for index in PASSAGES.size():
		var passage: Dictionary = PASSAGES[index]
		var center := Vector2((int(passage.x) + 1.0) * CELL,
			(int(passage.y) + int(passage.h) * 0.5) * CELL)

		var door := Sprite2D.new()
		door.name = "PassageDoor%d" % index
		door.texture = Game.door_texture(false)
		door.position = center
		door.rotation_degrees = 90.0
		door.z_index = -5
		add_child(door)

		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(6, 32)
		shape.shape = rect
		shape.position = center
		body.add_child(shape)

		_passage_doors.append({
			"sprite": door,
			"pos": center,
			"open": false,
			"shape": shape,
		})

		# 门两侧各一个开关，保证从任意一边都能开门。
		_add_switch(Vector2i(int(passage.x) - 2, int(passage.y) + 1), index)
		_add_switch(Vector2i(int(passage.x) + 3, int(passage.y) + 1), index)
		for dx in 2:
			for dy in int(passage.h):
				_occupied[Vector2i(int(passage.x) + dx, int(passage.y) + dy)] = true


func _add_switch(cell: Vector2i, door_index: int) -> void:
	if not _is_floor(cell):
		return
	_occupied[cell] = true
	var sprite := Sprite2D.new()
	sprite.name = "DoorSwitch%d_%d" % [door_index, _switches.size()]
	sprite.texture = Game.tex("lever_left")
	sprite.position = _cell_center(cell)
	sprite.z_index = -1
	add_child(sprite)
	_switches.append({"sprite": sprite, "pos": sprite.position, "door": door_index})


## 门开关：切换门贴图与碰撞，同时把两侧拉杆的朝向一起换掉。
func toggle_door(index: int) -> void:
	if index < 0 or index >= _passage_doors.size():
		return
	var door: Dictionary = _passage_doors[index]
	door.open = not bool(door.open)
	_passage_doors[index] = door
	var sprite: Sprite2D = door.sprite
	var shape: CollisionShape2D = door.shape
	sprite.texture = Game.door_texture(bool(door.open))
	shape.disabled = bool(door.open)
	for switch in _switches:
		if int(switch.door) != index:
			continue
		var lever: Sprite2D = switch.sprite
		lever.texture = Game.tex("lever_right" if bool(door.open) else "lever_left")


func is_passage_door_open(index: int) -> bool:
	if index < 0 or index >= _passage_doors.size():
		return true
	return bool(_passage_doors[index].open)


func door_position(index: int) -> Vector2:
	if index < 0 or index >= _passage_doors.size():
		return Vector2.ZERO
	return _passage_doors[index].pos


## 返回玩家附近开关对应的门序号，没有则 -1。
func switch_near(world_pos: Vector2) -> int:
	var best := -1
	var best_dist := 30.0
	for switch in _switches:
		var dist: float = world_pos.distance_to(switch.pos)
		if dist < best_dist:
			best_dist = dist
			best = int(switch.door)
	return best


## 撤离梯：随机刷在三个房间之一（第一间概率低，第二/第三间中等），避开所有道具。
## 刷新一个撤离梯；最多 5 个，随任务时间由 main 多次调用。
func spawn_extraction_ladder() -> bool:
	if _extraction_ladders.size() >= MAX_EXTRACTION_LADDERS:
		return false
	var room_index := _pick_extraction_room()
	var cell := _pick_extraction_cell(room_index)
	if cell.x < 0:
		return false
	_occupied[cell] = true
	var pos := _cell_center(cell)

	var sprite := Sprite2D.new()
	sprite.name = "ExtractionLadder%d" % _extraction_ladders.size()
	sprite.texture = Game.tex("floor_ladder")
	sprite.position = pos
	sprite.z_index = -1
	add_child(sprite)
	_extraction_ladders.append({"sprite": sprite, "pos": pos, "cell": cell})
	return true


## 权重 1 / 3 / 3：第一间小，第二、第三间中等。
func _pick_extraction_room() -> int:
	var roll := _rng.randi_range(0, 6)
	if roll == 0:
		return 0
	if roll <= 3:
		return 1
	return 2


func _pick_extraction_cell(room_index: int) -> Vector2i:
	var offset := room_index * ROOM_SIZE.x
	for attempt in 300:
		var cell := Vector2i(offset + _rng.randi_range(2, 37), _rng.randi_range(3, 20))
		if not _is_floor(cell) or _occupied.has(cell):
			continue
		if _cell_center(cell).distance_to(_spawn) < 120.0:
			continue
		var near_door := false
		for door in _passage_doors:
			if _cell_center(cell).distance_to(door.pos) < 56.0:
				near_door = true
				break
		if near_door:
			continue
		return cell

	# 兜底：在目标房间里找第一个没被占用的地板格。
	for y in range(3, 21):
		for x in range(offset + 2, offset + 38):
			var cell := Vector2i(x, y)
			if _is_floor(cell) and not _occupied.has(cell):
				return cell
	return Vector2i(-1, -1)


func _place_hall_door(door_x: int) -> void:
	_door_pos = Vector2((door_x + 1) * CELL, CELL)
	for dx in 2:
		for dy in TOP_WALL_ROWS:
			var cell := Vector2i(door_x + dx, dy)
			wall_layer.erase_cell(cell)
			floor_layer.set_cell(cell, 0, Game.tile_coord("floor_1"))

	# 大厅用素材包原本的正面门，不做成拱门。
	door_sprite = Sprite2D.new()
	door_sprite.name = "HallDoor"
	door_sprite.texture = Game.tex("doors_leaf_closed")
	door_sprite.position = _door_pos
	door_sprite.z_index = -5
	add_child(door_sprite)
	_door_open = true


func _mark_core_cells() -> void:
	_occupied[_spawn_cell] = true


func _place_chest_at(cell: Vector2i) -> void:
	if not _is_floor(cell):
		return
	_occupied[cell] = true

	chest_sprite = AnimatedSprite2D.new()
	chest_sprite.name = "Chest%d" % _searchables.size()
	chest_sprite.sprite_frames = Game.simple_frames(
		["chest_full_open_anim_f0", "chest_full_open_anim_f1", "chest_full_open_anim_f2"], 10.0, false)
	chest_sprite.play("default")
	chest_sprite.stop()
	chest_sprite.frame = 0
	chest_sprite.position = _cell_center(cell)
	chest_sprite.z_index = -1
	add_child(chest_sprite)
	_chest_pos = chest_sprite.position
	_register_searchable(chest_sprite, "chest", 3)


func _place_crate_at(cell: Vector2i) -> void:
	if not _is_floor(cell) or _occupied.has(cell):
		return
	_occupied[cell] = true
	var crate := Sprite2D.new()
	crate.name = "Crate%d" % _searchables.size()
	crate.texture = Game.tex("crate")
	crate.position = _cell_center(cell) - Vector2(0, 4)
	crate.z_index = -1
	add_child(crate)
	_register_searchable(crate, "crate", 1)


func _place_obstacles_at(cells: Array, offset: Vector2i) -> void:
	var body := get_node_or_null("ObstaclesBody") as StaticBody2D
	if body == null:
		body = StaticBody2D.new()
		body.name = "ObstaclesBody"
		body.collision_layer = 4
		body.collision_mask = 0
		add_child(body)

	var index := _obstacle_cells.size()
	for local in cells:
		var cell: Vector2i = local + offset
		if not _is_floor(cell) or _occupied.has(cell):
			continue
		_occupied[cell] = true
		_obstacle_cells.append(cell)

		var sprite := Sprite2D.new()
		sprite.name = "Obstacle%d" % index
		sprite.texture = Game.tex("column")
		sprite.position = _cell_center(cell) - Vector2(0, 22)
		sprite.z_index = -1
		add_child(sprite)

		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(14, 14)
		shape.shape = rect
		shape.position = Vector2((cell.x + 0.5) * CELL, (cell.y + 0.5) * CELL)
		body.add_child(shape)
		index += 1


func clear_crates() -> void:
	for child in get_children():
		if not str(child.name).begins_with("Crate"):
			continue
		for i in range(_searchables.size() - 1, -1, -1):
			if _searchables[i].sprite == child:
				_searchables.remove_at(i)
		remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------- 查询接口

func spawn_point(_side := "") -> Vector2:
	return _spawn


func room_pixel_size() -> Vector2:
	return Vector2(room) * CELL


func is_door_open() -> bool:
	return _door_open


func open_door() -> void:
	_door_open = true


## 大世界只有一个撤离门；返回 "top" 兼容旧调用，"" 表示不在门前。
func door_hit(world_pos: Vector2) -> String:
	return "top" if world_pos.distance_to(_door_pos) < 36.0 else ""


func door_distance(_side: String, world_pos: Vector2) -> float:
	return world_pos.distance_to(_door_pos)


func at_door(world_pos: Vector2) -> bool:
	return door_hit(world_pos) == "top"


func can_open_chest(world_pos: Vector2) -> bool:
	return not _chest_open and world_pos.distance_to(_chest_pos) < SEARCH_RANGE


func is_chest_open() -> bool:
	return _chest_open


func door_point() -> Vector2:
	return _door_pos


func extraction_point() -> Vector2:
	return _extraction_ladders[0].pos if not _extraction_ladders.is_empty() else Vector2.ZERO


func extraction_hit(world_pos: Vector2) -> bool:
	for ladder in _extraction_ladders:
		if world_pos.distance_to(ladder.pos) < 26.0:
			return true
	return false


func extraction_distance(world_pos: Vector2) -> float:
	var best := 1e9
	for ladder in _extraction_ladders:
		best = minf(best, world_pos.distance_to(ladder.pos))
	return best


func extraction_cell() -> Vector2i:
	return _extraction_ladders[0].cell if not _extraction_ladders.is_empty() else Vector2i(-1, -1)


func extraction_count() -> int:
	return _extraction_ladders.size()


func has_extraction_ladder() -> bool:
	return not _extraction_ladders.is_empty()


func chest_position() -> Vector2:
	return _chest_pos


# ---------------------------------------------------------------- 搜索

func _register_searchable(sprite: Node2D, kind: String, rolls: int) -> void:
	_searchables.append({
		"sprite": sprite,
		"pos": sprite.position,
		"kind": kind,
		"rolls": rolls,
		"opened": false,
	})


func can_search(world_pos: Vector2) -> bool:
	return _nearest_searchable(world_pos) >= 0


func searchable_left() -> int:
	var total := 0
	for entry in _searchables:
		if not bool(entry.opened):
			total += 1
	return total


func _nearest_searchable(world_pos: Vector2) -> int:
	var best := -1
	var best_dist := SEARCH_RANGE
	for i in _searchables.size():
		var entry: Dictionary = _searchables[i]
		if bool(entry.opened):
			continue
		var dist: float = world_pos.distance_to(entry.pos)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


func search(world_pos: Vector2) -> Dictionary:
	var index := _nearest_searchable(world_pos)
	if index < 0:
		return {"found": false}
	var entry: Dictionary = _searchables[index]
	entry.opened = true
	_searchables[index] = entry
	var sprite: Node2D = entry.sprite
	if entry.kind == "chest":
		_chest_open = true
		(sprite as AnimatedSprite2D).play("default")
	else:
		sprite.modulate = Color(0.55, 0.5, 0.45, 1.0)
		var tween := create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.12, 0.88), 0.08)
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.14)
	return {"found": true, "kind": entry.kind, "rolls": int(entry.rolls), "pos": entry.pos}


func random_floor_point(min_from_spawn := 0.0, margin := 2) -> Vector2:
	for i in 300:
		var cell := Vector2i(
			_rng.randi_range(margin, room.x - margin - 1),
			_rng.randi_range(TOP_WALL_ROWS + margin - 1, room.y - margin - 1))
		if not _is_floor(cell):
			continue
		if _occupied.has(cell):
			continue
		var point := _cell_center(cell)
		if point.distance_to(_spawn) < min_from_spawn:
			continue
		_occupied[cell] = true
		return point
	return _cell_center(Vector2i(3, 12))


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * CELL, (cell.y + 0.9) * CELL)
