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
## ⭐ 搜刮进度（可玩性 Step2，2026-10-16）：秒。0 = 还没开始搜。
## `ContainerDef.search_time` 这个字段**早就存在，但全仓没有任何逻辑用它**
## （只出现在定义与 from_dict 里）—— 是个配了没接线的死字段。
## 本轮把它接上：没搜够时间就拿不到东西，站着翻箱子的那几秒是风险窗口。
var search_progress: float = 0.0


func is_empty() -> bool:
	return drops.is_empty()


## 搜完这个容器需要几秒（数据驱动）
func search_required() -> float:
	return def.search_time if def != null else 0.0


## 搜完了吗？搜完才允许从里面拿东西。
func is_unlocked() -> bool:
	return search_progress >= search_required()


## 搜刮进度 0~1（供 UI 进度条 / HUD）
func search_ratio() -> float:
	var need := search_required()
	return 1.0 if need <= 0.0 else clampf(search_progress / need, 0.0, 1.0)


## 推进搜刮。返回 true = **刚好在本帧搜完**（调用方据此播音效/刷面板）。
func advance_search(delta: float) -> bool:
	var was := is_unlocked()
	search_progress += delta
	return (not was) and is_unlocked()


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
##
## ⭐ 全境2化 P2（2026-10-16 补断点）：带 "gear" 键的掉落**必须**走
## `Inventory.add_with_gear` —— 走 `add` 会把品质词条静默洗掉
## （体检发现：容器/尸体里的带词条枪捡进背包就变回普通品质）。
func take(item_id: String, count: int, inv: Inventory) -> int:
	if inv == null or count <= 0:
		return 0
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		if str(d.get("item_id", "")) != item_id:
			continue
		var have := int(d.get("count", 0))
		var want := mini(have, count)
		var taken := 0
		if d.has("gear"):
			# 装备类 stack_max=1：一次只搬一件，且走 gear-aware 路径
			if inv.add_with_gear(item_id, (d["gear"] as Dictionary)) == 0:
				taken = 1
		else:
			var leftover := inv.add(item_id, want)
			taken = want - leftover
		d["count"] = have - taken
		if int(d["count"]) <= 0:
			drops.remove_at(i)
		return taken
	return 0


## 全部拿走（能塞多少塞多少），返回**没塞下的**部分
## ⭐ 同上：没塞下的带 gear 掉落要把 gear 原样留在容器里（下次还能捡到），不能丢。
func take_all(inv: Inventory) -> Array:
	if inv == null:
		return drops.duplicate()
	var rest: Array = []
	for d in drops:
		var iid := str(d.get("item_id", ""))
		if d.has("gear"):
			var failed := inv.add_with_gear(iid, (d["gear"] as Dictionary))
			if failed > 0:
				rest.append({"item_id": iid, "count": int(d.get("count", 1)),
					"gear": d["gear"]})
		else:
			var leftover := inv.add(iid, int(d.get("count", 0)))
			if leftover > 0:
				rest.append({"item_id": iid, "count": leftover})
	drops = rest
	return rest


func _to_string() -> String:
	return "ContainerInstance#%d(%s @ %s, %d 堆)" % [
		id, display_name(), str(pos), drops.size()]
