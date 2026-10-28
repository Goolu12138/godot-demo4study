extends CanvasLayer
class_name GameHud
## 屏幕 UI：血量、携带战利品、背包占用、层数（RAID）、剩余敌人、倒计时、提示、
## 受击闪红、转场淡入淡出、局内背包面板，以及撤离/死亡共用的结算面板。

signal bag_drop(index: int)

@onready var hearts: HBoxContainer = $Root/Hearts
@onready var coin_icon: TextureRect = $Root/Coin/CoinIcon
@onready var coin_label: Label = $Root/Coin/CoinLabel
@onready var loot_label: Label = $Root/Loot
@onready var timer_label: Label = $Root/Timer
@onready var depth_label: Label = $Root/Depth
@onready var enemies_label: Label = $Root/Enemies
@onready var message_label: Label = $Root/Message
@onready var hint_label: Label = $Root/Hint
@onready var flash_rect: ColorRect = $Root/Flash
@onready var fade_rect: ColorRect = $Root/Fade
@onready var death: Control = $Root/Death
@onready var bag_panel: Control = $Root/Bag
@onready var bag_box: VBoxContainer = $Root/Bag/Panel/Box
@onready var bag_grid: CenterContainer = $Root/Bag/Panel/Box/Grid
@onready var bag_title: Label = $Root/Bag/Panel/Box/Title
@onready var bag_hint: Label = $Root/Bag/Panel/Box/Hint

var bag_view: GridInventoryView
var _bag_menu: PopupMenu
var _bag_menu_index := -1
var _message_tween: Tween
var _fade_tween: Tween
var _loot_count := 0
var _loot_value := 0
var _bag_count := 0
var _bag_max := 1


func _ready() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font = Game.ui_font()
	($Root as Control).theme = ui_theme
	coin_icon.texture = Game.tex("coin_anim_f0")
	fade_rect.color.a = 1.0
	death.visible = false
	bag_panel.visible = false
	depth_label.text = Loc.t("raid") % 1
	enemies_label.text = ""
	hint_label.text = Loc.t("hint_play")
	bag_title.text = Loc.t("backpack")
	($Root/Bag/Panel/Box/Hint as Label).text = Loc.t("bag_hint")
	_style_bag_panel()
	_ensure_bag_view()
	set_loot(0, 0)
	set_bag(0, 1)
	set_timer(900.0)


func _style_bag_panel() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.08, 0.97)
	style.border_color = Color("#6b4632")
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	var panel := $Root/Bag/Panel as PanelContainer
	panel.add_theme_stylebox_override("panel", style)


func set_health(hp: int, max_hp: int) -> void:
	for child in hearts.get_children():
		hearts.remove_child(child)
		child.queue_free()
	var half_hearts := int(ceil(max_hp / 2.0))
	for i in half_hearts:
		var texture_name := "ui_heart_empty"
		if hp >= (i + 1) * 2:
			texture_name = "ui_heart_full"
		elif hp == i * 2 + 1:
			texture_name = "ui_heart_half"
		var icon := TextureRect.new()
		icon.texture = Game.tex(texture_name)
		icon.custom_minimum_size = Vector2(20, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		hearts.add_child(icon)


func set_coins(amount: int) -> void:
	coin_label.text = str(amount)


## 本局贵重品：件数与估值。撤离前不会进存档。
func set_loot(count: int, value: int) -> void:
	_loot_count = count
	_loot_value = value
	_refresh_status()


## 背包占用按“格”算，不是按件数。
func set_bag(count: int, capacity: int) -> void:
	_bag_count = count
	_bag_max = maxi(1, capacity)
	_refresh_status()


func _refresh_status() -> void:
	loot_label.text = Loc.t("loot") % [_loot_count, _loot_value, _bag_count, _bag_max]


func pulse_loot() -> void:
	loot_label.modulate = Color(1.6, 1.4, 0.7, 1.0)
	var tween := create_tween()
	tween.tween_property(loot_label, "modulate", Color.WHITE, 0.25)


func set_timer(seconds: float) -> void:
	var total := int(ceil(maxf(seconds, 0.0)))
	timer_label.text = "%d:%02d" % [total / 60, total % 60]
	var color := Color("#e05a4a") if total <= 30 else Color("#f3e3c3")
	timer_label.add_theme_color_override("font_color", color)


func set_raid(level: int) -> void:
	depth_label.text = Loc.t("raid") % level


func set_enemies(count: int) -> void:
	if count < 0:
		enemies_label.text = ""
	elif count == 0:
		enemies_label.text = Loc.t("clear_hud")
	else:
		enemies_label.text = Loc.t("enemies") % count


func set_hint(text: String) -> void:
	hint_label.text = text


func message(text: String, duration := 2.0) -> void:
	message_label.text = text
	message_label.modulate.a = 1.0
	if _message_tween != null and _message_tween.is_valid():
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(duration)
	_message_tween.tween_property(message_label, "modulate:a", 0.0, 0.45)


func flash_damage() -> void:
	flash_rect.color.a = 0.32
	var tween := create_tween()
	tween.tween_property(flash_rect, "color:a", 0.0, 0.35)


func fade_to(alpha: float, duration: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", alpha, duration)


# ---------------------------------------------------------------- 背包面板

func is_bag_open() -> bool:
	return bag_panel.visible


func _ensure_bag_view() -> void:
	if bag_view != null:
		return
	bag_view = GridInventoryView.new()
	bag_view.item_right_clicked.connect(_on_bag_item_right_clicked)
	bag_view.item_hovered.connect(_on_bag_item_hovered)
	bag_view.item_moved.connect(_on_bag_item_moved)
	bag_grid.add_child(bag_view)


func _ensure_bag_menu() -> void:
	if _bag_menu != null:
		return
	_bag_menu = PopupMenu.new()
	_bag_menu.name = "BagMenu"
	_bag_menu.add_theme_font_override("font", Game.ui_font())
	_bag_menu.add_theme_font_size_override("font_size", 10)
	_bag_menu.add_theme_color_override("font_color", Color("#f3e3c3"))
	_bag_menu.add_theme_color_override("font_hover_color", Color("#1a1014"))
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.05, 0.08, 0.98)
	panel_style.border_color = Color("#6b4632")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(2)
	panel_style.content_margin_left = 8.0
	panel_style.content_margin_right = 8.0
	panel_style.content_margin_top = 6.0
	panel_style.content_margin_bottom = 6.0
	_bag_menu.add_theme_stylebox_override("panel", panel_style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color("#e8b563")
	hover_style.set_corner_radius_all(2)
	_bag_menu.add_theme_stylebox_override("hover", hover_style)
	_bag_menu.add_theme_constant_override("item_start_padding", 10)
	_bag_menu.add_theme_constant_override("item_end_padding", 10)
	_bag_menu.add_theme_constant_override("v_separation", 5)
	_bag_menu.add_item(Loc.t("discard"), 0)
	_bag_menu.id_pressed.connect(_on_bag_menu_pressed)
	$Root.add_child(_bag_menu)


## inventory 是 main.bag（带 x / y / w / h 的字典数组）；左键拖动换位，右键弹菜单。
func open_bag(inventory: GridInventory, tier := "") -> void:
	if inventory == null:
		return
	_hide_bag_menu()
	_ensure_bag_view()
	bag_view.set_inventory(inventory, 8)
	bag_hint.text = Loc.t("bag_hint")
	set_bag(inventory.used_cells(), inventory.capacity_cells())

	bag_title.text = Loc.t("backpack") if tier == "" else "%s  ·  %s" % [Loc.t("backpack"), tier]
	var panel := $Root/Bag/Panel as PanelContainer
	var panel_width := maxf(300.0, float(inventory.cols * 8 + 40))
	var panel_height := float(inventory.rows * 8 + 96)
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5
	bag_panel.visible = true


func close_bag() -> void:
	_hide_bag_menu()
	if bag_view != null:
		bag_view._cancel_interaction()
	bag_panel.visible = false


func _on_bag_item_right_clicked(index: int) -> void:
	if index < 0 or index >= bag_view.items.size():
		return
	_ensure_bag_menu()
	_bag_menu_index = index
	var view_size := Vector2i(get_viewport().get_visible_rect().size)
	var menu_size := Vector2i(_bag_menu.get_contents_minimum_size())
	var pos := Vector2i(get_viewport().get_mouse_position())
	pos.x = clampi(pos.x, 0, maxi(0, view_size.x - menu_size.x))
	pos.y = clampi(pos.y, 0, maxi(0, view_size.y - menu_size.y))
	_bag_menu.popup(Rect2i(pos, Vector2i.ZERO))


func _on_bag_menu_pressed(id: int) -> void:
	if id != 0:
		return
	var index := _bag_menu_index
	_bag_menu_index = -1
	if index >= 0 and index < bag_view.items.size():
		bag_drop.emit(index)


func _hide_bag_menu() -> void:
	if _bag_menu != null:
		_bag_menu.hide()
	_bag_menu_index = -1


func _on_bag_item_hovered(index: int) -> void:
	if index < 0 or index >= bag_view.items.size():
		bag_hint.text = Loc.t("bag_hint")
		return
	bag_hint.text = bag_view.item_summary(index) + Loc.t("bag_item_hint")


func _on_bag_item_moved(_index: int) -> void:
	bag_hint.text = Loc.t("bag_hint")


# ---------------------------------------------------------------- 结算

## 撤离成功 / 死亡 / 超时共用一块面板。
func show_end(title: String, subtitle: String, color: Color) -> void:
	close_bag()
	var title_label: Label = $Root/Death/Box/Title
	var sub_label: Label = $Root/Death/Box/Sub
	title_label.text = title
	title_label.add_theme_color_override("font_color", color)
	sub_label.text = subtitle
	death.visible = true
	death.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(death, "modulate:a", 1.0, 0.4)


func hide_end() -> void:
	death.visible = false


func show_death() -> void:
	show_end(Loc.t("death_title"), Loc.t("death_sub"), Color("#e0453c"))


func hide_death() -> void:
	hide_end()
