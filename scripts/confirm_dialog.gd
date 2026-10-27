extends CanvasLayer
## 通用二次确认弹窗：paused 时依然能操作。
## 用法：ask(标题, 正文, 确认按钮, 取消按钮)，然后监听 confirmed / cancelled。

signal confirmed
signal cancelled

const GOLD := Color("#e8b563")
const CREAM := Color("#f3e3c3")
const DARK := Color("#140c12")

var _root: Control
var _title: Label
var _body: Label
var _yes: Button
var _no: Button


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func ask(title_text: String, body_text: String, yes_text: String, no_text: String) -> void:
	_title.text = title_text
	_body.text = body_text
	_yes.text = yes_text
	_no.text = no_text
	_root.visible = true
	_yes.grab_focus()


func close() -> void:
	if _root != null:
		_root.visible = false


## 外部（例如大厅的 ESC）取消当前确认。
func cancel() -> void:
	_on_no()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	_root.theme = _make_theme()

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", GOLD)
	_title.add_theme_color_override("font_outline_color", DARK)
	_title.add_theme_constant_override("outline_size", 5)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_body = Label.new()
	_body.custom_minimum_size = Vector2(370, 0)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body.add_theme_font_size_override("font_size", 10)
	_body.add_theme_color_override("font_color", CREAM)
	box.add_child(_body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)

	_no = Button.new()
	_no.custom_minimum_size = Vector2(0, 34)
	_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_no.focus_mode = Control.FOCUS_ALL
	_no.pressed.connect(_on_no)
	row.add_child(_no)

	_yes = Button.new()
	_yes.custom_minimum_size = Vector2(0, 34)
	_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_yes.focus_mode = Control.FOCUS_ALL
	_yes.pressed.connect(_on_yes)
	row.add_child(_yes)


func _make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font = Game.ui_font()

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#231720")
	normal.border_color = Color("#6b4632")
	normal.set_border_width_all(2)
	normal.content_margin_left = 14.0
	normal.content_margin_right = 14.0
	normal.content_margin_top = 6.0
	normal.content_margin_bottom = 6.0

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#33232d")
	hover.border_color = GOLD

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#1a1016")
	pressed.border_color = GOLD

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", CREAM)
	theme.set_color("font_hover_color", "Button", Color("#ffeec2"))
	theme.set_font_size("font_size", "Button", 14)

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.07, 0.05, 0.08, 0.97)
	panel.border_color = Color("#6b4632")
	panel.set_border_width_all(2)
	panel.content_margin_left = 18.0
	panel.content_margin_right = 18.0
	panel.content_margin_top = 16.0
	panel.content_margin_bottom = 16.0
	theme.set_stylebox("panel", "PanelContainer", panel)
	return theme


func _on_yes() -> void:
	if not is_open():
		return
	close()
	confirmed.emit()


func _on_no() -> void:
	if not is_open():
		return
	close()
	cancelled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		_on_no()
		get_viewport().set_input_as_handled()
