class_name Room
extends RefCounted

## 地图上的一个房间（逻辑格坐标）。
## 关联：specs/tech-stack.md §5.2 图优先生成链路

var id: int = -1
var rect: Rect2i = Rect2i()        ## 逻辑格坐标
var center: Vector2i = Vector2i()  ## 逻辑格中心
var room_type_id: String = ""      ## 对应 data/rooms.json 的 id
var room_type: String = "common"   ## spawn / common / extract
var depth: int = 0                 ## 距出生点的图距离（跳数）
var enemy_budget: int = 0
var loot_table_id: String = ""
## 该房间要生成的可搜索容器：`[{container_id: String, pos: Vector2i}, ...]`
## 由 `RoomTypeDef.containers[]` 展开而来（2026-10-13）。
## MapGenerator 只负责**布点**；具体抽什么物品由 raid_scene 用掉落表执行
## （sim/mapgen 拿不到 loot_tables —— 保持分层干净）。
var container_spawns: Array = []


func _init(rid: int = -1, r: Rect2i = Rect2i()) -> void:
	id = rid
	rect = r
	center = Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)


func area() -> int:
	return rect.size.x * rect.size.y


func _to_string() -> String:
	return "Room#%d %s %s depth=%d" % [id, room_type, str(rect), depth]
