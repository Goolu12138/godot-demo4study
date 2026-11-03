extends CanvasLayer
class_name GameHud
## 屏幕 UI：血量、携带战利品、背包占用、层数（RAID）、剩余敌人、倒计时、提示、
## 受击闪红、转场淡入淡出、局内背包面板，以及撤离/死亡共用的结算面板。

signal bag_drop(index: int)
signal gear_equip(index: int, kind: String)
signal potion_use
signal backpack_switch
var equipment_buttons := {}
var character_preview: AnimatedSprite2D
var character_slots: Control
var quick_slots: Array[Button] = []
var bottom_slots: Array[Button] = []
var bottom_bar: HBoxContainer
var quick_bindings: Array[String] = ["", "", "", "", "", "", "", "", ""]
var potion_slot: Button

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
	_build_slots()
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
	bag_view.item_drag_released.connect(_assign_quick_slot)
	bag_view.external_drop_test = _is_quick_slot_target
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
	var cell_size := 7 if inventory.cols >= 50 else 8
	bag_view.set_inventory(inventory, cell_size)
	refresh_item_slots(inventory)
	bag_hint.text = Loc.t("bag_hint")
	set_bag(inventory.used_cells(), inventory.capacity_cells())

	bag_title.text = Loc.t("backpack") if tier == "" else "%s  ·  %s" % [Loc.t("backpack"), tier]
	var panel := $Root/Bag/Panel as PanelContainer
	var panel_width := maxf(300.0, float(inventory.cols * cell_size + 230))
	var panel_height := maxf(226.0, float(inventory.rows * cell_size + 28)) + 80.0
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5
	bag_panel.visible = true
	bottom_bar.hide()


func close_bag() -> void:
	_hide_bag_menu()
	if bag_view != null:
		bag_view._cancel_interaction()
	bag_panel.visible = false
	bottom_bar.visible = not death.visible


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
	refresh_item_slots(bag_view.inventory)
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
	bottom_bar.hide()
	death.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(death, "modulate:a", 1.0, 0.4)


func hide_end() -> void:
	death.visible = false
	bottom_bar.visible = not bag_panel.visible


func show_death() -> void:
	show_end(Loc.t("death_title"), Loc.t("death_sub"), Color("#e0453c"))


func hide_death() -> void:
	hide_end()


func _build_slots() -> void:
	var content := HBoxContainer.new()
	bag_box.add_child(content)
	bag_box.move_child(content, 1)
	character_slots = Control.new()
	character_slots.custom_minimum_size = Vector2(190, 226)
	content.add_child(character_slots)
	var right := VBoxContainer.new()
	content.add_child(right)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	right.add_child(bar)
	for i in 9:
		var button := Button.new()
		button.custom_minimum_size = Vector2(28, 28)
		button.add_theme_font_size_override("font_size", 10)
		button.pressed.connect(func(): activate_quick_slot(i))
		_style_quick_slot(button, i)
		bar.add_child(button)
		quick_slots.append(button)
	bottom_bar = HBoxContainer.new()
	bottom_bar.name = "QuickItems"
	$Root.add_child(bottom_bar)
	bottom_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom_bar.offset_left = -126
	bottom_bar.offset_right = 126
	bottom_bar.offset_top = -28
	bottom_bar.offset_bottom = 0
	bottom_bar.add_theme_constant_override("separation", 0)
	for i in 9:
		var button := Button.new()
		button.custom_minimum_size = Vector2(28, 28)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 10)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func(): activate_quick_slot(i))
		_style_quick_slot(button, i)
		bottom_bar.add_child(button)
		bottom_slots.append(button)
	bag_grid.reparent(right)
	_build_equipment_layout()


func refresh_item_slots(inventory: GridInventory) -> void:
	for kind in equipment_buttons:
		var slot: Button = equipment_buttons[kind]
		var id := Meta.equipped_id(kind)
		if kind == "backpack":
			slot.icon = Game.tex("chest_empty_open_anim_f0")
			slot.tooltip_text = Loc.t("pack_" + id) + "  %d x %d" % [Meta.bag_cols(), Meta.bag_rows()] + "\n" + Loc.t("pack_switch_hint")
		else:
			slot.icon = Game.tex(Meta.gear_texture(kind, id)) if id != "" else null
			slot.tooltip_text = Loc.t("slot_" + kind)
			if id != "":
				slot.tooltip_text += "\n" + Loc.gear_name(id) + "  +%d %s" % [Meta.gear_bonus(kind, id), Loc.t("unit_dmg") if kind in ["weapon", "ring"] else Loc.t("unit_hp")]
	var count := 0
	for item in inventory.items:
		if str(item.get("kind", "")) == "valuable" and str(item.get("id", "")) == "potion":
			count += int(item.get("quantity", 1))
	for i in 9:
		if count == 0 and quick_bindings[i] == "potion":
			quick_bindings[i] = ""
		for slot in [quick_slots[i], bottom_slots[i]]:
			slot.text = ""
			var amount := slot.get_node("Amount") as Label
			amount.text = str(count) if quick_bindings[i] == "potion" else ""
			slot.icon = Game.tex("flask_big_red") if quick_bindings[i] == "potion" else null
			slot.tooltip_text = "Drag potion here; press %d to use" % (i + 1)
			slot.disabled = quick_bindings[i] == ""


func _assign_quick_slot(index: int, position: Vector2) -> void:
	if index < 0 or index >= bag_view.items.size():
		return
	var item: Dictionary = bag_view.items[index]
	for kind in equipment_buttons:
		if (equipment_buttons[kind] as Control).get_global_rect().has_point(position):
			gear_equip.emit(index, kind)
			return
	if str(item.get("kind", "")) != "valuable" or str(item.get("id", "")) != "potion":
		return
	for i in 9:
		if quick_slots[i].get_global_rect().has_point(position):
			quick_bindings[i] = "potion"
			refresh_item_slots(bag_view.inventory)
			return


func activate_quick_slot(index: int) -> void:
	if index >= 0 and index < 9 and quick_bindings[index] == "potion":
		potion_use.emit()


func _is_quick_slot_target(position: Vector2) -> bool:
	for kind in equipment_buttons:
		if (equipment_buttons[kind] as Control).get_global_rect().has_point(position):
			return true
	for slot in quick_slots:
		if slot.get_global_rect().has_point(position):
			return true
	return false


func _style_quick_slot(button: Button, index: int) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 16)
	button.add_theme_color_override("icon_disabled_color", Color.WHITE)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#231720")
		style.border_color = Color("#6b4632")
		if state == "hover":
			style.bg_color = Color("#33232d")
			style.border_color = Color("#e8b563")
		elif state == "pressed":
			style.bg_color = Color("#141018")
			style.border_color = Color("#e8b563")
		elif state == "disabled":
			style.bg_color = Color("#1a1317")
			style.border_color = Color("#49332d")
		style.set_border_width_all(2)
		style.set_content_margin_all(3)
		button.add_theme_stylebox_override(state, style)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var key := Label.new()
	key.name = "Key"
	key.text = str(index + 1)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.position = Vector2(3, 0)
	key.add_theme_font_size_override("font_size", 8)
	key.add_theme_color_override("font_color", Color("#b89b79"))
	key.add_theme_color_override("font_outline_color", Color("#141018"))
	key.add_theme_constant_override("outline_size", 2)
	button.add_child(key)
	var amount := Label.new()
	amount.name = "Amount"
	amount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	amount.offset_right = -3
	amount.offset_bottom = -1
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	amount.add_theme_font_size_override("font_size", 8)
	amount.add_theme_color_override("font_color", Color("#f3e3c3"))
	amount.add_theme_color_override("font_outline_color", Color("#141018"))
	amount.add_theme_constant_override("outline_size", 2)
	button.add_child(amount)


func _build_equipment_layout() -> void:
	character_preview = AnimatedSprite2D.new()
	character_preview.sprite_frames = Game.frames(Meta.selected_hero)
	character_preview.play("idle")
	character_preview.position = Vector2(95, 100)
	character_preview.scale = Vector2(2.5, 2.5)
	character_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	character_slots.add_child(character_preview)
	var positions := {
		"head": Vector2(75, 0), "armor": Vector2(0, 46),
		"arms": Vector2(150, 46), "weapon": Vector2(0, 100),
		"ring": Vector2(150, 100), "legs": Vector2(75, 142),
		"boots": Vector2(75, 186), "backpack": Vector2(150, 186),
	}
	for kind in positions:
		var slot := Button.new()
		_style_quick_slot(slot, 0)
		(slot.get_node("Key") as Label).text = Loc.t("slot_" + kind)
		slot.position = positions[kind]
		slot.size = Vector2(40, 40)
		slot.custom_minimum_size = Vector2(40, 40)
		slot.tooltip_text = Loc.t("slot_" + kind)
		if kind == "backpack":
			slot.pressed.connect(func(): backpack_switch.emit())
		character_slots.add_child(slot)
		equipment_buttons[kind] = slot
