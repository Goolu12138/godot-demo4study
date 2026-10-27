extends Node2D
class_name Dungeon
## 一间地牢房间：地板/墙壁瓦片、碰撞、出口门、宝箱、装饰物。
## 每次换房间都重新生成，坐标全部以 16px 网格为单位。

const CELL := 16
## 顶墙做成两格厚，门（32x32）才能完整嵌进墙里。
const TOP_WALL_ROWS := 2
const SEARCH_RANGE := 30.0

var room := Vector2i(26, 16)
var floor_layer: TileMapLayer
var wall_layer: TileMapLayer
var door_sprite: Sprite2D
var chest_sprite: AnimatedSprite2D

var _rng := RandomNumberGenerator.new()
var _spawn := Vector2.ZERO
var _door_cell := Vector2i.ZERO
var _door_pos := Vector2.ZERO
var _chest_pos := Vector2.ZERO
var _chest_open := false
var _door_open := false
var _occupied: Dictionary = {}
## 可搜索容器：{sprite, pos, kind, rolls, opened}
var _searchables: Array[Dictionary] = []


func generate(seed_value: int, _depth: int) -> void:
	_clear()
	_rng.seed = seed_value
	_occupied.clear()
	_chest_open = false
	_door_open = false

	var w := room.x * CELL
	var h := room.y * CELL
	_spawn = Vector2(2.5 * CELL, h * 0.5)
	var door_x := int(room.x * 0.5) - 1
	_door_cell = Vector2i(door_x, 0)
	_door_pos = Vector2((door_x + 1) * CELL, CELL)

	_build_layers()
	_paint_floor()
	_paint_walls()
	_build_collision(w, h)
	_place_door()
	_place_chest()
	_place_props()


func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	floor_layer = null
	wall_layer = null
	door_sprite = null
	chest_sprite = null
	_searchables.clear()


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
	for y in range(TOP_WALL_ROWS, room.y - 1):
		for x in range(1, room.x - 1):
			# 大面积保持统一石材，只偶尔出现裂纹/磨损变体，避免地面过于嘈杂。
			var variant := 1
			if _rng.randf() < 0.08:
				variant = _rng.randi_range(2, 8)
			floor_layer.set_cell(Vector2i(x, y), 0, Game.tile_coord("floor_%d" % variant))


func _paint_walls() -> void:
	for y in room.y:
		for x in room.x:
			var is_border := x == 0 or y == 0 or x == room.x - 1 or y == room.y - 1 or y == 1
			if not is_border:
				continue
			var tile := "wall_mid"
			if y == 0:
				if x == 0:
					tile = "wall_top_left"
				elif x == room.x - 1:
					tile = "wall_top_right"
				else:
					tile = "wall_top_mid"
					# 顶墙偶尔挂一面旗帜，给空旷的墙面加点信息。
					var roll := _rng.randf()
					if roll < 0.10:
						tile = "wall_banner_red"
					elif roll < 0.20:
						tile = "wall_banner_blue"
			elif _rng.randf() < 0.05:
				tile = "wall_hole_1"
			wall_layer.set_cell(Vector2i(x, y), 0, Game.tile_coord(tile))


# ---------------------------------------------------------------- 碰撞

func _build_collision(w: int, h: int) -> void:
	var body := StaticBody2D.new()
	body.name = "WallsBody"
	body.collision_layer = 4
	body.collision_mask = 0
	add_child(body)

	_add_wall_rect(body, Vector2(w * 0.5, CELL), Vector2(w, CELL * TOP_WALL_ROWS))
	_add_wall_rect(body, Vector2(w * 0.5, h - CELL * 0.5), Vector2(w, CELL))
	_add_wall_rect(body, Vector2(CELL * 0.5, h * 0.5), Vector2(CELL, h))
	_add_wall_rect(body, Vector2(w - CELL * 0.5, h * 0.5), Vector2(CELL, h))


func _add_wall_rect(body: StaticBody2D, center: Vector2, size: Vector2) -> void:
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	shape.position = center
	body.add_child(shape)


# ---------------------------------------------------------------- 门与宝箱

func _place_door() -> void:
	# 挖出 2x2 的墙洞，把 32x32 的门完整嵌进顶墙。
	for dx in 2:
		for dy in TOP_WALL_ROWS:
			wall_layer.erase_cell(Vector2i(_door_cell.x + dx, dy))

	door_sprite = Sprite2D.new()
	door_sprite.name = "Door"
	door_sprite.texture = Game.tex("doors_leaf_closed")
	door_sprite.position = _door_pos
	door_sprite.z_index = -5
	add_child(door_sprite)


func _place_chest() -> void:
	var cell := Vector2i(_rng.randi_range(3, room.x - 5), _rng.randi_range(TOP_WALL_ROWS + 1, room.y - 4))
	if _occupied.has(cell):
		cell = Vector2i(4, 4)
	_occupied[cell] = true

	chest_sprite = AnimatedSprite2D.new()
	chest_sprite.name = "Chest"
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


func _place_props() -> void:
	# 顶墙前立几根石柱，增加纵深和遮挡感。
	var column_count := _rng.randi_range(2, 3)
	var column_x := 4
	for i in column_count:
		column_x += _rng.randi_range(5, 7)
		if column_x > room.x - 4:
			break
		var column_cell := Vector2i(column_x, TOP_WALL_ROWS)
		if _occupied.has(column_cell):
			continue
		_occupied[column_cell] = true
		var column := Sprite2D.new()
		column.name = "Column%d" % i
		column.texture = Game.tex("column")
		column.position = _cell_center(column_cell) - Vector2(0, 22)
		column.z_index = -1
		add_child(column)

	var crate_count := _rng.randi_range(3, 6)
	for i in crate_count:
		var cell := Vector2i(_rng.randi_range(2, room.x - 3), _rng.randi_range(2, room.y - 3))
		if _occupied.has(cell):
			continue
		if _cell_center(cell).distance_to(_spawn) < 96.0:
			continue
		_occupied[cell] = true
		var crate := Sprite2D.new()
		crate.name = "Crate%d" % i
		crate.texture = Game.tex("crate")
		crate.position = _cell_center(cell) - Vector2(0, 4)
		crate.z_index = -1
		add_child(crate)
		_register_searchable(crate, "crate", 1)


## 大厅等非战斗场景用：清掉随机木箱，避免和仓库大箱子挤在一起。
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

func spawn_point() -> Vector2:
	return _spawn


func room_pixel_size() -> Vector2:
	return Vector2(room) * CELL


func is_door_open() -> bool:
	return _door_open


func open_door() -> void:
	if _door_open:
		return
	_door_open = true
	door_sprite.texture = Game.tex("doors_leaf_open")
	var tween := create_tween()
	tween.tween_property(door_sprite, "modulate", Color(1.4, 1.4, 1.2, 1.0), 0.15)
	tween.tween_property(door_sprite, "modulate", Color.WHITE, 0.35)


func at_door(world_pos: Vector2) -> bool:
	return _door_open and world_pos.distance_to(_door_pos) < 36.0


func can_open_chest(world_pos: Vector2) -> bool:
	return not _chest_open and world_pos.distance_to(_chest_pos) < SEARCH_RANGE


func is_chest_open() -> bool:
	return _chest_open


func door_point() -> Vector2:
	return _door_pos


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


## 身边是否有还没搜过的容器。
func can_search(world_pos: Vector2) -> bool:
	return _nearest_searchable(world_pos) >= 0


## 还没搜过的容器数量。测试用它验证“一个容器只能搜一次”，不会被旁边的木箱干扰。
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


## 搜最近的容器，返回 {found, kind, rolls, pos}。一个容器只能搜一次。
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
		chest_sprite.play("default")
	else:
		sprite.modulate = Color(0.55, 0.5, 0.45, 1.0)
		var tween := create_tween()
		tween.tween_property(sprite, "scale", Vector2(1.12, 0.88), 0.08)
		tween.tween_property(sprite, "scale", Vector2.ONE, 0.14)
	return {"found": true, "kind": entry.kind, "rolls": int(entry.rolls), "pos": entry.pos}


func random_floor_point(min_from_spawn := 0.0, margin := 2) -> Vector2:
	for i in 200:
		var cx := _rng.randi_range(margin, room.x - margin - 1)
		var cy := _rng.randi_range(margin, room.y - margin - 1)
		var key := Vector2i(cx, cy)
		if _occupied.has(key):
			continue
		var point := _cell_center(key)
		if point.distance_to(_spawn) < min_from_spawn:
			continue
		_occupied[key] = true
		return point
	return _spawn + Vector2(80.0, 0.0)


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2((cell.x + 0.5) * CELL, (cell.y + 0.9) * CELL)
