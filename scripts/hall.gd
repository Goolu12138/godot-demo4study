extends Node2D
## 可走动的休息大厅：
##   - 复用 Dungeon 生成一间带墙和装饰的厅堂；
##   - 玩家可以自由走动；
##   - 商人负责装备商店，教官负责能力 / 技能；仓库是大厅里的大箱子；
##   - 顶墙的大门是出击入口，靠近后弹出“是否出击”确认。

const DUNGEON_SCENE := preload("res://scenes/dungeon.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")
const NPC_SCENE := preload("res://scenes/npc.tscn")
const HALL_UI_SCENE := preload("res://scenes/hall_ui.tscn")
const CONFIRM_SCENE := preload("res://scenes/confirm_dialog.tscn")

const ROOM := Vector2i(30, 12)
const TALK_RANGE := 38.0

var dungeon: Dungeon
var player: Player
var ui
var confirm
var actors: Node2D
var npcs: Array = []

var _nearest = null
var _door_armed := true
var _overlay_root: Control
var _prompt: Label
var _hint: Label
var _gold: Label
var _gear: Label
var _result: Label


func _ready() -> void:
	_build_room()
	_build_overlay()
	_build_ui()
	_build_actors()
	_show_last_result()
	if "--hall-shot" in OS.get_cmdline_user_args():
		_capture_hall()


func _process(_delta: float) -> void:
	if player == null:
		return
	var blocked: bool = ui.any_open() or confirm.is_open()
	player.control_enabled = not blocked
	_refresh_status()

	if blocked:
		_prompt.text = ""
		return

	_nearest = _find_nearest()
	_update_prompt()
	_update_nameplates()

	if Input.is_action_just_pressed("interact") and _nearest != null:
		_talk(_nearest)
		return

	var distance := dungeon.door_point().distance_to(player.global_position)
	if distance < 34.0 and _door_armed:
		_ask_deploy()
	elif distance > 46.0:
		_door_armed = true


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if confirm.is_open():
		confirm.cancel()
	elif ui.any_open():
		ui.close_all()
	else:
		ui.open_settings_panel()
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 场景

func _build_room() -> void:
	dungeon = DUNGEON_SCENE.instantiate()
	dungeon.room = ROOM
	add_child(dungeon)
	dungeon.build_hall()
	# 大厅里不需要宝箱，门保持敞开作为出击入口。
	if dungeon.chest_sprite != null:
		dungeon.chest_sprite.visible = false
	dungeon.open_door()


func _build_actors() -> void:
	actors = Node2D.new()
	actors.name = "Actors"
	actors.y_sort_enabled = true
	add_child(actors)

	player = PLAYER_SCENE.instantiate() as Player
	player.combat_enabled = false
	actors.add_child(player)
	player.global_position = dungeon.door_point() + Vector2(0, 104)

	var size := dungeon.room_pixel_size()
	var camera := player.camera
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(size.x)
	camera.limit_bottom = int(size.y)
	camera.reset_smoothing()

	_add_npc("shop", "doc", "npc_shop", Vector2i(7, 8))
	_add_npc("abilities", "wizzard_m", "npc_instructor", Vector2i(15, 4))
	_add_npc("stash", "", "stash_title", Vector2i(22, 8),
		"chest_full_open_anim_f0", 2.5, -112.0)
	_add_npc("stash", "dwarf_m", "npc_stash", Vector2i(19, 8))


func _add_npc(role: String, prefix: String, key: String, cell: Vector2i,
		texture := "", scale_factor := 1.0, label_y := -66.0) -> void:
	var npc = NPC_SCENE.instantiate()
	npc.role = role
	npc.sprite_prefix = prefix
	npc.name_key = key
	npc.texture_name = texture
	npc.sprite_scale = scale_factor
	npc.label_offset = label_y
	actors.add_child(npc)
	npc.global_position = Vector2((cell.x + 0.5) * 16.0, (cell.y + 0.9) * 16.0)
	npcs.append(npc)

	var label := _label(npc.display_name, 8, Color("#f3e3c3"), 3)
	label.position = Vector2(-70, -70)
	label.size = Vector2(140, 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay_root.add_child(label)
	npc.name_label = label


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	ui = HALL_UI_SCENE.instantiate()
	layer.add_child(ui)

	confirm = CONFIRM_SCENE.instantiate()
	add_child(confirm)
	confirm.confirmed.connect(_on_deploy_confirmed)
	confirm.cancelled.connect(_on_deploy_cancelled)


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	_overlay_root = root

	_gold = _label("", 12, Color("#ffd166"), 4)
	_gold.position = Vector2(10, 8)
	_gold.size = Vector2(220, 18)
	root.add_child(_gold)

	_gear = _label("", 9, Color("#c9b79c"), 3)
	_gear.position = Vector2(10, 28)
	_gear.size = Vector2(460, 14)
	root.add_child(_gear)

	_result = _label("", 9, Color("#8fd18a"), 3)
	_result.position = Vector2(0, 52)
	_result.size = Vector2(640, 14)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_result)

	_prompt = _label("", 11, Color("#f3e3c3"), 4)
	_prompt.position = Vector2(0, 298)
	_prompt.size = Vector2(640, 18)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_prompt)

	_hint = _label(Loc.t("hall_hint"), 8, Color(0.7, 0.66, 0.62), 2)
	_hint.position = Vector2(0, 326)
	_hint.size = Vector2(640, 14)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hint)


# ---------------------------------------------------------------- 交互

func _find_nearest():
	var best = null
	var best_distance := TALK_RANGE
	for npc in npcs:
		var distance: float = npc.global_position.distance_to(player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = npc
	return best


func _update_prompt() -> void:
	if _nearest != null:
		# 仓库大箱子用“打开”，NPC 用“交谈”。
		if str(_nearest.role) == "stash" and str(_nearest.texture_name) != "":
			_prompt.text = Loc.t("prompt_open") % str(_nearest.display_name)
		else:
			_prompt.text = Loc.t("prompt_talk") % str(_nearest.display_name)
	elif dungeon.door_point().distance_to(player.global_position) < 54.0:
		_prompt.text = Loc.t("prompt_gate")
	else:
		_prompt.text = ""


## NPC 名字放在屏幕空间，字号不会被相机放大。
func _update_nameplates() -> void:
	for npc in npcs:
		if npc.name_label == null:
			continue
		var screen: Vector2 = npc.get_global_transform_with_canvas().origin
		npc.name_label.position = screen + Vector2(-70, npc.label_offset)
		npc.name_label.visible = screen.x > -30.0 and screen.x < 670.0 \
			and screen.y > -30.0 and screen.y < 390.0


func _talk(npc) -> void:
	match str(npc.role):
		"shop":
			ui.open_shop("gear")
		"stash":
			ui.open_stash_panel()
		"abilities":
			ui.open_shop("upgrades")
	player.control_enabled = false


func _ask_deploy() -> void:
	_door_armed = false
	player.control_enabled = false
	confirm.ask(Loc.t("deploy_title"), Loc.t("deploy_body"),
		Loc.t("deploy_yes"), Loc.t("deploy_no"))


func _on_deploy_confirmed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_deploy_cancelled() -> void:
	player.control_enabled = true


func _refresh_status() -> void:
	_gold.text = Loc.t("hall_gold") % Meta.gold
	_gear.text = "%s   ·   %s" % [
		Loc.t("hall_gear") % [Loc.gear_name(Meta.weapon), Loc.gear_name(Meta.armor)],
		Loc.t("hall_pack") % [Loc.t("pack_" + Meta.backpack), Meta.bag_cols(), Meta.bag_rows()]]


func _show_last_result() -> void:
	if Meta.last_result == "" or _result == null:
		return
	_result.text = Meta.last_result
	_result.modulate.a = 1.0
	Meta.last_result = ""
	Meta.save_data()
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_property(_result, "modulate:a", 0.0, 0.6)


func _capture_hall() -> void:
	var suffix := "_zh" if Loc.language == "zh" else ""
	await get_tree().create_timer(0.5).timeout
	await _save_shot("hall%s.png" % suffix)
	ui.open_shop("gear")
	await get_tree().create_timer(0.3).timeout
	await _save_shot("hall_shop%s.png" % suffix)
	ui.close_all()
	await get_tree().create_timer(0.2).timeout
	ui.open_shop("upgrades")
	await get_tree().create_timer(0.3).timeout
	await _save_shot("hall_abilities%s.png" % suffix)
	ui.close_all()
	await get_tree().create_timer(0.2).timeout
	ui.open_stash_panel()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("hall_stash%s.png" % suffix)
	ui.close_all()
	await get_tree().create_timer(0.2).timeout
	ui.open_settings_panel()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("hall_settings%s.png" % suffix)
	ui.close_all()
	await get_tree().create_timer(0.2).timeout
	_ask_deploy()
	await get_tree().create_timer(0.3).timeout
	await _save_shot("hall_confirm%s.png" % suffix)
	get_tree().quit()


func _save_shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var directory := "res://screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory + "/" + file_name
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("saved ", path, " ", image.get_size())


func _label(text: String, size: int, color: Color, outline := 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", Game.ui_font())
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_color_override("font_outline_color", Color("#140c12"))
		label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
