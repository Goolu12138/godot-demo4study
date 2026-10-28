extends CharacterBody2D
class_name Enemy
## 敌人：待机 -> 警戒 -> 追逐 -> 脱战返回。
## 具体数值由 main.gd 在生成时通过 kind / tier 决定。
##
## 仇恨规则（长度单位像素，时间单位秒；要调手感改下面这组常量）：
##   - 生成后原地待机，不会主动去找玩家；
##   - 玩家进入 DETECT_RADIUS 且中间没有墙 / 门挡视线，才算被发现；
##   - 发现后先停顿 ALERT_TIME（变黄 + 轻微放大）给玩家反应时间，再开始追；
##   - 追击中满足任一条件即脱战：
##       玩家跑出 LOSE_RADIUS / 自己离家超过 LEASH_RADIUS / 被挡视线超过 LOS_LOSE_TIME；
##   - 脱战后直线走回出生点，到家恢复待机，之后可以再次被发现；
##   - 玩家贴近到 DISENGAGE_RANGE 内时不会脱战：不会在你面前转身走回锚点；
##   - 到家会回满血并进入 CALM_TIME 冷静期，所以“拉出仇恨范围跟着砍”没有收益；
##   - 被玩家打中会立刻进入追击，不用等“发现”半径；
##   - 听觉：挥剑 / 开门 / 走动会通过 Game.emit_noise() 发声，半径内的怪会走过来查看
##     （INVESTIGATE，不看视线，墙后的声音也听得到），看完再回家；
##   - 发现玩家时会喊 SHOUT_RADIUS 内的同伴，同伴直接进入追击，但不会再传话。

signal died(enemy: Node)

const TYPES := {
	"goblin": {"hp": 2, "speed": 53.0, "damage": 1},
	"skelet": {"hp": 3, "speed": 40.0, "damage": 1},
	"chort": {"hp": 5, "speed": 30.0, "damage": 1},
	"ogre": {"hp": 9, "speed": 24.0, "damage": 2},
}

## 每层 RAID 的速度成长。
## 玩家基础移速 92、挥剑硬直期间 55.2 —— 怪速低于这个值时“边打边退”就是免费的，
## 所以基速只降到 53/40/30/24，成长从 1.5 收到 1.2：第 1 局略松，第 2 局起重新有压力。
const SPEED_PER_TIER := 1.2

## ---------------------------------------------------------------- 仇恨参数
## 发现玩家的距离：比出生保护距离（110）略小，所以开局不会立刻扑上来。
const DETECT_RADIUS := 104.0
## 追击中玩家跑出这个距离就开始累计脱战时间（要跑得比“发现”更远才算甩掉）。
const LOSE_RADIUS := 224.0
## 离家（出生点）超过这个距离强制回头，防止被一路牵到地图另一头。
const LEASH_RADIUS := 320.0
## 超距多久彻底脱战；留一点容错，避免在边界上反复进出仇恨。
const LOSE_TIME := 1.2
## 视线被墙 / 关闭的门挡住多久彻底脱战：关一扇门就能把怪甩掉。
const LOS_LOSE_TIME := 2.5
## 发现后的警戒停顿，同时是给玩家看的“它注意到你了”的信号。
const ALERT_TIME := 0.2
## 回程超时：门被关上回不去时就地重新安家，避免永远顶着门抖。
const RETURN_TIMEOUT := 5.0
## 视线检测节流，20 只怪也才每秒 200 次射线。
const LOS_INTERVAL := 0.1
## 接触伤害的判定距离与冷却。
const ATTACK_RANGE := 17.0
const ATTACK_COOLDOWN := 0.9
## 墙 / 门所在的物理层。
const WALL_MASK := 4

## ---------------------------------------------------------------- 听觉参数
## 听见噪音后走到声源查看：到点环顾 INVESTIGATE_LOOK 秒再回家，
## 走不到（门锁着）就 INVESTIGATE_TIMEOUT 秒后放弃。
const INVESTIGATE_SPEED := 0.6
const INVESTIGATE_TIMEOUT := 4.0
const INVESTIGATE_LOOK := 0.8
const INVESTIGATE_ARRIVE := 10.0
## 发现玩家时喊话的半径：附近的同伴会直接进入追击（不会继续传话）。
## 比一群的直径略大，刚好覆盖自己的群落，够不到隔壁群落。
const SHOUT_RADIUS := 130.0
## 玩家贴近到这个距离时不允许脱战：不会在你面前转身走回锚点。
const DISENGAGE_RANGE := 72.0
## 回到锚点后的冷静期：这段时间内不会因为看见 / 听见玩家而重新仇恨（挨打仍会还手）。
const CALM_TIME := 3.0

const ALERT_TINT := Color(1.0, 0.86, 0.45)
const HIT_TINT := Color(1.0, 0.45, 0.45)
const HEAR_TINT := Color(1.0, 0.93, 0.72)

enum State { IDLE, ALERT, CHASE, RETURN, INVESTIGATE }

var kind := "goblin"
var tier := 1
var hp := 2
var max_hp := 2
var speed := 50.0
var damage := 1
var dead := false
## 出生点：脱战后回到这里。由 main 摆好位置后调用 set_home() 指定。
var home := Vector2.ZERO
## 所属群落编号（main 刷怪时分配，-1 表示不在任何群落里，仅用于调试 / 测试）。
var pack_id := -1
var state: int = State.IDLE
## 保持 Variant（未标注类型），避免与 Player 类形成循环依赖。
var player

var _attack_cd := 0.0
var _knockback := Vector2.ZERO
var _flash := 0.0
var _sprite_height := 16.0
var _home_ready := false
var _alert_left := 0.0
var _far_t := 0.0
var _blind_t := 0.0
var _los_cd := 0.0
var _can_see := false
var _return_t := 0.0
var _noise_point := Vector2.ZERO
var _investigate_left := 0.0
var _look_left := 0.0
## 到家后的冷静期剩余时间。
var _calm_left := 0.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var health_bar: Node2D = $HealthBar
@onready var fill: ColorRect = $HealthBar/Fill


func _ready() -> void:
	add_to_group("enemies")
	Game.noise_emitted.connect(_on_noise)
	var config: Dictionary = TYPES.get(kind, TYPES["goblin"])
	max_hp = int(config.hp) + int((tier - 1) / 2.0)
	hp = max_hp
	speed = float(config.speed) + tier * SPEED_PER_TIER
	damage = int(config.damage)

	sprite.sprite_frames = Game.frames(kind)
	sprite.play("idle")
	_sprite_height = sprite.sprite_frames.get_frame_texture("idle", 0).get_height()
	sprite.position.y = -_sprite_height * 0.5
	health_bar.position.y = -_sprite_height - 8.0
	fill.size = Vector2(18.0, 3.0)
	health_bar.visible = false


## main 摆好位置后调用；不调用则把入场后第一帧的位置当出生点。
func set_home(point: Vector2) -> void:
	home = point
	_home_ready = true


func _physics_process(delta: float) -> void:
	if dead:
		return
	if not _home_ready:
		set_home(global_position)

	_attack_cd = maxf(0.0, _attack_cd - delta)
	_flash = maxf(0.0, _flash - delta)
	_calm_left = maxf(0.0, _calm_left - delta)

	_los_cd -= delta
	if _los_cd <= 0.0:
		_los_cd = LOS_INTERVAL
		_can_see = _player_visible()

	match state:
		State.IDLE:
			_tick_idle()
		State.ALERT:
			_tick_alert(delta)
		State.CHASE:
			_tick_chase(delta)
		State.RETURN:
			_tick_return(delta)
		State.INVESTIGATE:
			_tick_investigate(delta)

	_update_look()


# ---------------------------------------------------------------- 状态

## 待机：站着不动，只等玩家走进发现半径。刚回巢的怪有冷静期，不会立刻又扑上来。
func _tick_idle() -> void:
	velocity = Vector2.ZERO
	if _calm_left > 0.0 or _player_gone():
		return
	if global_position.distance_to(player.global_position) <= DETECT_RADIUS and _can_see:
		_begin_alert()


## 看见玩家：先愣一下，同时喊一嗓子把附近同伴拉进来。
func _begin_alert(call_allies := true) -> void:
	state = State.ALERT
	_alert_left = ALERT_TIME
	velocity = Vector2.ZERO
	_look_left = 0.0
	sprite.play("idle")
	if call_allies:
		_call_allies()


func _tick_alert(delta: float) -> void:
	velocity = Vector2.ZERO
	_alert_left -= delta
	if _alert_left <= 0.0:
		_begin_chase()


func _begin_chase() -> void:
	state = State.CHASE
	_far_t = 0.0
	_blind_t = 0.0


## 追逐：直线靠近 + 分离 + 击退，同时判定三种脱战条件。
func _tick_chase(delta: float) -> void:
	if _player_gone():
		_give_up()
		return

	var to_player: Vector2 = player.global_position - global_position
	var distance := to_player.length()
	var direction := to_player / maxf(distance, 0.001)

	# 1) 玩家跑远：超距开始计时，回到范围内以两倍速度回落。
	if distance > LOSE_RADIUS:
		_far_t += delta
	else:
		_far_t = maxf(0.0, _far_t - delta * 2.0)

	# 2) 视线丢失：被墙、立柱或关闭的门挡住。
	if _can_see:
		_blind_t = maxf(0.0, _blind_t - delta * 2.0)
	else:
		_blind_t += delta

	# 3) 离家太远：被牵着走超过 LEASH_RADIUS 就放弃。
	#    但玩家贴着打的时候不许“转身走人”——否则它背对你往回走的路上可以白嫖伤害。
	var leashed := global_position.distance_to(home) > LEASH_RADIUS
	var cornered := distance <= DISENGAGE_RANGE
	if _blind_t >= LOS_LOSE_TIME or (not cornered and (_far_t >= LOSE_TIME or leashed)):
		_give_up()
		return

	velocity = direction * speed + _separation() * 6.0 + _knockback
	_knockback = _knockback.move_toward(Vector2.ZERO, 900.0 * delta)
	move_and_slide()

	if distance < ATTACK_RANGE and _attack_cd <= 0.0:
		_attack_cd = ATTACK_COOLDOWN
		player.take_damage(damage, global_position)
		_knockback = -direction * 70.0


func _give_up() -> void:
	state = State.RETURN
	_return_t = 0.0
	_far_t = 0.0
	_blind_t = 0.0
	_knockback = Vector2.ZERO
	_attack_cd = 0.0


## 返回出生点：回程中不再重新仇恨。到家后会回满血并进入冷静期，
## 所以“把它拉出仇恨范围、跟着它一路砍”没有收益。
func _tick_return(delta: float) -> void:
	_return_t += delta

	var to_home: Vector2 = home - global_position
	if to_home.length() <= 6.0:
		_settle_home()
		return
	if _return_t >= RETURN_TIMEOUT:
		# 门关着回不去：就地重新安家，恢复待机（不回血，算它没跑掉）。
		set_home(global_position)
		state = State.IDLE
		velocity = Vector2.ZERO
		return

	velocity = to_home.normalized() * speed * 0.75 + _separation() * 4.0
	move_and_slide()


## 到家：回满血 + 冷静期。冷静期内不会因为看见 / 听见玩家就重新仇恨，挨打除外。
func _settle_home() -> void:
	hp = max_hp
	fill.size.x = 18.0
	health_bar.visible = false
	state = State.IDLE
	velocity = Vector2.ZERO
	_calm_left = CALM_TIME


## 查看噪音源：走过去、环顾一下、再回家。路上看见玩家就直接转追击。
func _tick_investigate(delta: float) -> void:
	if _look_left > 0.0:
		_look_left -= delta
		velocity = Vector2.ZERO
		if _look_left <= 0.0:
			_give_up()
		return

	if _player_gone():
		_give_up()
		return

	if _can_see and global_position.distance_to(player.global_position) <= DETECT_RADIUS:
		_begin_alert()
		return

	var to_point: Vector2 = _noise_point - global_position
	if to_point.length() <= INVESTIGATE_ARRIVE:
		_look_left = INVESTIGATE_LOOK
		velocity = Vector2.ZERO
		return

	_investigate_left -= delta
	if _investigate_left <= 0.0 or global_position.distance_to(home) > LEASH_RADIUS:
		_give_up()
		return

	velocity = to_point.normalized() * speed * INVESTIGATE_SPEED + _separation() * 4.0
	move_and_slide()


# ---------------------------------------------------------------- 听觉

## 噪音总线回调：够响就过去查看。听觉不看视线，墙后的声音也听得到。
func hear_noise(at: Vector2, radius: float) -> void:
	if dead or _calm_left > 0.0:
		return
	if state == State.CHASE or state == State.ALERT:
		return
	if global_position.distance_to(at) > radius:
		return
	if state == State.INVESTIGATE:
		# 已经在查看：只有更近的新噪音能把它引走。
		if global_position.distance_to(at) >= global_position.distance_to(_noise_point):
			return
	_noise_point = at
	_investigate_left = INVESTIGATE_TIMEOUT
	_look_left = 0.0
	state = State.INVESTIGATE
	velocity = Vector2.ZERO


## 被同伴喊到：直接进入追击，但不会再继续传话，避免一只发现就惊动全图。
func get_shouted(_target: Vector2) -> void:
	if dead or state == State.CHASE or state == State.ALERT:
		return
	_begin_chase()
	_calm_left = 0.0


## 发现玩家时喊人：半径内还活着的同伴直接进入追击。
func _call_allies() -> void:
	if _player_gone():
		return
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		if global_position.distance_to(other.global_position) > SHOUT_RADIUS:
			continue
		other.get_shouted(player.global_position)


func _on_noise(at: Vector2, radius: float, _kind: String) -> void:
	hear_noise(at, radius)


# ---------------------------------------------------------------- 感知

## 视线检测：从身体中心向玩家打一条射线，撞到墙 / 关着的门就不算看见。
func _player_visible() -> bool:
	if _player_gone():
		return false
	if not is_inside_tree():
		return false
	var space := get_world_2d().direct_space_state
	var from := global_position + Vector2(0.0, -6.0)
	var to: Vector2 = player.global_position + Vector2(0.0, -6.0)
	var query := PhysicsRayQueryParameters2D.create(from, to, WALL_MASK)
	query.exclude = [get_rid()]
	return space.intersect_ray(query).is_empty()


func _player_gone() -> bool:
	return player == null or not is_instance_valid(player) or bool(player.dead)


func _separation() -> Vector2:
	var push := Vector2.ZERO
	for other in get_tree().get_nodes_in_group("enemies"):
		if other == self or not is_instance_valid(other):
			continue
		var away: Vector2 = global_position - other.global_position
		var length := away.length()
		if length < 20.0 and length > 0.01:
			push += away / length * (20.0 - length) * 0.5
	return push


# ---------------------------------------------------------------- 表现

func _update_look() -> void:
	var moving := state == State.CHASE or state == State.RETURN or state == State.INVESTIGATE
	var anim := "run" if moving else "idle"
	if sprite.animation != anim:
		sprite.play(anim)

	var facing := Vector2.ZERO
	if state == State.CHASE and not _player_gone():
		facing = player.global_position - global_position
	elif state == State.RETURN:
		facing = home - global_position
	elif state == State.INVESTIGATE:
		facing = _noise_point - global_position
	if absf(facing.x) > 0.05:
		sprite.flip_h = facing.x < 0.0

	if _flash > 0.0:
		sprite.modulate = HIT_TINT
	elif state == State.ALERT:
		sprite.modulate = ALERT_TINT
	elif state == State.INVESTIGATE:
		sprite.modulate = HEAR_TINT
	else:
		sprite.modulate = Color.WHITE

	# 警戒时轻微放大，配合变色当作“发现你了”的信号。
	var pop := 1.12 if state == State.ALERT else 1.0
	sprite.scale = Vector2(pop, pop)


# ---------------------------------------------------------------- 受击 / 死亡

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
		return

	# 挨打必定仇恨：待机 / 回家途中直接进入追击，跳过警戒停顿（冷静期内也一样）。
	if state != State.CHASE:
		_far_t = 0.0
		_blind_t = 0.0
		_calm_left = 0.0
		_can_see = _player_visible()
		state = State.CHASE


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
