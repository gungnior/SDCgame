class_name LootRoller
extends RefCounted

## 掉落抽取 —— 按 LootTableDef 的权重抽出容器内容
##
## 依据 specs/tech-stack.md §5.2 第 ⑨ 步：按房间类型 + 深度系数用 rand_weighted 花预算。
## 所有权重抽取都走【注入的 SimRng】，禁止全局随机（T-32）。

## 从一张掉落表抽一批物品。rolls 是抽取次数。
## 返回 [{item_id: String, count: int}, ...]
static func roll_container(table: LootTableDef, rng: SimRng, rolls: int) -> Array:
	var out: Array = []
	if table == null or rng == null or rolls <= 0:
		return out
	for _i in rolls:
		var e := table.roll_entry(rng)
		if e == null:
			continue
		var n := e.min_count
		if e.max_count > e.min_count:
			n = rng.randi_range(e.min_count, e.max_count)
		if n <= 0:
			continue
		out.append({"item_id": e.item_id, "count": n})
	return out


## 按房间深度决定抽取次数（越深越肥），再抽。
## depth_scale 是每跳深度增加的比例，base 是深度 0 的抽取次数。
static func roll_for_room(table: LootTableDef, rng: SimRng, depth: int,
		base_rolls: int = 1, depth_scale: float = 0.25, max_rolls: int = 6) -> Array:
	if table == null or rng == null:
		return []
	var rolls := base_rolls + int(floor(float(maxi(0, depth)) * depth_scale))
	rolls = clampi(rolls, 1, max_rolls)
	return roll_container(table, rng, rolls)


## 把抽到的一批物品塞进背包，返回【没塞下的】。
## 搜打撤的核心取舍就是在这里发生的：包满了，你得决定丢什么。
static func fill_inventory(inv: Inventory, drops: Array) -> Array:
	var leftover: Array = []
	for d in drops:
		var rest := inv.add(d["item_id"], int(d["count"]))
		if rest > 0:
			leftover.append({"item_id": d["item_id"], "count": rest})
	return leftover


## 把一批掉落折算成总价值（商人回收价），供经济曲线调参
static func total_value(drops: Array, items: Dictionary) -> int:
	var v := 0
	for d in drops:
		var def: ItemDef = items.get(d["item_id"])
		if def != null:
			v += def.value * int(d["count"])
	return v


## 把一批掉落折算成总重量
static func total_weight(drops: Array, items: Dictionary) -> float:
	var w := 0.0
	for d in drops:
		var def: ItemDef = items.get(d["item_id"])
		if def != null:
			w += def.weight * float(d["count"])
	return w
