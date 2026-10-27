extends Node2D
## 休息大厅的可交互对象：NPC（分帧动画）或仓库大箱子（单张贴图）。
## 名字标签由 hall.gd 放在屏幕空间里统一管理，避免跟着相机缩放得过大。

@export_enum("shop", "abilities", "stash") var role := "shop"
@export var sprite_prefix := "doc"
## 非空时改用单张贴图（例如仓库大箱子），忽略 sprite_prefix。
@export var texture_name := ""
@export var sprite_scale := 1.0
@export var name_key := "npc_shop"
## 名字牌相对脚底往上的屏幕像素偏移。
@export var label_offset := -66.0

var display_name := ""
var name_label: Label = null


func _ready() -> void:
	display_name = Loc.t(name_key)

	if texture_name != "":
		var texture: Texture2D = Game.tex(texture_name)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.scale = Vector2.ONE * sprite_scale
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var texture_height := float(texture.get_height()) * sprite_scale
		sprite.position.y = -texture_height * 0.5
		add_child(sprite)
		return

	var animated := AnimatedSprite2D.new()
	animated.sprite_frames = Game.frames(sprite_prefix)
	animated.play("idle")
	animated.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var height := animated.sprite_frames.get_frame_texture("idle", 0).get_height()
	animated.position.y = -height * 0.5
	add_child(animated)
