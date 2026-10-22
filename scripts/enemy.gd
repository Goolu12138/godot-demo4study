extends CharacterBody2D
class_name Enemy
## 敌人：追逐玩家、彼此分离、接触伤害、受击击退与死亡掉落。
## 具体数值由 main.gd 在生成时通过 kind / tier 决定。

signal died(enemy: Node)

const TYPES := {
	"goblin": {"hp": 2, "speed": 56.0, "damage": 1},
	"skelet": {"hp": 3, "speed": 44.0, "damage": 1},
	"chort": {"hp": 5, "speed": 34.0, "damage": 1},
	"ogre": {"hp": 9, "speed": 27.0, "damage": 2},
}

var kind := "goblin"
var tier := 1
var hp := 2
var max_hp := 2
var speed := 50.0
var damage := 1
var dead := false
## 保持 Variant（未标注类型），避免与 Player 类形成循环依赖。
var player

var _attack_cd := 0.0
var _knockback := Vector2.ZERO
var _flash := 0.0
var _sprite_height := 16.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var health_bar: Node2D = $HealthBar
@onready var fill: ColorRect = $HealthBar/Fill


func _ready() -> void:
	add_to_group("enemies")
	var config: Dictionary = TYPES.get(kind, TYPES["goblin"])
	max_hp = int(config.hp) + int((tier - 1) / 2.0)
	hp = max_hp
	speed = float(config.speed) + tier * 1.5
	damage = int(config.damage)

	sprite.sprite_frames = Game.frames(kind)
	sprite.play("idle")
	_sprite_height = sprite.sprite_frames.get_frame_texture("idle", 0).get_height()
	sprite.position.y = -_sprite_height * 0.5
	health_bar.position.y = -_sprite_height - 8.0
	fill.size = Vector2(18.0, 3.0)
	health_bar.visible = false


func _physics_process(delta: float) -> void:
	if dead or player == null:
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_flash = maxf(0.0, _flash - delta)

	var to_player: Vector2 = player.global_position - global_position
	var distance := to_player.length()
	var direction := to_player / maxf(distance, 0.001)

	var separation := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector2 = global_position - other.global_position
		var length := away.length()
		if length < 20.0 and length > 0.01:
			separation += away / length * (20.0 - length) * 0.5

	velocity = direction * speed + separation * 6.0 + _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()

	sprite.flip_h = direction.x < -0.05
	if sprite.animation != "run":
		sprite.play("run")
	sprite.modulate = Color(1.0, 0.45, 0.45) if _flash > 0.0 else Color.WHITE

	if distance < 17.0 and _attack_cd <= 0.0:
		_attack_cd = 0.9
		player.take_damage(damage, global_position)
		_knockback = -direction * 70.0


func take_damage(amount: int, from: Vector2) -> void:
	if dead:
		return
	hp -= amount
	_flash = 0.12
	_knockback = (global_position - from).normalized() * 170.0
	health_bar.visible = true
	fill.size.x = 18.0 * clampf(float(hp) / float(max_hp), 0.0, 1.0)
	if hp <= 0:
		_die()


func _die() -> void:
	dead = true
	collision_layer = 0
	collision_mask = 0
	health_bar.visible = false
	sprite.modulate = Color.WHITE
	died.emit(self)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(sprite, "scale", Vector2(1.35, 0.55), 0.3)
	tween.tween_callback(queue_free)
