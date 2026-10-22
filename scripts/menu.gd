extends Control
## 开始菜单：角色选取、开始游戏、商店、退出。
## 背景用同一套地牢生成器实时铺一张房间，再压暗，保证和游戏内是同一个风格。

const DUNGEON_SCENE := preload("res://scenes/dungeon.tscn")

const HEROES := [
	{"id": "knight_m", "name": "KNIGHT", "hp": 6, "speed": 92, "damage": 1, "unlocked": true,
		"blurb": "BALANCED SWORD FIGHTER"},
	{"id": "elf_f", "name": "ELF", "hp": 5, "speed": 104, "damage": 1, "unlocked": false,
		"blurb": "FAST AND FRAGILE"},
	{"id": "dwarf_m", "name": "DWARF", "hp": 8, "speed": 82, "damage": 1, "unlocked": false,
		"blurb": "TOUGH BUT SLOW"},
	{"id": "wizzard_m", "name": "WIZARD", "hp": 4, "speed": 90, "damage": 2, "unlocked": false,
		"blurb": "GLASS CANNON"},
]

const GOLD := Color("#e8b563")
const CREAM := Color("#f3e3c3")
const MUTED := Color("#9a8478")
const DARK := Color("#140c12")

var selected_hero := 0

var _hero_group := ButtonGroup.new()
var _hero_slots: Array[Button] = []
var _hero_info: Label
var _message: Label
var _shop_panel: Control
var _shop_gold: Label
var _shop_box: VBoxContainer
var _flash_tween: Tween


func _ready() -> void:
	_build_backdrop()
	theme = _build_theme()
	_build_title()
	_build_hero_panel()
	_build_main_buttons()
	_build_footer()
	_build_shop()
	_refresh_all()
	if "--menu-shot" in OS.get_cmdline_user_args():
		_capture_menu()
	if "--start" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.2).timeout
		_start_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _shop_panel != null and _shop_panel.visible:
		_close_shop()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 背景

func _build_backdrop() -> void:
	var dungeon: Dungeon = DUNGEON_SCENE.instantiate()
	dungeon.room = Vector2i(42, 24)
	dungeon.position = Vector2(-16, -4)
	add_child(dungeon)
	dungeon.generate(20261023, 1)

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
	return result


func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(2)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
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
	var title := _label("DUNGEON DEMO", 40, GOLD, 8)
	title.position = Vector2(0, 18)
	title.size = Vector2(640, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	var subtitle := _label("0x72 DUNGEON TILESET  ·  VERTICAL SLICE", 9, MUTED, 3)
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

	var header := _label("CHOOSE HERO", 12, GOLD, 4)
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

	var label := _label(str(hero.name) if hero.unlocked else "LOCKED", 8,
		CREAM if hero.unlocked else MUTED, 3)
	label.position = Vector2(0, 42)
	label.size = Vector2(120, 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(label)

	return button


func _on_hero_pressed(index: int) -> void:
	if not bool(HEROES[index].unlocked):
		_flash("LOCKED  ·  MORE HEROES COMING LATER")
		return
	selected_hero = index
	_refresh_heroes()


func _refresh_heroes() -> void:
	for i in _hero_slots.size():
		_hero_slots[i].button_pressed = i == selected_hero
	var hero: Dictionary = HEROES[selected_hero]
	var hp_bonus := Meta.upgrade_level("vitality") * 2
	var speed_bonus := int(round(hero.speed * 0.08 * Meta.upgrade_level("swiftness")))
	var damage_bonus := Meta.upgrade_level("might")
	_hero_info.text = "%s  ·  HP %d  ·  SPEED %d  ·  DMG %d\n%s" % [
		hero.name, int(hero.hp) + hp_bonus, int(hero.speed) + speed_bonus, int(hero.damage) + damage_bonus, hero.blurb]


# ---------------------------------------------------------------- 主按钮

func _build_main_buttons() -> void:
	var box := VBoxContainer.new()
	box.position = Vector2(356, 122)
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var start := _menu_button("START GAME")
	start.pressed.connect(_start_game)
	box.add_child(start)

	var shop := _menu_button("SHOP")
	shop.pressed.connect(_open_shop)
	box.add_child(shop)

	var quit := _menu_button("QUIT")
	quit.pressed.connect(_quit_game)
	box.add_child(quit)


func _menu_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(248, 46)
	button.focus_mode = Control.FOCUS_NONE
	return button


func _build_footer() -> void:
	var footer := _label("GODOT 4.7  ·  ART BY 0x72  ·  CLICK TO SELECT", 8, Color(0.55, 0.5, 0.55), 2)
	footer.position = Vector2(0, 340)
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
	panel.position = Vector2(150, 52)
	panel.custom_minimum_size = Vector2(340, 0)
	_shop_panel.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)

	var title := _label("SHOP", 18, GOLD, 5)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_shop_gold = _label("", 13, Color("#ffd166"), 4)
	_shop_gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_shop_gold)

	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 6)
	box.add_child(separator)

	_shop_box = VBoxContainer.new()
	_shop_box.add_theme_constant_override("separation", 8)
	box.add_child(_shop_box)

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0, 34)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_close_shop)
	box.add_child(close)


func _refresh_shop() -> void:
	_shop_gold.text = "GOLD %d" % Meta.gold
	for child in _shop_box.get_children():
		_shop_box.remove_child(child)
		child.queue_free()

	for key in Meta.UPGRADES:
		var definition: Dictionary = Meta.UPGRADES[key]
		var level := Meta.upgrade_level(key)
		var cost := Meta.next_cost(key)

		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 44)
		row.add_theme_constant_override("separation", 10)
		_shop_box.add_child(row)

		var texts := VBoxContainer.new()
		texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		texts.add_theme_constant_override("separation", 0)
		row.add_child(texts)

		texts.add_child(_label("%s   %d/%d" % [definition.title, level, definition.max], 11, CREAM, 3))
		texts.add_child(_label(definition.desc, 8, MUTED, 2))

		var buy := Button.new()
		buy.custom_minimum_size = Vector2(88, 34)
		buy.focus_mode = Control.FOCUS_NONE
		buy.text = "MAX" if cost < 0 else "%d G" % cost
		buy.disabled = cost < 0 or Meta.gold < cost
		buy.pressed.connect(_buy_upgrade.bind(key))
		row.add_child(buy)


func _buy_upgrade(key: String) -> void:
	if Meta.buy(key):
		_flash("PURCHASED  ·  %s" % Meta.UPGRADES[key].title, Color("#8fd18a"))
	_refresh_shop()
	_refresh_heroes()


func _open_shop() -> void:
	_shop_panel.visible = true
	_refresh_shop()


func _close_shop() -> void:
	_shop_panel.visible = false


# ---------------------------------------------------------------- 操作

func _start_game() -> void:
	Meta.selected_hero = str(HEROES[selected_hero].id)
	Meta.save_data()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _quit_game() -> void:
	get_tree().quit()


# ---------------------------------------------------------------- 工具

func _refresh_all() -> void:
	_refresh_heroes()
	_refresh_shop()


func _flash(text: String, color := Color("#e07a6a")) -> void:
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
	await get_tree().create_timer(0.4).timeout
	await _save_shot("menu.png")
	_open_shop()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("menu_shop.png")
	get_tree().quit()


func _save_shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := "res://screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/" + file_name
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("saved ", path, " ", image.get_size())
