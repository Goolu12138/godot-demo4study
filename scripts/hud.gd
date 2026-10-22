extends CanvasLayer
class_name GameHud
## 屏幕 UI：血量、金币、层数、剩余敌人、临时提示、受击闪红、转场淡入淡出、死亡界面。

@onready var hearts: HBoxContainer = $Root/Hearts
@onready var coin_icon: TextureRect = $Root/Coin/CoinIcon
@onready var coin_label: Label = $Root/Coin/CoinLabel
@onready var depth_label: Label = $Root/Depth
@onready var enemies_label: Label = $Root/Enemies
@onready var message_label: Label = $Root/Message
@onready var flash_rect: ColorRect = $Root/Flash
@onready var fade_rect: ColorRect = $Root/Fade
@onready var death: Control = $Root/Death

var _message_tween: Tween
var _fade_tween: Tween


func _ready() -> void:
	coin_icon.texture = Game.tex("coin_anim_f0")
	fade_rect.color.a = 1.0
	death.visible = false
	depth_label.text = "B1"
	enemies_label.text = ""


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


func set_depth(level: int) -> void:
	depth_label.text = "B%d" % level


func set_enemies(count: int) -> void:
	if count < 0:
		enemies_label.text = ""
	elif count == 0:
		enemies_label.text = "CLEAR"
	else:
		enemies_label.text = "ENEMIES %d" % count


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


func show_death() -> void:
	death.visible = true
	death.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(death, "modulate:a", 1.0, 0.4)


func hide_death() -> void:
	death.visible = false
