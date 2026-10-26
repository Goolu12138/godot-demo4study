extends Node
## 自动加载单例：素材管线 + 输入映射。
##
## 0x72 素材包提供三样东西：
##   1. 独立分帧 PNG（frames/），用于角色动画；
##   2. 512x512 总图 + tile_list_v1.7 坐标表，用于瓦片；
##   3. 三种图集（floor / walls_low / walls_high）。
## 这里全部按需懒加载并缓存，场景里不需要手动拖资源。

const CELL := 16
const ASSET_DIR := "res://0x72_DungeonTilesetII_v1.7/"
const FRAMES_DIR := ASSET_DIR + "frames/"
const SHEET_PATH := ASSET_DIR + "0x72_DungeonTilesetII_v1.7.png"

const FLOOR_TILES := ["floor_1", "floor_2", "floor_3", "floor_4", "floor_5", "floor_6", "floor_7", "floor_8"]
const WALL_TILES := ["wall_mid", "wall_top_left", "wall_top_mid", "wall_top_right", "wall_left", "wall_right",
	"wall_hole_1", "wall_banner_red", "wall_banner_blue"]

## 名字 -> 总图上的像素矩形，来自 tile_list_v1.7
var tile_rects: Dictionary = {}

var _tileset: TileSet
var _frames_cache: Dictionary = {}
var _simple_cache: Dictionary = {}
var _tex_cache: Dictionary = {}


func _ready() -> void:
	_setup_input()
	_load_tile_list()


func _load_tile_list() -> void:
	var file := FileAccess.open(ASSET_DIR + "tile_list_v1.7", FileAccess.READ)
	if file == null:
		push_error("找不到 tile_list_v1.7，素材路径是否被移动？")
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.is_empty():
			continue
		var parts := line.split(" ", false)
		if parts.size() < 5:
			continue
		tile_rects[parts[0]] = Rect2i(int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4]))


# ---------------------------------------------------------------- 输入

func _setup_input() -> void:
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("move_up", [KEY_W, KEY_UP])
	_bind_keys("move_down", [KEY_S, KEY_DOWN])
	_bind_keys("attack", [KEY_SPACE, KEY_J])
	_bind_keys("dash", [KEY_SHIFT, KEY_K])
	_bind_keys("interact", [KEY_E])
	_bind_keys("restart", [KEY_R])
	_bind_keys("menu", [KEY_ESCAPE])
	_bind_keys("bag", [KEY_TAB])
	_bind_mouse("attack", MOUSE_BUTTON_LEFT)


func _bind_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


func _bind_mouse(action: String, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)


# ---------------------------------------------------------------- 瓦片

## 用一个总图源构建 TileSet：只创建我们真正用到的图块。
func tileset() -> TileSet:
	if _tileset != null:
		return _tileset
	var sheet: Texture2D = load(SHEET_PATH)
	if sheet == null:
		push_error("找不到 0x72 总图")
		return null
	var ts := TileSet.new()
	ts.tile_size = Vector2i(CELL, CELL)
	var source := TileSetAtlasSource.new()
	source.texture = sheet
	source.texture_region_size = Vector2i(CELL, CELL)
	for tile_name in FLOOR_TILES + WALL_TILES:
		var rect: Rect2i = tile_rects.get(tile_name, Rect2i())
		if rect.size != Vector2i(CELL, CELL):
			push_warning("图块 %s 尺寸不是 16x16，已跳过" % tile_name)
			continue
		var coords := Vector2i(rect.position.x / CELL, rect.position.y / CELL)
		if source.has_tile(coords):
			continue
		source.create_tile(coords)
	ts.add_source(source, 0)
	_tileset = ts
	return _tileset


func tile_coord(tile_name: String) -> Vector2i:
	var rect: Rect2i = tile_rects.get(tile_name, Rect2i())
	if rect.size == Vector2i.ZERO:
		push_error("未知图块：%s" % tile_name)
		return Vector2i.ZERO
	return Vector2i(rect.position.x / CELL, rect.position.y / CELL)


# ---------------------------------------------------------------- 角色动画

## 从 frames/ 下的 xxx_idle_anim_fN.png / xxx_run_anim_fN.png 构建 SpriteFrames。
func frames(prefix: String) -> SpriteFrames:
	if _frames_cache.has(prefix):
		return _frames_cache[prefix]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	_add_anim(sf, "idle", prefix + "_idle_anim", 6.0, true)
	_add_anim(sf, "run", prefix + "_run_anim", 10.0, true)
	_frames_cache[prefix] = sf
	return sf


func _add_anim(sf: SpriteFrames, anim: String, base: String, fps: float, loop: bool) -> void:
	sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, loop)
	for i in 4:
		var frame_name := "%s_f%d" % [base, i]
		if ResourceLoader.exists(FRAMES_DIR + frame_name + ".png"):
			sf.add_frame(anim, load(FRAMES_DIR + frame_name + ".png"))


## 任意帧序列，例如宝箱、金币。
func simple_frames(frame_names: Array, fps: float, loop: bool) -> SpriteFrames:
	var key := "%s|%s|%s" % [str(frame_names), fps, loop]
	if _simple_cache.has(key):
		return _simple_cache[key]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("default")
	sf.set_animation_speed("default", fps)
	sf.set_animation_loop("default", loop)
	for frame_name in frame_names:
		if ResourceLoader.exists(FRAMES_DIR + str(frame_name) + ".png"):
			sf.add_frame("default", load(FRAMES_DIR + str(frame_name) + ".png"))
	_simple_cache[key] = sf
	return sf


func tex(texture_name: String) -> Texture2D:
	if not _tex_cache.has(texture_name):
		var path := FRAMES_DIR + texture_name + ".png"
		if ResourceLoader.exists(path):
			_tex_cache[texture_name] = load(path)
		else:
			push_error("找不到贴图：%s" % texture_name)
			_tex_cache[texture_name] = null
	return _tex_cache[texture_name]
