class_name GridInventory
extends RefCounted
## 二维格子背包 / 仓库。物品是字典，必须有 w / h（横向 / 纵向格数）。
## 放置采用“先扫描、再落位”的方式，失败时不会改动物品或占用表。

var cols := 1
var rows := 1
## 每个元素：{kind, id, name, tex, w, h, x, y, ...}
var items: Array[Dictionary] = []

var _occupied := PackedByteArray()


func _init(columns := 1, row_count := 1) -> void:
	cols = maxi(1, columns)
	rows = maxi(1, row_count)
	_occupied.resize(cols * rows)
	_occupied.fill(0)


func capacity_cells() -> int:
	return cols * rows


func used_cells() -> int:
	var total := 0
	for item in items:
		total += int(item.get("w", 1)) * int(item.get("h", 1))
	return total


func free_cells() -> int:
	return capacity_cells() - used_cells()


func is_empty() -> bool:
	return items.is_empty()


func clear() -> void:
	items.clear()
	_occupied.fill(0)


## 重新载入一组带 x / y 的物品；位置无效或重叠时自动找空位。
func set_items(new_items: Array) -> void:
	clear()
	for raw in new_items:
		if not raw is Dictionary:
			continue
		var item: Dictionary = raw.duplicate(true)
		_normalize(item)
		var x := int(item.get("x", -1))
		var y := int(item.get("y", -1))
		if x >= 0 and y >= 0 and place(item, x, y):
			continue
		auto_place(item)


func place(item: Dictionary, x: int, y: int) -> bool:
	_normalize(item)
	if not can_place(int(item.w), int(item.h), x, y):
		return false
	item.x = x
	item.y = y
	_stamp(int(item.w), int(item.h), x, y, 1)
	items.append(item)
	return true


## 从左上到右下找第一个能放下的位置。
func auto_place(item: Dictionary) -> bool:
	_normalize(item)
	var w := int(item.w)
	var h := int(item.h)
	if w > cols or h > rows:
		return false
	for y in range(rows - h + 1):
		for x in range(cols - w + 1):
			if can_place(w, h, x, y):
				return place(item, x, y)
	return false


func can_place(w: int, h: int, x: int, y: int) -> bool:
	if w <= 0 or h <= 0:
		return false
	if x < 0 or y < 0 or x + w > cols or y + h > rows:
		return false
	for yy in range(y, y + h):
		var row := yy * cols
		for xx in range(x, x + w):
			if _occupied[row + xx] == 1:
				return false
	return true


func remove_at(index: int) -> Dictionary:
	if index < 0 or index >= items.size():
		return {}
	var item: Dictionary = items[index]
	_stamp(int(item.w), int(item.h), int(item.x), int(item.y), 0)
	items.remove_at(index)
	return item


## 把物品拖到 (x, y)；目标被占用时尝试和占用者交换位置。
func move_item(index: int, x: int, y: int) -> bool:
	return _move(index, x, y, true)


## 只检查能否落位，不改变物品位置（供拖拽预览）。
func can_move_item(index: int, x: int, y: int) -> bool:
	return _move(index, x, y, false)


func _move(index: int, x: int, y: int, commit: bool) -> bool:
	if index < 0 or index >= items.size():
		return false
	var item: Dictionary = items[index]
	var w := maxi(1, int(item.get("w", 1)))
	var h := maxi(1, int(item.get("h", 1)))
	var old := Vector2i(int(item.get("x", -1)), int(item.get("y", -1)))
	if old.x < 0 or old.y < 0 or old.x + w > cols or old.y + h > rows:
		return false
	if x < 0 or y < 0 or x + w > cols or y + h > rows:
		return false

	var blocker := item_index_at(x, y, index)
	_stamp(w, h, old.x, old.y, 0)

	# 目标本身是空的（或只和原来的自己重叠）。
	if can_place(w, h, x, y):
		if commit:
			item.x = x
			item.y = y
			_stamp(w, h, x, y, 1)
		else:
			_stamp(w, h, old.x, old.y, 1)
		return true

	# 目标压住了另一件物品：两件都够放时直接交换。
	if blocker < 0:
		_stamp(w, h, old.x, old.y, 1)
		return false
	var other: Dictionary = items[blocker]
	var ow := maxi(1, int(other.get("w", 1)))
	var oh := maxi(1, int(other.get("h", 1)))
	var other_old := Vector2i(int(other.get("x", -1)), int(other.get("y", -1)))
	if other_old.x < 0 or other_old.y < 0 or other_old.x + ow > cols or other_old.y + oh > rows:
		_stamp(w, h, old.x, old.y, 1)
		return false
	_stamp(ow, oh, other_old.x, other_old.y, 0)
	if can_place(w, h, x, y) and can_place(ow, oh, old.x, old.y):
		if commit:
			item.x = x
			item.y = y
			other.x = old.x
			other.y = old.y
			_stamp(w, h, x, y, 1)
			_stamp(ow, oh, old.x, old.y, 1)
		else:
			_stamp(w, h, old.x, old.y, 1)
			_stamp(ow, oh, other_old.x, other_old.y, 1)
		return true
	_stamp(ow, oh, other_old.x, other_old.y, 1)
	_stamp(w, h, old.x, old.y, 1)
	return false


## 返回鼠标格子下的物品下标；没有则 -1。
func index_at(cell_x: int, cell_y: int) -> int:
	return item_index_at(cell_x, cell_y)


func item_index_at(cell_x: int, cell_y: int, ignore_index := -1) -> int:
	for i in range(items.size() - 1, -1, -1):
		if i == ignore_index:
			continue
		var item: Dictionary = items[i]
		var x := int(item.x)
		var y := int(item.y)
		if cell_x >= x and cell_x < x + int(item.w) and cell_y >= y and cell_y < y + int(item.h):
			return i
	return -1


func _stamp(w: int, h: int, x: int, y: int, value: int) -> void:
	for yy in range(y, y + h):
		var row := yy * cols
		for xx in range(x, x + w):
			_occupied[row + xx] = value


func _normalize(item: Dictionary) -> void:
	var size = item.get("size", null)
	if typeof(size) == TYPE_VECTOR2I:
		item["w"] = int(size.x)
		item["h"] = int(size.y)
	if not item.has("w"):
		item["w"] = 1
	if not item.has("h"):
		item["h"] = 1
	item["w"] = maxi(1, int(item.w))
	item["h"] = maxi(1, int(item.h))
