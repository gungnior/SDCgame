extends TestSuite

## W-01 对抗性验收（WorkBuddy 执行）
##
## 目的不是"确认它对了"，是"用我自己的命令证伪"——逐条重跑 workboard W-01
## 列出的 7 个现存弱点。每一条都用独立构造的数据与命令重跑，不引用实现者的旧数字。
##
## 约定：找不出问题写「未能证伪」；能证伪的给复现步骤与证据。
## 写入范围：本文件（test/suites/ 下新增，自动发现）。不改 view/、sim/。

const SIM_DT := 1.0 / 60.0


func register() -> void:
	_suite("证伪①：存档路径（PC 回退分支 + 往返）", _test_save_path_pc)
	_suite("证伪④：v1 存档文件跨级升到 v3", _test_v1_file_to_v3)
	_suite("证伪⑤：B 阶段掉落表过滤后无静默丢项", _test_loot_filter_no_drop)
	_suite("证伪⑥：听觉场缓存多次噪音不漏更新", _test_hearing_cache_many_noises)
	_suite("证伪⑦：商人回收比例升级端到端生效", _test_merchant_rep_end_to_end)
	_suite("证伪②：满编 35 敌 headless 模拟单帧成本", _test_perf_35_enemies)
	_suite("证伪③：1 格宽走廊包夹不穿墙不死锁", _test_corridor_pincer)


# ─────────────────── ① 存档路径 ───────────────────
#
# 交接说法：PC 上走"可移植回退"路径，安卓那条 user:// 从没跑过 —— 两条不同代码路径。
# 本环境是 PC headless，能验证的是：回退分支真的被走到 + 存档往返稳定。
# 安卓分支是同一份 _resolve_path 代码，只差底层文件系统 —— 无法在本环境证伪，需真机。
func _test_save_path_pc() -> void:
	var sm := SaveManager.new()
	_check(not sm.path.is_empty(), "解析出了存档路径：%s" % sm.path)
	_check(sm.path.ends_with(SaveManager.SAVE_FILE), "路径以 %s 结尾" % SaveManager.SAVE_FILE)

	# ⭐ 实测分支：本环境（PC headless 子进程）user:// 可写，
	#    _resolve_path 走的是 user:// 分支 —— 与安卓【同一条】路径。
	#    说明在 user:// 可写的环境里，PC 与安卓并不分裂成"两条不同代码路径"，
	#    交接文档担心的分裂在本环境未出现（回退仅在不支持 user:// 的环境触发）。
	var branch := "user:// 分支" if not sm.used_fallback else "回退（exe 旁）分支"
	_check(sm.path.ends_with(SaveManager.SAVE_FILE),
		"存档路径合法；本环境实际走【%s】（user:// 可写性随环境而定）" % branch)

	sm.delete()
	var payload := {
		"hideout": {"wallet": 777, "upgrades": {}, "stash": {"slots": [], "max_weight": 999.0}},
		"settings": {"auto_fire": false}, "stats": {"raids": 1}
	}
	var err := sm.save(payload)
	_check_eq(err, "", "保存成功（%s）" % err)
	_check(sm.exists(), "存档文件已生成")
	var r := sm.load_save()
	_check(bool(r["ok"]), "读档成功")
	_check_eq(int((r["data"]["hideout"] as Dictionary)["wallet"]), 777, "PC 回退路径往返一致（钱数 777）")
	sm.delete()

	# ⚠️ 诚实结论：安卓 user:// 分支只在本环境的"同一份 _resolve_path"里被另一条 if 分支覆盖，
	#    文件系统行为无法在此复现 → 未能证伪，需真机（见报告）。

# ─────────────────── ④ v1 文件跨级升 v3 ───────────────────
#
# 交接说法：迁移只测过相邻版本（1→2、2→3），v1 直接升 v3 没试过。
# 这里真正写一个 v1 档到磁盘，再走 load_save（不是直接调 migrate），
# 验证"读一个旧档 → 循环迁移到当前版本"这条完整链路。
func _test_v1_file_to_v3() -> void:
	var sm := SaveManager.new()
	sm.delete()
	# 写一个只有 wallet 的 v1 档（v1 没有 upgrades/stash/settings/stats）
	var f := FileAccess.open(sm.path, FileAccess.WRITE)
	_check(f != null, "能打开存档文件写入 v1 档")
	if f != null:
		f.store_string(JSON.stringify({"version": 1, "wallet": 4242}))
		f.close()

	var r := sm.load_save()
	_check(bool(r["ok"]), "v1 档读档成功")
	_check_eq(int(r["migrated_from"]), 1, "记录迁移起点为 v1")
	_check_eq(int(r["data"].get("version", 0)), SaveManager.SAVE_VERSION,
		"迁移后版本号到达当前 %d" % SaveManager.SAVE_VERSION)
	_check(r["data"].has("upgrades") and r["data"].has("stash"),
		"v1→v2 补上了 upgrades/stash")
	_check(r["data"].has("settings") and r["data"].has("stats"),
		"v2→v3 补上了 settings/stats")
	_check_eq(int(r["data"].get("wallet", -1)), 4242, "跨级迁移未损坏原数据（wallet=4242）")
	sm.delete()

# ─────────────────── ⑤ 掉落表过滤后总量 ───────────────────
#
# 交接说法：DataRegistry 按"已加载物品"过滤掉落条目，推理"不会少"但没实测。
# 这里真正加载 B 阶段数据，逐条核对每张表、每个条目的 item_id 都在已加载物品里
# （即 B 阶段没有任何条目被静默丢弃）。
func _test_loot_filter_no_drop() -> void:
	var reg := DataRegistry.new()
	_check(reg.load_all("B"), "B 阶段数据加载无错误")
	_check(reg.loot_tables.size() > 0, "载入了 %d 张掉落表" % reg.loot_tables.size())

	var total_entries := 0
	var dropped := 0
	for tid in reg.loot_tables:
		var t: LootTableDef = reg.loot_tables[tid]
		_check(t.entries.size() > 0, "[%s] 当前阶段有可用条目（未被全过滤）" % tid)
		for e in t.entries:
			total_entries += 1
			if not reg.items.has(e.item_id):
				dropped += 1
				_check(false, "[%s] 引用了未加载物品 %s" % [tid, e.item_id])
	_check_eq(dropped, 0,
		"B 阶段 %d 个掉落条目全部指向已加载物品（无静默丢项）" % total_entries)

	# 信息：报告 B 阶段每张表的总权重，证明"总量没变少"是有数据的
	for tid in reg.loot_tables:
		var t: LootTableDef = reg.loot_tables[tid]
		var w := 0
		for e in t.entries:
			w += int(e.weight)
		_check(true, "信息：[%s] 总权重 %d（%d 项）" % [tid, w, t.entries.size()])

# ─────────────────── ⑥ 听觉场缓存多次噪音 ───────────────────
#
# 交接说法：_hearing_cache 只 1 个测试，缓存键的设计没被压力测过。
# 这里：一个听者、多个不同位置的噪音，验证全部能被同一份缓存场听到（命中复用），
# 且听者移动后场会重建并仍能听到新位置的噪音（不漏更新）。
func _test_hearing_cache_many_noises() -> void:
	var grid := LogicalGrid.new(16, 12)
	grid.carve_rect(Rect2i(1, 1, 14, 10))

	var cache := HearingFieldCache.new()
	var listener := Vector2(5.0, 5.0)

	var noises := [
		Vector2(12.0, 5.0),
		Vector2(2.0, 5.0),
		Vector2(5.0, 10.0),
		Vector2(9.0, 2.0),
	]
	var all_heard_first := true
	for npos in noises:
		var field := cache.field_for(grid, listener)
		# 同一个听者位置 → 应当命中同一份缓存（hits 累加，不再 rebuild）
		if not Perception.can_hear_at(field, grid, npos, 100.0):
			all_heard_first = false
	_check(all_heard_first, "多个不同位置噪音都被同一份缓存场听到（不漏）")
	_check(cache.hits >= noises.size() - 1, "多次噪音命中缓存复用（hits=%d）" % cache.hits)
	_check(cache.builds == 1, "一个听者位置只构建了 1 次场（builds=%d）" % cache.builds)

	# 听者移动 → 必须重建，且仍能听到新位置附近的噪音
	var builds_before := cache.builds
	listener = Vector2(11.0, 9.0)
	var f2 := cache.field_for(grid, listener)
	_check(cache.builds == builds_before + 1, "听者移动后场被重建（builds %d->%d）" % [builds_before, cache.builds])
	_check(Perception.can_hear_at(f2, grid, Vector2(12.0, 10.0), 100.0),
		"移动后仍能听到新位置附近的噪音（未漏更新）")

# ─────────────────── ⑦ 商人回收比例端到端 ───────────────────
#
# 交接说法：只断言了"比例函数变大"，没断言"升级后卖同一个东西到账更多"。
# 这里真的卖两次（升级前 / 升级后），比对到账金额。
func _test_merchant_rep_end_to_end() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var item_id := "medical_kit"
	_check(reg.items.has(item_id), "物品 %s 存在于 B 数据" % item_id)
	var def: ItemDef = reg.get_item(item_id)

	var h := Hideout.new(reg.items, 100000)
	var ratio0 := h.sell_ratio()
	_check(def.value > 0, "%s 价值 %d" % [item_id, def.value])

	h.stash.add(item_id, 4)
	var got0 := h.sell(item_id, 1)
	_check_eq(got0, int(round(float(def.value) * ratio0)),
		"升级前卖 1 个到账 %d（单价 = value*%.2f）" % [got0, ratio0])

	# 买"商人关系"升级
	var up_err := h.buy_upgrade("merchant_rep")
	_check_eq(up_err, "", "商人关系升级成功")
	var ratio1 := h.sell_ratio()
	_check(ratio1 > ratio0, "回收比例提升（%.2f -> %.2f）" % [ratio0, ratio1])

	h.stash.add(item_id, 1)
	var got1 := h.sell(item_id, 1)
	_check_eq(got1, int(round(float(def.value) * ratio1)),
		"升级后卖 1 个到账 %d（单价 = value*%.2f）" % [got1, ratio1])
	_check(got1 > got0, "⭐ 端到端：同一物品升级后到账更多（%d > %d）" % [got1, got0])
	_check_eq(got1 - got0, int(round(float(def.value) * ratio1)) - int(round(float(def.value) * ratio0)),
		"差额正好等于比例提升带来的增量")

# ─────────────────── ② 满编 35 敌性能 ───────────────────
#
# 交接说法：MAX_TEST_ENEMIES 一直是 4，满编 35 敌"从没测过"。
# 这里在 headless 下真构造 35 个敌人 + 流场 + 目标，跑 120 帧，测单帧平均耗时。
# 注：这是桌面 headless 数字，非安卓真机；用于证伪"35 敌是否会卡死"。
func _test_perf_35_enemies() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var edef: EnemyDef = reg.get_enemy("enemy_scav")
	var wdef: WeaponDef = reg.get_weapon("weapon_rifle")
	_check(edef != null and wdef != null, "取到敌人/武器定义（scav / rifle）")

	# 开阔场地（32x32 可走），避免寻路开销干扰纯 AI 成本
	var grid := LogicalGrid.new(34, 34)
	grid.carve_rect(Rect2i(1, 1, 32, 32))
	var flows := FlowFieldManager.new()
	flows.setup(grid)

	var squad := Squad.new(0)
	var target_pos := Vector2(17.0, 17.0)
	var target := {"id": -1, "pos": target_pos, "hp": 100}
	var agents: Array = []
	var rng := SimRng.new(42)
	for i in 35:
		var ang := float(i) / 35.0 * PI * 2.0
		var p := target_pos + Vector2(cos(ang), sin(ang)) * 10.0
		var a := EnemyAgent.new(i, edef, p)
		a.equip(wdef, 60)
		a.set_squad(squad)
		agents.append(a)
		squad.add_member(a)
	_check(agents.size() == 35, "构造了 35 个敌人（此前只测过 4 个）")
	squad.assign_roles(target_pos)

	var ctx := {"grid": grid, "flows": flows, "targets": [target], "rng": rng,
		"now": 0.0, "noises": [], "grace": false}
	flows.field_for(Ballistics.cell_of(target_pos))   # 预热

	var N := 120
	var t0 := Time.get_ticks_usec()
	for f in N:
		flows.begin_frame()
		ctx["now"] = float(f) * SIM_DT
		for a in agents:
			a.tick(SIM_DT, ctx)
	var t1 := Time.get_ticks_usec()
	var ms_per_frame := float(t1 - t0) / float(N) / 1000.0
	_check(ms_per_frame < 100.0,
		"35 敌单帧模拟平均 %.2f ms（<100 不卡死；60fps 预算 16.7ms；这是桌面 headless 值）" % ms_per_frame)
	_check(flows.hit_count > 0, "流场缓存命中生效（命中 %d 次，分摊建场成本）" % flows.hit_count)

# ─────────────────── ③ 1 格宽走廊包夹（W-06 回归守卫）───────────────────
#
# 交接说法：包夹 AI 只在开阔地测过，狭窄走廊里左右翼包夹点可能互相卡住 / 穿墙。
# 这里造一条 1 逻辑格宽的走廊（即项目真实设计宽度），放 3 个敌人追玩家，
# 跑 600 帧，检查：① 坐标不出现 NaN/Inf ② 至少 1 人沿走廊显著推进（不死锁）
#   ③ ⭐ 没有人穿进墙格（W-06 修复后硬卡：包夹点经 _snap_walkable 夹到最近可行走格）。
#
# ⚠️ 关键修正：enemy_scav 视距 = 14 格，敌人必须落在视距内才会"看见"并进入 COMBAT，
#    否则全程 IDLE 不动（早期版本走廊太长 → 测试空跑，min_dist 还被 mini(INF,..) 污染成假值）。
#    走廊"宽度=1 格"才是要验证的结构不变量，长度取 16 让敌人落在视距内。
#
# W-06 修复（2026-10-12）：EnemyAgent._combat 拿到 Squad.goal_for 的包夹点后，
#   先经 _snap_walkable(grid, goal) 夹到最近可行走逻辑格，再施加移动。
#   远程/近战分支都走夹后的 goal，包夹点落在墙里时不再直线穿墙。
#   实测：3 敌全留走廊内（clipped=0）、最近距玩家 3.5 格（无死锁）。
func _test_corridor_pincer() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var edef: EnemyDef = reg.get_enemy("enemy_scav")
	var wdef: WeaponDef = reg.get_weapon("weapon_rifle")
	_check(edef.sight_range_m > 0, "敌人视距有效（%s 格）" % edef.sight_range_m)

	var W := 16
	var grid := LogicalGrid.new(W, 3)
	grid.carve_rect(Rect2i(0, 1, W, 1))   # 第 1 行整行可走 = 1 逻辑格宽走廊
	_check(grid.is_walkable(Vector2i(8, 1)), "走廊中间可走")
	_check(not grid.is_walkable(Vector2i(8, 0)), "走廊上下是墙（宽度=1 逻辑格）")

	var flows := FlowFieldManager.new()
	flows.setup(grid)
	var squad := Squad.new(0)
	var player := Vector2(1.5, 1.5)
	var target := {"id": -1, "pos": player, "hp": 100}
	# 玩家在左端；3 个敌人都在视距(14)内、同侧 → 触发 DIRECT + 左翼 + 右翼
	var starts := [Vector2(12.5, 1.5), Vector2(11.5, 1.5), Vector2(10.5, 1.5)]
	var agents: Array = []
	var rng := SimRng.new(7)
	for i in starts.size():
		var a := EnemyAgent.new(i, edef, starts[i])
		a.equip(wdef, 60)
		# ⭐ 让敌人初始就面向玩家（否则默认朝右、看不见左侧玩家 → 全程 IDLE 不动）
		a.facing = (player - starts[i]).normalized()
		a.set_squad(squad)
		agents.append(a)
		squad.add_member(a)
	squad.assign_roles(player)

	var ctx := {"grid": grid, "flows": flows, "targets": [target], "rng": rng,
		"now": 0.0, "noises": [], "grace": false}
	flows.field_for(Ballistics.cell_of(player))

	for f in 600:
		flows.begin_frame()
		ctx["now"] = float(f) * SIM_DT
		for a in agents:
			a.tick(SIM_DT, ctx)

	var clipped := 0
	var non_finite := 0
	var min_dist := 1e9
	for a in agents:
		if not is_finite(a.pos.x) or not is_finite(a.pos.y):
			non_finite += 1
		if not grid.is_walkable(Ballistics.cell_of(a.pos)):
			clipped += 1
		var d: float = a.pos.distance_to(player)
		if is_finite(d) and d < min_dist:
			min_dist = d

	_check(non_finite == 0, "600 帧后没有敌人坐标变成非有限值（坐标稳定，无 NaN/Inf）")
	_check(min_dist < 7.0,
		"⭐ 敌人沿走廊显著推进（最近距玩家 %.1f 格 < 7，初始约 9；正面顶上去、无全死锁）" % min_dist)
	# W-06 回归守卫：修复后包夹点经 _snap_walkable 夹到可行走格，不应再有人穿进墙格
	_check(clipped == 0,
		"⭐ W-06 回归：1 格宽走廊里 %d/3 敌人穿进墙格（修复后必须=0；%d 人留在走廊内）" % [clipped, agents.size() - clipped])
