extends TestSuite

## 全境2化装备 Phase 1（2026-10-16 · WorkBuddy）
##
## 背景：拥有者拍板「数值偏 RPG，装备系统参考全境封锁2」。本套件钉死：
##   ① roll 确定性（同 seed 同结果，T-32）；
##   ② 品质词条数上限 + 同类别词条不重复；
##   ③ 三种词条类型（pct / pct_neg / flat）的应用数学；
##   ④ 装备评分随品质/词条数单调递增；
##   ⑤ 向后兼容 —— 空表 / 无 gear 装备的行为与 2026-10-16 之前逐字一致；
##   ⑥ Inventory 槽位 gear round-trip（含 transfer_to 与存档序列化）；
##   ⑦ Equipment 穿上/脱下搬运 gear + effective_armor 词条叠加；
##   ⑧ build_loadout 武器词条乘区（32 × 1.10 = 35）；
##   ⑨ raid_session 只 roll 装备类掉落 + 死亡保留品质加权；
##   ⑩ 数据契约（5 品质 8 词条，id 唯一，零 errors）。


func register() -> void:
	_suite("roll 确定性：同 seed 同结果，不同 seed 不同", _test_roll_determinism)
	_suite("品质词条数上限 + 同类别不重复", _test_affix_count_and_unique)
	_suite("三种词条类型的应用数学", _test_affix_apply_math)
	_suite("装备评分单调性", _test_score_monotonic)
	_suite("向后兼容：空表 / 无 gear 行为不变", _test_backward_compat)
	_suite("Inventory gear round-trip", _test_inventory_gear)
	_suite("Equipment 穿脱搬运 gear + effective_armor", _test_equipment_gear)
	_suite("build_loadout 武器词条乘区", _test_loadout_weapon_affix)
	_suite("raid_session 掉落 roll + 死亡品质加权", _test_raid_session_gear)
	_suite("数据契约：5 品质 8 词条", _test_data_contract)


func _fresh_reg() -> DataRegistry:
	var reg := DataRegistry.new()
	var ok: bool = reg.load_all("C")
	_check(ok, "DataRegistry.load_all(C) 应零错误（含 gear_rarity/gear_affixes）")
	return reg


func _test_roll_determinism() -> void:
	var reg := _fresh_reg()
	var a := GearGen.roll_gear(SimRng.new(12345), reg.gear_rarities, reg.gear_affixes, "weapon")
	var b := GearGen.roll_gear(SimRng.new(12345), reg.gear_rarities, reg.gear_affixes, "weapon")
	_check_eq(str(a), str(b), "同 seed 两次 roll 必须逐字节相等（T-32 可复现）")
	var c := GearGen.roll_gear(SimRng.new(999), reg.gear_rarities, reg.gear_affixes, "weapon")
	if str(a) == str(c):
		# 概率事件，不视为 bug（2^32 空间里撞一次纯属运气）
		print("[s28] 备注：seed 12345 与 999 恰好 roll 出同一件装备（概率极小，非 bug）")
	_check(not a.is_empty(), "roll 出装备（rarities 非空）")


func _test_affix_count_and_unique() -> void:
	var reg := _fresh_reg()
	# 200 个 seed 全类别采样：词条数 ≤ 品质上限、同类别内不重复
	for i in range(200):
		var g := GearGen.roll_gear(SimRng.new(1000 + i), reg.gear_rarities, reg.gear_affixes, "weapon")
		var r: RarityDef = GearGen.find_rarity(reg.gear_rarities, str(g.get("rarity", "")))
		_check(r != null, "roll 出的 rarity id 必须在表里")
		if r == null:
			continue
		var seen: Array = []
		for e in (g.get("affixes", []) as Array):
			_check((e as Dictionary).has("id"), "词条必须带 id")
			_check(not seen.has((e as Dictionary)["id"]), "同类别词条不许重复（%s）" % str((e as Dictionary)["id"]))
			seen.append((e as Dictionary)["id"])
		var n: int = (g.get("affixes", []) as Array).size()
		_check(n <= r.affix_count, "词条数 %d 不得超过品质上限 %d" % [n, r.affix_count])
		_check(n == r.affix_count, "Phase 1 词条数应精确等于品质上限（%d vs %d）" % [n, r.affix_count])


func _test_affix_apply_math() -> void:
	var reg := _fresh_reg()
	var dmg: AffixDef = reg.get_affix("aff_weapon_dmg")
	var reload: AffixDef = reg.get_affix("aff_reload")
	var armor: AffixDef = reg.get_affix("aff_armor")
	_check(dmg != null and reload != null and armor != null, "三类代表词条都应在表里")
	if dmg == null or reload == null or armor == null:
		return
	_check_eq(dmg.kind, "pct", "武器伤害 = 正向 pct")
	_check_eq(reload.kind, "pct_neg", "装填速度 = 负向 pct_neg")
	_check_eq(armor.kind, "flat", "护甲强化 = flat 直加")
	# pct：100 × 1.10 = 110
	_check(absf(dmg.apply_to(100.0, 0.10) - 110.0) < 0.001, "pct：100×(1+0.10)=110")
	# pct_neg：2.0 × 0.90 = 1.8
	_check(absf(reload.apply_to(2.0, 0.10) - 1.8) < 0.001, "pct_neg：2.0×(1-0.10)=1.8")
	# flat：3 + 2 = 5
	_check(absf(armor.apply_to(3.0, 2.0) - 5.0) < 0.001, "flat：3+2=5")
	# pct_neg 的钳制：-95% 是下限（不许把数值干到 0 以下）
	_check(reload.apply_to(2.0, 0.99) > 0.0, "pct_neg 有 0.95 下界钳制")
	# describe 展示
	_check_eq(dmg.describe(0.08), "武器伤害 +8%", "describe：pct 带 %")
	_check_eq(reload.describe(0.09), "装填速度 -9%", "describe：pct_neg 带负号")
	_check_eq(armor.describe(2.0), "护甲强化 +2", "describe：flat 无 %")


func _test_score_monotonic() -> void:
	var reg := _fresh_reg()
	var prev := -1
	for id in ["common", "fine", "rare", "epic", "legendary"]:
		var r: RarityDef = reg.get_rarity(id)
		_check(r != null, "品质 %s 应在表里" % id)
		if r == null:
			continue
		var s := GearGen.score_of({}, "weapon", r)
		_check(s > prev, "评分随品质递增（%s: %d > %d）" % [id, s, prev])
		prev = s
	# 词条加分：同品质下词条越多分越高
	var r: RarityDef = reg.get_rarity("rare")
	var g2 := {"rarity": "rare", "affixes": [{"id": "aff_rpm", "value": 0.05}]}
	var g4 := {"rarity": "rare", "affixes": [
		{"id": "aff_rpm", "value": 0.05}, {"id": "aff_range", "value": 0.05}]}
	_check(GearGen.score_of(g4, "weapon", r) > GearGen.score_of(g2, "weapon", r),
		"同品质词条越多评分越高")


func _test_backward_compat() -> void:
	# 空表 -> roll_gear 返回空字典（调用方 = 普通品质）
	var empty := GearGen.roll_gear(SimRng.new(1), [], [], "weapon")
	_check(empty.is_empty(), "rarities 为空 -> {}（无品质可 roll）")
	var reg := _fresh_reg()
	# 无 gear 的 Equipment：数值与 2026-10-16 之前逐字一致
	var eq := Equipment.new(reg.items, reg.weapons, reg.attachments, reg.affix_map())
	var inv := Inventory.new(12, reg.items, 50.0)
	_check_eq(inv.add_with_gear("armor_light", {}), 0, "无 gear 装备可入包")
	_check_eq(eq.equip(inv, "armor_light"), "", "穿上普通护甲")
	# armor_light 基础 armor=3，无词条 -> effective == worn
	_check_eq(eq.effective_armor(), 3, "无词条时 effective_armor == 基础护甲 3")
	_check_eq(eq.affix_pct("hp"), 0.0, "无词条时 hp 加成 0")
	# build_loadout 无 gear：伤害 = 裸枪值
	_check_eq(inv.add("weapon_rifle", 1), 0, "步枪入包")
	_check_eq(eq.equip(inv, "weapon_rifle"), "", "穿上步枪")
	var lo := eq.build_loadout()
	_check(lo != null, "无 gear 也能建 loadout")
	if lo != null:
		_check_eq(lo.to_weapon_def().damage, 32, "无词条时伤害 = 裸枪 32（与旧行为一致）")


func _test_inventory_gear() -> void:
	var reg := _fresh_reg()
	var inv := Inventory.new(12, reg.items, 50.0)
	var g := {"rarity": "epic", "affixes": [{"id": "aff_armor", "value": 2}]}
	_check_eq(inv.add_with_gear("armor_light", g), 0, "带 gear 装备入包")
	_check_eq(inv.add_with_gear("armor_light", g), 0, "同 id 第二件另开一槽（装备不堆叠）")
	_check_eq(inv.used_slots(), 2, "两件各占一槽")
	# take_slot 整件取出（含 gear）
	var idx := inv.first_slot_of("armor_light")
	var taken: Variant = inv.take_slot(idx)
	_check(taken is Dictionary, "take_slot 返回 dict")
	if taken is Dictionary:
		_check((taken as Dictionary).has("gear"), "取出的装备带着 gear")
		_check_eq((taken as Dictionary)["gear"], g, "gear 内容逐字节一致")
	_check_eq(inv.count_of("armor_light"), 1, "取走一件剩一件")
	# transfer_to 保留 gear（走 add_with_gear 不是 add）
	inv.add_with_gear("armor_light", g)
	var dst := Inventory.new(12, reg.items, 50.0)
	# count=5 但只有 2 件可搬 -> 未搬完的数量 = 3（与原语义一致：return count - moved）
	var left := inv.transfer_to(dst, "armor_light", 5)
	_check_eq(left, 3, "搬完 2 件，剩余请求量 3 计为未转移")
	_check_eq(dst.count_of("armor_light"), 2, "目标收到两件")
	var didx := dst.first_slot_of("armor_light")
	var dt: Variant = dst.take_slot(didx)
	if dt is Dictionary:
		_check((dt as Dictionary).has("gear"), "transfer_to 保留 gear（不被 add 洗掉）")
	# 存档 round-trip
	var d := dst.to_dict()
	var dst2 := Inventory.new(12, reg.items, 50.0)
	dst2.from_dict(d)
	var didx2 := dst2.first_slot_of("armor_light")
	var dt2: Variant = dst2.take_slot(didx2)
	if dt2 is Dictionary:
		_check((dt2 as Dictionary).has("gear"), "存档 round-trip 保留 gear")


func _test_equipment_gear() -> void:
	var reg := _fresh_reg()
	var eq := Equipment.new(reg.items, reg.weapons, reg.attachments, reg.affix_map())
	var inv := Inventory.new(12, reg.items, 50.0)
	var g := {"rarity": "epic", "affixes": [
		{"id": "aff_armor", "value": 2}, {"id": "aff_hp", "value": 0.08}]}
	inv.add_with_gear("armor_light", g)
	_check_eq(eq.equip(inv, "armor_light"), "", "穿上带词条护甲")
	_check(eq.gear.has("armor"), "gear 上车（槽位级）")
	# 基础 3 + flat 2 = 5
	_check_eq(eq.effective_armor(), 5, "effective_armor = 基础 3 + 词条 2")
	# hp 词条 8%
	_check(absf(eq.affix_pct("hp") - 0.08) < 0.001, "affix_pct(hp) = 0.08")
	# 脱下：gear 回背包
	_check_eq(eq.unequip(inv, "armor"), "", "脱下")
	_check(not eq.gear.has("armor"), "脱下后槽位 gear 清空")
	_check_eq(eq.effective_armor(), 0, "脱下后护甲回 0")
	var idx := inv.first_slot_of("armor_light")
	var back: Variant = inv.take_slot(idx)
	if back is Dictionary:
		_check((back as Dictionary).has("gear"), "脱下放回背包时 gear 不丢")
	# 存档 round-trip（v7 gear 键）
	inv.add_with_gear("armor_light", g)
	eq.equip(inv, "armor_light")
	var d := eq.to_dict()
	_check(d.has("gear"), "to_dict 带 gear 键")
	var eq2 := Equipment.new(reg.items, reg.weapons, reg.attachments, reg.affix_map())
	eq2.from_dict(d)
	_check_eq(eq2.effective_armor(), 5, "存档 round-trip 后词条护甲仍在")
	# 老档兼容：from_dict 无 gear 键 -> 空表（普通货，不补 roll）
	var eq3 := Equipment.new(reg.items, reg.weapons, reg.attachments, reg.affix_map())
	eq3.from_dict({"slots": {"armor": "armor_light"}})
	_check_eq(eq3.effective_armor(), 3, "老档无 gear -> 基础护甲，不凭空发词条")


func _test_loadout_weapon_affix() -> void:
	var reg := _fresh_reg()
	var eq := Equipment.new(reg.items, reg.weapons, reg.attachments, reg.affix_map())
	var inv := Inventory.new(12, reg.items, 50.0)
	var g := {"rarity": "rare", "affixes": [
		{"id": "aff_weapon_dmg", "value": 0.10},
		{"id": "aff_spread", "value": 0.15}]}
	inv.add_with_gear("weapon_rifle", g)
	_check_eq(eq.equip(inv, "weapon_rifle"), "", "穿上带词条步枪")
	var lo := eq.build_loadout()
	_check(lo != null, "建 loadout")
	if lo == null:
		return
	# damage 32 × (1+0.10) = 35.2 -> 35
	_check_eq(lo.to_weapon_def().damage, 35, "武器伤害词条：32×1.10=35.2->35")
	# spread 0.8 × (1-0.15) = 0.68（越低越好）
	_check(absf(lo.effective["spread_deg"] - 0.68) < 0.001, "散布词条：0.8×0.85=0.68")
	# rpm 不在词条里 -> 不变（600）
	_check_eq(lo.effective["rpm"], 600.0, "无词条字段保持原值（rpm 600）")


func _test_raid_session_gear() -> void:
	var reg := _fresh_reg()
	var rng := SimRng.new(42)
	var raid := RaidSession.new(reg.items, rng, null, {}, {},
		{"rarities": reg.gear_rarities, "affixes": reg.gear_affixes})
	_check(raid.gear_enabled(), "注入了品质表 -> gear_enabled")
	# 只 roll 装备类：弹药（堆叠货）跳过
	var drops := [
		{"item_id": "ammo_rifle", "count": 10},
		{"item_id": "armor_light", "count": 1},
		{"item_id": "consumable_can", "count": 1},
	]
	raid.roll_gear_for_drops(drops)
	_check(not (drops[0] as Dictionary).has("gear"), "弹药不 roll 品质（堆叠货）")
	_check((drops[1] as Dictionary).has("gear"), "护甲 roll 了品质词条")
	_check(not (drops[2] as Dictionary).has("gear"), "罐头不 roll 品质（非装备类）")
	# 已有 gear 不重复 roll
	var g0: Dictionary = (drops[1] as Dictionary)["gear"]
	raid.roll_gear_for_drops(drops)
	_check_eq((drops[1] as Dictionary)["gear"], g0, "已有 gear 不重复 roll")
	# 死亡保留权重：价值 × 品质权重（armor_light value=200）
	var wc := raid._keep_weight("armor_light", {})
	var wl := raid._keep_weight("armor_light", {"rarity": "legendary"})
	_check(absf(wc - 200.0) < 0.001, "无 gear -> 权重 = 价值 200")
	_check(wl > wc * 2.0, "传说(3.2x) 权重 640 >> 无 gear 200")
	_check(raid._keep_weight("armor_light", {"rarity": "common"}) < wc,
		"普通(0.7x) 权重 140 < 无 gear 200（白装该丢就丢）")
	# 缺表时 gear_enabled=false、roll 是空操作
	var raid2 := RaidSession.new(reg.items, SimRng.new(1), null, {}, {}, {})
	_check(not raid2.gear_enabled(), "不注入 -> gear_enabled=false")
	var d2 := [{"item_id": "armor_light", "count": 1}]
	raid2.roll_gear_for_drops(d2)
	_check(not (d2[0] as Dictionary).has("gear"), "缺表时不 roll（全普通品质）")


func _test_data_contract() -> void:
	var reg := DataRegistry.new()
	var ok: bool = reg.load_all("C")
	_check(ok, "load_all(C) 零错误（gear 表契约包含在内）")
	_check_eq(reg.gear_rarities.size(), 5, "5 个品质")
	_check_eq(reg.gear_affixes.size(), 8, "8 条词条")
	_check(reg.errors.is_empty(), "registry.errors 为空")
	var prev_w := 999999        # 第一个品质没有前序，用大数起跳
	for r in reg.gear_rarities:
		_check(not r.name.is_empty(), "品质 %s 有中文名" % r.id)
		_check(r.color.is_valid_html_color(), "品质 %s 颜色合法" % r.id)
		_check(r.drop_weight <= prev_w, "drop_weight 应按品质递减（%s: %d <= %d）" % [r.id, r.drop_weight, prev_w])
		prev_w = r.drop_weight
		_check(r.death_weight > 0.0, "品质 %s 死亡权重 > 0" % r.id)
	for a in reg.gear_affixes:
		_check(not a.name.is_empty(), "词条 %s 有中文名" % a.id)
		_check(not a.field.is_empty(), "词条 %s 有目标字段" % a.id)
		_check(a.max_value > 0.0, "词条 %s max > 0" % a.id)
		_check(a.fits("weapon") or a.fits("armor") or a.fits("backpack"),
			"词条 %s 至少适用一个装备类别" % a.id)
	# 武器词条 5 条、玩家属性词条 3 条
	var w := 0
	var p := 0
	for a in reg.gear_affixes:
		if a.fits("weapon"):
			w += 1
		if a.field in ["hp", "move_speed", "armor"]:
			p += 1
	_check_eq(w, 5, "武器词条 5 条")
	_check_eq(p, 3, "玩家属性词条 3 条（armor/hp/move_speed）")
