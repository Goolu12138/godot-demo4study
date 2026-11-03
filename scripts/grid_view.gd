class_name GridInventoryView
extends Control
## 格子背包 / 仓库显示控件：画格子、物品图标、悬停提示。
## 左键按住拖动可以换位；右键物品发出 item_right_clicked，由 UI 弹出丢弃菜单。

signal item_clicked(index: int)
signal item_right_clicked(index: int)
signal item_hovered(index: int)
signal item_moved(index: int)
signal item_drag_released(index: int, screen_position: Vector2)

const GRID_COLOR := Color(0.24, 0.19, 0.16, 0.9)
const GRID_MAJOR := Color(0.38, 0.29, 0.22, 0.95)
const EMPTY_COLOR := Color(0.045, 0.035, 0.045, 0.94)
const GOLD := Color("#e8b563")
const DRAG_THRESHOLD := 4.0

const KIND_COLORS := {
	"weapon": Color("#5aa9e6"),
	"armor": Color("#8fd18a"),
	"valuable": Color("#e8b563"),
}

var external_drop_test: Callable

var cols := 1
var rows := 1
var cell := 8
var items: Array[Dictionary] = []
## {"weapon:katana": true} —— 已装备的物品描金边。
var highlights := {}
## 有 inventory 才能拖放；只传 items 的只读视图不能移动。
var inventory: GridInventory = null
var _hover_index := -1
var _press_index := -1
var _press_position := Vector2.ZERO
var _grab_offset := Vector2i.ZERO
var _dragging := false
var _drag_index := -1
var _drag_cell := Vector2i.ZERO
var _drag_offset := Vector2i.ZERO
var _drag_layer: CanvasLayer
var _drag_preview: TextureRect
var _preview_offset := Vector2.ZERO


func _ready() -> void:
	# PASS：点击物品时 accept_event 拦住；滚轮 / 空白处让给父级 ScrollContainer。
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func set_grid(columns: int, row_count: int, cell_size: int, new_items: Array,
		highlight_keys := {}) -> void:
	cols = maxi(1, columns)
	rows = maxi(1, row_count)
	cell = maxi(2, cell_size)
	items = new_items
	inventory = null
	highlights = highlight_keys
	_hover_index = -1
	tooltip_text = ""
	_cancel_interaction()
	custom_minimum_size = Vector2(cols * cell, rows * cell)
	size = custom_minimum_size
	queue_redraw()


func set_inventory(inventory_ref: GridInventory, cell_size: int, highlight_keys := {}) -> void:
	set_grid(inventory_ref.cols, inventory_ref.rows, cell_size, inventory_ref.items, highlight_keys)
	inventory = inventory_ref


func index_at_position(position: Vector2) -> int:
	var cell_x := floori(position.x / float(cell))
	var cell_y := floori(position.y / float(cell))
	if cell_x < 0 or cell_y < 0 or cell_x >= cols or cell_y >= rows:
		return -1
	for i in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[i]
		var x := int(item.x)
		var y := int(item.y)
		if cell_x >= x and cell_x < x + int(item.w) \
				and cell_y >= y and cell_y < y + int(item.h):
			return i
	return -1


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, Vector2(cols * cell, rows * cell))
	draw_rect(full, EMPTY_COLOR)
	for x in range(cols + 1):
		var color := GRID_MAJOR if x % 5 == 0 else GRID_COLOR
		draw_line(Vector2(x * cell, 0), Vector2(x * cell, full.size.y), color, 1.0)
	for y in range(rows + 1):
		var color := GRID_MAJOR if y % 5 == 0 else GRID_COLOR
		draw_line(Vector2(0, y * cell), Vector2(full.size.x, y * cell), color, 1.0)

	for i in range(items.size()):
		var item: Dictionary = items[i]
		var dimmed := _dragging and i == _drag_index
		var alpha := 0.22 if dimmed else 1.0
		var rect := Rect2(
			Vector2(int(item.x) * cell + 1, int(item.y) * cell + 1),
			Vector2(int(item.w) * cell - 2, int(item.h) * cell - 2))
		var color: Color = KIND_COLORS.get(str(item.get("kind", "")), Color("#9a8478"))
		draw_rect(rect, Color(color.r, color.g, color.b, 0.24 * alpha))
		var tex_name := str(item.get("tex", ""))
		var tex := Game.tex(tex_name) if tex_name != "" else null
		if tex != null and rect.size.x > 2.0 and rect.size.y > 2.0:
			draw_texture_rect(tex, _fit_texture(rect.grow(-1.0), tex.get_size()), false,
				Color(1, 1, 1, alpha))
		draw_rect(rect, Color(color.r, color.g, color.b, alpha), false, 1.0)
		var key := "%s:%s" % [str(item.get("kind", "")), str(item.get("id", ""))]
		if highlights.has(key):
			draw_rect(rect.grow(1.0), Color(GOLD.r, GOLD.g, GOLD.b, alpha), false, 2.0)

	if _dragging:
		_draw_drag_ghost()


func _draw_drag_ghost() -> void:
	if inventory == null or _drag_index < 0 or _drag_index >= items.size():
		return
	var item: Dictionary = items[_drag_index]
	var rect := Rect2(
		Vector2(_drag_cell.x * cell + 1, _drag_cell.y * cell + 1),
		Vector2(int(item.w) * cell - 2, int(item.h) * cell - 2))
	var color: Color = KIND_COLORS.get(str(item.get("kind", "")), Color("#9a8478"))
	var valid := inventory.can_move_item(_drag_index, _drag_cell.x, _drag_cell.y)
	draw_rect(rect, Color(color.r, color.g, color.b, 0.38))
	draw_rect(rect, Color("#8fd18a") if valid else Color("#e0453c"), false, 2.0)



func _fit_texture(rect: Rect2, tex_size: Vector2) -> Rect2:
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return rect
	var factor := minf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
	var draw_size := tex_size * factor
	return Rect2(rect.position + (rect.size - draw_size) * 0.5, draw_size)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging:
			_update_drag(motion.position)
			accept_event()
			return
		if _press_index >= 0 and inventory != null \
				and (motion.position - _press_position).length() > DRAG_THRESHOLD:
			_start_drag()
			_update_drag(motion.position)
			accept_event()
			return
		_update_hover(motion.position)
		return

	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_RIGHT:
			if mouse.pressed:
				var index := index_at_position(mouse.position)
				if index >= 0:
					item_right_clicked.emit(index)
					accept_event()
			return
		if mouse.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse.pressed:
			_on_left_press(mouse.position)
			if _press_index >= 0:
				accept_event()
			return
		if _dragging:
			_finish_drag()
			accept_event()
		elif _press_index >= 0:
			var index := _press_index
			_cancel_interaction()
			item_clicked.emit(index)
			accept_event()


## 鼠标移出网格后松开左键时，_gui_input 可能收不到 release，用 _input 兜底。
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		_update_drag(get_local_mouse_position())
		_update_drag_preview()
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_LEFT and not mouse.pressed:
			_finish_drag()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_hover_index = -1
		tooltip_text = ""
		item_hovered.emit(-1)
		if not _dragging:
			mouse_default_cursor_shape = Control.CURSOR_ARROW


func _on_left_press(position: Vector2) -> void:
	_cancel_interaction()
	var index := index_at_position(position)
	if index < 0:
		return
	_press_index = index
	_press_position = position
	var item: Dictionary = items[index]
	var cell_position := _cell_at(position)
	_grab_offset = cell_position - Vector2i(int(item.x), int(item.y))
	_drag_offset = _grab_offset
	_drag_index = index
	_drag_cell = Vector2i(int(item.x), int(item.y))


func _start_drag() -> void:
	if inventory == null or _press_index < 0 or _press_index >= items.size():
		return
	_dragging = true
	_drag_index = _press_index
	_drag_offset = _grab_offset
	var item: Dictionary = items[_drag_index]
	_drag_cell = Vector2i(int(item.x), int(item.y))
	_show_drag_preview(item)
	_hover_index = -1
	tooltip_text = ""
	item_hovered.emit(-1)
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	queue_redraw()


func _update_drag(position: Vector2) -> void:
	if not _dragging or _drag_index < 0 or _drag_index >= items.size():
		return
	var raw := _cell_at(position) - _drag_offset
	_drag_cell = _clamp_drag_cell(_drag_index, raw)
	queue_redraw()


func _clamp_drag_cell(index: int, raw: Vector2i) -> Vector2i:
	if index < 0 or index >= items.size():
		return raw
	var item: Dictionary = items[index]
	var max_x := maxi(0, cols - int(item.w))
	var max_y := maxi(0, rows - int(item.h))
	return Vector2i(clampi(raw.x, 0, max_x), clampi(raw.y, 0, max_y))


func _finish_drag() -> void:
	if not _dragging:
		_cancel_interaction()
		return
	var index := _drag_index
	if external_drop_test.is_valid() and external_drop_test.call(get_global_mouse_position()):
		var released := _drag_index
		_cancel_interaction()
		item_drag_released.emit(released, get_global_mouse_position())
		return
	var target := _drag_cell
	var inv := inventory
	_cancel_interaction()
	if inv != null and index >= 0 and inv.move_item(index, target.x, target.y):
		item_moved.emit(index)
	queue_redraw()


func _cancel_interaction() -> void:
	if is_instance_valid(_drag_preview):
		_drag_preview.hide()
	queue_redraw()
	_press_index = -1
	_dragging = false
	_drag_index = -1
	_grab_offset = Vector2i.ZERO
	_drag_offset = Vector2i.ZERO
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	tooltip_text = ""


func _update_hover(position: Vector2) -> void:
	var index := index_at_position(position)
	if index != _hover_index:
		_hover_index = index
		item_hovered.emit(index)
	tooltip_text = item_summary(index)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if index >= 0 \
		else Control.CURSOR_ARROW


func _cell_at(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / float(cell)), floori(position.y / float(cell)))


func _get_tooltip(at_position: Vector2) -> String:
	return item_summary(index_at_position(at_position))


## 统一的一行物品描述，供 tooltip 和底部提示共用；装备名 / 属性按当前语言实时取。
func item_summary(index: int) -> String:
	if index < 0 or index >= items.size():
		return ""
	var item: Dictionary = items[index]
	var kind := str(item.get("kind", ""))
	var id := str(item.get("id", ""))
	var display := str(item.get("name", id))
	var detail := str(item.get("bonus_text", ""))
	if not Meta.gear_table(kind).is_empty():
		display = Loc.gear_name(id)
		var unit := Loc.t("unit_dmg") if kind in ["weapon", "ring"] else Loc.t("unit_hp")
		detail = Loc.t("gear_desc") % [int(item.get("bonus", 0)), unit]
	if kind == "backpack":
		display = Loc.t("pack_" + id)
		detail = "%d x %d" % [int(Meta.BACKPACKS[id].cols), int(Meta.BACKPACKS[id].rows)]
	if kind == "valuable" and id in ["relic", "idol"]:
		display = Loc.t("item_" + id)
		detail = Loc.t("desc_" + id)
	var text := "%s   %d×%d" % [display, int(item.get("w", 1)), int(item.get("h", 1))]
	if int(item.get("quantity", 1)) > 1:
		text += " x%d / %d" % [int(item.quantity), GridInventory.stack_limit(item)]
	if detail != "":
		text += "   ·   " + detail
	if int(item.get("value", 0)) > 0:
		text += "   ·   +%d G" % int(item.value)
	return text


# A separate canvas keeps the carried icon above panels and scroll clipping.
func _show_drag_preview(item: Dictionary) -> void:
	if not is_instance_valid(_drag_preview):
		_drag_layer = CanvasLayer.new()
		_drag_layer.layer = 100
		add_child(_drag_layer)
		_drag_preview = TextureRect.new()
		_drag_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_drag_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_drag_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_drag_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_drag_layer.add_child(_drag_preview)
	_drag_preview.texture = Game.tex(str(item.get("tex", "")))
	_drag_preview.size = Vector2(int(item.w) * cell, int(item.h) * cell)
	_preview_offset = Vector2(_grab_offset) * cell + Vector2(cell, cell) * 0.5
	_drag_preview.show()
	_update_drag_preview()


func _update_drag_preview() -> void:
	if is_instance_valid(_drag_preview):
		_drag_preview.position = get_viewport().get_mouse_position() - _preview_offset
