class_name RaidSession
extends RefCounted

## 一次突袭（搜 → 打 → 撤）的完整回合
##
## B 阶段核心循环的编排者：
##   进入地图 → 搜刮（LootRoller 填充容器）→ 战斗 → 撤离 / 死亡 → 结算
##
## ⚠️ 搜打撤的灵魂是【死亡掉落全部装备】。本类把这个规则做成了不可绕过的判定：
##   死亡 → carry 背包全部清空；只有 stash（藏身处仓库）里的东西能留下来。
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。

enum Phase { PREP, ACTIVE, EXTRACTED, DEAD }

const PHASE_NAME := {
	Phase.PREP: "PREP",
	Phase.ACTIVE: "ACTIVE",
	Phase.EXTRACTED: "EXTRACTED",
	Phase.DEAD: "DEAD",
}

const DEFAULT_RAID_SECONDS := 300.0        ## 一局 5 分钟
const EXTRACT_COUNTDOWN := 5.0             ## 站在撤离点需要待够的秒数

## 玩家
var hp: int = 100
var max_hp: int = 100

## 两本背包：
##   carry —— 带进战局的东西，【死了就全丢】
##   stash —— 藏身处仓库，永远安全
var carry: Inventory
var stash: Inventory

var phase: int = Phase.PREP
var time_left: float = DEFAULT_RAID_SECONDS
var raid_seconds: float = DEFAULT_RAID_SECONDS

## 撤离点（逻辑格坐标的浮点中心）
var extract_points: Array[Vector2] = []
var extract_progress: float = 0.0
var extract_radius: float = 1.5            ## 距离撤离点多少格内算"在撤离"

## 战局统计
var containers_looted: int = 0
var enemies_killed: int = 0
var damage_taken: int = 0
var damage_dealt: int = 0

var _items: Dictionary = {}
var _rng: SimRng = null
var _map: MapGenerator = null


## shared_stash：藏身处仓库必须【跨局共享】——否则"死亡掉装备"就没有对照物了。
## 不传则本局自带一个空仓库（仅适合单局测试）。
func _init(items: Dictionary = {}, rng: SimRng = null, shared_stash: Inventory = null) -> void:
	_items = items
	_rng = rng if rng != null else SimRng.new(1)
	carry = Inventory.new(12, _items, 20.0)
	stash = shared_stash if shared_stash != null else Inventory.new(40, _items, 999.0)


## 载入地图，取出撤离点
func load_map(map: MapGenerator) -> void:
	_map = map
	extract_points.clear()
	if map == null:
		return
	for r in map.extract_rooms():
		extract_points.append(Ballistics.cell_center(r.center))


## 开始一局
func start(seconds: float = DEFAULT_RAID_SECONDS) -> void:
	raid_seconds = seconds
	time_left = seconds
	extract_progress = 0.0
	phase = Phase.ACTIVE
	containers_looted = 0
	enemies_killed = 0
	damage_taken = 0
	damage_dealt = 0


func is_over() -> bool:
	return phase == Phase.EXTRACTED or phase == Phase.DEAD


func phase_name() -> String:
	return PHASE_NAME.get(phase, "?")


## 主循环。player_pos 是玩家当前的逻辑格浮点坐标。
func tick(delta: float, player_pos: Vector2) -> void:
	if phase != Phase.ACTIVE:
		return

	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		# 超时 = 撤离失败 = 死亡（装备全丢）—— 这是"必须做取舍"的压力来源
		_on_death("撤离超时")
		return

	# 撤离判定：站在撤离点范围内需要持续待够 EXTRACT_COUNTDOWN 秒
	var inside := false
	for p in extract_points:
		if player_pos.distance_to(p) <= extract_radius:
			inside = true
			break
	if inside:
		extract_progress += delta
		if extract_progress >= EXTRACT_COUNTDOWN:
			extract()
	else:
		extract_progress = maxf(0.0, extract_progress - delta * 2.0)


func extract_progress_ratio() -> float:
	return clampf(extract_progress / EXTRACT_COUNTDOWN, 0.0, 1.0)


## 搜刮一个容器。table 来自房间类型对应的 loot_table。
## 返回 {drops: Array, leftover: Array, value: int}
func loot_container(table: LootTableDef, depth: int = 0, base_rolls: int = 1) -> Dictionary:
	if phase != Phase.ACTIVE:
		return {"drops": [], "leftover": [], "value": 0}
	var drops := LootRoller.roll_for_room(table, _rng, depth, base_rolls)
	var leftover := LootRoller.fill_inventory(carry, drops)
	containers_looted += 1
	return {
		"drops": drops,
		"leftover": leftover,
		"value": LootRoller.total_value(drops, _items),
	}


## 玩家受伤
func take_damage(amount: int) -> void:
	if phase != Phase.ACTIVE or amount <= 0:
		return
	damage_taken += amount
	hp = maxi(0, hp - amount)
	if hp <= 0:
		_on_death("阵亡")


## 治疗
func heal(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before


## 击杀一个敌人（计入统计）
func register_kill() -> void:
	enemies_killed += 1


func _on_death(reason: String) -> void:
	phase = Phase.DEAD
	# ⚠️ 搜打撤的灵魂：死亡掉落【全部】携带装备。
	#    只有 stash 是安全的。
	# 先记下丢了多少格，供结算界面显示（清空后就数不出来了）
	lost_slots = carry.used_slots()
	lost_value = LootRoller.total_value(_carry_as_drops(), _items)
	carry.clear()
	extract_progress = 0.0
	death_reason = reason


## 把当前携带物转成掉落数组（用于统计价值）
func _carry_as_drops() -> Array:
	var out: Array = []
	for s in carry.slots:
		if s != null:
			out.append({"item_id": s["item_id"], "count": int(s["count"])})
	return out


var death_reason: String = ""
## 阵亡时丢掉的格数与价值（结算界面用）
var lost_slots: int = 0
var lost_value: int = 0


# ─────────────────── 尸体容器（真机反馈 #6）───────────────────
#
# 「敌人死亡后会有战利品在尸体里，配合背包框架给玩家搜索」
# 所以尸体不是"掉落在地上的一堆物品"，而是一个**可搜索的容器**：
# 玩家走到旁边 -> 打开搜索界面 -> 逐个拿。
# 这样才和背包框架形成闭环。

## 尸体列表。每项 {id, pos, enemy_id, drops:[{item_id,count}], searched:bool}
var corpses: Array = []
var _next_corpse_id: int = 0


## 敌人死亡时登记一具尸体。drops 是 LootRoller 抽出来的数组。
func add_corpse(pos: Vector2, enemy_id: String, drops: Array) -> int:
	var id := _next_corpse_id
	_next_corpse_id += 1
	var items: Array = []
	for d in drops:
		items.append({"item_id": str(d.get("item_id", "")), "count": int(d.get("count", 0))})
	corpses.append({
		"id": id, "pos": pos, "enemy_id": enemy_id,
		"drops": items, "searched": false,
	})
	return id


## 找到玩家搜索范围内最近的尸体索引（没有则 -1）
func corpse_near(pos: Vector2, radius: float = 1.6) -> int:
	var best := -1
	var bd := radius
	for i in corpses.size():
		var c: Dictionary = corpses[i]
		if c["drops"].is_empty() and bool(c["searched"]):
			continue                      # 已搜空的尸体不再提示
		var d := (c["pos"] as Vector2).distance_to(pos)
		if d <= bd:
			bd = d
			best = i
	return best


## 搜索一具尸体：标记为已搜，返回其中的物品
func search_corpse(idx: int) -> Array:
	if idx < 0 or idx >= corpses.size():
		return []
	corpses[idx]["searched"] = true
	return corpses[idx]["drops"]


## 从尸体拿走若干。返回实际拿走的数量（背包放不下会少于请求量）。
func take_from_corpse(idx: int, item_id: String, count: int) -> int:
	if idx < 0 or idx >= corpses.size() or count <= 0:
		return 0
	var drops: Array = corpses[idx]["drops"]
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		if str(d["item_id"]) != item_id:
			continue
		var have := int(d["count"])
		var want := mini(have, count)
		var leftover := carry.add(item_id, want)
		var taken := want - leftover
		d["count"] = have - taken
		if int(d["count"]) <= 0:
			drops.remove_at(i)
		return taken
	return 0


## 拿走一具尸体的全部（能塞多少塞多少），返回没塞下的部分
func take_all_from_corpse(idx: int) -> Array:
	if idx < 0 or idx >= corpses.size():
		return []
	var drops: Array = corpses[idx]["drops"]
	var rest: Array = []
	for d in drops:
		var leftover := carry.add(str(d["item_id"]), int(d["count"]))
		if leftover > 0:
			rest.append({"item_id": str(d["item_id"]), "count": leftover})
	corpses[idx]["drops"] = rest.duplicate()
	return rest


## 主动撤离（也用于撤离进度走满时）
func extract() -> bool:
	if phase != Phase.ACTIVE:
		return false
	phase = Phase.EXTRACTED
	extract_progress = EXTRACT_COUNTDOWN
	return true


## 结算：把带出来的战利品搬进藏身处，返回结算报告
func settle() -> Dictionary:
	if not is_over():
		return {}
	var brought: Array = []
	if phase == Phase.EXTRACTED:
		# 撤离成功 → 携带物全部进藏身处
		for i in carry.slots.size():
			var s = carry.slots[i]
			if s == null:
				continue
			brought.append({"item_id": s["item_id"], "count": int(s["count"])})
			var rest := stash.add(s["item_id"], int(s["count"]))
			if rest > 0:
				# 仓库也满了：多出来的丢失（B 阶段简化）
				pass
		carry.clear()

	return {
		"phase": phase_name(),
		"reason": death_reason,
		"extracted": phase == Phase.EXTRACTED,
		"brought_out": brought,
		"brought_out_value": LootRoller.total_value(brought, _items),
		"containers_looted": containers_looted,
		"enemies_killed": enemies_killed,
		"lost_slots": lost_slots,
		"lost_value": lost_value,
		"damage_taken": damage_taken,
		"damage_dealt": damage_dealt,
		"time_used": raid_seconds - time_left,
		"hp_left": hp,
	}


func summary() -> String:
	return "局内 %s | 剩余 %ds | HP %d/%d | 携带 %s | 撤离进度 %.0f%%" % [
		phase_name(), int(time_left), hp, max_hp, carry.summary(), extract_progress_ratio() * 100.0]
