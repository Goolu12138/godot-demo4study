extends Node
## 跨局存档：金币、永久升级、已选角色。
## 存档位置：user://meta.cfg（Windows: %APPDATA%\Godot\app_userdata\dungeon-demo\meta.cfg）

const SAVE_PATH := "user://meta.cfg"

const UPGRADES := {
	"vitality": {"title": "VITALITY", "desc": "+2 MAX HP", "costs": [30, 55, 85], "max": 3},
	"swiftness": {"title": "SWIFTNESS", "desc": "+8% MOVE SPEED", "costs": [25, 45, 70], "max": 3},
	"might": {"title": "MIGHT", "desc": "+1 SWORD DAMAGE", "costs": [70, 140], "max": 2},
}

var gold := 0
var selected_hero := "knight_m"

var _levels := {"vitality": 0, "swiftness": 0, "might": 0}


func _ready() -> void:
	load_data()


func load_data() -> void:
	_levels = {"vitality": 0, "swiftness": 0, "might": 0}
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	gold = int(config.get_value("meta", "gold", 0))
	selected_hero = str(config.get_value("meta", "hero", "knight_m"))
	for key in _levels:
		_levels[key] = int(config.get_value("upgrades", key, 0))


func save_data() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "gold", gold)
	config.set_value("meta", "hero", selected_hero)
	for key in _levels:
		config.set_value("upgrades", key, _levels[key])
	config.save(SAVE_PATH)


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
