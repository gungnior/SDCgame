class_name ContainerInstance
extends RefCounted

## 战局里的**一个具体容器实例**。
##
## 由 `RoomTypeDef.containers[]`（房间挂靠）+ `ContainerDef`（容器类型）生成，
## 里面装着 `LootRoller` 按容器类型对应的掉落表抽出来的具体物品。
##
## 三级对应关系（这就是"容器与房间类型挂靠、物品与容器类型对应"的落点）：
##   room_type.containers[]  →  def.id  →  def.loot_table_id  →  items
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测（D-06 / T-69）。

var id: int = 0
var def: ContainerDef = null
var pos: Vector2 = Vector2.ZERO
## [{item_id: String, count: int}, ...]
var drops: Array = []
## 是否已被打开过（用于"已搜过"的视觉/交互区分）
var searched: bool = false


func is_empty() -> bool:
	return drops.is_empty()


## 已搜空 —— 不再提示交互
func is_done() -> bool:
	return searched and drops.is_empty()


func display_name() -> String:
	return def.name if def != null else "容器"


func loot_table_id() -> String:
	return def.loot_table_id if def != null else ""


## 容器里某物品的总数
func count_of(item_id: String) -> int:
	var n := 0
	for d in drops:
		if str(d.get("item_id", "")) == item_id:
			n += int(d.get("count", 0))
	return n


## 拿走若干进 inv，返回**实际拿走**的数量（背包放不下会少于请求量）。
func take(item_id: String, count: int, inv: Inventory) -> int:
	if inv == null or count <= 0:
		return 0
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		if str(d.get("item_id", "")) != item_id:
			continue
		var have := int(d.get("count", 0))
		var want := mini(have, count)
		var leftover := inv.add(item_id, want)
		var taken := want - leftover
		d["count"] = have - taken
		if int(d["count"]) <= 0:
			drops.remove_at(i)
		return taken
	return 0


## 全部拿走（能塞多少塞多少），返回**没塞下的**部分
func take_all(inv: Inventory) -> Array:
	if inv == null:
		return drops.duplicate()
	var rest: Array = []
	for d in drops:
		var leftover := inv.add(str(d.get("item_id", "")), int(d.get("count", 0)))
		if leftover > 0:
			rest.append({"item_id": str(d.get("item_id", "")), "count": leftover})
	drops = rest
	return rest


func _to_string() -> String:
	return "ContainerInstance#%d(%s @ %s, %d 堆)" % [
		id, display_name(), str(pos), drops.size()]
