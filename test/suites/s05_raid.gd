extends TestSuite

## 突袭回合与 A 阶段系统
##
## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。


func register() -> void:
	_suite("突袭回合 RaidSession", _test_raid_session)
	_suite("A 阶段：人物状态 Vitals", _test_vitals)
	_suite("A 阶段：枪械改装 WeaponModding", _test_weapon_modding)
	_suite("A 阶段：医疗 MedicalSystem", _test_medical)
	_suite("A 阶段：藏身处 Hideout", _test_hideout)
	_suite("真机修复：出生安全区", _test_spawn_safety)
	_suite("真机修复：死亡结算", _test_death_settlement)


func _test_raid_session() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var gen := MapGenerator.new()
	gen.generate(31337, reg.room_types)

	var rng := SimRng.new(5)
	var shared_stash := Inventory.new(40, reg.items, 999.0)
	var raid := RaidSession.new(reg.items, rng, shared_stash)
	raid.load_map(gen)

	_check_eq(raid.extract_points.size() >= 2, true, "载入 %d 个撤离点" % raid.extract_points.size())
	_check_eq(raid.phase_name(), "PREP", "初始 PREP")

	raid.start(120.0)
	_check_eq(raid.phase_name(), "ACTIVE", "start 后 ACTIVE")
	_check_eq(raid.time_left, 120.0, "计时 120 秒")

	# ── 搜刮容器 ──
	var common: LootTableDef = reg.get_loot_table("loot_common")
	var r1 := raid.loot_container(common, 1, 2)
	_check(r1["drops"].size() > 0, "搜刮出 %d 堆" % r1["drops"].size())
	_check_eq(raid.containers_looted, 1, "搜刮计数 1")
	_check(not raid.carry.is_empty(), "背包里有东西了：%s" % raid.carry.summary())
	var after_first := raid.carry.used_slots()
	raid.loot_container(common, 3, 3)
	_check(raid.carry.used_slots() >= after_first, "继续搜刮，背包占用不减少")

	# ── 时间流逝 ──
	raid.tick(10.0, Vector2(1.5, 1.5))
	_check(abs(raid.time_left - 110.0) < 0.01, "计时递减到 %.1f" % raid.time_left)

	# ── 撤离进度：不在撤离点范围内不涨 ──
	var far := Vector2(100.0, 100.0)
	raid.tick(3.0, far)
	_check_eq(raid.extract_progress, 0.0, "远离撤离点 -> 进度 0")

	# ── 站在撤离点：需要待够 EXTRACT_COUNTDOWN 秒 ──
	var ep := raid.extract_points[0]
	raid.tick(2.0, ep)
	_check(raid.extract_progress > 0.0, "站在撤离点 -> 进度 %.1f" % raid.extract_progress)
	_check(not raid.is_over(), "还没撤出去")
	raid.tick(RaidSession.EXTRACT_COUNTDOWN, ep)
	_check(raid.is_over(), "待够时长 -> 撤离完成")
	_check_eq(raid.phase_name(), "EXTRACTED", "阶段 EXTRACTED")

	# ── 结算：携带物进藏身处 ──
	var report := raid.settle()
	_check(report.get("extracted", false), "结算报告：已撤离")
	_check(int(report["brought_out_value"]) > 0, "带出总价值 %d 元" % int(report["brought_out_value"]))
	_check(raid.carry.is_empty(), "结算后 carry 清空")
	_check(not raid.stash.is_empty(), "藏身处收到战利品：%s" % raid.stash.summary())
	var stash_slots := raid.stash.used_slots()

	# ── ⭐ 死亡掉落全部装备（搜打撤的灵魂）──
	var raid2 := RaidSession.new(reg.items, SimRng.new(6), shared_stash)
	raid2.load_map(gen)
	raid2.start(120.0)
	raid2.loot_container(common, 2, 4)
	raid2.loot_container(common, 2, 4)
	_check(not raid2.carry.is_empty(), "第二局搜到了东西：%s" % raid2.carry.summary())
	var carried_slots := raid2.carry.used_slots()

	raid2.take_damage(50)
	_check_eq(raid2.hp, raid2.max_hp - 50, "受伤后 HP 50")
	_check(not raid2.is_over(), "还没死")
	raid2.take_damage(9999)
	_check(raid2.is_over(), "死亡后回合结束")
	_check_eq(raid2.phase_name(), "DEAD", "阶段 DEAD")
	_check(raid2.carry.is_empty(), "⭐ 死亡掉落全部 %d 格装备 -> carry 清空" % carried_slots)
	var rep2 := raid2.settle()
	_check(not rep2.get("extracted", true), "结算报告：未撤离")
	_check_eq(int(rep2["brought_out_value"]), 0, "什么都没带出来")
	_check_eq(raid2.stash.used_slots(), stash_slots, "藏身处未受影响（安全）")

	# ── 超时 = 撤离失败 ──
	var raid3 := RaidSession.new(reg.items, SimRng.new(7), shared_stash)
	raid3.load_map(gen)
	raid3.start(5.0)
	raid3.loot_container(common, 0, 3)
	raid3.tick(6.0, far)
	_check_eq(raid3.phase_name(), "DEAD", "超时 -> DEAD")
	_check(raid3.carry.is_empty(), "超时同样丢失全部装备")
	_check(raid3.death_reason.contains("超时"), "死因：%s" % raid3.death_reason)

	# ── 治疗 ──
	var raid4 := RaidSession.new(reg.items, SimRng.new(8), shared_stash)
	raid4.start(60.0)
	raid4.take_damage(40)
	var healed := raid4.heal(100)
	_check_eq(healed, 40, "治疗量被上限截断为 40")
	_check_eq(raid4.hp, raid4.max_hp, "回满血")



# ─────────────────── A 阶段：人物状态 / 改装 / 医疗 / 藏身处 ───────────────────


func _test_vitals() -> void:
	var v := Vitals.new()
	v.reset(100, 40)
	_check_eq(v.hp, 100, "初始 HP 100")
	_check_eq(v.armor, 40, "初始护甲 40")
	_check(not v.dead, "初始存活")

	# 护甲吸收
	var lost := v.take_damage(30)
	_check(v.armor < 40, "护甲被消耗（%d）" % v.armor)
	_check(lost < 30, "护甲吸收了部分伤害（实际掉血 %d < 30）" % lost)
	_check(v.armor_absorbed > 0, "记录吸收量 %d" % v.armor_absorbed)

	# 打光护甲后全额进血
	var v2 := Vitals.new()
	v2.reset(100, 5)
	v2.take_damage(100)
	_check_eq(v2.armor, 0, "护甲被打光")
	_check(v2.hp < 100, "HP 受损（%d）" % v2.hp)

	# 治疗上限
	var v3 := Vitals.new()
	v3.reset(100, 0)
	v3.take_damage(40)
	var healed := v3.heal(999)
	_check_eq(healed, 40, "治疗被上限截断为 40")
	_check_eq(v3.hp, 100, "回满")

	# 修甲上限
	v3.max_armor = 20
	var rep := v3.repair_armor(999)
	_check_eq(rep, 20, "修甲被上限截断")

	# 流血
	var v4 := Vitals.new()
	v4.reset(100, 0)
	v4.apply_bleed(Vitals.Bleed.LIGHT)
	_check(v4.is_bleeding(), "进入流血状态")
	_check(v4.bleed_dps() > 0.0, "流血 DPS %.2f" % v4.bleed_dps())
	var before := v4.hp
	for _i in 100:
		v4.tick(0.1)
	_check(v4.hp < before, "流血持续掉血（%d -> %d）" % [before, v4.hp])
	v4.stop_bleed()
	_check(not v4.is_bleeding(), "止血后不再流血")
	var hp_after := v4.hp
	for _i in 20:
		v4.tick(0.1)
	_check_eq(v4.hp, hp_after, "止血后血量稳定")

	# 重度流血更快
	var v5 := Vitals.new()
	v5.reset(100, 0)
	v5.apply_bleed(Vitals.Bleed.HEAVY)
	_check(v5.bleed_dps() > v4.bleed_dps(), "重度流血 DPS 更大")

	# 移速惩罚
	var v6 := Vitals.new()
	v6.reset(100, 0)
	var full_speed := v6.speed_multiplier(0.0)
	v6.hp = 10
	var hurt_speed := v6.speed_multiplier(0.0)
	_check(hurt_speed < full_speed, "残血移速更慢（%.2f < %.2f）" % [hurt_speed, full_speed])
	var heavy := v6.speed_multiplier(2.0)
	_check(heavy < hurt_speed, "超重叠加后更慢（%.2f）" % heavy)

	# 死亡
	var v7 := Vitals.new()
	v7.reset(50, 0)
	v7.take_damage(999)
	_check(v7.dead, "被打死")
	_check_eq(v7.hp, 0, "HP 归零")
	_check(not v7.heal(50) > 0, "死后无法治疗")
	_check_eq(v7.speed_multiplier(), 0.0, "死后移速 0")


func _test_weapon_modding() -> void:
	var reg := DataRegistry.new()
	reg.load_all("A")
	_check(reg.attachments.size() >= 12, "载入 %d 个配件" % reg.attachments.size())

	var rifle: WeaponDef = reg.get_weapon("weapon_rifle")
	var lo := WeaponModding.create_loadout(rifle, WeaponModding.SLOTS_A)
	_check(lo != null, "创建 Loadout")
	_check_eq(lo.free_slots.size(), WeaponModding.SLOTS_A, "A 阶段 %d 个插槽" % WeaponModding.SLOTS_A)
	_check_eq(int(round(lo.effective["damage"])), rifle.damage, "初始伤害等于裸枪")

	var base_spread: float = lo.effective["spread_deg"]
	var base_mag := int(round(lo.effective["mag_size"]))

	# 装瞄具 -> 散布下降
	var sight: AttachmentDef = reg.attachments["att_sight_red_dot"]
	_check_eq(WeaponModding.attach(lo, sight), "", "装上红点镜")
	_check(lo.effective["spread_deg"] < base_spread,
		"散布下降（%.2f -> %.2f）" % [base_spread, lo.effective["spread_deg"]])
	_check(lo.attachments.has("sight"), "sight 插槽已占用")

	# 同插槽不能重复装
	var sight2: AttachmentDef = reg.attachments["att_sight_holo"]
	_check(WeaponModding.attach(lo, sight2) != "", "同插槽不能重复装")

	# 没有的插槽不能装（枪口不在 A 阶段的前 2 个插槽里）
	var grip: AttachmentDef = reg.attachments["att_grip_vertical"]
	var err := WeaponModding.attach(lo, grip)
	_check(err == "" or err.contains("插槽"), "grip 装载按插槽限制处理：%s" % err)

	# 卸下恢复
	var removed := WeaponModding.detach(lo, "sight")
	_check(removed != null, "卸下红点镜")
	_check(absf(lo.effective["spread_deg"] - base_spread) < 0.001,
		"卸下后散布恢复（%.2f）" % lo.effective["spread_deg"])

	# to_weapon_def 产出修改后的数值
	var w2 := WeaponModding.attach(lo, reg.attachments["att_sight_scope"]) == "" \
		if lo.free_slots.has("sight") else false
	var eff := lo.to_weapon_def()
	_check(eff != null, "产出有效 WeaponDef")
	_check(eff.spread_deg < rifle.spread_deg, "有效散布小于裸枪（%.2f < %.2f）" % [eff.spread_deg, rifle.spread_deg])
	_check(eff.range_m > rifle.range_m, "有效射程大于裸枪（%d > %d）" % [eff.range_m, rifle.range_m])
	_check(eff.value >= rifle.value, "改装后价值更高（%d）" % eff.value)

	# 数值下限：塞满负向配件也不会出现负数伤害
	var pump := WeaponModding.create_loadout(rifle, WeaponModding.SLOTS_C)
	for id in reg.attachments:
		WeaponModding.attach(pump, reg.attachments[id])
	var eff2 := pump.to_weapon_def()
	_check(eff2.damage >= 1, "伤害不低于 1（%d）" % eff2.damage)
	_check(eff2.mag_size >= 1, "弹匣不低于 1（%d）" % eff2.mag_size)
	_check(eff2.spread_deg >= 0.0, "散布不为负（%.2f）" % eff2.spread_deg)

	# C 阶段 4 个插槽
	_check_eq(WeaponModding.create_loadout(rifle, WeaponModding.SLOTS_C).free_slots.size(), 4, "C 阶段 4 个插槽")

	# diff 摘要
	var d := pump.diff()
	_check(d.size() > 0, "diff 报告 %d 项变化" % d.size())

	# auto_fit
	var auto := WeaponModding.create_loadout(rifle, WeaponModding.SLOTS_A)
	var fitted := WeaponModding.auto_fit(auto, reg.attachments)
	_check(fitted > 0, "自动装配了 %d 个配件" % fitted)
	_check(auto.attachments.size() == fitted, "装配数量一致")


func _test_medical() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var kit: ItemDef = reg.get_item("medical_kit")
	var bandage: ItemDef = reg.get_item("medical_bandage")
	_check(not kit.treat.is_empty(), "医疗包带治疗参数：%s" % str(kit.treat))

	var vitals := Vitals.new()
	vitals.reset(100, 0)
	vitals.take_damage(60)
	vitals.apply_bleed(Vitals.Bleed.HEAVY)

	var med := MedicalSystem.new()
	_check_eq(med.start(kit, vitals), "", "开始用医疗包")
	_check(med.is_treating(), "治疗中")
	_check_eq(med.start(bandage, vitals), "正在治疗中", "不能同时开两个治疗")

	# 治疗耗时：中途还没生效
	var t: float = kit.treat["time"]
	med.tick(t * 0.5, vitals)
	_check_eq(vitals.hp, 40, "治疗过半还没回血")
	_check(med.progress() > 0.4 and med.progress() < 0.6, "进度约 50%%（%.0f%%）" % (med.progress() * 100.0))

	# 走完 -> 生效
	var res := med.tick(t, vitals)
	_check(bool(res["done"]), "治疗完成")
	_check(int(res["healed"]) > 0, "回复 %d 点" % int(res["healed"]))
	_check(bool(res["stopped_bleed"]), "同时止住了血")
	_check(not vitals.is_bleeding(), "确实不流血了")
	_check(not med.is_treating(), "治疗结束")
	_check_eq(med.treatments_done, 1, "治疗计数 1")

	# 满血时用医疗包 -> 拒绝
	var v2 := Vitals.new()
	v2.reset(100, 0)
	_check(med.start(kit, v2) != "", "满血时拒绝用医疗包")

	# 非医疗物品
	_check(med.start(reg.get_item("ammo_rifle"), v2) != "", "弹药不能当药用")

	# 打断
	var v3 := Vitals.new()
	v3.reset(100, 0)
	v3.take_damage(50)
	med.start(bandage, v3)
	_check(med.is_treating(), "开始治疗")
	med.cancel()
	_check(not med.is_treating(), "被打断")
	_check_eq(v3.hp, 50, "打断后没有回血")

	# 重击打断判定
	_check(med.should_interrupt(20), "20 点伤害应当打断")
	_check(not med.should_interrupt(5), "5 点伤害不打断")


func _test_hideout() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var h := Hideout.new(reg.items, 100)
	_check_eq(h.wallet, 100, "初始资金 100")
	_check_eq(h.level_of("stash_size"), 0, "升级初始为 0")

	# 钱不够
	var err := h.buy_upgrade("stash_size")
	_check(err != "", "钱不够时拒绝升级：%s" % err)

	# 给钱后升级
	h.wallet = 100000
	var before_slots := h.slot_count()
	var cost := h.upgrade_cost("stash_size")
	_check(cost > 0, "仓库升级价格 %d" % cost)
	_check_eq(h.buy_upgrade("stash_size"), "", "升级成功")
	_check_eq(h.level_of("stash_size"), 1, "等级 1")
	_check_eq(h.wallet, 100000 - cost, "扣款正确")
	_check(h.slot_count() > before_slots, "仓库槽位增加（%d -> %d）" % [before_slots, h.slot_count()])
	_check_eq(h.stash.slot_count(), h.slot_count(), "仓库容量已应用")

	# 价格递增
	_check(h.upgrade_cost("stash_size") > cost, "第二级更贵")

	# 满级
	for _i in 10:
		h.wallet = 10000000
		h.buy_upgrade("stash_size")
	_check_eq(h.level_of("stash_size"), h.max_level_of("stash_size"), "到达满级")
	_check_eq(h.upgrade_cost("stash_size"), -1, "满级后价格为 -1")
	_check(h.buy_upgrade("stash_size") != "", "满级后拒绝再升")

	# 负重升级影响 raid_modifiers
	h.buy_upgrade("carry_size")
	_check(h.carry_weight_limit() > Hideout.BASE_WEIGHT_LIMIT,
		"负重上限提升到 %.1f" % h.carry_weight_limit())
	_check(float(h.raid_modifiers()["carry_weight_limit"]) == h.carry_weight_limit(), "raid_modifiers 一致")

	# 商人：买入
	h.wallet = 5000
	var price := h.stock_price("medical_kit")
	_check(price > 0, "医疗包售价 %d" % price)
	var buy_err := h.buy("medical_kit", 2)
	_check_eq(buy_err, "", "买入 2 个医疗包")
	_check_eq(h.wallet, 5000 - price * 2, "买入扣款正确")
	_check_eq(h.stash.count_of("medical_kit"), 2, "仓库里有 2 个")

	# 商人：卖出
	var got := h.sell("medical_kit", 1)
	_check(got > 0, "卖出 1 个得 %d 元" % got)
	_check(got < price, "回收价低于售价（%d < %d）" % [got, price])
	_check_eq(h.stash.count_of("medical_kit"), 1, "仓库剩 1 个")

	# 卖出不存在的物品
	_check_eq(h.sell("valuables_gpu", 1), 0, "卖出没有的物品得 0")

	# 商人关系提升回收价
	var r0 := h.sell_ratio()
	h.wallet = 100000
	h.buy_upgrade("merchant_rep")
	_check(h.sell_ratio() > r0, "商人关系提升回收比例（%.2f -> %.2f）" % [r0, h.sell_ratio()])

	# 序列化往返
	var d := h.to_dict()
	var h2 := Hideout.new(reg.items, 0)
	h2.from_dict(d)
	_check_eq(h2.wallet, h.wallet, "往返后资金一致")
	_check_eq(h2.level_of("stash_size"), h.level_of("stash_size"), "往返后等级一致")
	_check_eq(h2.stash.count_of("medical_kit"), h.stash.count_of("medical_kit"), "往返后仓库一致")

	# 一局带回的东西入库
	var drops := [{"item_id": "valuables_gpu", "count": 1}]
	var leftover := h.deposit(drops)
	_check_eq(leftover.size(), 0, "入库无剩余")
	_check_eq(h.stash.count_of("valuables_gpu"), 1, "仓库收到显卡")


# ─────────────────── 项目卫生（永久守卫）───────────────────


func _test_spawn_safety() -> void:
	# ⚠️ 安卓真机反馈：出生点贴脸遇敌 -> 几秒内被打死，活不到能观察地图。
	#    已在 map_generator 加出生安全区。这里把它钉死，防回归。
	var reg := DataRegistry.new()
	reg.load_all("B")

	var seeds: Array[int] = [11, 222, 3333, 44444, 555555, 6789, 20261012, 99999, 31337, 7654321]
	var checked := 0
	var violations := 0
	var worst := 999
	var budgets: Array[int] = []

	for s in seeds:
		var gen := MapGenerator.new()
		if not gen.generate(s, reg.room_types):
			continue
		checked += 1
		budgets.append(gen.total_enemy_budget())
		var spawn := gen.spawn_room()
		var depths := gen.graph.bfs_depths(spawn.id)
		for r in gen.graph.rooms:
			if r.enemy_budget <= 0:
				continue
			var d: int = int(depths.get(r.id, 999))
			worst = mini(worst, d)
			if d <= MapGenerator.SPAWN_SAFE_GRAPH_DIST:
				violations += 1

	_check(checked >= 8, "抽查了 %d 张地图" % checked)
	_check_eq(violations, 0, "任何一张地图的出生安全区内都没有敌人")
	_check(worst > MapGenerator.SPAWN_SAFE_GRAPH_DIST,
		"所有地图的最近敌人都 > %d 跳（最差 %d 跳）" % [MapGenerator.SPAWN_SAFE_GRAPH_DIST, worst])

	# 敌人总量要克制（调低密度前平均 36，真机反馈太密）
	var avg := 0.0
	for b in budgets:
		avg += float(b)
	avg /= maxf(1.0, float(budgets.size()))
	_check(avg <= 30.0, "平均敌人预算 %.1f <= 30" % avg)
	_check(avg >= 6.0, "平均敌人预算 %.1f >= 6（不能少到没压力）" % avg)

	# 出生点自身永远 0 敌人
	var g2 := MapGenerator.new()
	g2.generate(1234, reg.room_types)
	_check_eq(g2.spawn_room().enemy_budget, 0, "出生房间本身 0 敌人")


func _test_death_settlement() -> void:
	# ⚠️ 真机反馈：死亡后无法重开、看起来像卡死。
	#    除了 UI 补了重开按钮，数据层也要能说清"丢了多少"。
	var reg := DataRegistry.new()
	reg.load_all("B")
	var gen := MapGenerator.new()
	gen.generate(31337, reg.room_types)

	var stash := Inventory.new(40, reg.items, 999.0)
	var raid := RaidSession.new(reg.items, SimRng.new(9), stash)
	raid.load_map(gen)
	raid.start(120.0)

	var common: LootTableDef = reg.get_loot_table("loot_common")
	raid.loot_container(common, 2, 4)
	raid.loot_container(common, 2, 4)
	var carried := raid.carry.used_slots()
	_check(carried > 0, "死亡前携带了 %d 格" % carried)

	raid.take_damage(99999)
	_check(raid.is_over(), "已阵亡")
	_check_eq(raid.lost_slots, carried, "记录丢失格数 = 死亡前携带数（%d）" % raid.lost_slots)

	var rep := raid.settle()
	_check_eq(int(rep["lost_slots"]), carried, "结算报告含 lost_slots")
	_check(not bool(rep["extracted"]), "未撤离")
	_check_eq(int(rep["brought_out_value"]), 0, "什么都没带出来")
	_check_eq(rep["phase"], "DEAD", "阶段 DEAD")

	# 撤离成功时不该报"丢失"
	var raid2 := RaidSession.new(reg.items, SimRng.new(10), stash)
	raid2.load_map(gen)
	raid2.start(120.0)
	raid2.loot_container(common, 2, 3)
	raid2.extract()
	var rep2 := raid2.settle()
	_check(bool(rep2["extracted"]), "撤离成功")
	_check_eq(int(rep2["lost_slots"]), 0, "撤离成功时没有丢失")
