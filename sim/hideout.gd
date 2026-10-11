class_name Hideout
extends RefCounted

## 藏身处 —— A 阶段：仓库 + 商人 + 升级
##
## 依据 specs/tech-stack.md §4.7 / roadmap-bac.md §2：
##   A 阶段的藏身处 = 「商人 + 仓库」，不做自由摆放建造（D-07）。
##   升级树是内容消耗品，不是玩法本身 —— 这里只保留最必要的几条。
##
## 纯 RefCounted，可 headless 单测。

## 升级项：id -> {name, desc, base_cost, cost_growth, max_level, effect}
const UPGRADES := {
	"stash_size": {
		"name": "仓库扩建", "desc": "每级 +8 个仓库槽位", "base_cost": 1500,
		"cost_growth": 1.8, "max_level": 5, "per_level": 8,
	},
	"carry_size": {
		"name": "负重训练", "desc": "每级 +3 kg 负重上限", "base_cost": 1200,
		"cost_growth": 1.7, "max_level": 4, "per_level": 3,
	},
	"heal_speed": {
		"name": "战地急救", "desc": "每级治疗速度 +12%", "base_cost": 1800,
		"cost_growth": 1.9, "max_level": 3, "per_level": 0.12,
	},
	"merchant_rep": {
		"name": "商人关系", "desc": "每级出售价 +6%", "base_cost": 2200,
		"cost_growth": 2.0, "max_level": 3, "per_level": 0.06,
	},
}

## 商人的基础回收比例（按物品 value 的百分比）
const BASE_SELL_RATIO := 0.55
const BASE_SLOT_COUNT := 40
const BASE_WEIGHT_LIMIT := 20.0

var stash: Inventory
var wallet: int = 0
var upgrades: Dictionary = {}       ## id -> level
var _items: Dictionary = {}


func _init(items: Dictionary = {}, starting_money: int = 0) -> void:
	_items = items
	wallet = starting_money
	stash = Inventory.new(slot_count(), items, BASE_WEIGHT_LIMIT * 99.0)
	for id in UPGRADES:
		upgrades[id] = 0


# ─────────────────── 升级 ───────────────────

func level_of(id: String) -> int:
	return int(upgrades.get(id, 0))


func max_level_of(id: String) -> int:
	var u: Dictionary = UPGRADES.get(id, {})
	return int(u.get("max_level", 0))


func upgrade_cost(id: String) -> int:
	var u: Dictionary = UPGRADES.get(id, {})
	if u.is_empty():
		return -1
	var lv := level_of(id)
	if lv >= max_level_of(id):
		return -1
	return int(round(float(u["base_cost"]) * pow(float(u["cost_growth"]), float(lv))))


## 买一级升级。返回失败原因（空串 = 成功）。
func buy_upgrade(id: String) -> String:
	if not UPGRADES.has(id):
		return "没有这个升级项：%s" % id
	if level_of(id) >= max_level_of(id):
		return "已满级"
	var cost := upgrade_cost(id)
	if wallet < cost:
		return "钱不够（需要 %d，现有 %d）" % [cost, wallet]
	wallet -= cost
	upgrades[id] = level_of(id) + 1
	_apply_upgrades()
	return ""


func _apply_upgrades() -> void:
	# 仓库扩容
	var want_slots := slot_count()
	if stash.slot_count() != want_slots:
		stash.set_slot_capacity(want_slots)
	stash.max_weight = 999.0


func slot_count() -> int:
	return BASE_SLOT_COUNT + level_of("stash_size") * int(UPGRADES["stash_size"]["per_level"])


func carry_weight_limit() -> float:
	return BASE_WEIGHT_LIMIT + float(level_of("carry_size")) * float(UPGRADES["carry_size"]["per_level"])


func heal_speed_multiplier() -> float:
	return 1.0 + float(level_of("heal_speed")) * float(UPGRADES["heal_speed"]["per_level"])


func sell_ratio() -> float:
	return BASE_SELL_RATIO + float(level_of("merchant_rep")) * float(UPGRADES["merchant_rep"]["per_level"])


## 产生一份"给这一局用"的装备配置（负重上限、治疗速度等）
func raid_modifiers() -> Dictionary:
	return {
		"carry_slots": 12,
		"carry_weight_limit": carry_weight_limit(),
		"heal_speed": heal_speed_multiplier(),
	}


# ─────────────────── 商人 ───────────────────

## 卖出物品。返回实际到账金额。
func sell(item_id: String, count: int) -> int:
	if count <= 0 or not stash.has_item(item_id):
		return 0
	var have := stash.count_of(item_id)
	var n := mini(have, count)
	if n <= 0:
		return 0
	var def: ItemDef = _items.get(item_id)
	if def == null:
		return 0
	var unit := int(round(float(def.value) * sell_ratio()))
	var total := unit * n
	stash.remove(item_id, n)
	wallet += total
	return total


## 买入物品（从商人处）。返回失败原因（空串 = 成功）。
func buy(item_id: String, count: int, unit_price: int = -1) -> String:
	if count <= 0:
		return "数量非法"
	var def: ItemDef = _items.get(item_id)
	if def == null:
		return "商人没有这个物品：%s" % item_id
	var price := unit_price if unit_price >= 0 else int(round(float(def.value) * 1.9))
	var total := price * count
	if wallet < total:
		return "钱不够（需要 %d，现有 %d）" % [total, wallet]
	var leftover := stash.add(item_id, count)
	if leftover > 0:
		return "仓库放不下（还差 %d 个）" % leftover
	wallet -= total
	return ""


func stock_price(item_id: String) -> int:
	var def: ItemDef = _items.get(item_id)
	if def == null:
		return -1
	return int(round(float(def.value) * 1.9))


## 把一局带回来的东西入库
func deposit(drops: Array) -> Array:
	return LootRoller.fill_inventory(stash, drops)


# ─────────────────── 状态 ───────────────────

func summary() -> String:
	var lv: Array[String] = []
	for id in UPGRADES:
		var l := level_of(id)
		if l > 0:
			lv.append("%s Lv%d" % [UPGRADES[id]["name"], l])
	return "藏身处：%s | 资金 %d 元 | 升级 [%s]" % [
		stash.summary(), wallet, "无" if lv.is_empty() else ", ".join(lv)]


func to_dict() -> Dictionary:
	return {
		"wallet": wallet,
		"upgrades": upgrades.duplicate(),
		"stash": stash.to_dict(),
	}


func from_dict(d: Dictionary) -> void:
	wallet = int(d.get("wallet", 0))
	upgrades = (d.get("upgrades", {}) as Dictionary).duplicate()
	stash.from_dict(d.get("stash", {}))
	_apply_upgrades()
