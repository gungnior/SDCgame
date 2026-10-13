class_name ContainerDef
extends RefCounted

## 容器类型定义。数据来源：data/containers.json
## 契约：data/SCHEMA.md §9
##
## 容器是「房间里真正能搜的东西」，它把三级对应关系串起来：
##   room_type.containers[]  →  container.id  →  container.loot_table_id  →  items
##
## 纯 RefCounted —— 不 extends Node、不引用 Control、不读文件（D-06 / T-69）。

var id: String = ""
var name: String = ""
var capacity: int = 8
var loot_table_id: String = ""
var search_time: float = 1.5
var desc: String = ""
var stage: String = "C"


static func from_dict(d: Dictionary) -> ContainerDef:
	var o := ContainerDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.capacity = int(d.get("capacity", 8))
	o.loot_table_id = str(d.get("loot_table_id", ""))
	o.search_time = float(d.get("search_time", 1.5))
	o.desc = str(d.get("desc", ""))
	o.stage = str(d.get("stage", "C"))
	return o


func _to_string() -> String:
	return "ContainerDef(%s, cap=%d, loot=%s)" % [id, capacity, loot_table_id]
