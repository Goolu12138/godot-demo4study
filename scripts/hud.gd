extends CanvasLayer
class_name GameHud
## 屏幕 UI：血量、携带战利品、背包占用、层数（RAID）、剩余敌人、倒计时、提示、
## 受击闪红、转场淡入淡出、局内背包面板，以及撤离/死亡共用的结算面板。

signal bag_drop(index: int)

const BAG_CAPACITY := 6

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
@onready var bag_slots: GridContainer = $Root/Bag/Panel/Box/Slots

var _message_tween: Tween
var _fade_tween: Tween
var _loot_count := 0
var _loot_value := 0
var _bag_count := 0
var _bag_max := BAG_CAPACITY


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
	($Root/Bag/Panel/Box/Title as Label).text = Loc.t("backpack")
	($Root/Bag/Panel/Box/Hint as Label).text = Loc.t("bag_hint")
	_style_bag_panel()
	set_loot(0, 0)
	set_bag(0, BAG_CAPACITY)
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


## 背包只装装备，容量固定。
func set_bag(count: int, capacity: int) -> void:
	_bag_count = count
	_bag_max = capacity
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


## items 是 main.bag（装备字典数组）。点哪一格就丢掉哪一格。
func open_bag(items: Array) -> void:
	for child in bag_slots.get_children():
		bag_slots.remove_child(child)
		child.queue_free()
	for i in BAG_CAPACITY:
		bag_slots.add_child(_make_bag_slot(i, items[i] if i < items.size() else {}))
	bag_panel.visible = true


func close_bag() -> void:
	bag_panel.visible = false


func _make_bag_slot(index: int, item: Dictionary) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(100, 56)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 8)
	if item.is_empty():
		button.text = Loc.t("empty")
		button.disabled = true
		button.add_theme_color_override("font_disabled_color", Color(0.4, 0.36, 0.42, 1))
		return button

	button.pressed.connect(_on_bag_slot.bind(index))
	var icon := TextureRect.new()
	icon.texture = Game.tex(str(item.tex))
	icon.position = Vector2(38, 3)
	icon.size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)

	var title := Label.new()
	title.text = str(item.name)
	title.position = Vector2(0, 29)
	title.size = Vector2(100, 12)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 7)
	title.add_theme_color_override("font_color", Color("#f3e3c3"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(title)

	var bonus := Label.new()
	bonus.text = str(item.bonus_text)
	bonus.position = Vector2(0, 41)
	bonus.size = Vector2(100, 12)
	bonus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bonus.add_theme_font_size_override("font_size", 7)
	bonus.add_theme_color_override("font_color", Color("#8fd18a"))
	bonus.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(bonus)
	return button


func _on_bag_slot(index: int) -> void:
	bag_drop.emit(index)


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
