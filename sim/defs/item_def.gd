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
	return o


func is_stackable() -> bool:
	return stack_max > 1


func _to_string() -> String:
	return "ItemDef(%s, %s, stack=%d)" % [id, name, stack_max]
