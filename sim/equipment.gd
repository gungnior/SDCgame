class_name Equipment
extends RefCounted

## 装备系统 —— 身上「穿着 / 拿着」的东西
##
## ⚠️ 关键设计决策：装备槽**独立持有 id**；装备时从背包 `remove`、脱下时 `add` 回去。
##    为什么不用"在背包里打个已装备标记"：
##      · 穿一身甲不该占掉背包槽位（否则没地方装战利品 —— 搜打撤的灵魂是"带得走多少"）；
##      · 重量要区分「在包里」（算背包限重）与「在身上」（通常不算）。
##
## ⚠️ 槽位与 id 空间**不同源，别混**：
##   weapon   -> **weapon_id**（weapons.json；同时也在 items.json 里有一条
##               category="weapon" 的**物品**记录，因为 Inventory 只认 item ——
##               战斗数值以 weapons.json 的 WeaponDef 为**单一真源**）
##   armor    -> item_id（category=armor 且 id 不含 "helmet"）
##   helmet   -> item_id（category=armor 且 id 含 "helmet"）
##   backpack -> item_id（category=backpack）
##
## 装备/脱下都**走 Inventory**（物品真的在背包与身上之间搬家），
## 所以"从尸体拿到枪 -> 装到身上"和"脱下 -> 卖掉"是同一套 API。
##
## ⚠️ 配件（mods）**不是物品**（attachments.json 独立于 items.json），
##    所以它们只记在 `mods` 里、**不占背包**。这也是"配件跟枪走"的实现方式：
##    表按 **weapon_id** 索引，换枪再换回来配置还在。
##
## 纯 RefCounted，可 headless 单测（D-06 / T-69）。

const SLOTS := ["weapon", "armor", "helmet", "backpack"]
## 槽位的中文名。**放在这里而不是各 UI 各写一份** —— 槽位定义在本文件，
## 名字跟着定义走，加槽位时不会漏改某个面板。
const SLOT_LABEL := {
	"weapon": "武器", "armor": "护甲", "helmet": "头盔", "backpack": "背包",
}

var slots: Dictionary = {}        ## slot -> id（"" = 空）
## ── 装备品质词条（全境2化 P1，2026-10-16）──
## slot -> gear dict（{"rarity": id, "affixes": [{"id":..,"value":..}, ...]}）。
## ⭐ 按【槽位】而不是按【id】记：两把同款枪品质/词条不同是刷装备的核心体验。
##    （dur 按 id 记是"同 id 共享磨损"的已知简化；gear 不能那么简化。）
##    无记录 = 普通品质零词条 = 与 2026-10-16 之前的行为一致（向后兼容老存档）。
var gear: Dictionary = {}
## weapon_id -> {att_slot -> att_id}。配件表按枪索引，**跟枪走**。
var mods: Dictionary = {}
## ── 装备损耗（2026-10-13）──
## item_id -> 当前耐久。**没有记录 = 全新**（dur_of 会返回最大耐久）。
## ⚠️ 按【id】而不是按【槽位】记：脱下再穿上**不会**刷新成新的（否则损耗形同虚设）。
##    代价是同 id 的多件装备共享磨损 —— Inventory 是纯堆叠模型，本来就分不出实例，
##    这是技术验证期的简化；将来 Inventory 支持实例后应改成实例级。
var dur: Dictionary = {}
var _items: Dictionary = {}       ## item_id   -> ItemDef
var _weapons: Dictionary = {}     ## weapon_id -> WeaponDef
var _attachments: Dictionary = {} ## attachment_id -> AttachmentDef
var _affixes: Dictionary = {}     ## affix_id -> AffixDef（全境2化 P1；空表 = 词条全不生效）
var _affix_list: Array = []       ## 同一份表的数组形态（GearGen.apply_affixes 要数组）


func _init(items: Dictionary = {}, weapons: Dictionary = {},
		attachments: Dictionary = {}, affixes: Dictionary = {}) -> void:
	_items = items
	_weapons = weapons
	_attachments = attachments
	_affixes = affixes
	_affix_list = affixes.values()
	for s in SLOTS:
		slots[s] = ""


## ⚠️ 方法名**不能叫 get** —— `get` 是 `Object` 的内置成员（`Object.get(property)`）；
##    在 class_name 类上定义同名方法会让调用方解析失败（实测：Parse Error
##    "Could not resolve external class member 'get'"，且 Godot --script 加载失败会
##    空转不退出 -> verify_all 卡死十几分钟）。所以用 `id_in`。
func id_in(slot: String) -> String:
	return str(slots.get(slot, ""))


func is_empty(slot: String) -> bool:
	return id_in(slot) == ""


## 身上穿了几件（死亡掉落统计用）
func worn_count() -> int:
	var n := 0
	for s in SLOTS:
		if id_in(s) != "":
			n += 1
	return n


## 清空身上装备（死亡掉落用）。
## ⚠️ **只清槽位与磨损，不清 mods**：配件不是物品、不占物质成本，
##    清掉它只是让玩家重调一遍，属于纯摩擦。枪丢了，配置留着
##    （= "你还记得这把枪怎么调"），下次拿到同款枪直接可用。
##    而 `dur`（磨损）是**实物属性**，装备都没了自然也不该留着 —— 否则
##    死亡后重新买一把同款枪，它一上手就是"半坏的"。
func clear() -> void:
	for s in SLOTS:
		slots[s] = ""
	dur.clear()
	gear.clear()      # 全境2化 P1：装备没了词条也没了（与 dur 同理，实物属性）


## 这个 id 该进哪个槽位（"" = 不能装备）
func slot_for(id: String) -> String:
	if _weapons.has(id):
		return "weapon"
	var d: ItemDef = _items.get(id)
	if d == null:
		return ""
	match d.category:
		"weapon":
			# 武器已作为 item 存在（id 与 weapons.json 一致），见 items.json
			return "weapon"
		"armor":
			# ⚠️ items.json 里头盔与护甲同为 category="armor"，
			#    目前靠 id 含 "helmet" 区分（数据层约定，见 SCHEMA.md）。
			return "helmet" if id.contains("helmet") else "armor"
		"backpack":
			return "backpack"
	return ""


func is_equippable(id: String) -> bool:
	return slot_for(id) != ""


## 装备。成功返回 ""，否则返回**中文原因**（直接给 UI toast 用）。
## ⚠️ 顺序：先取新的（腾出空间）再退回旧的 —— 否则背包满时换装会失败。
## ⚠️ 全境2化 P1：gear 随装备一起搬运（穿上的同时词条上车；脱下时放回背包）。
func equip(inv: Inventory, id: String) -> String:
	var slot := slot_for(id)
	if slot == "":
		return "这件不能装备"
	var idx := inv.first_slot_of(id)
	if idx == Inventory.UNSET:
		return "背包里没有这件"
	var taken: Variant = inv.take_slot(idx)
	if taken == null:
		return "背包里没有这件"
	var new_gear: Dictionary = {}
	if taken is Dictionary and (taken as Dictionary).has("gear"):
		new_gear = (taken as Dictionary)["gear"]
	var old: String = id_in(slot)
	if old != "":
		if not inv.can_add(old, 1):
			inv.add_with_gear(id, new_gear)   # 回滚：换新后放不下旧装备
			return "背包放不下换下的装备"
		inv.add_with_gear(old, gear.get(slot, {}))
	slots[slot] = id
	if new_gear.is_empty():
		gear.erase(slot)
	else:
		gear[slot] = new_gear
	return ""


## 脱下并放回背包。成功返回 ""，否则返回中文原因。
func unequip(inv: Inventory, slot: String) -> String:
	if not SLOTS.has(slot):
		return "没有这个槽位"
	var cur: String = id_in(slot)
	if cur == "":
		return "该槽位是空的"
	if not inv.can_add(cur, 1):
		return "背包放不下"
	var g: Dictionary = gear.get(slot, {})
	if not g.is_empty():
		if inv.add_with_gear(cur, g) > 0:
			return "背包放不下"
	else:
		inv.add(cur, 1)
	slots[slot] = ""
	gear.erase(slot)
	return ""


# ─────────────────── 装备损耗（2026-10-13）───────────────────
#
# 设计：耐久按 **item_id** 记在 `dur` 表里（见字段注释）。
#   · 武器：每次开火扣 1；磨损越重伤害越低（最差 ×0.6，不会变 0 —— 那太挫败）
#   · 护甲/头盔：每次受击按伤害量扣；耐久归零 -> 护甲值失效（不再减伤）
#   · 修理：藏身处商人 / 修理台（`repair` / `repair_full`）
# 契约见 data/SCHEMA.md §1 的 `durability` 字段。

## 该 id 的最大耐久。0 = 不参与损耗（弹药/医疗品等）。
func max_dur_of(id: String) -> int:
	if id == "":
		return 0
	var d: ItemDef = _items.get(id)
	if d != null and d.durability > 0:
		return d.durability
	# 武器若没有 items 记录（只注入了 weapons），给个保守默认值，
	# 否则"枪永不磨损"，损耗系统会在武器上静默失效。
	if _weapons.has(id):
		return 200
	return 0


## 当前耐久。没有记录 = 全新（返回最大耐久）。
func dur_of(id: String) -> int:
	var mx := max_dur_of(id)
	if mx <= 0:
		return 0
	return int(dur[id]) if dur.has(id) else mx


## 磨损比例 0~1（1 = 全新，0 = 完全损坏）。不参与损耗的物品恒为 1.0。
func wear_ratio(id: String) -> float:
	var mx := max_dur_of(id)
	if mx <= 0:
		return 1.0
	return clampf(float(dur_of(id)) / float(mx), 0.0, 1.0)


## 是否已损坏（有耐久且已归零）
func is_broken(id: String) -> bool:
	return max_dur_of(id) > 0 and dur_of(id) <= 0


## 扣耐久。返回【本次是否刚好损坏】（供 UI 播提示音 / toast）。
func apply_wear(id: String, amount: int = 1) -> bool:
	var mx := max_dur_of(id)
	if mx <= 0 or amount <= 0 or id == "":
		return false
	var before := dur_of(id)
	if before <= 0:
		return false
	var after := maxi(0, before - amount)
	dur[id] = after
	return after <= 0


## 修理，返回实际修回的耐久
func repair(id: String, amount: int) -> int:
	var mx := max_dur_of(id)
	if mx <= 0 or amount <= 0 or id == "":
		return 0
	var before := dur_of(id)
	var after := mini(mx, before + amount)
	dur[id] = after
	return after - before


## 修满，返回实际修回的耐久
func repair_full(id: String) -> int:
	return repair(id, max_dur_of(id))


## 某个槽位上装备的当前 / 最大耐久
func slot_dur(slot: String) -> int:
	return dur_of(id_in(slot))


func slot_max_dur(slot: String) -> int:
	return max_dur_of(id_in(slot))


## 磨损某个槽位上的装备。返回是否损坏。
func wear_slot(slot: String, amount: int = 1) -> bool:
	return apply_wear(id_in(slot), amount)


## ── 数值效果 ──

## 武器磨损对伤害的折损系数（1.0 ~ 0.6）。
## ⚠️ 刻意**留 0.6 的下限**：枪坏到打不动会让玩家直接删游戏，
##    而"变弱、想修"才是损耗系统该给的驱动力。
func weapon_damage_factor() -> float:
	return lerpf(0.6, 1.0, wear_ratio(id_in("weapon")))


## 身上护甲**基础**总值（护甲 + 头盔物品的 armor 字段，不含词条）。**已损坏的不计**。
## effective_armor() = 本函数 + 词条 flat 加成；玩家受击减伤请用 effective_armor()。
func worn_armor() -> int:
	var a := 0
	for s in ["armor", "helmet"]:
		var id := id_in(s)
		if id == "" or is_broken(id):
			continue
		var d: ItemDef = _items.get(id)
		if d != null:
			a += d.armor
	return a


## 身上护甲总值（护甲 + 头盔 + **护甲词条 flat 加成**）。**已损坏的不计**。玩家受击减伤用。
## 全境2化 P1：词条加成叠在基础护甲上（flat 直加，不走百分比）。
func effective_armor() -> int:
	var a := worn_armor()
	for s in ["armor", "helmet"]:
		var id := id_in(s)
		if id == "" or is_broken(id):
			continue
		a += int(round(_affix_sum(s, "armor")))
	return a


## 某槽位上某个字段的词条值总和（flat/pct 一律直接相加，符号在应用时处理）。
func _affix_sum(slot: String, field: String) -> float:
	var g: Dictionary = gear.get(slot, {})
	if g.is_empty():
		return 0.0
	var sum := 0.0
	for e in (g.get("affixes", []) as Array):
		if not (e is Dictionary):
			continue
		var ed: Dictionary = e as Dictionary
		var ad: AffixDef = _affixes.get(str(ed.get("id", "")))
		if ad == null or ad.field != field:
			continue
		sum += float(ed.get("value", 0.0))
	return sum


## 身上所有装备某个 pct 字段的百分比总和（raid_scene 建 vitals / 算移速时用）。
## flat 词条不计入（调用方要的是"乘区"）。例：affix_pct("hp") -> 0.08 = 生命 +8%。
func affix_pct(field: String) -> float:
	var sum := 0.0
	for s in SLOTS:
		var g: Dictionary = gear.get(s, {})
		if g.is_empty():
			continue
		for e in (g.get("affixes", []) as Array):
			if not (e is Dictionary):
				continue
			var ed: Dictionary = e as Dictionary
			var ad: AffixDef = _affixes.get(str(ed.get("id", "")))
			if ad == null or ad.field != field or ad.kind == "flat":
				continue
			sum += float(ed.get("value", 0.0))
	return sum


## 身上装备的总重量（武器取 WeaponDef.weight，其余取 ItemDef.weight）
func worn_weight() -> float:
	var w := 0.0
	for s in SLOTS:
		var id: String = id_in(s)
		if id == "":
			continue
		if s == "weapon":
			var wd: WeaponDef = _weapons.get(id)
			if wd != null:
				w += wd.weight
			else:
				# 没注入 weapons 时（如藏身处只拿到 items）退回物品重量，
				# 别让"身上重量"静默变 0
				var dw: ItemDef = _items.get(id)
				if dw != null:
					w += dw.weight
		else:
			var d: ItemDef = _items.get(id)
			if d != null:
				w += d.weight
	return w


# ─────────────────── 配件（改枪）───────────────────
#
# 配件不占背包槽（它们不是 item）—— 见文件头的说明。
# 面板负责"选中哪把枪"，本类只负责把 (gun, att_slot) -> att_id 记住。

## 某把枪当前的配件表（att_slot -> att_id）；返回的是**副本**，调用方改它没用
func mods_of(weapon_id: String) -> Dictionary:
	var m: Dictionary = mods.get(weapon_id, {})
	return m.duplicate()


## 装/换一个配件。att_id 传 "" 表示卸下该插槽。
## 返回错误原因（空串 = 成功）—— UI 直接拿去 toast。
func set_mod(weapon_id: String, att_slot: String, att_id: String) -> String:
	if weapon_id == "":
		return "没有选中武器"
	if not AttachmentDef.SLOTS.has(att_slot):
		return "没有这个配件插槽：%s" % att_slot
	if att_id == "":
		var m0: Dictionary = mods.get(weapon_id, {})
		m0.erase(att_slot)
		if m0.is_empty():
			mods.erase(weapon_id)
		else:
			mods[weapon_id] = m0
		return ""
	var a: AttachmentDef = _attachments.get(att_id)
	if a == null:
		return "没有这个配件：%s" % att_id
	if a.slot != att_slot:
		return "%s 是 %s 插槽的配件，装不进 %s" % [a.name, a.slot, att_slot]
	var m: Dictionary = mods.get(weapon_id, {})
	m[att_slot] = att_id
	mods[weapon_id] = m
	return ""


func clear_mods(weapon_id: String) -> void:
	mods.erase(weapon_id)


## 用当前装备的武器 + 记下的配件，构造一份**有效战斗数值**。
## 返回 null 表示武器槽是空的（调用方应回退到默认枪）。
func build_loadout(slot_limit: int = WeaponModding.SLOTS_C) -> WeaponModding.Loadout:
	var wid := id_in("weapon")
	if wid == "":
		return null
	var w: WeaponDef = _weapons.get(wid)
	if w == null:
		return null
	var lo := WeaponModding.create_loadout(w, slot_limit)
	if lo == null:
		return null
	# 排序只为让结果可复现（各配件改的字段互不重叠时顺序无关，
	# 但同一字段被两个配件叠加时顺序会影响 clamp —— 固定住更安全）
	var keys: Array = mods_of(wid).keys()
	keys.sort()
	var m := mods_of(wid)
	for k in keys:
		var a: AttachmentDef = _attachments.get(str(m[k]))
		if a == null:
			continue          # 数据里没有这个配件（脏档）—— 跳过，不清掉记录
		# 该枪插槽不够时 attach 会返回原因：静默保留配置，等玩家换回更"高级"的枪
		var _err := WeaponModding.attach(lo, a)
	return _apply_weapon_affixes(lo)


## 把武器槽 gear 的词条乘进 Loadout.effective（全境2化 P1，词条直加成乘区）。
## field 不在 effective 里的词条（armor/hp/move_speed 是玩家属性，不属武器数值）
## 自然跳过 —— 防呆：武器上滚出护甲词条也不会污染武器数值。
## 无 gear / 无词条表时原样返回（行为与 2026-10-16 之前逐字一致）。
func _apply_weapon_affixes(lo: WeaponModding.Loadout) -> WeaponModding.Loadout:
	if lo == null:
		return null
	# ⭐ 数学抽到 GearGen.apply_affixes —— 敌人侧（raid_scene）用的是**同一个函数**，
	#    两边公式不会各走各的（2026-10-16 Phase C）。
	return GearGen.apply_affixes(lo, gear.get("weapon", {}), _affix_list)


func summary() -> String:
	var parts: Array[String] = []
	for s in SLOTS:
		var id := id_in(s)
		parts.append("%s=%s" % [s, "-" if id == "" else id])
	return "[%s] 身上 %.1f kg" % [", ".join(parts), worn_weight()]


func to_dict() -> Dictionary:
	# ⚠️ 键名从 v3 起是 {"slots":…, "mods":…}；**旧档是扁平的 slot->id**，
	#    from_dict 必须两种都认（见那里的说明）。
	# v6 起加入 "dur"（装备损耗）；v7 起加入 "gear"（品质词条，全境2化 P1）。
	return {"slots": slots.duplicate(), "mods": mods.duplicate(true), "dur": dur.duplicate(),
		"gear": gear.duplicate(true)}


func from_dict(d: Dictionary) -> void:
	# 兼容两种历史形状：
	#   ① 新：{"slots": {...}, "mods": {...}, "dur": {...}, "gear": {...}}
	#   ② 旧：{"weapon": "weapon_rifle", ...}（v3 以前 to_dict 直接返回 slots）
	if d.has("slots"):
		var sd: Dictionary = d.get("slots", {})
		for s in SLOTS:
			slots[s] = str(sd.get(s, ""))
		mods = (d.get("mods", {}) as Dictionary).duplicate(true)
	else:
		for s in SLOTS:
			slots[s] = str(d.get(s, ""))
		mods = {}
	# 磨损表：老档没有 -> 空表 = 全部视为全新（不补偿、不惩罚）
	dur = (d.get("dur", {}) as Dictionary).duplicate()
	# 品质词条表：老档（v7 以前）没有 -> 空表 = 全部普通品质零词条。
	# ⚠️ 刻意不"补 roll"：老装备就该是普通货，凭空发词条会破坏搜打撤经济。
	gear = (d.get("gear", {}) as Dictionary).duplicate(true)
