extends Control
## 标题菜单。ui_only = true 时只构建商店 / 仓库 / 设置面板，给可走动的休息大厅当 UI 层复用。
## 背景用同一套地牢生成器实时铺一张房间，再压暗，保证和游戏内是同一个风格。

const DUNGEON_SCENE := preload("res://scenes/dungeon.tscn")

const HEROES := [
	{"id": "knight_m", "key": "knight", "name": "KNIGHT", "hp": 6, "speed": 92, "damage": 1, "unlocked": true,
		"blurb": "BALANCED SWORD FIGHTER"},
	{"id": "elf_f", "key": "elf", "name": "ELF", "hp": 5, "speed": 104, "damage": 1, "unlocked": false,
		"blurb": "FAST AND FRAGILE"},
	{"id": "dwarf_m", "key": "dwarf", "name": "DWARF", "hp": 8, "speed": 82, "damage": 1, "unlocked": false,
		"blurb": "TOUGH BUT SLOW"},
	{"id": "wizzard_m", "key": "wizard", "name": "WIZARD", "hp": 4, "speed": 90, "damage": 2, "unlocked": false,
		"blurb": "GLASS CANNON"},
]

const GOLD := Color("#e8b563")
const CREAM := Color("#f3e3c3")
const MUTED := Color("#9a8478")
const DARK := Color("#141018")

## true = 只构建商店 / 仓库 / 设置面板，供可走动的休息大厅当 UI 层复用。
@export var ui_only := false

var selected_hero := 0
var _shop_scope := "all"
var _main_box: VBoxContainer

var _hero_group := ButtonGroup.new()
var _hero_slots: Array[Button] = []
var _hero_info: Label
var _message: Label
var _shop_panel: Control
var _shop_title: Label
var _shop_gold: Label
var _shop_box: VBoxContainer
var _stash_panel: Control
var _stash_box: VBoxContainer
var _stash_loadout: Label
var _settings_panel: Control
var _settings_box: VBoxContainer
var _volume_slider: HSlider
var _quit_button: Button
var _flash_tween: Tween


func _ready() -> void:
	if ui_only:
		theme = _build_theme()
		_build_shop()
		_build_stash()
		_build_settings()
		_refresh_shop()
		_refresh_stash()
		return
	# 大厅要沿用标题菜单里选好的角色。
	for i in HEROES.size():
		if str(HEROES[i].id) == Meta.selected_hero and bool(HEROES[i].unlocked):
			selected_hero = i
	_build_backdrop()
	theme = _build_theme()
	_build_title()
	_build_hero_panel()
	_build_main_buttons()
	_build_footer()
	_build_shop()
	_build_stash()
	_build_settings()
	_refresh_all()
	if "--menu-shot" in OS.get_cmdline_user_args():
		_capture_menu()
	if "--start" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.2).timeout
		_start_game()


func _unhandled_input(event: InputEvent) -> void:
	if ui_only:
		# 面板的 ESC 由大厅统一处理，避免两处抢输入。
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings_panel != null and _settings_panel.visible:
		_close_settings()
		get_viewport().set_input_as_handled()
	elif _shop_panel != null and _shop_panel.visible:
		_close_shop()
		get_viewport().set_input_as_handled()
	elif _stash_panel != null and _stash_panel.visible:
		_close_stash()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 背景

func _build_backdrop() -> void:
	var dungeon: Dungeon = DUNGEON_SCENE.instantiate()
	dungeon.build_hall()
	# 大厅只有 30x12；标题背景放大一点铺满 640x360。
	dungeon.scale = Vector2(2.2, 2.2)
	dungeon.position = Vector2(-100, -60)
	add_child(dungeon)

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.05, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)


# ---------------------------------------------------------------- 主题

func _build_theme() -> Theme:
	var result := Theme.new()
	result.set_stylebox("normal", "Button", _button_style(Color("#231720"), Color("#6b4632")))
	result.set_stylebox("hover", "Button", _button_style(Color("#33232d"), GOLD))
	result.set_stylebox("pressed", "Button", _button_style(Color("#1a1016"), GOLD))
	result.set_stylebox("disabled", "Button", _button_style(Color("#1a1317"), Color("#3b2b33")))
	result.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	result.set_color("font_color", "Button", CREAM)
	result.set_color("font_hover_color", "Button", Color("#ffeec2"))
	result.set_color("font_pressed_color", "Button", GOLD)
	result.set_color("font_disabled_color", "Button", Color("#5f4f57"))
	result.set_font_size("font_size", "Button", 16)
	result.set_stylebox("panel", "PanelContainer", _panel_style())
	result.set_color("font_color", "Label", CREAM)
	result.default_font = Game.ui_font()
	return result


func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.05, 0.08, 0.92)
	style.border_color = Color("#6b4632")
	style.set_border_width_all(2)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style


# ---------------------------------------------------------------- 标题

func _build_title() -> void:
	var title := _label(Loc.t("menu_title"), 34, GOLD, 8)
	title.position = Vector2(0, 18)
	title.size = Vector2(640, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var subtitle := _label(Loc.t("menu_sub"), 9, MUTED, 3)
	subtitle.position = Vector2(0, 72)
	subtitle.size = Vector2(640, 16)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(subtitle)


# ---------------------------------------------------------------- 角色选择

func _build_hero_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(30, 100)
	panel.custom_minimum_size = Vector2(292, 0)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var header := _label(Loc.t("choose_hero"), 12, GOLD, 4)
	box.add_child(header)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)

	for i in HEROES.size():
		var slot := _make_hero_slot(i, HEROES[i])
		_hero_slots.append(slot)
		grid.add_child(slot)

	_hero_info = _label("", 10, CREAM, 3)
	_hero_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(_hero_info)

	_message = _label("", 9, Color("#e07a6a"), 3)
	box.add_child(_message)


func _make_hero_slot(index: int, hero: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(120, 58)
	button.toggle_mode = hero.unlocked
	button.button_group = _hero_group
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_hero_pressed.bind(index))

	var portrait := TextureRect.new()
	portrait.texture = Game.tex(str(hero.id) + "_idle_anim_f0")
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.position = Vector2(37, 2)
	portrait.size = Vector2(46, 40)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not hero.unlocked:
		portrait.modulate = Color(0.16, 0.13, 0.19, 1.0)
	button.add_child(portrait)

	var label := _label(Loc.t("hero_" + str(hero.key)) if hero.unlocked else Loc.t("locked"), 8,
		CREAM if hero.unlocked else MUTED, 3)
	label.position = Vector2(0, 42)
	label.size = Vector2(120, 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)

	return button


func _on_hero_pressed(index: int) -> void:
	if not bool(HEROES[index].unlocked):
		_flash(Loc.t("locked_msg"))
		return
	selected_hero = index
	_refresh_heroes()


func _refresh_heroes() -> void:
	# ui_only 模式下没有角色面板，购买后不需要刷新它。
	if _hero_info == null:
		return
	for i in _hero_slots.size():
		_hero_slots[i].button_pressed = i == selected_hero
	var hero: Dictionary = HEROES[selected_hero]
	var hp_bonus := Meta.upgrade_level("vitality") * 2 + Meta.armor_bonus()
	var speed_bonus := int(round(hero.speed * 0.08 * Meta.upgrade_level("swiftness")))
	var damage_bonus := Meta.upgrade_level("might") + Meta.weapon_bonus()
	_hero_info.text = Loc.t("stats") % [
		Loc.t("hero_" + str(hero.key)), int(hero.hp) + hp_bonus,
		int(hero.speed) + speed_bonus, int(hero.damage) + damage_bonus,
		Loc.t("blurb_" + str(hero.key))]


# ---------------------------------------------------------------- 主按钮

func _build_main_buttons() -> void:
	_main_box = VBoxContainer.new()
	_main_box.position = Vector2(356, 112)
	_main_box.add_theme_constant_override("separation", 5)
	add_child(_main_box)

	var enter := _menu_button(Loc.t("enter_hall"))
	enter.pressed.connect(_start_game)
	_main_box.add_child(enter)

	var settings := _menu_button(Loc.t("settings"))
	settings.pressed.connect(_open_settings)
	_main_box.add_child(settings)

	var quit := _menu_button(Loc.t("quit"))
	quit.pressed.connect(_quit_game)
	_main_box.add_child(quit)


func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(248, 34)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _build_footer() -> void:
	var footer := _label(Loc.t("footer"), 8, Color(0.55, 0.5, 0.55), 2)
	footer.position = Vector2(0, 342)
	footer.size = Vector2(640, 14)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(footer)


# ---------------------------------------------------------------- 商店

func _build_shop() -> void:
	_shop_panel = Control.new()
	_shop_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shop_panel.visible = false
	_shop_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shop_panel)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.01, 0.03, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_shop_panel.add_child(shade)

	var panel := PanelContainer.new()
	panel.position = Vector2(150, 28)
	panel.custom_minimum_size = Vector2(340, 0)
	_shop_panel.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)

	var title := _label(Loc.t("shop_title"), 18, GOLD, 5)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_shop_title = title

	_shop_gold = _label("", 13, Color("#ffd166"), 4)
	_shop_gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_shop_gold)

	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 6)
	box.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_shop_box = VBoxContainer.new()
	_shop_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_shop_box)

	var close := Button.new()
	close.text = Loc.t("close")
	close.custom_minimum_size = Vector2(0, 34)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close_shop)
	box.add_child(close)


func _refresh_shop() -> void:
	_shop_title.text = Loc.t("abilities_title") if _shop_scope == "upgrades" else Loc.t("shop_title")
	_shop_gold.text = Loc.t("gold") % Meta.gold
	for child in _shop_box.get_children():
		_shop_box.remove_child(child)
		child.queue_free()

	if _shop_scope != "gear":
		_add_section(Loc.t("upgrades"))
		for key in Meta.UPGRADES:
			_add_upgrade_row(key)

		# 后续在这里接技能学习；先把入口占位。
		_add_section(Loc.t("skills"))
		_shop_box.add_child(_label(Loc.t("skills_soon"), 8, MUTED, 1))

	if _shop_scope != "upgrades":
		_add_section(Loc.t("storage"))
		_add_storage_row()

		_add_section(Loc.t("sell"))
		var sellables := 0
		for kind in ["weapon", "armor"]:
			for id in Meta.stash_counts(kind):
				_add_sell_row(kind, str(id))
				sellables += 1
		if sellables == 0:
			_shop_box.add_child(_label(Loc.t("sell_none"), 8, MUTED, 1))

		_add_section(Loc.t("weapons"))
		for id in Meta.WEAPONS:
			_add_gear_row("weapon", str(id), Meta.WEAPONS[id])

		_add_section(Loc.t("armors"))
		for id in Meta.ARMORS:
			_add_gear_row("armor", str(id), Meta.ARMORS[id])


func _add_storage_row() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 38)
	row.add_theme_constant_override("separation", 10)
	_shop_box.add_child(row)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)

	texts.add_child(_label("%s   %d" % [Loc.t("storage"), Meta.stash_capacity], 10, CREAM, 2))
	texts.add_child(_label(Loc.t("storage_desc") % Meta.STASH_STEP, 8, MUTED, 1))

	var cost := Meta.next_stash_cost()
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(88, 30)
	buy.focus_mode = Control.FOCUS_NONE
	buy.text = Loc.t("max") if cost < 0 else "%d G" % cost
	buy.disabled = cost < 0 or Meta.gold < cost
	buy.pressed.connect(_buy_storage)
	row.add_child(buy)


func _buy_storage() -> void:
	if Meta.upgrade_stash():
		_flash(Loc.t("purchased") % Loc.t("storage"), Color("#8fd18a"))
	_refresh_shop()


func _add_sell_row(kind: String, id: String) -> void:
	var count := Meta.owned_count(kind, id)
	if count <= 0:
		return
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.add_theme_constant_override("separation", 8)
	_shop_box.add_child(row)

	var icon := TextureRect.new()
	icon.texture = Game.tex(Meta.gear_texture(kind, id))
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	var suffix := "" if count <= 1 else "   x%d" % count
	texts.add_child(_label("%s%s" % [Loc.gear_name(id), suffix], 9, CREAM, 2))
	texts.add_child(_label("+%d G" % Meta.gear_sell_price(kind, id), 7, MUTED, 1))

	var sell := Button.new()
	sell.custom_minimum_size = Vector2(84, 26)
	sell.focus_mode = Control.FOCUS_NONE
	if Meta.can_sell_gear(kind, id):
		sell.text = Loc.t("sell_action")
		sell.pressed.connect(_sell_gear.bind(kind, id))
	else:
		sell.text = Loc.t("equipped")
		sell.disabled = true
	row.add_child(sell)


func _sell_gear(kind: String, id: String) -> void:
	var price := Meta.gear_sell_price(kind, id)
	if Meta.sell_gear(kind, id):
		_flash(Loc.t("sold") % price, Color("#8fd18a"))
	_refresh_shop()
	_refresh_stash()
	_refresh_heroes()


func _add_section(text: String) -> void:
	_shop_box.add_child(_label(text, 10, GOLD, 3))


func _add_upgrade_row(key: String) -> void:
	var definition: Dictionary = Meta.UPGRADES[key]
	var level := Meta.upgrade_level(key)
	var cost := Meta.next_cost(key)

	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 38)
	row.add_theme_constant_override("separation", 10)
	_shop_box.add_child(row)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)

	texts.add_child(_label("%s   %d/%d" % [Loc.t("up_" + key + "_title"), level, int(definition.max)], 10, CREAM, 2))
	texts.add_child(_label(Loc.t("up_" + key + "_desc"), 8, MUTED, 1))

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(88, 30)
	buy.focus_mode = Control.FOCUS_NONE
	buy.text = Loc.t("max") if cost < 0 else "%d G" % cost
	buy.disabled = cost < 0 or Meta.gold < cost
	buy.pressed.connect(_buy_upgrade.bind(key))
	row.add_child(buy)


func _add_gear_row(kind: String, id: String, definition: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.add_theme_constant_override("separation", 8)
	_shop_box.add_child(row)

	var icon := TextureRect.new()
	icon.texture = Game.tex(str(definition.texture))
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	texts.add_child(_label(Loc.gear_name(id), 9, CREAM, 2))
	var unit := Loc.t("unit_dmg") if kind == "weapon" else Loc.t("unit_hp")
	texts.add_child(_label(Loc.t("gear_desc") % [int(definition.bonus), unit], 7, MUTED, 1))

	var equipped: String = Meta.weapon if kind == "weapon" else Meta.armor
	var cost := int(definition.cost)
	var owned := Meta.owned_count(kind, id)

	var buy := Button.new()
	buy.custom_minimum_size = Vector2(84, 26)
	buy.focus_mode = Control.FOCUS_NONE
	if id == equipped:
		buy.text = Loc.t("equipped")
		buy.disabled = true
	elif cost <= 0:
		buy.text = Loc.t("default_gear")
		buy.disabled = true
	elif owned > 0:
		buy.text = Loc.t("owned") % owned
		buy.disabled = true
	else:
		buy.text = "%d G" % cost
		buy.disabled = Meta.gold < cost
		buy.pressed.connect(_buy_gear.bind(kind, id))
	row.add_child(buy)


func _buy_upgrade(key: String) -> void:
	if Meta.buy(key):
		_flash(Loc.t("purchased") % Loc.t("up_" + key + "_title"), Color("#8fd18a"))
	_refresh_shop()
	_refresh_heroes()


func _buy_gear(kind: String, id: String) -> void:
	if Meta.buy_gear(kind, id):
		_flash(Loc.t("stored") % Loc.gear_name(id), Color("#8fd18a"))
	else:
		_flash(Loc.t("not_enough"))
	_refresh_shop()
	_refresh_stash()
	_refresh_heroes()


func _open_shop() -> void:
	_close_stash()
	if _settings_panel != null:
		_settings_panel.visible = false
	_shop_panel.visible = true
	_refresh_shop()


## 供休息大厅调用：scope = all / gear / upgrades。
func open_shop(scope := "all") -> void:
	_shop_scope = scope
	_open_shop()


func open_stash_panel() -> void:
	_open_stash()


func open_settings_panel() -> void:
	_open_settings()


func any_open() -> bool:
	return (_shop_panel != null and _shop_panel.visible) \
		or (_stash_panel != null and _stash_panel.visible) \
		or (_settings_panel != null and _settings_panel.visible)


func close_all() -> void:
	if _shop_panel != null:
		_shop_panel.visible = false
	if _stash_panel != null:
		_stash_panel.visible = false
	if _settings_panel != null:
		_settings_panel.visible = false


func _close_shop() -> void:
	_shop_panel.visible = false


# ---------------------------------------------------------------- 仓库

func _build_stash() -> void:
	_stash_panel = Control.new()
	_stash_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stash_panel.visible = false
	_stash_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_stash_panel)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.01, 0.03, 0.8)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_stash_panel.add_child(shade)

	var panel := PanelContainer.new()
	panel.position = Vector2(150, 28)
	panel.custom_minimum_size = Vector2(340, 0)
	_stash_panel.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)

	var title := _label(Loc.t("stash_title"), 18, GOLD, 5)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_stash_loadout = _label("", 9, MUTED, 3)
	_stash_loadout.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_stash_loadout)

	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 6)
	box.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	_stash_box = VBoxContainer.new()
	_stash_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stash_box.add_theme_constant_override("separation", 6)
	scroll.add_child(_stash_box)

	var close := Button.new()
	close.text = Loc.t("close")
	close.custom_minimum_size = Vector2(0, 34)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close_stash)
	box.add_child(close)


func _refresh_stash() -> void:
	if _stash_panel == null:
		return
	_stash_loadout.text = "%s  ·  %s%s" % [Loc.gear_name(Meta.weapon), Loc.gear_name(Meta.armor),
		Loc.t("stash_slots") % [Meta.stash_used(), Meta.stash_capacity]]
	for child in _stash_box.get_children():
		_stash_box.remove_child(child)
		child.queue_free()

	_add_stash_section(Loc.t("weapons"), "weapon")
	_add_stash_section(Loc.t("armors"), "armor")


func _add_stash_section(title: String, kind: String) -> void:
	_stash_box.add_child(_label(title, 10, GOLD, 3))
	var counts := Meta.stash_counts(kind)
	var ids: Array[String] = [Meta.default_gear(kind)]
	for id in counts:
		if not ids.has(id):
			ids.append(str(id))
	ids.sort_custom(func(a, b): return Meta.gear_bonus(kind, a) > Meta.gear_bonus(kind, b))
	for id in ids:
		_add_stash_row(kind, id, int(counts.get(id, 0)))


func _add_stash_row(kind: String, id: String, looted: int) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.add_theme_constant_override("separation", 8)
	_stash_box.add_child(row)

	var icon := TextureRect.new()
	icon.texture = Game.tex(Meta.gear_texture(kind, id))
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	row.add_child(texts)
	var unit := Loc.t("unit_dmg") if kind == "weapon" else Loc.t("unit_hp")
	var count := Meta.owned_count(kind, id)
	var suffix := "" if count <= 1 else "   x%d" % count
	texts.add_child(_label("%s%s" % [Loc.gear_name(id), suffix], 9, CREAM, 2))
	var tag := "   ·   " + (Loc.t("looted") if looted > 0 else Loc.t("default_gear"))
	texts.add_child(_label(Loc.t("gear_desc") % [Meta.gear_bonus(kind, id), unit] + tag, 7, MUTED, 1))

	var equipped: String = Meta.weapon if kind == "weapon" else Meta.armor
	var button := Button.new()
	button.custom_minimum_size = Vector2(84, 26)
	button.focus_mode = Control.FOCUS_NONE
	if id == equipped:
		button.text = Loc.t("equipped")
		button.disabled = true
	else:
		button.text = Loc.t("equip")
		button.pressed.connect(_equip_gear.bind(kind, id))
	row.add_child(button)


func _equip_gear(kind: String, id: String) -> void:
	if Meta.equip_gear(kind, id):
		_flash(Loc.t("equipped_msg") % Loc.gear_name(id), Color("#8fd18a"))
	_refresh_stash()
	_refresh_shop()
	_refresh_heroes()


func _open_stash() -> void:
	_close_shop()
	if _settings_panel != null:
		_settings_panel.visible = false
	_stash_panel.visible = true
	_refresh_stash()


func _close_stash() -> void:
	if _stash_panel != null:
		_stash_panel.visible = false


# ---------------------------------------------------------------- 设置

func _build_settings() -> void:
	_settings_panel = Control.new()
	_settings_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_settings_panel.visible = false
	_settings_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_settings_panel)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.01, 0.03, 0.82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_panel.add_child(shade)

	var panel := PanelContainer.new()
	panel.position = Vector2(115, 14)
	panel.custom_minimum_size = Vector2(410, 0)
	_settings_panel.add_child(panel)

	_settings_box = VBoxContainer.new()
	_settings_box.add_theme_constant_override("separation", 4)
	panel.add_child(_settings_box)

	_refresh_settings()


func _refresh_settings() -> void:
	_quit_button = null
	for child in _settings_box.get_children():
		_settings_box.remove_child(child)
		child.queue_free()

	_settings_box.add_child(_label(Loc.t("settings_title"), 18, GOLD, 5))

	_settings_box.add_child(_label(Loc.t("volume"), 11, CREAM, 3))
	var volume_row := HBoxContainer.new()
	volume_row.add_theme_constant_override("separation", 10)
	_settings_box.add_child(volume_row)

	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.value = Meta.volume
	slider.custom_minimum_size = Vector2(300, 18)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_row.add_child(slider)
	_volume_slider = slider

	var value_label := _label("%d%%" % Meta.volume, 10, MUTED, 2)
	value_label.custom_minimum_size = Vector2(44, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	volume_row.add_child(value_label)

	slider.value_changed.connect(_on_volume_changed.bind(value_label))
	slider.drag_ended.connect(func(_changed: bool) -> void: Meta.save_data())

	var language_row := HBoxContainer.new()
	language_row.add_theme_constant_override("separation", 8)
	_settings_box.add_child(language_row)
	language_row.add_child(_label(Loc.t("language"), 11, CREAM, 3))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	language_row.add_child(spacer)

	var group := ButtonGroup.new()
	for code in ["en", "zh"]:
		var button := Button.new()
		button.text = Loc.t("lang_" + code)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = Loc.language == code
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(72, 28)
		button.pressed.connect(_on_language_pressed.bind(code))
		language_row.add_child(button)

	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 4)
	_settings_box.add_child(separator)

	_settings_box.add_child(_label(Loc.t("keybindings"), 11, GOLD, 3))
	_settings_box.add_child(_label(Loc.t("coming_soon"), 8, MUTED, 1))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 1)
	_settings_box.add_child(grid)
	for pair in [["key_move", "key_move_keys"], ["key_attack", "key_attack_keys"],
			["key_dash", "key_dash_keys"], ["key_search", "key_search_keys"],
			["key_bag", "key_bag_keys"], ["key_menu", "key_menu_keys"]]:
		grid.add_child(_label(Loc.t(str(pair[0])), 9, CREAM, 2))
		var keys := _label(Loc.t(str(pair[1])), 9, MUTED, 1)
		keys.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(keys)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	_settings_box.add_child(actions)

	# 大厅里 Esc 打开的这层设置面板顺便提供退出游戏；标题菜单本身已有 QUIT。
	if ui_only:
		_quit_button = Button.new()
		_quit_button.text = Loc.t("quit")
		_quit_button.custom_minimum_size = Vector2(0, 32)
		_quit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_quit_button.focus_mode = Control.FOCUS_NONE
		_quit_button.pressed.connect(_quit_game)
		actions.add_child(_quit_button)

	var close := Button.new()
	close.text = Loc.t("close")
	close.custom_minimum_size = Vector2(0, 32)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close_settings)
	actions.add_child(close)


func _on_volume_changed(value: float, label: Label) -> void:
	Meta.volume = int(round(value))
	Meta.apply_audio()
	label.text = "%d%%" % Meta.volume


func _on_language_pressed(code: String) -> void:
	if code == Loc.language:
		return
	Loc.set_language(code)
	get_tree().reload_current_scene()


func _open_settings() -> void:
	_close_shop()
	_close_stash()
	_settings_panel.visible = true
	_refresh_settings()


func _close_settings() -> void:
	if _settings_panel == null:
		return
	Meta.apply_audio()
	Meta.save_data()
	_settings_panel.visible = false


# ---------------------------------------------------------------- 操作

func _start_game() -> void:
	Meta.selected_hero = str(HEROES[selected_hero].id)
	Meta.save_data()
	get_tree().change_scene_to_file("res://scenes/hall.tscn")


func _quit_game() -> void:
	get_tree().quit()


# ---------------------------------------------------------------- 工具

func _refresh_all() -> void:
	_refresh_heroes()
	_refresh_shop()
	_refresh_stash()


func _flash(text: String, color := Color("#e07a6a")) -> void:
	if _message == null:
		return
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.modulate.a = 1.0
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_interval(1.6)
	_flash_tween.tween_property(_message, "modulate:a", 0.0, 0.4)


func _label(text: String, size: int, color: Color, outline := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", DARK)
		label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _capture_menu() -> void:
	var suffix := "_zh" if Loc.language == "zh" else ""
	await get_tree().create_timer(0.4).timeout
	await _save_shot("menu%s.png" % suffix)
	_open_settings()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("menu_settings%s.png" % suffix)
	_close_settings()
	get_tree().quit()


func _save_shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := "res://screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/" + file_name
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("saved ", path, " ", image.get_size())
