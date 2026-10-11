class_name RoomTypeDef
extends RefCounted

## 房间类型定义。数据来源：data/rooms.json
## 契约：data/SCHEMA.md §5
##
## 纯 RefCounted —— 见 ItemDef 的说明。

const TYPES := ["spawn", "common", "extract"]

## 地图生成硬约束（SCHEMA §5 / tech-stack.md §5.9 T-34）
const MIN_EXTRACT_COUNT := 2      ## 撤离点至少两个，否则玩家无选择
const MIN_EXTRACT_GRAPH_DIST := 4 ## 防止出生即撤离

var id: String = ""
var name: String = ""
var room_type: String = "common"
var min_count: int = 0
var max_count: int = 0
var loot_table_id: String = ""
var enemy_budget_min: int = 0
var enemy_budget_max: int = 0
var min_graph_dist: int = 0
var stage: String = "B"


static func from_dict(d: Dictionary) -> RoomTypeDef:
	var o := RoomTypeDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.room_type = str(d.get("room_type", "common"))
	o.min_count = int(d.get("min_count", 0))
	o.max_count = int(d.get("max_count", 0))
	o.loot_table_id = str(d.get("loot_table_id", ""))
	o.enemy_budget_min = int(d.get("enemy_budget_min", 0))
	o.enemy_budget_max = int(d.get("enemy_budget_max", 0))
	o.min_graph_dist = int(d.get("min_graph_dist", 0))
	o.stage = str(d.get("stage", "B"))
	return o


func is_spawn() -> bool:
	return room_type == "spawn"


func is_extract() -> bool:
	return room_type == "extract"


## 在 [min_count, max_count] 内抽一个数量。rng 必须注入（T-32）。
func roll_count(rng: SimRng) -> int:
	if max_count <= min_count:
		return min_count
	return rng.randi_range(min_count, max_count)


func _to_string() -> String:
	return "RoomTypeDef(%s, %s, count=%d-%d)" % [id, room_type, min_count, max_count]
