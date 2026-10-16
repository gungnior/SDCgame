class_name RaidSession
extends RefCounted

## 一次突袭（搜 → 打 → 撤）的完整回合
##
## B 阶段核心循环的编排者：
##   进入地图 → 搜刮（LootRoller 填充容器）→ 战斗 → 撤离 / 死亡 → 结算
##
## ⚠️ 搜打撤的灵魂是【死亡掉落全部装备】。本类把这个规则做成了不可绕过的判定：
##   死亡 → carry 背包全部清空 + equipment（身上穿的）一并清空；
##   只有 stash（藏身处仓库）里的东西能留下来。
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

## 身上穿着的装备（由藏身处配装注入；null = 本局没有装备系统）
##
## ⚠️ 这里刻意**持引用而不是拷贝**：战局里捡到一把枪装到身上，
##    撤离后它就该是你的新配装 —— 写完直接落到 hideout.loadout 上，
##    不需要"结算时再搬一次"（多一次搬运就多一个漏搬的机会）。
##    代价是**死亡时必须显式清空**（见 _on_death）—— 那正是搜打撤的灵魂。
var equipment: Equipment = null
## 死亡损失策略（3c）。默认全掉（与旧行为一致）；保留比例/保险槽位由平衡专家调。
var death_policy: DeathPolicy = DeathPolicy.new()

## 任务系统（C 阶段内容，GameDesigner 填 data/missions.json）。
## 框架事件驱动：本会话在击杀/撤离/搜刮时 notify()，完成时发 mission_completed。
## 纯 RefCounted，无 Node 依赖，可 headless 单测。
var mission: MissionSystem = null
## 本局任务完成累计发放的钱（撤离结算后由调用方并入藏身处钱包）
var mission_wallet_earned: int = 0

var phase: int = Phase.PREP
var time_left: float = DEFAULT_RAID_SECONDS
var raid_seconds: float = DEFAULT_RAID_SECONDS

## 撤离点（逻辑格坐标的浮点中心）
var extract_points: Array[Vector2] = []
var extract_progress: float = 0.0
var extract_radius: float = 1.5            ## 距离撤离点多少格内算"在撤离"

## 肉鸽：本局生效的规则变体（2026-10-16）。由 view 层 roll 后注入；
## null = 无变体（老路径/单测直接构造 session 时）。
var run_mods: RunModifiers = null

## 战局统计
var containers_looted: int = 0
var enemies_killed: int = 0
var damage_taken: int = 0
var damage_dealt: int = 0

var _items: Dictionary = {}
var _rng: SimRng = null
var _map: MapGenerator = null
## ── 装备品质词条表（全境2化 P1，2026-10-16）──
## 本局世界生成（容器/尸体）roll 装备品质词条用；死亡保留的品质权重也查它。
## 空表 = 不 roll = 全普通品质（向后兼容）。
var _rarities: Array = []
var _affixes: Array = []


## 本局是否启用了装备品质词条（缺表时为 false）
func gear_enabled() -> bool:
	return not _rarities.is_empty() and not _affixes.is_empty()


## 对一批掉落里的【装备类】物品 roll 品质词条（全境2化 P1）。
## 规则：
##   · 只 roll weapon/armor/backpack 三类（数据层 helmet 同属 armor）；
##   · 已有 gear 键的跳过（不重复 roll）；
##   · 缺表 / rng 为空时原样返回（向后兼容）；
##   · rng 走本局注入的流（T-32：同 seed 整局可复现）。
## 返回同一个数组（原地改），方便链式调用。
func roll_gear_for_drops(drops: Array) -> Array:
	if not gear_enabled() or _rng == null:
		return drops
	for d in drops:
		if not (d is Dictionary):
			continue
		var dd: Dictionary = d as Dictionary
		if dd.has("gear"):
			continue
		var iid := str(dd.get("item_id", ""))
		var idef: ItemDef = _items.get(iid)
		if idef == null:
			continue
		if not ["weapon", "armor", "backpack"].has(idef.category):
			continue
		var g := GearGen.roll_gear(_rng, _rarities, _affixes, idef.category)
		if not g.is_empty():
			dd["gear"] = g
	return drops


## 死亡保留权重 = 物品价值 × 品质权重（全境2化 P1）。
## 高品质装备更可能被 plan_keep 留下 —— "金色枪比白色枪更值得活下来"。
## 无 gear（普通货/老档）时权重就是价值本身（与旧行为一致）。
func _keep_weight(item_id: String, gear: Dictionary) -> float:
	var v := float(_item_value(item_id))
	if gear.is_empty():
		return v
	var r: RarityDef = GearGen.find_rarity(_rarities, str(gear.get("rarity", "")))
	if r != null:
		v *= r.death_weight
	return v


## shared_stash：藏身处仓库必须【跨局共享】——否则"死亡掉装备"就没有对照物了。
## 不传则本局自带一个空仓库（仅适合单局测试）。
## mission_defs：任务定义字典（来自 DataRegistry.missions），空则本局无任务。
## gear_defs：装备品质/词条表（全境2化 P1）—— {"rarities": Array[RarityDef], "affixes": Array[AffixDef]}。
##   空字典 = 本局不 roll 品质词条（向后兼容：老调用方/缺表时全普通品质）。
func _init(items: Dictionary = {}, rng: SimRng = null, shared_stash: Inventory = null,
		modifiers: Dictionary = {}, mission_defs: Dictionary = {},
		gear_defs: Dictionary = {}) -> void:
	_items = items
	_rng = rng if rng != null else SimRng.new(1)
	_rarities = (gear_defs.get("rarities", []) as Array).duplicate()
	_affixes = (gear_defs.get("affixes", []) as Array).duplicate()
	if not mission_defs.is_empty():
		mission = MissionSystem.new(mission_defs)
		if mission != null:
			mission.mission_completed.connect(_on_mission_completed)
	# ⚠️ 负重上限与背包格数必须来自藏身处升级，**不能硬编码**。
	#    早先写死 `Inventory.new(12, _items, 20.0)` ——
	#    于是 `Hideout.carry_weight_limit()` 从来没被用过，
	#    玩家花 1200 元买「负重训练」完全没效果。
	var slots := int(modifiers.get("carry_slots", DEFAULT_CARRY_SLOTS))
	var wlimit := float(modifiers.get("carry_weight_limit", DEFAULT_CARRY_WEIGHT))
	carry = Inventory.new(slots, _items, wlimit)
	# 死亡损失策略（3c）：默认全掉；保留比例/保险槽位由 hideout 通过 modifiers 注入。
	death_policy.keep_equipment_ratio = clampf(float(modifiers.get("death_keep_equipment", 0.0)), 0.0, 1.0)
	death_policy.keep_carry_ratio = clampf(float(modifiers.get("death_keep_carry", 0.0)), 0.0, 1.0)
	death_policy.insured_slots = maxi(0, int(modifiers.get("death_insured", 0)))
	# 治疗速度同理（藏身处「战地急救」升级）
	heal_speed = clampf(float(modifiers.get("heal_speed", 1.0)), 0.2, 5.0)
	stash = shared_stash if shared_stash != null else Inventory.new(40, _items, 999.0)


const DEFAULT_CARRY_SLOTS := 12
const DEFAULT_CARRY_WEIGHT := 20.0

## 治疗速度倍率（藏身处升级提供，本局生效）
var heal_speed: float = 1.0


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
	# 任务：开局自动接取所有已加载任务（框架是"事件驱动 + 显式 start"，
	# 这里统一在开局部署，避免"任务永远停在 LOCKED、notify 不生效"）。
	if mission != null:
		for id in mission.ids():
			mission.start(id)


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
	# ⭐ 全境2化 P1：掉落先 roll 品质词条再入包（装备类才 roll，缺表时原样）
	var drops := roll_gear_for_drops(LootRoller.roll_for_room(table, _rng, depth, base_rolls))
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
	if mission != null:
		mission.notify("kill")


## 任务完成时发奖：物品直接进（共享）仓库；钱累计到 mission_wallet_earned，
## 由调用方在结算后并入藏身处钱包（wallet 在 Hideout，不在本会话）。
func _on_mission_completed(id: String) -> void:
	if mission == null:
		return
	var def: Dictionary = mission.def_of(id)
	var r: Dictionary = def.get("reward", {})
	var wallet := int(r.get("wallet", 0))
	if wallet > 0:
		mission_wallet_earned += wallet
	for it in r.get("items", []):
		var iid := str(it.get("item_id", ""))
		var cnt := int(it.get("count", 0))
		if iid != "" and cnt > 0:
			stash.add(iid, cnt)


## 当前任务进度快照（供 UI 显示）。无任务返回空数组。
func mission_status() -> Array:
	if mission == null:
		return []
	var out: Array = []
	for id in mission.ids():
		out.append({"id": id, "state": mission.state_of(id), "progress": mission.progress_of(id)})
	return out


func _on_death(reason: String) -> void:
	phase = Phase.DEAD
	# ⚠️ 搜打撤的灵魂：死亡按「死亡损失策略」掉落携带装备。
	#    默认策略 = 全掉（与旧行为一致）；具体保留比例/保险槽位由 DeathPolicy 调，
	#    【平衡专家】在 hideout.raid_modifiers() 或 raid.death_policy 上设。
	#    只有 stash（藏身处仓库）永远安全。
	lost_slots = 0
	lost_value = 0

	# ── 携带背包：按策略保留最值钱的若干槽，其余丢失 ──
	if death_policy.keep_carry_ratio > 0.0 or death_policy.insured_slots > 0:
		var cidx: Array = []
		var cvals: Array = []
		for i in carry.slots.size():
			var s = carry.slots[i]
			if s != null:
				cidx.append(i)
				# ⭐ 全境2化 P1：保留排序用 价值×品质权重（高品质更可能活下来）
				cvals.append(_keep_weight(str(s["item_id"]), s.get("gear", {})))
		var keep := DeathPolicy.plan_keep(cvals, death_policy.keep_carry_ratio, death_policy.insured_slots)
		var keepset := {}
		for i in keep:
			keepset[cidx[i]] = true
		for i in cidx:
			if not keepset.has(i):
				var sid := str(carry.slots[i]["item_id"])
				var cnt := int(carry.slots[i]["count"])
				carry.remove(sid, cnt)
				lost_slots += 1
				lost_value += _item_value(sid) * cnt
	else:
		lost_slots += carry.used_slots()
		lost_value += LootRoller.total_value(_carry_as_drops(), _items)
		carry.clear()

	# ── 身上装备：同理按策略保留，其余脱下（彻底丢失）──
	#    ⭐ 只丢背包是"半个搜打撤"：玩家会"好装备留身上、垃圾塞背包"，
	#       死亡惩罚就落不到真正值钱的东西上。所以身上装备也要过策略。
	if equipment != null:
		var eids: Array = []
		var evals: Array = []
		for s in Equipment.SLOTS:
			var id := equipment.id_in(s)
			if id != "":
				eids.append(id)
				# ⭐ 全境2化 P1：身上装备同样按 价值×品质权重 决定去留
				evals.append(_keep_weight(id, equipment.gear.get(s, {})))
		var keep_eq := DeathPolicy.plan_keep(evals, death_policy.keep_equipment_ratio, death_policy.insured_slots)
		var keepmap := {}
		for i in keep_eq:
			keepmap[eids[i]] = true
		for s in Equipment.SLOTS:
			var id := equipment.id_in(s)
			if id != "" and not keepmap.has(id):
				equipment.slots[s] = ""
				lost_slots += 1
				lost_value += _item_value(id)

	extract_progress = 0.0
	death_reason = reason


## 物品价值（死亡结算用）。_items 是 id -> ItemDef。
func _item_value(id: String) -> int:
	var d = _items.get(id)
	if d == null:
		return 0
	return int(d.value)


## 身上装备的总价值（只用于死亡结算的"丢了多少钱"）
func _worn_value() -> int:
	var v := 0
	if equipment == null:
		return 0
	for slot in Equipment.SLOTS:
		var id: String = equipment.id_in(slot)
		if id == "":
			continue
		var d: ItemDef = _items.get(id)
		if d != null:
			v += d.value
	return v


# ─────────────────── 装备（局内穿脱）───────────────────
#
# 局内从随身背包里穿/脱。**走 carry 而不是 stash** —— 这是"死亡掉装备"的
# 承载体：你从尸体上捡的枪先装进 carry，装上身后就归 equipment，
# 死了两者一起没。

## 局内穿装备（从随身背包里拿）。返回失败原因（空串 = 成功）。
func equip_from_carry(id: String) -> String:
	if equipment == null:
		return "本局没有装备系统"
	if phase != Phase.ACTIVE:
		return "本局已经结束了"
	return equipment.equip(carry, id)


## 局内脱下装备（放回随身背包）。返回失败原因（空串 = 成功）。
func unequip_from_carry(slot: String) -> String:
	if equipment == null:
		return "本局没有装备系统"
	if phase != Phase.ACTIVE:
		return "本局已经结束了"
	return equipment.unequip(carry, slot)


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
		var row := {"item_id": str(d.get("item_id", "")), "count": int(d.get("count", 0))}
		if d.has("gear"):
			row["gear"] = d["gear"]      # 全境2化 P1：品质词条随掉落进尸体
		items.append(row)
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
		if taken > 0 and mission != null:
			mission.notify("loot", taken)
		return taken
	return 0


## 拿走一具尸体的全部（能塞多少塞多少），返回没塞下的部分
func take_all_from_corpse(idx: int) -> Array:
	if idx < 0 or idx >= corpses.size():
		return []
	var drops: Array = corpses[idx]["drops"]
	var before_count := 0
	for d in drops:
		before_count += int(d["count"])
	var rest: Array = []
	for d in drops:
		var leftover := carry.add(str(d["item_id"]), int(d["count"]))
		if leftover > 0:
			rest.append({"item_id": str(d["item_id"]), "count": leftover})
	corpses[idx]["drops"] = rest.duplicate()
	var after_count := 0
	for d in rest:
		after_count += int(d["count"])
	var taken := before_count - after_count
	if taken > 0 and mission != null:
		mission.notify("loot", taken)
	return rest


# ─────────────────── 可搜索容器（2026-10-13）───────────────────
#
# 与尸体容器是同一套交互模式，但容器由**房间类型挂靠**生成：
#   房间 -> room_type.containers[] -> ContainerDef -> loot_table -> items
# 于是"军械库里有枪架、医疗室里有药柜"是**数据驱动**出来的，不是硬编码。

var containers: Array[ContainerInstance] = []
var _next_container_id: int = 0


## 登记一个容器实例。drops 是 LootRoller 按容器类型对应掉落表抽出来的。
func add_container(def: ContainerDef, pos: Vector2, drops: Array) -> int:
	var c := ContainerInstance.new()
	c.id = _next_container_id
	_next_container_id += 1
	c.def = def
	c.pos = pos
	for d in drops:
		c.drops.append({"item_id": str(d.get("item_id", "")), "count": int(d.get("count", 0))})
	containers.append(c)
	return c.id


## 附近最近的【未搜空】容器索引（没有则 -1）
func container_near(pos: Vector2, radius: float = 1.4) -> int:
	var best := -1
	var bd := radius
	for i in containers.size():
		var c: ContainerInstance = containers[i]
		if c.is_done():
			continue                      # 已搜空的容器不再提示
		var d := c.pos.distance_to(pos)
		if d <= bd:
			bd = d
			best = i
	return best


## 从容器拿走若干。返回实际拿走的数量（背包放不下会少于请求量）。
func take_from_container(idx: int, item_id: String, count: int) -> int:
	if idx < 0 or idx >= containers.size():
		return 0
	var c: ContainerInstance = containers[idx]
	var first := not c.searched
	var taken := c.take(item_id, count, carry)
	c.searched = true
	if taken > 0 and first:
		containers_looted += 1
	if taken > 0 and mission != null:
		mission.notify("loot", taken)
	return taken


## 拿走一个容器的全部（能塞多少塞多少），返回没塞下的部分
func take_all_from_container(idx: int) -> Array:
	if idx < 0 or idx >= containers.size():
		return []
	var c: ContainerInstance = containers[idx]
	var first := not c.searched
	var before_count := 0
	for d in c.drops:
		before_count += int(d["count"])
	var rest := c.take_all(carry)
	c.searched = true
	if first:
		containers_looted += 1
	var after_count := 0
	for d in rest:
		after_count += int(d["count"])
	var taken := before_count - after_count
	if taken > 0 and mission != null:
		mission.notify("loot", taken)
	return rest


## 主动撤离（也用于撤离进度走满时）
func extract() -> bool:
	if phase != Phase.ACTIVE:
		return false
	phase = Phase.EXTRACTED
	extract_progress = EXTRACT_COUNTDOWN
	if mission != null:
		mission.notify("extract")
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
		"mission_wallet": mission_wallet_earned,
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
