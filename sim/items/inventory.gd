class_name Inventory
extends RefCounted

## 背包 —— 纯槽位 + 重量（specs/tech-stack.md §6.2 T-61）
##
##   ⚠️ 决策：B/A 阶段【不做 Tetris 占格】。
##     理由（T-61）：占格背包开发成本是槽位的 3~5 倍，自动整理是 NP-hard 近似，
##     而触屏上"手指遮挡目标格、需精确对齐 1~4 格"体验很差。
##     改为「槽位 + 宽格视觉」——有网格视觉、无占格。
##     Tetris 占格将来只放在藏身处（玩家不急的场景）。
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。UI 只做转发（T-63）。

const UNSET := -1

## 每个槽位是 null 或 {"item_id": String, "count": int}
var slots: Array = []
var max_weight: float = 20.0

## items 是 DataRegistry.items（id -> ItemDef），用于查 stack_max / weight
var _items: Dictionary = {}


func _init(slot_count: int = 12, items: Dictionary = {}, weight_limit: float = 20.0) -> void:
	slots.resize(slot_count)
	slots.fill(null)
	_items = items
	max_weight = weight_limit


func slot_count() -> int:
	return slots.size()


func set_slot_capacity(n: int) -> void:
	var old := slots.size()
	slots.resize(n)
	for i in range(old, n):
		slots[i] = null


func is_empty() -> bool:
	for s in slots:
		if s != null:
			return false
	return true


func used_slots() -> int:
	var n := 0
	for s in slots:
		if s != null:
			n += 1
	return n


func has_item(item_id: String) -> bool:
	return count_of(item_id) > 0


func count_of(item_id: String) -> int:
	var n := 0
	for s in slots:
		if s != null and s["item_id"] == item_id:
			n += int(s["count"])
	return n


func total_weight() -> float:
	var w := 0.0
	for s in slots:
		if s == null:
			continue
		var d: ItemDef = _items.get(s["item_id"])
		if d != null:
			w += d.weight * float(s["count"])
	return w


func is_overweight() -> bool:
	return total_weight() > max_weight


## 负重比（0~1+），供表现层做超重惩罚
func weight_ratio() -> float:
	if max_weight <= 0.0:
		return 0.0
	return total_weight() / max_weight


## 加物品。返回【没放下的剩余数量】（0 表示全部放入）。
## ⚠️ 装备类要走 `add_with_gear`（带品质词条）；本接口是无 gear 的普通路径
##    （商店货/老存档/堆叠货都用它，行为与 2026-10-16 之前逐字一致）。
func add(item_id: String, count: int) -> int:
	if count <= 0:
		return 0
	var d: ItemDef = _items.get(item_id)
	if d == null:
		return count   # 未知物品，一点都放不进

	var remaining := count

	# 1) 先填已有的同类堆叠
	if d.is_stackable():
		for i in slots.size():
			if remaining <= 0:
				break
			var s = slots[i]
			if s == null or s["item_id"] != item_id:
				continue
			var space := d.stack_max - int(s["count"])
			if space <= 0:
				continue
			var take := mini(space, remaining)
			s["count"] = int(s["count"]) + take
			remaining -= take

	# 2) 再开新槽位
	var per_slot := d.stack_max if d.is_stackable() else 1
	while remaining > 0:
		var idx := _first_free_slot()
		if idx == UNSET:
			break
		var take2 := mini(per_slot, remaining)
		slots[idx] = {"item_id": item_id, "count": take2}
		remaining -= take2

	return remaining


func _first_free_slot() -> int:
	for i in slots.size():
		if slots[i] == null:
			return i
	return UNSET


## 加一件【带品质词条的装备】（全境2化 Phase 1，2026-10-16）。
##
## ⭐ 只适用于 stack_max == 1 的装备类物品：装备永不堆叠，所以每槽天然是一件
##    独立装备，slot 上加一个可选 "gear" 键即可表达"这件有它自己的品质和词条"，
##    不破坏现有堆叠语义（弹药/医疗仍走普通 add）。
## gear 为空字典时等价于普通 add 一件（无品质 = 普通）。
## 返回没放下的剩余数量（装备只有 0/1 两种结果）。
func add_with_gear(item_id: String, gear: Dictionary) -> int:
	var d: ItemDef = _items.get(item_id)
	if d == null:
		return 1
	if d.is_stackable():
		return add(item_id, 1)      # 堆叠货不带 gear（防御：调用方不该这么用）
	var idx := _first_free_slot()
	if idx == UNSET:
		return 1
	var slot := {"item_id": item_id, "count": 1}
	if not gear.is_empty():
		slot["gear"] = gear.duplicate(true)
	slots[idx] = slot
	return 0


## 该 id 第一个所在槽位索引（挑选装备用，全境2化 P1）。没有返回 UNSET。
func first_slot_of(item_id: String) -> int:
	for i in slots.size():
		var s = slots[i]
		if s != null and s["item_id"] == item_id:
			return i
	return UNSET


## 把某个槽位**整件取出**（含 gear 字段），返回 slot dict 或 null。
## Equipment.equip 用它来"把这一件（连同它的品质词条）穿上"。
func take_slot(idx: int) -> Variant:
	if idx < 0 or idx >= slots.size():
		return null
	var s = slots[idx]
	if s == null:
		return null
	slots[idx] = null
	return s


## 移除若干。返回【实际移除的数量】。
func remove(item_id: String, count: int) -> int:
	if count <= 0:
		return 0
	var remaining := count
	for i in slots.size():
		if remaining <= 0:
			break
		var s = slots[i]
		if s == null or s["item_id"] != item_id:
			continue
		var take := mini(int(s["count"]), remaining)
		s["count"] = int(s["count"]) - take
		remaining -= take
		if int(s["count"]) <= 0:
			slots[i] = null
	return count - remaining


## 能否放下（不实际修改）
func can_add(item_id: String, count: int) -> bool:
	var d: ItemDef = _items.get(item_id)
	if d == null:
		return false
	var capacity := 0
	var per_slot := d.stack_max if d.is_stackable() else 1
	for s in slots:
		if s == null:
			capacity += per_slot
		elif d.is_stackable() and s["item_id"] == item_id:
			capacity += maxi(0, d.stack_max - int(s["count"]))
	return capacity >= count


## 本背包**还能再装下多少个**该物品（不实际修改）。
## 用于「自定义拾取数量」的上限提示（真机反馈 #5）：
## 让玩家知道"最多能拿几个"，而不是输入一个数然后被告知放不下。
func fit_count(item_id: String, want: int) -> int:
	var d: ItemDef = _items.get(item_id)
	if d == null or want <= 0:
		return 0
	var capacity := 0
	var per_slot := d.stack_max if d.is_stackable() else 1
	for s in slots:
		if s == null:
			capacity += per_slot
		elif d.is_stackable() and s["item_id"] == item_id:
			capacity += maxi(0, d.stack_max - int(s["count"]))
	return mini(want, capacity)


## 把"想拿的数量"夹到合法区间（真机反馈 #5：自定义拾取数量）。
##
## `want <= 0` 语义 = **全部**（与 Hideout.stash_to_pack / pack_to_stash 一致）；
## `avail` 是源里实际有的数量。返回 0 表示"一个都拿不了"。
##
## 纯静态 -> 可 headless 单测（UI 层的 -/+ 步进、一半、全部都调它，
## 保证"界面算出来的数"和"真正搬走的数"用的是同一套规则）。
static func clamp_amount(want: int, avail: int) -> int:
	if avail <= 0:
		return 0
	if want <= 0:
		return avail
	return mini(want, avail)


## 移到另一个背包（拾取/转移）。返回未转移的数量。
## ⚠️ 全境2化 P1：装备（stack_max=1）**逐槽整体搬运**，保留 gear ——
##    走 add/remove 会把品质词条洗掉（两把同款枪词条不同是刷装备的核心体验）。
##    堆叠货（弹药/医疗）仍走原来的 add/remove 路径，行为不变。
func transfer_to(dst: Inventory, item_id: String, count: int) -> int:
	var d: ItemDef = _items.get(item_id)
	if d == null:
		return count
	if not d.is_stackable():
		var moved := 0
		var i := 0
		while i < slots.size() and moved < count:
			var s = slots[i]
			if s != null and s["item_id"] == item_id:
				var leftover := dst.add_with_gear(item_id, s.get("gear", {}))
				if leftover > 0:
					break               # 对方放不下，停止搬运
				slots[i] = null
				moved += 1
			i += 1
		return count - moved
	var avail := mini(count, count_of(item_id))
	if avail <= 0:
		return count
	var leftover := dst.add(item_id, avail)
	var moved := avail - leftover
	remove(item_id, moved)
	return count - moved


## 一键整理：合并同类堆叠 + 挤紧空槽（触屏上"一键整理"是必需品，T-62）
func compact() -> void:
	var d_merged := 0
	for i in slots.size():
		var s = slots[i]
		if s == null:
			continue
		var d: ItemDef = _items.get(s["item_id"])
		if d == null or not d.is_stackable():
			continue
		# 把后面的同类并到当前格
		for j in range(i + 1, slots.size()):
			var t = slots[j]
			if t == null or t["item_id"] != s["item_id"]:
				continue
			var space := d.stack_max - int(s["count"])
			if space <= 0:
				break
			var take := mini(space, int(t["count"]))
			s["count"] = int(s["count"]) + take
			t["count"] = int(t["count"]) - take
			d_merged += take
			if int(t["count"]) <= 0:
				slots[j] = null
	# 挤紧：非空槽位前移
	var packed: Array = []
	for s in slots:
		if s != null:
			packed.append(s)
	while packed.size() < slots.size():
		packed.append(null)
	slots = packed


## 清空（死亡掉落全部装备用 —— 搜打撤的灵魂）
func clear() -> Array:
	var dropped: Array = []
	for i in slots.size():
		if slots[i] != null:
			dropped.append(slots[i])
			slots[i] = null
	return dropped


func to_dict() -> Dictionary:
	return {
		"slots": slots.duplicate(true),
		"max_weight": max_weight,
	}


func from_dict(d: Dictionary) -> void:
	var arr: Array = d.get("slots", [])
	slots = arr.duplicate(true)
	max_weight = float(d.get("max_weight", max_weight))


func summary() -> String:
	return "背包 %d/%d 槽，负重 %.1f/%.1f kg%s" % [
		used_slots(), slot_count(), total_weight(), max_weight,
		"（超重）" if is_overweight() else ""]
