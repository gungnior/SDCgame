class_name LootTableDef
extends RefCounted

## 掉落表定义。数据来源：data/loot_tables.json
## 契约：data/SCHEMA.md §4
##
## 纯 RefCounted —— 见 ItemDef 的说明。

## 掉落表中的一个条目
class Entry extends RefCounted:
	var item_id: String = ""
	var weight: int = 1
	var min_count: int = 1
	var max_count: int = 1

	static func from_dict(d: Dictionary) -> Entry:
		var e := Entry.new()
		e.item_id = str(d.get("item_id", ""))
		e.weight = int(d.get("weight", 1))
		e.min_count = int(d.get("min", 1))
		e.max_count = int(d.get("max", 1))
		return e

	func _to_string() -> String:
		return "Entry(%s x%d-%d w=%d)" % [item_id, min_count, max_count, weight]

var id: String = ""
var name: String = ""
var entries: Array[Entry] = []
var stage: String = "B"


static func from_dict(d: Dictionary) -> LootTableDef:
	var o := LootTableDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.stage = str(d.get("stage", "B"))
	var raw: Array = d.get("entries", [])
	for e in raw:
		if e is Dictionary:
			o.entries.append(Entry.from_dict(e))
	return o


func total_weight() -> int:
	var t := 0
	for e in entries:
		t += e.weight
	return t


## 按权重抽一个条目。rng 必须是注入的 SimRng（T-32 禁止全局随机）。
func roll_entry(rng: SimRng) -> Entry:
	var total := total_weight()
	if total <= 0:
		return null
	var pick := rng.randi_range(0, total - 1)
	var acc := 0
	for e in entries:
		acc += e.weight
		if pick < acc:
			return e
	return entries[-1] if not entries.is_empty() else null


func _to_string() -> String:
	return "LootTableDef(%s, %d entries)" % [id, entries.size()]
