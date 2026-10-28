extends Node
## 跨局存档：金币、永久升级、仓库装备、背包等级、撤离战绩。
## 存档位置：user://meta.cfg（Windows: %APPDATA%\Godot\app_userdata\dungeon-demo\meta.cfg）
##
## 搜打撤规则：
##   - 局内捡到的贵重品不立刻入账，只有成功撤离才折算成金币；
##   - 局内所有战利品都占用背包格子（贵重品 / 武器 / 护甲体积不同）；
##   - 撤离后背包里的装备进仓库，仓库是 100×100 的格子；
##   - 死亡 / 超时 / 主动放弃：背包清空，身上的武器与护甲也从仓库消失。
##
## 背包等级是永久解锁，不会因死亡丢失；容量分别为 30×20 / 40×20 / 50×20。

const SAVE_PATH := "user://meta.cfg"

const UPGRADES := {
	"vitality": {"title": "VITALITY", "desc": "+2 MAX HP", "costs": [30, 55, 85], "max": 3},
	"swiftness": {"title": "SWIFTNESS", "desc": "+8% MOVE SPEED", "costs": [25, 45, 70], "max": 3},
	"might": {"title": "MIGHT", "desc": "+1 SWORD DAMAGE", "costs": [70, 140], "max": 2},
}

const DEFAULT_WEAPON := "rusty_sword"
const DEFAULT_ARMOR := "cloth"

## 仓库固定 100×100 格。格子大小由 UI 决定，不占存档。
const STASH_COLS := 100
const STASH_ROWS := 100

## 背包等级：永久解锁，购买后可在商店里免费切换。
const BACKPACKS := {
	"basic": {"cols": 30, "rows": 20, "cost": 0},
	"medium": {"cols": 40, "rows": 20, "cost": 250},
	"large": {"cols": 50, "rows": 20, "cost": 600},
}
const DEFAULT_BACKPACK := "basic"

const WEAPONS := {
	"rusty_sword": {"title": "RUSTY SWORD", "desc": "+0 DAMAGE", "bonus": 0, "cost": 0, "texture": "weapon_rusty_sword"},
	"knight_sword": {"title": "KNIGHT SWORD", "desc": "+1 DAMAGE", "bonus": 1, "cost": 120, "texture": "weapon_knight_sword"},
	"katana": {"title": "KATANA", "desc": "+2 DAMAGE", "bonus": 2, "cost": 300, "texture": "weapon_katana"},
	"golden_sword": {"title": "GOLDEN SWORD", "desc": "+3 DAMAGE", "bonus": 3, "cost": 600, "texture": "weapon_golden_sword"},
}

const ARMORS := {
	"cloth": {"title": "CLOTH", "desc": "+0 MAX HP", "bonus": 0, "cost": 0, "texture": "ui_heart_empty"},
	"leather": {"title": "LEATHER", "desc": "+2 MAX HP", "bonus": 2, "cost": 100, "texture": "ui_heart_half"},
	"chain": {"title": "CHAIN", "desc": "+4 MAX HP", "bonus": 4, "cost": 250, "texture": "ui_heart_full"},
	"plate": {"title": "PLATE", "desc": "+6 MAX HP", "bonus": 6, "cost": 500, "texture": "ui_heart_full"},
}

## 装备体积：宽 × 高（格）。
const WEAPON_SIZES := {
	"rusty_sword": Vector2i(2, 3),
	"knight_sword": Vector2i(2, 3),
	"katana": Vector2i(2, 3),
	"golden_sword": Vector2i(3, 3),
}

const ARMOR_SIZES := {
	"cloth": Vector2i(2, 2),
	"leather": Vector2i(2, 3),
	"chain": Vector2i(3, 3),
	"plate": Vector2i(3, 4),
}

var gold := 0
var selected_hero := "knight_m"
## 当前装备（带入局内，死了就没）。
var weapon := DEFAULT_WEAPON
var armor := DEFAULT_ARMOR
var raids := 0
var best_haul := 0
## 仓库：二维格子，里面是带 x / y 的装备字典。
var stash: GridInventory = null
## 背包等级与已解锁列表。
var backpack := DEFAULT_BACKPACK
var owned_backpacks: Array[String] = [DEFAULT_BACKPACK]
## 休息处顶部展示的上一局结果。
var last_result := ""
## 设置项：主音量 0-100，界面语言 en / zh。
var volume := 80
var language := "en"

var _levels := {"vitality": 0, "swiftness": 0, "might": 0}


func _ready() -> void:
	_ensure_stash()
	load_data()
	apply_audio()


func _ensure_stash() -> void:
	if stash == null:
		stash = GridInventory.new(STASH_COLS, STASH_ROWS)


func load_data() -> void:
	_ensure_stash()
	stash.clear()
	gold = 0
	selected_hero = "knight_m"
	_levels = {"vitality": 0, "swiftness": 0, "might": 0}
	weapon = DEFAULT_WEAPON
	armor = DEFAULT_ARMOR
	raids = 0
	best_haul = 0
	backpack = DEFAULT_BACKPACK
	owned_backpacks = [DEFAULT_BACKPACK]
	last_result = ""
	volume = 80
	language = "en"

	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return

	gold = int(config.get_value("meta", "gold", 0))
	selected_hero = str(config.get_value("meta", "hero", "knight_m"))
	for key in _levels:
		_levels[key] = int(config.get_value("upgrades", key, 0))
	weapon = str(config.get_value("gear", "weapon", DEFAULT_WEAPON))
	armor = str(config.get_value("gear", "armor", DEFAULT_ARMOR))
	raids = int(config.get_value("run", "raids", 0))
	best_haul = int(config.get_value("run", "best_haul", 0))
	last_result = str(config.get_value("run", "last_result", ""))
	volume = int(config.get_value("settings", "volume", 80))
	language = str(config.get_value("settings", "language", "en"))

	backpack = str(config.get_value("backpack", "current", DEFAULT_BACKPACK))
	owned_backpacks = []
	for id in _string_array(config.get_value("backpack", "owned", [DEFAULT_BACKPACK])):
		if BACKPACKS.has(id) and not owned_backpacks.has(id):
			owned_backpacks.append(id)
	if not owned_backpacks.has(DEFAULT_BACKPACK):
		owned_backpacks.push_front(DEFAULT_BACKPACK)
	if not BACKPACKS.has(backpack) or not owned_backpacks.has(backpack):
		backpack = DEFAULT_BACKPACK

	var migrated := false
	if int(config.get_value("stash", "version", 0)) >= 1:
		var raw_items = config.get_value("stash", "items", [])
		if raw_items is Array:
			for raw in raw_items:
				_load_stash_entry(raw)
	else:
		# 旧存档：仓库是两串装备 id，这里转成格子并自动排布。
		for id in _string_array(config.get_value("stash", "weapons", [])):
			if WEAPONS.has(id) and id != DEFAULT_WEAPON:
				stash.auto_place(make_gear_item("weapon", id))
		for id in _string_array(config.get_value("stash", "armors", [])):
			if ARMORS.has(id) and id != DEFAULT_ARMOR:
				stash.auto_place(make_gear_item("armor", id))
		migrated = true

	# 身上的装备必须真的在仓库里；旧存档 / 手动改档时退回默认。
	if not WEAPONS.has(weapon) or (weapon != DEFAULT_WEAPON and owned_count("weapon", weapon) <= 0):
		weapon = DEFAULT_WEAPON
	if not ARMORS.has(armor) or (armor != DEFAULT_ARMOR and owned_count("armor", armor) <= 0):
		armor = DEFAULT_ARMOR

	if migrated:
		save_data()


func save_data() -> void:
	_ensure_stash()
	var config := ConfigFile.new()
	config.set_value("meta", "gold", gold)
	config.set_value("meta", "hero", selected_hero)
	for key in _levels:
		config.set_value("upgrades", key, _levels[key])
	config.set_value("gear", "weapon", weapon)
	config.set_value("gear", "armor", armor)
	config.set_value("run", "raids", raids)
	config.set_value("run", "best_haul", best_haul)
	config.set_value("run", "last_result", last_result)
	config.set_value("settings", "volume", volume)
	config.set_value("settings", "language", language)
	config.set_value("backpack", "current", backpack)
	config.set_value("backpack", "owned", owned_backpacks)
	config.set_value("stash", "version", 1)
	config.set_value("stash", "items", _saved_stash_items())
	config.save(SAVE_PATH)


func _saved_stash_items() -> Array:
	var result: Array = []
	for item in stash.items:
		result.append({
			"kind": str(item.get("kind", "")),
			"id": str(item.get("id", "")),
			"x": int(item.get("x", 0)),
			"y": int(item.get("y", 0)),
		})
	return result


## 把 volume 应用在 Master 总线上。现在还没有音频资源，接音效后自动生效。
func apply_audio() -> void:
	var linear := clampf(float(volume) / 100.0, 0.0, 1.0)
	AudioServer.set_bus_mute(0, linear <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(linear, 0.001)))


func _load_stash_entry(raw) -> void:
	if not raw is Dictionary:
		return
	var kind := str(raw.get("kind", ""))
	var id := str(raw.get("id", ""))
	var item := make_gear_item(kind, id)
	if item.is_empty():
		return
	var x := int(raw.get("x", -1))
	var y := int(raw.get("y", -1))
	if x >= 0 and y >= 0 and stash.place(item, x, y):
		return
	stash.auto_place(item)


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			result.append(str(entry))
	return result


# ---------------------------------------------------------------- 背包等级

func bag_cols() -> int:
	return int(BACKPACKS[backpack].cols)


func bag_rows() -> int:
	return int(BACKPACKS[backpack].rows)


func bag_capacity() -> int:
	return bag_cols() * bag_rows()


func owns_backpack(id: String) -> bool:
	return owned_backpacks.has(id)


func buy_backpack(id: String) -> bool:
	if not BACKPACKS.has(id) or owns_backpack(id):
		return false
	var cost := int(BACKPACKS[id].cost)
	if cost <= 0 or gold < cost:
		return false
	gold -= cost
	owned_backpacks.append(id)
	backpack = id
	save_data()
	return true


func equip_backpack(id: String) -> bool:
	if not owns_backpack(id):
		return false
	backpack = id
	save_data()
	return true


# ---------------------------------------------------------------- 永久升级


func upgrade_level(key: String) -> int:
	return int(_levels.get(key, 0))


## 返回下一级价格；已满级返回 -1。
func next_cost(key: String) -> int:
	var definition: Dictionary = UPGRADES[key]
	var level := upgrade_level(key)
	if level >= int(definition.max):
		return -1
	return int(definition.costs[level])


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	save_data()


func buy(key: String) -> bool:
	var cost := next_cost(key)
	if cost < 0 or gold < cost:
		return false
	gold -= cost
	_levels[key] = upgrade_level(key) + 1
	save_data()
	return true


# ---------------------------------------------------------------- 仓库格子

func stash_used() -> int:
	_ensure_stash()
	return stash.used_cells()


func stash_capacity() -> int:
	return STASH_COLS * STASH_ROWS


func stash_item_count() -> int:
	_ensure_stash()
	return stash.items.size()


## 把一件装备塞进仓库；返回是否放得下。调用方负责 save_data。
func stash_add(kind: String, id: String) -> bool:
	_ensure_stash()
	var item := make_gear_item(kind, id)
	if item.is_empty():
		return false
	return stash.auto_place(item)


func stash_remove_one(kind: String, id: String) -> bool:
	_ensure_stash()
	for i in stash.items.size():
		var item: Dictionary = stash.items[i]
		if str(item.get("kind", "")) == kind and str(item.get("id", "")) == id:
			stash.remove_at(i)
			return true
	return false


# ---------------------------------------------------------------- 装备数据

func weapon_bonus() -> int:
	return int(WEAPONS[weapon].bonus)


func armor_bonus() -> int:
	return int(ARMORS[armor].bonus)


func weapon_texture() -> String:
	return str(WEAPONS[weapon].texture)


func gear_table(kind: String) -> Dictionary:
	return WEAPONS if kind == "weapon" else ARMORS


func default_gear(kind: String) -> String:
	return DEFAULT_WEAPON if kind == "weapon" else DEFAULT_ARMOR


func gear_title(kind: String, id: String) -> String:
	return str(gear_table(kind)[id].title)


func gear_bonus(kind: String, id: String) -> int:
	return int(gear_table(kind)[id].bonus)


func gear_texture(kind: String, id: String) -> String:
	return str(gear_table(kind)[id].texture)


func gear_cost(kind: String, id: String) -> int:
	return int(gear_table(kind)[id].cost)


func gear_size(kind: String, id: String) -> Vector2i:
	var sizes: Dictionary = WEAPON_SIZES if kind == "weapon" else ARMOR_SIZES
	if sizes.has(id):
		return sizes[id]
	return Vector2i(2, 3)


## 生成一件带体积、贴图、说明的装备字典，供背包 / 仓库 / UI 共用。
func make_gear_item(kind: String, id: String) -> Dictionary:
	if kind != "weapon" and kind != "armor":
		return {}
	var table := gear_table(kind)
	if not table.has(id):
		return {}
	var size := gear_size(kind, id)
	var bonus := int(table[id].bonus)
	var unit := Loc.t("unit_dmg") if kind == "weapon" else Loc.t("unit_hp")
	return {
		"kind": kind,
		"id": id,
		"name": Loc.gear_name(id),
		"tex": str(table[id].texture),
		"bonus": bonus,
		"bonus_text": Loc.t("gear_desc") % [bonus, unit],
		"w": size.x,
		"h": size.y,
		"size": size,
	}


## 出售价：买入价的一半，最低 10 金；默认装备不可出售。
func gear_sell_price(kind: String, id: String) -> int:
	var cost := gear_cost(kind, id)
	if cost <= 0:
		return 0
	return maxi(10, int(cost * 0.5))


func can_sell_gear(kind: String, id: String) -> bool:
	if id == default_gear(kind):
		return false
	if owned_count(kind, id) <= 0:
		return false
	var equipped: String = weapon if kind == "weapon" else armor
	# 身上正穿着、且只剩这一件时不能卖，避免把装备卖空。
	if id == equipped and owned_count(kind, id) <= 1:
		return false
	return true


## 卖掉一件仓库里的装备，返回是否成功。
func sell_gear(kind: String, id: String) -> bool:
	if not can_sell_gear(kind, id):
		return false
	if not stash_remove_one(kind, id):
		return false
	gold += gear_sell_price(kind, id)
	save_data()
	return true


## 仓库里这件装备有几件（默认装备永远算 1 件，但不占仓库格）。
func owned_count(kind: String, id: String) -> int:
	if id == default_gear(kind):
		return 1
	_ensure_stash()
	var count := 0
	for item in stash.items:
		if str(item.get("kind", "")) == kind and str(item.get("id", "")) == id:
			count += 1
	return count


func has_gear(kind: String, id: String) -> bool:
	return owned_count(kind, id) > 0


## 仓库聚合：{id: count}。用于商店出售区。
func stash_counts(kind: String) -> Dictionary:
	_ensure_stash()
	var result := {}
	for item in stash.items:
		if str(item.get("kind", "")) != kind:
			continue
		var id := str(item.get("id", ""))
		result[id] = int(result.get(id, 0)) + 1
	return result


func equip_gear(kind: String, id: String) -> bool:
	if not has_gear(kind, id):
		return false
	if kind == "weapon":
		weapon = id
	else:
		armor = id
	save_data()
	return true


## 商店购买：直接进仓库；比当前装备强就顺手换上。
func buy_gear(kind: String, id: String) -> bool:
	var table := gear_table(kind)
	if not table.has(id):
		return false
	if owned_count(kind, id) > 0:
		return false
	var cost := int(table[id].cost)
	if cost <= 0 or gold < cost:
		return false
	var item := make_gear_item(kind, id)
	if not stash.auto_place(item):
		return false
	gold -= cost
	var bonus := int(table[id].bonus)
	var current := weapon_bonus() if kind == "weapon" else armor_bonus()
	if bonus > current:
		if kind == "weapon":
			weapon = id
		else:
			armor = id
	save_data()
	return true


## 死亡 / 超时 / 放弃：背包由 main 清空，这里把身上的装备从仓库删掉。
func lose_gear() -> void:
	if weapon != DEFAULT_WEAPON:
		stash_remove_one("weapon", weapon)
		weapon = DEFAULT_WEAPON
	if armor != DEFAULT_ARMOR:
		stash_remove_one("armor", armor)
		armor = DEFAULT_ARMOR
	save_data()


# ---------------------------------------------------------------- 撤离结算

## 只有撤离成功才会调用：贵重品折算金币，背包里的装备进仓库。
## 返回实际塞进仓库的件数（仓库满时可能小于 gear.size()）。
func finish_extraction(value: int, gear: Array) -> int:
	gold = maxi(0, gold + value)
	raids += 1
	best_haul = maxi(best_haul, value)
	var stored := 0
	for item in gear:
		var kind := str(item.get("kind", ""))
		var id := str(item.get("id", ""))
		if (kind == "weapon" or kind == "armor") and stash_add(kind, id):
			stored += 1
	last_result = Loc.t("result_extracted") % [value, stored]
	save_data()
	return stored


func record_result(text: String) -> void:
	last_result = text
	save_data()
