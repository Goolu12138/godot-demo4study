extends CharacterBody2D
class_name Player
## 玩家：八向移动、近战挥砍、冲刺、受击无敌与摄像机抖动。

signal health_changed(hp: int, max_hp: int)
signal died

## 休息大厅里只走路，不挥刀不冲刺。
@export var combat_enabled := true

const BASE_MAX_HP := 6
const BASE_SPEED := 92.0
const BASE_DAMAGE := 1
const ACCEL := 1100.0
const FRICTION := 1400.0
const DASH_SPEED := 340.0
const DASH_TIME := 0.16
const ATTACK_RANGE := 42.0
const ATTACK_ARC := 1.15  # 弧度，约 ±66°

var max_hp := BASE_MAX_HP
var hp := BASE_MAX_HP
var speed := BASE_SPEED
var damage := BASE_DAMAGE
var dead := false
## 撤离结算 / 死亡后关掉操作，但保留节点用于展示。
var control_enabled := true
var facing := Vector2.RIGHT
var invuln := 0.0
var attack_cd := 0.0
var attack_t := 0.0
var dash_cd := 0.0
var dash_t := 0.0
var knockback := Vector2.ZERO

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var sword_pivot: Node2D = $SwordPivot
@onready var sword: Sprite2D = $SwordPivot/Sword
@onready var camera: Camera2D = $Camera

var _trauma := 0.0


func _ready() -> void:
	max_hp = BASE_MAX_HP + Meta.upgrade_level("vitality") * 2 + Meta.armor_bonus()
	hp = max_hp
	speed = BASE_SPEED * (1.0 + 0.08 * Meta.upgrade_level("swiftness"))
	damage = BASE_DAMAGE + Meta.upgrade_level("might") + Meta.weapon_bonus()
	sprite.sprite_frames = Game.frames("knight_m")
	sprite.play("idle")
	sword.texture = Game.tex(Meta.weapon_texture())
	sword.visible = false
	health_changed.emit(hp, max_hp)


func _physics_process(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	attack_t = maxf(0.0, attack_t - delta)
	dash_cd = maxf(0.0, dash_cd - delta)
	dash_t = maxf(0.0, dash_t - delta)

	if not dead and control_enabled:
		_read_input(delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, 700.0 * delta)
		move_and_slide()

	_update_visuals()
	_update_camera(delta)


func _read_input(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input.length() > 0.1:
		facing = input.normalized()
		sprite.flip_h = facing.x < -0.05

	if combat_enabled and Input.is_action_just_pressed("attack") and attack_cd <= 0.0:
		_start_attack()
	if combat_enabled and Input.is_action_just_pressed("dash") and dash_cd <= 0.0 and dash_t <= 0.0:
		dash_t = DASH_TIME
		dash_cd = 0.65
		invuln = maxf(invuln, 0.24)
		add_trauma(0.12)

	var target := input * speed
	if dash_t > 0.0:
		target = facing * DASH_SPEED
	var accel := ACCEL if input.length() > 0.1 else FRICTION
	velocity = velocity.move_toward(target + knockback, accel * (3.0 if dash_t > 0.0 else 1.0) * delta)
	move_and_slide()
	knockback = knockback.move_toward(Vector2.ZERO, 1400.0 * delta)


func _update_visuals() -> void:
	if dead:
		return
	var moving := velocity.length() > 12.0
	if dash_t > 0.0 or moving:
		if sprite.animation != "run":
			sprite.play("run")
	else:
		if sprite.animation != "idle":
			sprite.play("idle")

	if invuln > 0.0 and dash_t <= 0.0:
		sprite.modulate.a = 0.45 + 0.55 * absf(sin(Time.get_ticks_msec() * 0.022))
	else:
		sprite.modulate.a = 1.0

	if attack_t <= 0.0:
		sword.visible = false
		return
	var progress := 1.0 - attack_t / 0.16
	sword_pivot.rotation = facing.angle() + lerpf(-0.95, 0.95, progress)
	sword.modulate.a = 1.0 - progress * 0.5


func _start_attack() -> void:
	attack_cd = 0.34
	attack_t = 0.16
	sword.visible = true
	sword_pivot.rotation = facing.angle() - 0.95
	_deal_damage()


func _deal_damage() -> void:
	var connected := false
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Enemy
		if enemy == null or enemy.dead:
			continue
		var offset: Vector2 = enemy.global_position - global_position
		if offset.length() > ATTACK_RANGE:
			continue
		if absf(facing.angle_to(offset)) > ATTACK_ARC:
			continue
		enemy.take_damage(damage, global_position)
		connected = true
	if connected:
		add_trauma(0.28)


func take_damage(amount: int, from: Vector2) -> void:
	if dead or invuln > 0.0:
		return
	hp = maxi(0, hp - amount)
	health_changed.emit(hp, max_hp)
	invuln = 0.85
	knockback = (global_position - from).normalized() * 190.0
	add_trauma(0.55)
	if hp <= 0:
		_die()


func heal(amount: int) -> void:
	if dead:
		return
	hp = mini(max_hp, hp + amount)
	health_changed.emit(hp, max_hp)


func _die() -> void:
	dead = true
	sword.visible = false
	collision_layer = 0
	collision_mask = 0
	sprite.modulate = Color(1.0, 0.4, 0.4, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "rotation", 1.35, 0.45)
	tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.45)
	died.emit()


func reset(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	knockback = Vector2.ZERO
	hp = max_hp
	dead = false
	control_enabled = true
	invuln = 1.0
	attack_cd = 0.0
	dash_cd = 0.0
	dash_t = 0.0
	_trauma = 0.0
	collision_layer = 1
	collision_mask = 4
	sprite.rotation = 0.0
	sprite.modulate = Color.WHITE
	sprite.play("idle")
	health_changed.emit(hp, max_hp)


func add_trauma(amount: float) -> void:
	_trauma = minf(1.0, _trauma + amount)


func _update_camera(delta: float) -> void:
	_trauma = maxf(0.0, _trauma - delta * 2.0)
	var shake := _trauma * _trauma
	camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 8.0 * shake
