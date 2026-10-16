class_name Hideout
extends RefCounted

## 藏身处 —— A 阶段：仓库 + 商人 + 升级
##
## 依据 specs/tech-stack.md §4.7 / roadmap-bac.md §2：
##   A 阶段的藏身处 = 「商人 + 仓库」，不做自由摆放建造（D-07）。
##   升级树是内容消耗品，不是玩法本身 —— 这里只保留最必要的几条。
##
## 纯 RefCounted，可 headless 单测。

## 升级项：id -> {name, desc, base_cost, cost_growth, max_level, effect}
const UPGRADES := {
	"stash_size": {
		"name": "仓库扩建", "desc": "每级 +8 个仓库槽位", "base_cost": 1500,
		"cost_growth": 1.8, "max_level": 5, "per_level": 8,
	},
	"carry_size": {
		"name": "负重训练", "desc": "每级 +3 kg 负重上限", "base_cost": 1200,
		"cost_growth": 1.7, "max_level": 4, "per_level": 3,
	},
	"heal_speed": {
		"name": "战地急救", "desc": "每级治疗速度 +12%", "base_cost": 1800,
		"cost_growth": 1.9, "max_level": 3, "per_level": 0.12,
	},
	"merchant_rep": {
		"name": "商人关系", "desc": "每级出售价 +6%", "base_cost": 2200,
		"cost_growth": 2.0, "max_level": 3, "per_level": 0.06,
	},
}

## 商人的基础回收比例（按物品 value 的百分比）
const BASE_SELL_RATIO := 0.55
const BASE_SLOT_COUNT := 64        ## 仓库基础槽位（2026-10-14「优化仓库」扩容：40 -> 64）
const BASE_WEIGHT_LIMIT := 20.0
## 携带背包的槽位数。与 `RaidSession.DEFAULT_CARRY_SLOTS` 对齐 ——
## 两处不一致的话，玩家在藏身处能装下 12 格、进局却只有 10 格可用。
const PACK_SLOTS := 12

var stash: Inventory
var wallet: int = 0
var upgrades: Dictionary = {}       ## id -> level
## 藏身处的**配装**（穿在身上、要带进下一局的东西）。
##
## ⚠️ 为什么配装归藏身处而不是归战局：搜打撤的循环是
##   「在藏身处配装 -> 带进去 -> 死了全丢 / 活着带回来」。
##   如果配装每局临时决定，"死亡掉装备"就没有承担物 —— 丢掉的东西必须是
##   你**自己选好**带进去的。所以它是跨局持久状态，和 stash 一样进存档。
var loadout: Equipment = null
## ── 携带背包（"这一局带什么进去"）──
#
# ⚠️ 真机反馈 #2："人物在藏身处配装时候应该可以选择带物品去背包"。
#    改之前 `raid.carry` 里是**写死的三样起始物资**（绷带×2 + 医疗包 + 子弹×90），
#    玩家在藏身处完全没有发言权 —— 而搜打撤的核心恰恰是"自己决定带什么进去"。
#
# 语义（和 loadout 对称）：
#   · pack 里的东西 = **已经从仓库拿出来、准备带进去的**
#   · 进局：pack -> raid.carry（本局随身）
#   · 撤离：carry（含搜到的战利品）-> stash，pack 保持空（下一局重新选）
#   · 阵亡：carry 全丢 —— 所以"带进去的"就是有风险的，这正是该有的承担物
var pack: Inventory = null
var _items: Dictionary = {}
var _weapons: Dictionary = {}
var _attachments: Dictionary = {}
var _affixes: Dictionary = {}       ## affix_id -> AffixDef（全境2化 P1，透传给 loadout）


func _init(items: Dictionary = {}, starting_money: int = 0,
		weapons: Dictionary = {}, attachments: Dictionary = {},
		affixes: Dictionary = {}) -> void:
	_items = items
	_weapons = weapons
	_attachments = attachments
	_affixes = affixes
	wallet = starting_money
	stash = Inventory.new(slot_count(), items, BASE_WEIGHT_LIMIT * 99.0)
	for id in UPGRADES:
		upgrades[id] = 0
	loadout = Equipment.new(items, weapons, attachments, _affixes)
	pack = Inventory.new(PACK_SLOTS, items, BASE_WEIGHT_LIMIT)
	_apply_pack_limits()


# ─────────────────── 升级 ───────────────────

func level_of(id: String) -> int:
	return int(upgrades.get(id, 0))


func max_level_of(id: String) -> int:
	var u: Dictionary = UPGRADES.get(id, {})
	return int(u.get("max_level", 0))


func upgrade_cost(id: String) -> int:
	var u: Dictionary = UPGRADES.get(id, {})
	if u.is_empty():
		return -1
	var lv := level_of(id)
	if lv >= max_level_of(id):
		return -1
	return int(round(float(u["base_cost"]) * pow(float(u["cost_growth"]), float(lv))))


## 买一级升级。返回失败原因（空串 = 成功）。
func buy_upgrade(id: String) -> String:
	if not UPGRADES.has(id):
		return "没有这个升级项：%s" % id
	if level_of(id) >= max_level_of(id):
		return "已满级"
	var cost := upgrade_cost(id)
	if wallet < cost:
		return "钱不够（需要 %d，现有 %d）" % [cost, wallet]
	wallet -= cost
	upgrades[id] = level_of(id) + 1
	_apply_upgrades()
	return ""


func _apply_upgrades() -> void:
	# 仓库扩容
	var want_slots := slot_count()
	if stash.slot_count() != want_slots:
		stash.set_slot_capacity(want_slots)
	stash.max_weight = 999.0
	_apply_pack_limits()


## 携带背包的槽位数 / 负重上限跟随升级（「负重训练」加的就是这个上限）。
## ⚠️ 必须在这里同步，否则升级买了钱花了、背包上限却没变。
func _apply_pack_limits() -> void:
	if pack == null:
		return
	pack.set_slot_capacity(PACK_SLOTS)
	pack.max_weight = carry_weight_limit()


func slot_count() -> int:
	return BASE_SLOT_COUNT + level_of("stash_size") * int(UPGRADES["stash_size"]["per_level"])


func carry_weight_limit() -> float:
	return BASE_WEIGHT_LIMIT + float(level_of("carry_size")) * float(UPGRADES["carry_size"]["per_level"])


func heal_speed_multiplier() -> float:
	return 1.0 + float(level_of("heal_speed")) * float(UPGRADES["heal_speed"]["per_level"])


func sell_ratio() -> float:
	return BASE_SELL_RATIO + float(level_of("merchant_rep")) * float(UPGRADES["merchant_rep"]["per_level"])


## 产生一份"给这一局用"的装备配置（负重上限、治疗速度等）
func raid_modifiers() -> Dictionary:
	return {
		"carry_slots": 12,
		"carry_weight_limit": carry_weight_limit(),
		"heal_speed": heal_speed_multiplier(),
		# 死亡损失策略（3c）：默认【全掉】—— 与第七轮"死亡掉光装备"契约一致。
		# ⚠️ 这三个是【平衡专家的旋钮】（见 data/BALANCE_TUNING.md §9），默认全 0 = 严格全掉。
		#    想做"最值钱的 1 个装备槽 + 1 个背包槽必留"的保底安全网（避免"一死回到解放前"），
		#    把 death_insured 设 1；保险购买系统则另做 UI。改默认值属难度调参，交给专家拍板。
		"death_keep_equipment": 0.0,
		"death_keep_carry": 0.0,
		"death_insured": 0,
	}


# ─────────────────── 商人 ───────────────────

## 卖出物品。返回实际到账金额。
func sell(item_id: String, count: int) -> int:
	if count <= 0 or not stash.has_item(item_id):
		return 0
	var have := stash.count_of(item_id)
	var n := mini(have, count)
	if n <= 0:
		return 0
	var def: ItemDef = _items.get(item_id)
	if def == null:
		return 0
	var unit := int(round(float(def.value) * sell_ratio()))
	var total := unit * n
	stash.remove(item_id, n)
	wallet += total
	return total


## 买入物品（从商人处）。返回失败原因（空串 = 成功）。
func buy(item_id: String, count: int, unit_price: int = -1) -> String:
	if count <= 0:
		return "数量非法"
	var def: ItemDef = _items.get(item_id)
	if def == null:
		return "商人没有这个物品：%s" % item_id
	var price := unit_price if unit_price >= 0 else int(round(float(def.value) * 1.9))
	var total := price * count
	if wallet < total:
		return "钱不够（需要 %d，现有 %d）" % [total, wallet]
	var leftover := stash.add(item_id, count)
	if leftover > 0:
		return "仓库放不下（还差 %d 个）" % leftover
	wallet -= total
	return ""


func stock_price(item_id: String) -> int:
	var def: ItemDef = _items.get(item_id)
	if def == null:
		return -1
	return int(round(float(def.value) * 1.9))


## 把一局带回来的东西入库
func deposit(drops: Array) -> Array:
	return LootRoller.fill_inventory(stash, drops)


# ─────────────────── 配装（装备系统）───────────────────
#
# 藏身处这一侧只做两件事：把仓库里的东西穿上、把身上的东西脱回仓库。
# 判定与错误文案全在 Equipment 里（那里有单测），这里只是**换个容器** ——
# 战局里是 carry（死了就丢），藏身处里是 stash（永远安全）。

## 从仓库装备到身上。返回失败原因（空串 = 成功）。
func equip_from_stash(id: String) -> String:
	if loadout == null:
		return "配装不可用"
	return loadout.equip(stash, id)


## 把身上的装备脱回仓库。返回失败原因（空串 = 成功）。
func unequip_to_stash(slot: String) -> String:
	if loadout == null:
		return "配装不可用"
	return loadout.unequip(stash, slot)


## 仓库里【可装备】的物品 id（去重，按价值从高到低）—— 配装面板左栏用
func equippable_in_stash() -> Array[String]:
	var seen: Dictionary = {}
	var out: Array[String] = []
	if loadout == null:
		return out
	for s in stash.slots:
		if s == null:
			continue
		var id := str(s["item_id"])
		if seen.has(id) or not loadout.is_equippable(id):
			continue
		seen[id] = true
		out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool:
		var da: ItemDef = _items.get(a)
		var db: ItemDef = _items.get(b)
		return (0 if da == null else da.value) > (0 if db == null else db.value))
	return out


## 装备槽的显示名（id -> 中文名）
func display_name_of(id: String) -> String:
	if id == "":
		return "（空）"
	var d: ItemDef = _items.get(id)
	if d != null:
		return d.name
	var w: WeaponDef = _weapons.get(id)
	if w != null:
		return w.name
	return id


# ─────────────────── 修理（装备损耗系统）───────────────────
#
# 损耗发生在战局（打一局 -> 枪/甲掉耐久），**回本**发生在藏身处 ——
# 这里是那个"回本"入口。逻辑放 sim 层（纯 RefCounted）才好单测。

## 每点耐久的修理费。缺 1 点 = 2 元。
## ⚠️ 刻意便宜：损耗系统要制造"维护节奏"，不是"修不起"的惩罚。
const REPAIR_PRICE_PER_POINT := 2


## 身上装备的耐久清单（只列**有耐久上限**的槽位）。
## 返回 [{slot, id, name, cur, max, missing}, ...]
func equipped_wear() -> Array:
	var out: Array = []
	if loadout == null:
		return out
	for slot in Equipment.SLOTS:
		var id: String = loadout.id_in(slot)
		if id == "":
			continue
		var mx := loadout.max_dur_of(id)
		if mx <= 0:
			continue                      # 无耐久的物件（如医疗品）不进清单
		var cur := loadout.dur_of(id)
		out.append({
			"slot": slot, "id": id, "name": display_name_of(id),
			"cur": cur, "max": mx, "missing": mx - cur,
		})
	return out


## 把身上装备全部修满需要的费用。
func repair_cost() -> int:
	var missing := 0
	for e in equipped_wear():
		missing += int(e["missing"])
	return missing * REPAIR_PRICE_PER_POINT


## 修满全部装备。返回 {ok, cost, points, err}。
## 资金不足时**不修**（全或无 —— 可预测，不做部分修理）。
func repair_all() -> Dictionary:
	var cost := repair_cost()
	if cost <= 0:
		return {"ok": true, "cost": 0, "points": 0, "err": ""}
	if wallet < cost:
		return {"ok": false, "cost": cost, "points": 0,
			"err": "资金不足（需 %d 元，现有 %d 元）" % [cost, wallet]}
	var points := 0
	for e in equipped_wear():
		points += loadout.repair_full(str(e["id"]))
	wallet -= cost
	return {"ok": true, "cost": cost, "points": points, "err": ""}


# ─────────────────── 携带背包（"带什么进局"）───────────────────
#
# 见 `pack` 字段的说明。这里是 stash <-> pack 的搬运，以及进局时的一次性转移。

## 仓库 -> 携带背包。count <= 0 表示"能带多少带多少"。
## 返回失败原因（空串 = 成功）。
func stash_to_pack(item_id: String, count: int = 0) -> String:
	if pack == null:
		return "携带背包不可用"
	var have := stash.count_of(item_id)
	if have <= 0:
		return "仓库里没有 %s" % display_name_of(item_id)
	var want := have if count <= 0 else mini(count, have)
	if want <= 0:
		return "数量非法"
	# 先查重量：不查的话进局立刻超重，玩家会莫名其妙变慢
	var d: ItemDef = _items.get(item_id)
	if d != null and pack.total_weight() + d.weight * float(want) > pack.max_weight + 0.0001:
		return "携带背包超重（上限 %.1f kg，现有 %.1f kg）" % [
			pack.max_weight, pack.total_weight()]
	# ⚠️ `Inventory.transfer_to()` 返回的是**没搬过去的数量**（leftover），不是搬过去的数量。
	#    第一版把它当成 moved，于是"全都搬成功"（leftover=0）反而被判成失败 ——
	#    表现是：物品其实进背包了，但界面报"槽位不够"。
	var leftover := stash.transfer_to(pack, item_id, want)
	if leftover >= want:
		return "携带背包槽位不够（%d/%d 已用）" % [pack.used_slots(), pack.slot_count()]
	if leftover > 0:
		return "携带背包放不下，只搬了 %d/%d 个（%d/%d 槽已用）" % [
			want - leftover, want, pack.used_slots(), pack.slot_count()]
	return ""


## 携带背包 -> 仓库。count <= 0 表示全部还回去。
func pack_to_stash(item_id: String, count: int = 0) -> String:
	if pack == null:
		return "携带背包不可用"
	var have := pack.count_of(item_id)
	if have <= 0:
		return "携带背包里没有 %s" % display_name_of(item_id)
	var want := have if count <= 0 else mini(count, have)
	# 同上：transfer_to 返回 leftover
	var leftover := pack.transfer_to(stash, item_id, want)
	if leftover > 0:
		return "仓库放不下（还差 %d 个）" % leftover
	return ""


## 把携带背包清空并还回仓库（面板上的「全部放回」）。
func pack_clear_to_stash() -> void:
	if pack == null:
		return
	for s in pack.slots.duplicate():
		if s == null:
			continue
		pack_to_stash(str(s["item_id"]))


## 进局时调用一次：把携带背包里的东西**搬进本局的随身背包**。
## 返回搬成功的【种数】（0 = 携带背包是空的，调用方可以走起始物资兜底）。
func drain_pack_into(carry: Inventory) -> int:
	if pack == null or carry == null:
		return 0
	var kinds := 0
	for s in pack.slots.duplicate():
		if s == null:
			continue
		var id := str(s["item_id"])
		var n := int(s["count"])
		var left := carry.add(id, n)
		var took := n - left
		if took > 0:
			kinds += 1
			pack.remove(id, took)
	return kinds


## 携带背包的清单（去重、按价值降序），面板与提示共用。
func pack_entries() -> Array:
	return _entries_of(pack)


## 仓库的清单（去重、按价值降序）。
func stash_entries() -> Array:
	return _entries_of(stash)


## 物品 category（原始字符串，来自 data/items.json）。未知 id 返回 ""。
func category_of(item_id: String) -> String:
	var d: ItemDef = _items.get(item_id)
	return "" if d == null else str(d.category)


## 把原始 category 归并成"仓库标签页"分组（UI 用，纯静态可单测）。
## 分组：武器 / 护甲 / 弹药 / 医疗 / 贵重（含钥匙）/ 杂物（其余，含背包）。
static func group_of(cat: String) -> String:
	match cat:
		"weapon": return "武器"
		"armor", "helmet": return "护甲"
		"ammo": return "弹药"
		"medical", "consumable": return "医疗"
		"valuables", "key": return "贵重"
		_: return "杂物"


## 仓库清单（经过滤 + 排序），供「优化仓库」的标签页/排序 UI 直接消费。
## [param group] "全部" 或 group_of() 的某分组；[param sort_mode] 0=价值降序 1=名称升序 2=数量降序。
func stash_entries_filtered(group: String, sort_mode: int) -> Array:
	var out: Array = []
	for e in stash_entries():
		if group == "全部" or group_of(category_of(str(e["id"]))) == group:
			out.append(e)
	out.sort_custom(func(a, b):
		if sort_mode == 1:
			return str(a["name"]) < str(b["name"])
		if sort_mode == 2:
			return int(a["count"]) > int(b["count"])
		return int(a["value"]) > int(b["value"]))   # 0 = 价值降序（默认）
	return out


func _entries_of(inv: Inventory) -> Array:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for s in inv.slots:
		if s == null:
			continue
		var id := str(s["item_id"])
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + int(s["count"])
	var out: Array = []
	for id in order:
		var d: ItemDef = _items.get(id)
		out.append({
			"id": id,
			"count": int(counts[id]),
			"name": str(d.name) if d != null else id,
			"value": (0 if d == null else d.value) * int(counts[id]),
		})
	out.sort_custom(func(a, b): return int(a["value"]) > int(b["value"]))
	return out


# ─────────────────── 状态 ───────────────────

func summary() -> String:
	var lv: Array[String] = []
	for id in UPGRADES:
		var l := level_of(id)
		if l > 0:
			lv.append("%s Lv%d" % [UPGRADES[id]["name"], l])
	return "藏身处：%s | 资金 %d 元 | 升级 [%s] | 配装 %s" % [
		stash.summary(), wallet, "无" if lv.is_empty() else ", ".join(lv),
		loadout.summary() if loadout != null else "不可用"]


func to_dict() -> Dictionary:
	return {
		"wallet": wallet,
		"upgrades": upgrades.duplicate(),
		"stash": stash.to_dict(),
		# v4 起：配装进存档。旧档没有这个键 -> from_dict 里默认空装备。
		"loadout": loadout.to_dict() if loadout != null else {},
		# v5 起：携带背包进存档（否则每次进藏身处都要重选一遍）。
		"pack": pack.to_dict() if pack != null else {},
	}


func from_dict(d: Dictionary) -> void:
	wallet = int(d.get("wallet", 0))
	upgrades = (d.get("upgrades", {}) as Dictionary).duplicate()
	stash.from_dict(d.get("stash", {}))
	if loadout != null:
		# ⚠️ 不能只在 has("loadout") 时重置 —— 否则"用一份没有 loadout 的
		#    dict 清空状态"（测试与读档失败路径都会这么做）会留下上一次的装备。
		loadout.from_dict(d.get("loadout", {}))
	if pack != null:
		pack.from_dict(d.get("pack", {}))
	_apply_upgrades()
