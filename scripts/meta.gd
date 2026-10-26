extends Node
## 跨局存档：金币、永久升级、仓库装备、撤离战绩。
## 存档位置：user://meta.cfg（Windows: %APPDATA%\Godot\app_userdata\dungeon-demo\meta.cfg）
##
## 搜打撤规则：
##   - 局内捡到的贵重品不立刻入账，只有成功撤离才折算成金币；
##   - 局内捡到的装备先进背包，撤离后进仓库；
##   - 死亡 / 超时 / 主动放弃：背包清空，身上的武器与护甲也从仓库消失。

const SAVE_PATH := "user://meta.cfg"

const UPGRADES := {
	"vitality": {"title": "VITALITY", "desc": "+2 MAX HP", "costs": [30, 55, 85], "max": 3},
	"swiftness": {"title": "SWIFTNESS", "desc": "+8% MOVE SPEED", "costs": [25, 45, 70], "max": 3},
	"might": {"title": "MIGHT", "desc": "+1 SWORD DAMAGE", "costs": [70, 140], "max": 2},
}

const DEFAULT_WEAPON := "rusty_sword"
const DEFAULT_ARMOR := "cloth"

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

var gold := 0
var selected_hero := "knight_m"
## 当前装备（带入局内，死了就没）。
var weapon := DEFAULT_WEAPON
var armor := DEFAULT_ARMOR
var raids := 0
var best_haul := 0
## 仓库：同一件装备可以有多把，用数组存。
var owned_weapons: Array[String] = []
var owned_armors: Array[String] = []
## 休息处顶部展示的上一局结果。
var last_result := ""

var _levels := {"vitality": 0, "swiftness": 0, "might": 0}


func _ready() -> void:
	load_data()


func load_data() -> void:
	gold = 0
	selected_hero = "knight_m"
	_levels = {"vitality": 0, "swiftness": 0, "might": 0}
	weapon = DEFAULT_WEAPON
	armor = DEFAULT_ARMOR
	raids = 0
	best_haul = 0
	last_result = ""
	owned_weapons = []
	owned_armors = []
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
	for id in _string_array(config.get_value("stash", "weapons", [])):
		if WEAPONS.has(id) and id != DEFAULT_WEAPON:
			owned_weapons.append(id)
	for id in _string_array(config.get_value("stash", "armors", [])):
		if ARMORS.has(id) and id != DEFAULT_ARMOR:
			owned_armors.append(id)
	if not WEAPONS.has(weapon) or (weapon != DEFAULT_WEAPON and not owned_weapons.has(weapon)):
		weapon = DEFAULT_WEAPON
	if not ARMORS.has(armor) or (armor != DEFAULT_ARMOR and not owned_armors.has(armor)):
		armor = DEFAULT_ARMOR


func save_data() -> void:
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
	config.set_value("stash", "weapons", owned_weapons)
	config.set_value("stash", "armors", owned_armors)
	config.save(SAVE_PATH)


func _string_array(value) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for entry in value:
			result.append(str(entry))
	return result


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


## 仓库里这件装备有几件（默认装备永远算 1 件）。
func owned_count(kind: String, id: String) -> int:
	if id == default_gear(kind):
		return 1
	var list: Array[String] = owned_weapons if kind == "weapon" else owned_armors
	var count := 0
	for entry in list:
		if entry == id:
			count += 1
	return count


func has_gear(kind: String, id: String) -> bool:
	return owned_count(kind, id) > 0


## 仓库聚合：{id: count}。用于休息处仓库面板。
func stash_counts(kind: String) -> Dictionary:
	var result := {}
	var list: Array[String] = owned_weapons if kind == "weapon" else owned_armors
	for id in list:
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
	gold -= cost
	var bonus := int(table[id].bonus)
	var current := weapon_bonus() if kind == "weapon" else armor_bonus()
	if kind == "weapon":
		owned_weapons.append(id)
		if bonus > current:
			weapon = id
	else:
		owned_armors.append(id)
		if bonus > current:
			armor = id
	save_data()
	return true


## 死亡 / 超时 / 放弃：背包由 main 清空，这里把身上的装备从仓库删掉。
func lose_gear() -> void:
	if weapon != DEFAULT_WEAPON:
		owned_weapons.erase(weapon)
		weapon = DEFAULT_WEAPON
	if armor != DEFAULT_ARMOR:
		owned_armors.erase(armor)
		armor = DEFAULT_ARMOR
	save_data()


# ---------------------------------------------------------------- 撤离结算

## 只有撤离成功才会调用：贵重品折算金币，背包里的装备进仓库。
func finish_extraction(value: int, gear: Array) -> void:
	gold = maxi(0, gold + value)
	raids += 1
	best_haul = maxi(best_haul, value)
	var stored := 0
	for item in gear:
		var kind := str(item.kind)
		var id := str(item.id)
		if kind == "weapon" and WEAPONS.has(id):
			owned_weapons.append(id)
			stored += 1
		elif kind == "armor" and ARMORS.has(id):
			owned_armors.append(id)
			stored += 1
	last_result = "EXTRACTED   +%d G   ·   %d GEAR STORED" % [value, stored]
	save_data()


func record_result(text: String) -> void:
	last_result = text
	save_data()
