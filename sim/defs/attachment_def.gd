class_name AttachmentDef
extends RefCounted

## 枪械配件定义。数据来源：data/attachments.json
## 契约：data/SCHEMA.md §7
##
## 依据 specs/feasibility.md D-08：
##   第一版只改数值 + 锚点外观叠加，【不做视觉变形】。
##
## 纯 RefCounted，可 headless 单测。

const SLOTS := ["sight", "muzzle", "grip", "mag"]

var id: String = ""
var name: String = ""
var name_en: String = ""
var slot: String = ""              ## sight / muzzle / grip / mag
var mods: Dictionary = {}          ## 字段 -> 增量（正负皆可）
var weight: float = 0.0
var value: int = 0
var icon: String = ""
var desc: String = ""
var stage: String = "A"


static func from_dict(d: Dictionary) -> AttachmentDef:
	var o := AttachmentDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.name_en = str(d.get("name_en", ""))
	o.slot = str(d.get("slot", ""))
	o.mods = d.get("mods", {})
	o.weight = float(d.get("weight", 0.0))
	o.value = int(d.get("value", 0))
	o.icon = str(d.get("icon", ""))
	o.desc = str(d.get("desc", ""))
	o.stage = str(d.get("stage", "A"))
	return o


func is_valid_slot() -> bool:
	return SLOTS.has(slot)


func _to_string() -> String:
	return "AttachmentDef(%s, %s, mods=%s)" % [id, slot, str(mods)]
