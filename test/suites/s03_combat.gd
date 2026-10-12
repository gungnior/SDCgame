extends TestSuite

## 战斗与物品
##
## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。


func register() -> void:
	_suite("战斗：弹道与视线 Ballistics", _test_ballistics)
	_suite("战斗：伤害与部位 DamageModel", _test_damage_model)
	_suite("战斗：武器状态 WeaponState", _test_weapon_state)
	_suite("背包 Inventory", _test_inventory)
	_suite("掉落 LootRoller", _test_loot_roller)
	_suite("触屏：子弹磁性 AimAssist", _test_aim_assist)


func _test_ballistics() -> void:
	var g := _open_grid()
	# 空地射线：从 (1,1) 到 (5,1) 应经过 5 个格
	var cells := Ballistics.raycast_cells(g, Vector2(1.5, 1.5), Vector2(5.5, 1.5))
	_check_eq(cells.size(), 5, "空地射线经过 5 格")
	_check_eq(cells[0], Vector2i(1, 1), "射线起点格正确")
	_check_eq(cells[cells.size() - 1], Vector2i(5, 1), "射线终点格正确")
	_check_eq(Ballistics.first_blocking_cell(g, Vector2(1.5, 1.5), Vector2(5.5, 1.5)), null, "空地无阻挡")

	# 加一堵墙
	g.set_cell(Vector2i(3, 1), LogicalGrid.Cell.SOLID)
	var wall = Ballistics.first_blocking_cell(g, Vector2(1.5, 1.5), Vector2(5.5, 1.5))
	_check_eq(wall, Vector2i(3, 1), "第一个阻挡格是墙 (3,1)")
	_check(not Ballistics.has_line_of_sight(g, Vector2(1.5, 1.5), Vector2(5.5, 1.5)), "被墙挡住 -> 无通视")
	_check(Ballistics.has_line_of_sight(g, Vector2(1.5, 1.5), Vector2(2.5, 1.5)), "墙这边 -> 通视")

	# 目标获取：锥内 + 通视
	var targets := [
		{"id": "near", "pos": Vector2(2.5, 1.5)},
		{"id": "far", "pos": Vector2(5.5, 1.5)},
		{"id": "behind", "pos": Vector2(0.5, 1.5)},
	]
	var got := Ballistics.acquire_target(g, Vector2(1.5, 1.5), Vector2.RIGHT, targets, 10.0, 60.0)
	_check(not got.is_empty(), "能获取到目标")
	_check_eq(got.get("id", ""), "near", "优先取最近的可见目标（far 被墙挡）")

	# 锥外不应被获取
	var got2 := Ballistics.acquire_target(g, Vector2(1.5, 1.5), Vector2.LEFT, targets, 10.0, 30.0)
	_check(got2.is_empty() or got2.get("id", "") == "behind", "朝左时只可能看到 behind")

	# hitscan 命中最近实体
	var ents := [
		{"id": "e1", "pos": Vector2(2.5, 1.5)},
		{"id": "e2", "pos": Vector2(4.5, 1.5)},
	]
	var hit := Ballistics.hitscan_entities(g, Vector2(1.5, 1.5), Vector2(6.0, 1.5), ents)
	_check(not hit.is_empty(), "hitscan 命中")
	_check_eq(hit["entity"].get("id", ""), "e1", "命中墙上【前】最近的实体 e1（e2 被墙挡住）")

	# 坐标换算
	_check_eq(Ballistics.cell_of(Vector2(3.7, 2.1)), Vector2i(3, 2), "cell_of 向下取整")
	_check_eq(Ballistics.cell_center(Vector2i(3, 2)), Vector2(3.5, 2.5), "cell_center 是格中心")


func _test_damage_model() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var pistol: WeaponDef = reg.get_weapon("weapon_pistol")
	var rifle: WeaponDef = reg.get_weapon("weapon_rifle")
	var shotgun: WeaponDef = reg.get_weapon("weapon_shotgun")
	_check(pistol != null and rifle != null and shotgun != null, "取到三把枪")

	# 精度随距离下降
	var a_near := DamageModel.accuracy_at(rifle, 5.0)
	var a_far := DamageModel.accuracy_at(rifle, 80.0)
	_check(a_near > a_far, "精度随距离下降（%.2f -> %.2f）" % [a_near, a_far])

	# 霰弹枪散布大 -> 精度更低
	_check(DamageModel.accuracy_at(shotgun, 10.0) < DamageModel.accuracy_at(rifle, 10.0),
		"霰弹枪精度低于步枪")

	# 部位倍率：头 > 躯干 > 四肢
	var rng := SimRng.new(7)
	var d_head := DamageModel.resolve(rifle, 10.0, DamageModel.PART_HEAD)
	var d_torso := DamageModel.resolve(rifle, 10.0, DamageModel.PART_TORSO)
	var d_limb := DamageModel.resolve(rifle, 10.0, DamageModel.PART_LIMB)
	_check(d_head > d_torso, "头部伤害 > 躯干（%d > %d）" % [d_head, d_torso])
	_check(d_torso > d_limb, "躯干伤害 > 四肢（%d > %d）" % [d_torso, d_limb])

	# 距离衰减但不会归零
	var d_close := DamageModel.resolve(rifle, 1.0, DamageModel.PART_TORSO)
	var d_veryfar := DamageModel.resolve(rifle, 500.0, DamageModel.PART_TORSO)
	_check(d_close > d_veryfar, "远距离伤害更低")
	_check(d_veryfar >= 1, "再远也至少 1 点伤害（%d）" % d_veryfar)

	# 部位分布：高精度时更常打头
	var rng2 := SimRng.new(99)
	var head_low := 0
	var head_high := 0
	for _i in 400:
		if DamageModel.pick_part(rng2, 0.0) == DamageModel.PART_HEAD:
			head_low += 1
		if DamageModel.pick_part(rng2, 1.0) == DamageModel.PART_HEAD:
			head_high += 1
	_check(head_high > head_low, "高精度时头部命中更多（%d vs %d）" % [head_high, head_low])

	# 同 seed 可复现
	var r1 := SimRng.new(555)
	var r2 := SimRng.new(555)
	var same := true
	for _i in 50:
		var h1 := DamageModel.resolve_hit(rifle, 20.0, 0.0, r1)
		var h2 := DamageModel.resolve_hit(rifle, 20.0, 0.0, r2)
		if h1["part"] != h2["part"] or h1["damage"] != h2["damage"]:
			same = false
			break
	_check(same, "同 seed 的命中结算完全一致")

	# 几发打死：霰弹枪近战应当明显少于步枪远战
	var scav: EnemyDef = reg.get_enemy("enemy_scav")
	var stk_shotgun := DamageModel.shots_to_kill(shotgun, scav, 5.0)
	var stk_rifle_far := DamageModel.shots_to_kill(rifle, scav, 80.0)
	_check(stk_shotgun < stk_rifle_far, "霰弹枪近战杀敌更快（%.1f 发 vs %.1f 发）" % [stk_shotgun, stk_rifle_far])


func _test_weapon_state() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var rifle: WeaponDef = reg.get_weapon("weapon_rifle")
	var ws := WeaponState.new(rifle, 90)

	_check_eq(ws.ammo_in_mag, rifle.mag_size, "初始弹匣满")
	_check_eq(ws.reserve_ammo, 90, "备弹 90")
	_check(ws.can_fire(), "初始可射击")

	# 开一枪：扣弹 + 进入冷却 + 后坐力上升
	_check(ws.fire(), "第一枪打出去了")
	_check_eq(ws.ammo_in_mag, rifle.mag_size - 1, "弹匣 -1")
	_check(not ws.can_fire(), "冷却中不可再射")
	_check(ws.recoil > 0.0, "后坐力累积 %.3f" % ws.recoil)

	# 射速：600rpm -> 0.1 秒一发
	ws.tick(0.05)
	_check(not ws.can_fire(), "0.05 秒后仍在冷却")
	ws.tick(0.06)
	_check(ws.can_fire(), "0.11 秒后可射")

	# 后坐力恢复
	ws.recoil = WeaponState.RECOIL_PER_SHOT * 3.0
	var r_before := ws.recoil
	ws.tick(0.3)
	_check(ws.recoil < r_before, "后坐力随时间恢复（%.3f -> %.3f）" % [r_before, ws.recoil])

	# 散布随后坐力变大
	var spread_base := WeaponState.new(rifle, 0).current_spread_deg()
	_check(ws.current_spread_deg() >= spread_base, "当前散布 >= 基础散布")

	# 换弹
	ws.ammo_in_mag = 3
	_check(ws.start_reload(), "开始换弹")
	_check(ws.is_reloading(), "换弹中")
	_check(not ws.can_fire(), "换弹中不可射击")
	ws.tick(rifle.reload_time + 0.01)
	_check_eq(ws.ammo_in_mag, rifle.mag_size, "换弹后弹匣满")
	_check_eq(ws.reserve_ammo, 90 - (rifle.mag_size - 3), "备弹按需扣减")

	# 打空
	var ws2 := WeaponState.new(rifle, 0)
	for _i in rifle.mag_size:
		ws2.tick(1.0)
		ws2.fire()
	_check_eq(ws2.ammo_in_mag, 0, "打空弹匣")
	_check(not ws2.can_fire(), "没子弹不能射击")
	_check(not ws2.start_reload(), "没备弹换不了弹")

	# 取消换弹
	ws2.reserve_ammo = 30
	ws2.start_reload()
	ws2.cancel_reload()
	_check(not ws2.is_reloading(), "换弹被打断")


func _test_inventory() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var items := reg.items
	var inv := Inventory.new(6, items, 10.0)

	# 加物品与堆叠
	var left := inv.add("ammo_rifle", 50)
	_check_eq(left, 0, "50 发步枪弹全部放入")
	_check_eq(inv.count_of("ammo_rifle"), 50, "计数 50")
	_check_eq(inv.used_slots(), 1, "只占了 1 个槽（堆叠生效）")

	# 超过 stack_max 会开新槽
	var stack_max := (items["ammo_rifle"] as ItemDef).stack_max
	inv.add("ammo_rifle", stack_max)
	_check(inv.used_slots() >= 2, "超过 stack_max 后开新槽位")

	# 移除
	var removed := inv.remove("ammo_rifle", 20)
	_check_eq(removed, 20, "移除 20 发")
	_check_eq(inv.count_of("ammo_rifle"), 50 + stack_max - 20, "移除后计数正确")

	# 负重
	var w := inv.total_weight()
	_check(w > 0.0, "负重 %.2f kg" % w)

	# 不可堆叠物品每件占一格
	var inv2 := Inventory.new(4, items, 100.0)
	inv2.add("armor_light", 3)
	_check_eq(inv2.used_slots(), 3, "3 件轻甲占 3 格（stack_max=1）")

	# 槽位用尽
	var inv3 := Inventory.new(2, items, 100.0)
	var rest := inv3.add("armor_heavy", 5)
	_check_eq(rest, 3, "2 格只能放 2 件，剩 3 件放不下")

	# compact 合并同类
	# 手工造出两个部分堆叠（add() 本身会自动合并，所以直接摆槽位）
	var inv4 := Inventory.new(8, items, 100.0)
	inv4.slots[0] = {"item_id": "ammo_pistol", "count": 5}
	inv4.slots[3] = {"item_id": "armor_light", "count": 1}
	inv4.slots[5] = {"item_id": "ammo_pistol", "count": 5}
	_check_eq(inv4.used_slots(), 3, "整理前占 3 格")
	inv4.compact()
	_check_eq(inv4.used_slots(), 2, "整理后合并为 2 格")
	_check_eq(inv4.count_of("ammo_pistol"), 10, "合并后数量不变")

	# can_add
	_check(inv4.can_add("ammo_pistol", 5), "还能再放 5 发")
	_check(not inv4.can_add("armor_heavy", 99), "放不下 99 件重甲")

	# 转移
	var dst := Inventory.new(4, items, 100.0)
	var leftover := inv4.transfer_to(dst, "ammo_pistol", 6)
	_check_eq(leftover, 0, "转移 6 发无剩余")
	_check_eq(dst.count_of("ammo_pistol"), 6, "目标收到 6 发")
	_check_eq(inv4.count_of("ammo_pistol"), 4, "来源剩 4 发")

	# clear 返回掉落的全部
	var dropped := inv4.clear()
	_check(dropped.size() > 0, "clear 返回 %d 堆掉落" % dropped.size())
	_check(inv4.is_empty(), "clear 后背包为空")

	# 序列化往返
	var inv5 := Inventory.new(4, items, 50.0)
	inv5.add("medical_kit", 2)
	var d := inv5.to_dict()
	var inv6 := Inventory.new(4, items, 50.0)
	inv6.from_dict(d)
	_check_eq(inv6.count_of("medical_kit"), 2, "序列化往返后数量一致")


func _test_loot_roller() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var table: LootTableDef = reg.get_loot_table("loot_common")
	_check(table != null, "取到 loot_common")

	var rng := SimRng.new(2026)
	var drops := LootRoller.roll_container(table, rng, 5)
	_check(drops.size() > 0, "抽出 %d 堆" % drops.size())
	var all_valid := true
	for d in drops:
		if not reg.items.has(d["item_id"]):
			all_valid = false
		if int(d["count"]) <= 0:
			all_valid = false
	_check(all_valid, "所有掉落都是合法物品且数量 > 0")

	# 同 seed 可复现
	var d1 := LootRoller.roll_container(table, SimRng.new(1), 6)
	var d2 := LootRoller.roll_container(table, SimRng.new(1), 6)
	_check_eq(d1, d2, "同 seed 掉落完全一致")

	# 深度越深抽得越多
	var deep := LootRoller.roll_for_room(table, SimRng.new(3), 8, 1, 0.25, 6)
	_check(deep.size() >= 1, "深度 8 的掉落数 %d" % deep.size())

	# 价值与重量统计
	var v := LootRoller.total_value(drops, reg.items)
	var w := LootRoller.total_weight(drops, reg.items)
	_check(v > 0, "掉落总价值 %d 元" % v)
	_check(w >= 0.0, "掉落总重量 %.2f kg" % w)

	# 塞满背包后返回剩余
	var tiny := Inventory.new(1, reg.items, 1.0)
	var leftover := LootRoller.fill_inventory(tiny, drops)
	_check(leftover.size() > 0, "小背包塞不下，剩 %d 堆" % leftover.size())


func _test_aim_assist() -> void:
	var g := _open_grid(20, 14)

	# ── FOV 门限按视口尺寸换算（spec §7.7）──
	var a_ref := AimAssist.half_angle_for_viewport(AimAssist.REF_VIEWPORT_WIDTH)
	_check(absf(a_ref - AimAssist.BASE_HALF_ANGLE_DEG) < 0.001, "参考视口下等于基础锥角")
	var a_small := AimAssist.half_angle_for_viewport(360.0)
	var a_big := AimAssist.half_angle_for_viewport(1920.0)
	_check(a_small > a_ref, "小视口锥角更大（%.2f > %.2f）" % [a_small, a_ref])
	_check(a_big < a_ref, "大视口锥角更小（%.2f < %.2f）" % [a_big, a_ref])
	_check(a_big >= AimAssist.BASE_HALF_ANGLE_DEG * 0.55 - 0.001, "锥角有下限（%.2f）" % a_big)
	_check(a_small <= AimAssist.BASE_HALF_ANGLE_DEG * 1.6 + 0.001, "锥角有上限（%.2f）" % a_small)

	var origin := Vector2(5.5, 5.5)
	var targets := [
		{"id": "e1", "pos": Vector2(9.5, 5.5), "faction": "enemy", "alive": true},
	]

	# ── 回中即失效（spec：只在推摇杆时生效）──
	var r0 := AimAssist.pick(origin, Vector2.RIGHT, 0.0, targets, g, 5.0, 30.0)
	_check(r0.is_empty(), "推力 0（回中）-> 不启用辅助")
	var r_low := AimAssist.pick(origin, Vector2.RIGHT, AimAssist.MIN_PUSH * 0.5, targets, g, 5.0, 30.0)
	_check(r_low.is_empty(), "推力低于死区 -> 不启用")
	var r_on := AimAssist.pick(origin, Vector2.RIGHT, 0.6, targets, g, 5.0, 30.0)
	_check(not r_on.is_empty(), "推力足够 -> 启用")
	_check_eq(r_on["target"]["id"], "e1", "锁定正确目标")

	# ── 不改准心：偏折很小且有硬上限 ──
	_check(float(r_on["bend_deg"]) <= AimAssist.MAX_BEND_DEG + 0.001,
		"偏折不超过硬上限（%.2f° <= %.2f°）" % [float(r_on["bend_deg"]), AimAssist.MAX_BEND_DEG])
	# 偏折量用【偏心】目标验证（正对目标时无可偏折的量）
	var off_axis := [{"id": "o", "pos": Vector2(9.5, 6.0), "faction": "enemy", "alive": true}]
	var r_off := AimAssist.pick(origin, Vector2.RIGHT, 0.6, off_axis, g, 8.0, 30.0)
	_check(not r_off.is_empty(), "偏心目标也能吸（夹角内）")
	var bent: Vector2 = r_off["dir"]
	var bend_rad: float = absf(wrapf(bent.angle() - Vector2.RIGHT.angle(), -PI, PI))
	_check(bend_rad > 0.0005, "有偏折（%.4f rad = %.2f°）" % [bend_rad, rad_to_deg(bend_rad)])
	_check(bend_rad <= deg_to_rad(AimAssist.MAX_BEND_DEG) + 0.001,
		"偏折角不超过硬上限（%.2f° <= %.2f°）" % [rad_to_deg(bend_rad), AimAssist.MAX_BEND_DEG])

	# ── 硬原则 2：不能吸附同伴 / 中立 ──
	var ally := [{"id": "ally", "pos": Vector2(9.5, 5.5), "faction": "player", "alive": true}]
	_check(AimAssist.pick(origin, Vector2.RIGHT, 0.9, ally, g, 8.0, 30.0).is_empty(),
		"不吸附同阵营（硬原则 2）")
	var neutral := [{"id": "npc", "pos": Vector2(9.5, 5.5), "faction": "neutral", "alive": true}]
	_check(not AimAssist.pick(origin, Vector2.RIGHT, 0.9, neutral, g, 8.0, 30.0).is_empty(),
		"中立目标可被吸附（非同伴）")

	# ── 锥外不吸 ──
	var behind := [{"id": "b", "pos": Vector2(1.5, 5.5), "faction": "enemy", "alive": true}]
	_check(AimAssist.pick(origin, Vector2.RIGHT, 0.9, behind, g, 8.0, 30.0).is_empty(),
		"背后目标不吸附")

	# ── 约束 3：视线遮挡检查 ──
	g.set_cell(Vector2i(7, 5), LogicalGrid.Cell.SOLID)
	_check(AimAssist.pick(origin, Vector2.RIGHT, 0.9, targets, g, 8.0, 30.0).is_empty(),
		"隔墙 -> 不吸附（约束 3）")
	g.set_cell(Vector2i(7, 5), LogicalGrid.Cell.FLOOR)
	_check(not AimAssist.pick(origin, Vector2.RIGHT, 0.9, targets, g, 8.0, 30.0).is_empty(),
		"拆墙后可吸附")

	# ── 超出射程不吸 ──
	_check(AimAssist.pick(origin, Vector2.RIGHT, 0.9, targets, g, 8.0, 2.0).is_empty(),
		"超出射程不吸附")

	# ── 死亡目标不吸 ──
	var dead := [{"id": "d", "pos": Vector2(9.5, 5.5), "faction": "enemy", "alive": false}]
	_check(AimAssist.pick(origin, Vector2.RIGHT, 0.9, dead, g, 8.0, 30.0).is_empty(),
		"已死目标不吸附")

	# ── 硬原则 1：玩家可超越（推得越满，辅助越弱）──
	var w_low := float(AimAssist.pick(origin, Vector2.RIGHT, 0.30, targets, g, 8.0, 30.0)["weight"])
	var w_high := float(AimAssist.pick(origin, Vector2.RIGHT, 1.00, targets, g, 8.0, 30.0)["weight"])
	_check(w_high <= w_low, "推满时辅助权重不高于轻推（%.3f <= %.3f）" % [w_high, w_low])

	# ── 主动反向拨杆即脱锁 ──
	_check(AimAssist.is_counter_pushing(Vector2.RIGHT, Vector2.LEFT), "正反向 -> 判定脱锁")
	_check(not AimAssist.is_counter_pushing(Vector2.RIGHT, Vector2.RIGHT), "同向 -> 不脱锁")

	# ── 空输入不崩 ──
	_check(AimAssist.pick(origin, Vector2.ZERO, 0.9, targets, g, 8.0, 30.0).is_empty(),
		"零方向不崩溃")
	_check(AimAssist.pick(origin, Vector2.RIGHT, 0.9, [], g, 8.0, 30.0).is_empty(),
		"空目标列表不崩溃")
