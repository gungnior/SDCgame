class_name CraftSystem
extends RefCounted

## 制造系统（C 阶段，specs/roadmap-bac.md §2「制造系统」）
##
## 职责：按 data/recipes.json 的配方，把背包里的输入物品换成产物。
##   纯 RefCounted —— 不读文件、不碰节点树，可在 --headless 下单测（D-06/T-69）。
##
## ─── 设计（最小可用，但一次定死、能直接长到 C 完整） ───
##   · 每个配方有 station（工作台类型）+ inputs（输入消耗）+ output（产物）。
##   · can_craft() 三道闸：① 玩家解锁了该 station ② 背包输入全部够数
##     ③ 背包放得下产物。
##   · craft() **原子执行**：先扣全部输入，再加产物。任一条件不满足整体不动
##     （绝不出现"扣了料没出货"的半吊子状态）。
##   · station 解锁状态由外部以 Dictionary 注入（station -> bool），CraftSystem
##     不判定来源（藏身处升级 / 任务奖励都行）—— 与 T-32「禁全局随机」同思路：
##     依赖注入，不自持状态。
##
## ⚠️ 制造【时间】(`RecipeDef.time`) 由表现层/会话层驱动（类似 raid 的倒计时），
##    本类只负责"能不能造 + 原子结算"，不自己计时 —— 保持可 headless 单测。

var _recipes: Dictionary = {}   # recipe_id -> RecipeDef
var _items: Dictionary = {}     # item_id   -> ItemDef（备用：可拓展产量/价值校验）


func _init(recipes: Dictionary, items: Dictionary = {}) -> void:
	_recipes = recipes
	_items = items


func get_recipe(recipe_id: String) -> RecipeDef:
	return _recipes.get(recipe_id)


func recipe_count() -> int:
	return _recipes.size()


## 某 station 是否已解锁（stations: Dictionary station_id -> bool）
static func station_unlocked(stations: Dictionary, station: String) -> bool:
	return bool(stations.get(station, false))


## 缺什么材料。返回第一个"数量不足"的成分；材料齐全则返回 null。
##   供 UI 显示"还差 2 个 XX"。
func missing_input(recipe_id: String, inv: Inventory) -> RecipeDef.Ingredient:
	var r: RecipeDef = _recipes.get(recipe_id)
	if r == null:
		return null
	for g in r.inputs:
		if inv.count_of(g.item_id) < g.count:
			return g
	return null


## 三道闸全过才返回 true（不修改任何状态）
func can_craft(recipe_id: String, inv: Inventory, stations: Dictionary) -> bool:
	var r: RecipeDef = _recipes.get(recipe_id)
	if r == null:
		return false
	if not station_unlocked(stations, r.station):
		return false
	if missing_input(recipe_id, inv) != null:
		return false
	if not inv.can_add(r.output_item_id, r.output_count):
		return false
	return true


## 原子制造。成功返回 true，失败返回 false 且【不改动背包】。
func craft(recipe_id: String, inv: Inventory, stations: Dictionary) -> bool:
	if not can_craft(recipe_id, inv, stations):
		return false
	var r: RecipeDef = _recipes.get(recipe_id)
	# can_craft 已保证：输入够 + 产物放得下。先扣输入只会腾出更多空间，
	# 所以 add 的 leftover 必为 0；仍 defensive 检查，避免未来规则变动引入半吊子。
	for g in r.inputs:
		inv.remove(g.item_id, g.count)
	var leftover := inv.add(r.output_item_id, r.output_count)
	if leftover > 0:
		# 理论上不可达。若发生，回滚输入，保证原子性。
		for g in r.inputs:
			inv.add(g.item_id, g.count)
		inv.remove(r.output_item_id, r.output_count - leftover)
		return false
	return true
