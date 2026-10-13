class_name ItemDef
extends RefCounted

## 物品定义。数据来源：data/items.json
## 契约：data/SCHEMA.md §1
##
## 纯 RefCounted —— 不 extends Node、不引用 Control/Sprite2D、不读文件。
## 这是 D-06 / T-69「模拟层可 headless 单测」的硬性要求。

const CATEGORIES := [
	"medical", "ammo", "armor", "backpack",
	"consumable", "valuables", "key", "misc",
	## ⚠️ 2026-10-12 新增：武器也做成 item（**id 与 weapons.json 一致**）。
	##    理由：要让"敌人掉枪 -> 进背包 -> 装备到武器槽 -> 战斗用 WeaponDef"
	##    全链路统一，武器就必须能被 Inventory 持有；而 Inventory 只认 item。
	##    items.json 里只放"作为物品"的属性（重量/价值/堆叠=1），
	##    **战斗数值仍以 weapons.json 的 WeaponDef 为准**（单一真源，不重复定义）。
	"weapon",
]

var id: String = ""
var name: String = ""
var name_en: String = ""
var category: String = ""
var weight: float = 0.0
var stack_max: int = 1
var icon: String = ""
var value: int = 0
var desc: String = ""
var stage: String = "B"
## 医疗物品的治疗参数（medical 类才有）：{hp, time, bleed, armor}
var treat: Dictionary = {}

## ── 弹药弹型（2026-10-13 新增，仅 ammo 类）──
## ammo_type: standard / ap / hp
##   standard = 标准弹（万金油）· ap = 穿甲弹（打有甲强）· hp = 肉伤弹（打无甲强）
## pen   = 穿甲值 0~10，越高越能穿透护甲
## flesh = 对【无甲】目标的伤害倍率
## 结算见 sim/combat/damage_model.gd::resolve_vs_armor
var ammo_type: String = ""
var pen: float = 0.0
var flesh: float = 0.0

## ── 装备损耗（2026-10-13 新增，weapon/armor/backpack 类）──
## durability = 最大耐久（实例化时作为初始值）。0 表示该物品不参与损耗。
var durability: int = 0
## armor 值 0~10（仅 armor 类）。0 = 无甲。
var armor: int = 0

## ── 背包容量（仅 backpack 类，2026-10-13 第八轮后「3a」补全）──
## carry_slots  = 本局携带背包的【槽位数】（>0 时覆盖默认 12）
## carry_weight = 本局携带背包的【负重上限 kg】（>0 时取 max(升级上限, 此值)）
## ⚠️ 这两个是**数据驱动的数值**，具体多少由【平衡专家】在 data/items.json 调；
##    这里只把"装备背包槽 → 本局容量"的管道打通（默认 0 = 不覆盖）。
var carry_slots: int = 0
var carry_weight: float = 0.0


static func from_dict(d: Dictionary) -> ItemDef:
	var o := ItemDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.name_en = str(d.get("name_en", ""))
	o.category = str(d.get("category", ""))
	o.weight = float(d.get("weight", 0.0))
	o.stack_max = int(d.get("stack_max", 1))
	o.icon = str(d.get("icon", ""))
	o.value = int(d.get("value", 0))
	o.desc = str(d.get("desc", ""))
	o.stage = str(d.get("stage", "B"))
	o.treat = d.get("treat", {})
	o.ammo_type = str(d.get("ammo_type", ""))
	o.pen = float(d.get("pen", 0.0))
	o.flesh = float(d.get("flesh", 0.0))
	o.durability = int(d.get("durability", 0))
	o.armor = int(d.get("armor", 0))
	o.carry_slots = int(d.get("carry_slots", 0))
	o.carry_weight = float(d.get("carry_weight", 0.0))
	return o


func is_ammo() -> bool:
	return category == "ammo"


## 该物品是否参与损耗（有耐久上限）
func has_durability() -> bool:
	return durability > 0


## 对无甲目标的伤害倍率。没配 flesh 时视为 1.0（向后兼容老数据）。
func flesh_mult() -> float:
	return flesh if flesh > 0.0 else 1.0


func is_stackable() -> bool:
	return stack_max > 1


func _to_string() -> String:
	return "ItemDef(%s, %s, stack=%d)" % [id, name, stack_max]
