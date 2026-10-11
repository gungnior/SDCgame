extends SceneTree

## Headless 测试运行器
##
## 运行方式：
##   godot --headless --path . --script res://test/run_tests.gd
##
## 退出码 = 失败数（0 = 全部通过），可直接作为 CI gate。
##
## 只测 sim/ 与 io/ —— 它们不依赖场景树、不依赖渲染器，毫秒级跑完。
## 这是 D-06 / T-69 的核心价值：让 AI 自己跑测试验证，而不是来回贴报错日志。

var _passed := 0
var _failed := 0
var _current := ""


func _initialize() -> void:
	print("")
	print("=== 项目测试  (Godot %s) ===" % Engine.get_version_info().string)
	print("")

	_suite("数据加载", _test_data_load)
	_suite("数据内容", _test_data_content)
	_suite("阶段开关", _test_stage_switch)
	_suite("SimRng 确定性", _test_rng_determinism)
	_suite("定义类辅助方法", _test_def_helpers)
	_suite("掉落表抽样", _test_loot_roll)
	_suite("CJK 字体与中文断行", _test_font_cjk)
	_suite("逻辑网格 LogicalGrid", _test_logical_grid)
	_suite("房间图 RoomGraph", _test_room_graph)
	_suite("地图生成器 MapGenerator", _test_map_generator)
	_suite("流场寻路 FlowField", _test_flow_field)
	_suite("流场缓存 FlowFieldManager", _test_flow_field_manager)
	_suite("战斗：弹道与视线 Ballistics", _test_ballistics)
	_suite("战斗：伤害与部位 DamageModel", _test_damage_model)
	_suite("战斗：武器状态 WeaponState", _test_weapon_state)
	_suite("背包 Inventory", _test_inventory)
	_suite("掉落 LootRoller", _test_loot_roller)
	_suite("感知 Perception", _test_perception)
	_suite("小队 Squad", _test_squad)
	_suite("敌人个体 EnemyAgent", _test_enemy_agent)
	_suite("突袭回合 RaidSession", _test_raid_session)

	print("")
	if _failed == 0:
		print("通过：%d 项，0 失败" % _passed)
	else:
		print("失败：%d 项通过，%d 项失败" % [_passed, _failed])
	print("")

	quit(_failed)


# ─────────────────────── 迷你断言框架 ───────────────────────

func _suite(name: String, fn: Callable) -> void:
	_current = name
	print("[%s]" % name)
	fn.call()


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s   <-- [%s]" % [label, _current])


func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s  (期望 %s，实际 %s)   <-- [%s]" % [label, str(expected), str(actual), _current])


# ─────────────────────── 测试用例 ───────────────────────

func _test_data_load() -> void:
	var reg := DataRegistry.new()
	var ok := reg.load_all("B")

	if not reg.errors.is_empty():
		for e in reg.errors:
			print("        err: %s" % e)

	_check(ok, "load_all(\"B\") 无错误")
	_check(reg.items.size() > 0, "items 非空")
	print("        %s" % reg.summary())


func _test_data_content() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")

	# B 阶段的数量（roadmap-bac.md §3）
	_check_eq(reg.items.size(), 15, "items = 15")
	_check_eq(reg.weapons.size(), 3, "weapons = 3")
	_check_eq(reg.enemies.size(), 2, "enemies = 2")
	_check_eq(reg.loot_tables.size(), 3, "loot_tables = 3")
	_check_eq(reg.room_types.size(), 3, "room_types = 3")

	# 抽查一条内容
	var bandage: ItemDef = reg.get_item("medical_bandage")
	_check(bandage != null, "能找到 medical_bandage")
	if bandage:
		_check_eq(bandage.category, "medical", "medical_bandage.category")
		_check(bandage.is_stackable(), "medical_bandage 可堆叠")

	# 枪械的弹药引用必须有效（交叉引用由 DataRegistry 校验）
	var rifle: WeaponDef = reg.get_weapon("weapon_rifle")
	_check(rifle != null, "能找到 weapon_rifle")
	if rifle:
		_check(reg.items.has(rifle.ammo_id), "weapon_rifle.ammo_id 指向存在的物品")
		_check_eq((reg.items[rifle.ammo_id] as ItemDef).category, "ammo", "weapon_rifle 用的是弹药")

	# 远程敌人的反应时间下限
	var scav: EnemyDef = reg.get_enemy("enemy_scav")
	if scav:
		_check(scav.reaction_time >= EnemyDef.MIN_RANGED_REACTION,
			"enemy_scav.reaction_time >= %.2f" % EnemyDef.MIN_RANGED_REACTION)


func _test_stage_switch() -> void:
	# B 阶段的数据全部是 stage=B，所以 B/A/C 三档装载量应当相同
	var reg_b := DataRegistry.new()
	reg_b.load_all("B")
	var reg_c := DataRegistry.new()
	reg_c.load_all("C")

	_check(reg_c.items.size() >= reg_b.items.size(), "C 档装载量 >= B 档")
	_check_eq(reg_c.items.size(), reg_b.items.size(), "当前数据全为 B 档，B/C 装载量相同")
	print("        B: %s" % reg_b.summary())
	print("        C: %s" % reg_c.summary())


func _test_rng_determinism() -> void:
	# 同一 seed 必须产生完全相同的序列（T-32：可复现）
	var a := SimRng.new(12345)
	var b := SimRng.new(12345)
	var same := true
	for i in 20:
		if a.randi_range(0, 999) != b.randi_range(0, 999):
			same = false
			break
	_check(same, "同 seed 的 20 次取数完全一致")

	# 不同 seed 应当产生不同序列
	var c := SimRng.new(999)
	var differs := false
	for i in 20:
		if a.randi_range(0, 999) != c.randi_range(0, 999):
			differs = true
			break
	_check(differs, "不同 seed 产生不同序列")

	# state 可保存与恢复，用于重放
	var r := SimRng.new(777)
	var first := r.randi_range(0, 100000)
	var st := r.save_state()
	var second := r.randi_range(0, 100000)
	r.restore_state(st)
	var second_replay := r.randi_range(0, 100000)
	_check_eq(second_replay, second, "state 恢复后能重放同一段序列")

	# 子 seed 派生不应产生相邻整数
	var s1 := SimRng.derive_seed(1000, 1)
	var s2 := SimRng.derive_seed(1000, 2)
	_check(abs(s1 - s2) > 1, "派生 seed 不是相邻整数")


func _test_def_helpers() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")

	var rifle: WeaponDef = reg.get_weapon("weapon_rifle")
	if rifle:
		_check_eq(rifle.shots_per_second(), 10.0, "步枪 600rpm = 10 发/秒")
		_check(abs(rifle.shot_interval() - 0.1) < 0.0001, "步枪射间隔 = 0.1 秒")

	var e: EnemyDef = reg.get_enemy("enemy_scav")
	if e:
		var c := e.sight_cos_half_angle()
		_check(c > 0.0 and c < 1.0, "视线锥半角余弦在 (0,1) 内")
		# 110 度半角 55 度 -> cos ≈ 0.5736
		_check(abs(c - 0.5736) < 0.001, "110 度视野锥的余弦 ≈ 0.5736")


func _test_loot_roll() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")

	var table: LootTableDef = reg.get_loot_table("loot_common")
	if table == null:
		_check(false, "能找到 loot_common")
		return

	_check(table.total_weight() > 0, "loot_common 权重总和 > 0")

	# 抽样必须始终落在合法条目上，且可复现
	var rng := SimRng.new(4242)
	var all_valid := true
	var ids := {}
	for i in 200:
		var e := table.roll_entry(rng)
		if e == null or not reg.items.has(e.item_id):
			all_valid = false
			break
		ids[e.item_id] = true
	_check(all_valid, "200 次抽样全部命中合法物品")
	_check(ids.size() >= 3, "抽样覆盖 >= 3 种物品（权重生效）")

	# 同 seed 抽样结果一致
	var r1 := SimRng.new(555)
	var r2 := SimRng.new(555)
	var same := true
	for i in 50:
		var e1 := table.roll_entry(r1)
		var e2 := table.roll_entry(r2)
		if e1 == null or e2 == null or e1.item_id != e2.item_id:
			same = false
			break
	_check(same, "同 seed 的掉落抽样完全一致")


# ─────────────────── M0 隐形炸弹 (1/2)：中文显示与断行 ───────────────────
#
# 背景（specs/tech-stack.md §6.8 / V-16）：
#   🚨 Godot 默认项目字体只支持 Latin-1 子集，【无法显示中文】——不换字体就是满屏方块。
#   🚨 中文断行需要 ICU 断行规则数据，该数据【默认不导出】。必须开
#      Project Settings > Internationalization > Locale > Include Text Server Data。
#      代价：包体约 +4 MB。
#
# ⚠️ 实测重要发现（2026-10-11，Godot 4.7.2）：
#   把 include_text_server_data 设为 false 后，本套件的断行断言【依然全部通过】。
#   原因：该开关只控制数据是否打进【导出包】，而编辑器/headless 运行自带这份数据。
#   ⇒ **断行行为在编辑器里无法证伪，只有导出的 APK/PCK 才能验证。**
#   ⇒ 因此本套件里：
#        · 「设置已开启」是【真正的守门断言】——它防止误关
#        · 断行断言是【编辑器层的健全性检查】，不能当作导出包的证明
#   ⇒ 导出包的验证交给 test/m0_device_check.gd（真机场景，目视确认）

func _test_font_cjk() -> void:
	# ⭐ 守门断言：防止误关这个开关
	var tsd: Variant = ProjectSettings.get_setting("internationalization/locale/include_text_server_data", null)
	_check(tsd == true, "[守门] include_text_server_data 已开启（当前: %s）" % str(tsd))

	# 1) 字体能否加载
	var font := load("res://art/fonts/NotoSansSC-VF.ttf") as FontFile
	if font == null:
		_check(false, "加载 res://art/fonts/NotoSansSC-VF.ttf")
		return
	_check(true, "CJK 字体加载成功")

	# 2) 字形覆盖 —— 缺字形会显示成豆腐块
	var sample := "撤离枪械医疗背包弹药护甲战利品倒计时"
	var missing := ""
	for i in sample.length():
		if not font.has_char(sample.unicode_at(i)):
			missing += sample[i]
	_check(missing.is_empty(), "游戏常用字全有字形" + ("" if missing.is_empty() else "  缺: " + missing))

	# 3) 中文断行 —— 这是 include_text_server_data 的直接效果
	#    不开这一项时，CJK 没有词边界规则，长中文串在受限宽度下无法正常换行。
	var size := 16
	var text := "在倒计时结束之前带着装备撤离否则你将失去本次行动的全部战利品"
	var narrow := 160.0

	var m_narrow := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, narrow, size)
	var m_wide := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)

	var one_line_h := float(size) * 1.5
	_check(m_wide.y <= one_line_h, "[编辑器] 不限宽度时只有一行（高 %.1f px）" % m_wide.y)
	_check(m_narrow.y > m_wide.y, "[编辑器] 限宽后行数增加（%.1f -> %.1f px）" % [m_wide.y, m_narrow.y])
	_check(m_narrow.y > one_line_h, "[编辑器] 限宽 160px 时换行了（高 %.1f px）" % m_narrow.y)
	_check(m_narrow.x <= narrow + 0.5, "[编辑器] 换行后不超出限定宽度（宽 %.1f <= %.1f）" % [m_narrow.x, narrow])

	# 4) 行数应当合理：既不是完全不换行，也没退化成每字一行
	_check(m_narrow.y < float(size) * 20.0, "[编辑器] 行数在合理范围（总高 %.1f px）" % m_narrow.y)

	# 5) 中英混排也要能断
	var mixed := "拾荒者 dropped a 战术背包 worth 1200 元"
	var m_mixed := font.get_multiline_string_size(mixed, HORIZONTAL_ALIGNMENT_LEFT, 200.0, size)
	_check(m_mixed.x > 0.0 and m_mixed.y > 0.0, "[编辑器] 中英混排测量正常（%.1f x %.1f）" % [m_mixed.x, m_mixed.y])

	print("        ⚠️ 以上断行断言在编辑器里恒真（见文件头说明）。")
	print("           导出包的真实断行效果请在真机上跑 test/m0_device_check.tscn 目视确认。")


# ─────────────────── B 阶段：逻辑网格（T-31） ───────────────────

func _test_logical_grid() -> void:
	var g := LogicalGrid.new(20, 14)   # 20x14 逻辑格 = 60x42 tile

	_check_eq(g.width, 20, "宽度 20 逻辑格")
	_check_eq(g.height, 14, "高度 14 逻辑格")
	_check_eq(g.walkable_count(), 0, "初始全为墙")

	# tile 尺寸换算
	_check_eq(g.tile_extents(), Vector2i(60, 42), "tile 范围 = 60x42")
	_check_eq(LogicalGrid.CELL_SIZE_TILES, 3, "1 逻辑格 = 3 tile")
	_check_eq(LogicalGrid.CELL_PX, 48, "1 逻辑格 = 48 px")

	# ── 核心保证：走廊恒宽 1 逻辑格 = 3 tile ──
	# 这是 T-31 的全部意义：手机触屏操作要求最小可行走宽度 >=3 格，
	# 而"走廊恒宽 1 逻辑格"让它在【结构上不可能被违反】。
	var c := Vector2i(2, 5)
	g.carve_corridor_l(Vector2i(2, 5), Vector2i(15, 5))
	_check_eq(g.get_cell(c), LogicalGrid.Cell.CORRIDOR, "走廊格被标记为 CORRIDOR")
	_check_eq(g.get_cell(Vector2i(15, 5)), LogicalGrid.Cell.CORRIDOR, "走廊终点被挖开")

	# 走廊的 tile 宽度必须正好 3
	var rect := g.cell_to_tile_rect(c)
	_check_eq(rect.size, Vector2i(3, 3), "一个逻辑格覆盖 3x3 tile")
	_check_eq(rect.size.x, LogicalGrid.CELL_SIZE_TILES, "走廊 tile 宽度 == 3（>=3 格硬约束）")

	# 走廊上下必须是墙（否则宽度就 >3 了）
	_check_eq(g.is_walkable(c + Vector2i(0, -1)), false, "走廊上方是墙")
	_check_eq(g.is_walkable(c + Vector2i(0, 1)), false, "走廊下方是墙")

	# ── V 形走廊也要挖通 ──
	g.carve_corridor_l(Vector2i(15, 5), Vector2i(15, 11))
	_check_eq(g.get_cell(Vector2i(15, 11)), LogicalGrid.Cell.CORRIDOR, "L 形走廊的竖段被挖开")
	_check(g.is_fully_connected(), "L 形走廊连通")

	# ── 挖房间 ──
	g.carve_rect(Rect2i(2, 2, 5, 3))
	_check_eq(g.get_cell(Vector2i(3, 3)), LogicalGrid.Cell.FLOOR, "房间内部是 FLOOR")
	_check_eq(g.get_cell(Vector2i(2, 2)), LogicalGrid.Cell.FLOOR, "房间左上角被挖开")

	# ── tile 坐标换算往返 ──
	var probes: Array[Vector2i] = [Vector2i(0, 0), Vector2i(5, 5), Vector2i(59, 41), Vector2i(17, 32)]
	for t in probes:
		var cell := g.tile_to_cell(t)
		var back := g.cell_to_tile_rect(cell)
		_check(back.has_point(t), "tile %s 落在其所属逻辑格 %s 的矩形内" % [str(t), str(cell)])

	# 边界：越界 tile 归到界外逻辑格，is_walkable 应返回 false
	_check_eq(g.in_bounds(Vector2i(-1, 0)), false, "负坐标越界")
	_check_eq(g.tile_is_walkable(Vector2i(-1, -1)), false, "越界 tile 不可走")

	# ── 连通性校验 ──
	# 孤立一个房间，整图应当不连通
	var g2 := LogicalGrid.new(20, 14)
	g2.carve_rect(Rect2i(1, 1, 3, 3))
	g2.carve_rect(Rect2i(15, 10, 3, 3))
	_check_eq(g2.is_fully_connected(), false, "两个互不相连的房间 -> 不连通")
	g2.carve_corridor_l(Vector2i(2, 2), Vector2i(16, 11))
	_check(g2.is_fully_connected(), "挖通走廊后 -> 连通")

	# flood_fill 只覆盖可达部分
	var reach := g2.flood_fill(Vector2i(2, 2))
	_check_eq(reach.size(), g2.walkable_count(), "连通后 flood_fill 覆盖全部可走格")

	# ── ASCII 便于目视调试 ──
	var ascii := g2.to_ascii()
	_check(ascii.contains("#"), "ASCII 图含墙")
	_check(ascii.contains("."), "ASCII 图含地面")
	_check(ascii.contains("+"), "ASCII 图含走廊")


# ─────────────────── B 阶段：房间图 ───────────────────

func _test_room_graph() -> void:
	var rg := RoomGraph.new()
	for i in 6:
		rg.add_room(Rect2i(i * 5, (i % 2) * 6, 3, 3))
	_check_eq(rg.room_count(), 6, "6 个房间")
	_check_eq(rg.edges.size(), 0, "初始无边")

	# ── Kruskal MST 必须给出 n-1 条边且全连通 ──
	var ok := rg.build_mst()
	_check(ok, "MST 构建成功")
	_check_eq(rg.mst_edges.size(), 5, "MST 边数 = n-1 = 5")
	_check(rg.is_graph_connected(), "MST 后图全连通")

	# ── BFS 图距离 ──
	rg.assign_depths(0)
	var d0 := rg.graph_distance(0, 0)
	var d5 := rg.graph_distance(0, 5)
	_check_eq(d0, 0, "自己到自己的图距离 = 0")
	_check(d5 > 0, "到第 5 个房间的图距离 > 0")
	# 图距离满足三角不等式
	_check(d5 <= rg.graph_distance(0, 2) + rg.graph_distance(2, 5), "图距离满足三角不等式")

	# ── 回加环 ──
	var rng := SimRng.new(2024)
	var added := rg.add_cycle_edges(0.15, rng)
	_check(added > 0, "回加了 %d 条环边（>0）" % added)
	_check_eq(rg.edges.size(), 5 + added, "总边数 = MST + 环")
	_check(rg.is_graph_connected(), "加环后仍连通")
	# 环边不能与 MST 边重复
	var dup := false
	for e in rg.cycle_edges:
		if rg.mst_edges.has(e):
			dup = true
	_check(not dup, "环边与 MST 边不重复")

	# ── 同 seed 的环边选择可复现 ──
	var rg_b := RoomGraph.new()
	for i in 6:
		rg_b.add_room(Rect2i(i * 5, (i % 2) * 6, 3, 3))
	rg_b.build_mst()
	rg_b.add_cycle_edges(0.15, SimRng.new(2024))
	_check_eq(rg_b.cycle_edges, rg.cycle_edges, "同 seed 的环边完全一致")

	# ── 邻居查询 ──
	_check(rg.neighbors(0).size() >= 1, "房间 0 至少有一个邻居")


# ─────────────────── B 阶段：地图生成器 ───────────────────

func _test_map_generator() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")

	var gen := MapGenerator.new()
	var ok := gen.generate(12345, reg.room_types, 26, 26)

	if not ok:
		for e in gen.errors:
			print("        err: %s" % e)

	_check(ok, "地图生成成功")
	if not ok:
		return

	print("        %s" % gen.summary())
	print("        尝试 %d 次，使用 seed %d" % [gen.attempts_used, gen.used_seed])

	# ── 硬约束（T-34 / data/rooms.json）──
	var spawn_n := 0
	var extract_n := 0
	var extract_min_depth := 999999
	for r in gen.graph.rooms:
		if r.room_type == "spawn":
			spawn_n += 1
		elif r.room_type == "extract":
			extract_n += 1
			extract_min_depth = mini(extract_min_depth, r.depth)

	_check_eq(spawn_n, 1, "出生点恰好 1 个")
	_check(extract_n >= 2, "撤离点 %d 个（>=2）" % extract_n)
	_check(extract_min_depth >= 4, "撤离点最小图距离 %d（>=4，防出生即撤离）" % extract_min_depth)
	_check(gen.grid.is_fully_connected(), "逻辑格级全连通")
	_check(gen.graph.is_graph_connected(), "房间图级全连通")
	_check(gen.graph.rooms.size() >= 4, "房间数 %d（>=4）" % gen.graph.rooms.size())

	# ── 环的存在：纯树走起来很闷 ──
	_check(gen.graph.cycle_edges.size() > 0, "存在环边 %d 条" % gen.graph.cycle_edges.size())
	_check(gen.graph.edges.size() > gen.graph.rooms.size() - 1, "边数 > n-1（确实成环）")

	# ── ⭐ 走廊宽度硬约束：在【tile 层级】测量最小通行段 ──
	# 这是 T-31 唯一真正该测的东西。
	# 之前写成「走廊格不能四向开阔」是错的 —— 走廊交叉口本来就四向开阔。
	# 正确测法：把逻辑格展开到 tile，量最窄的连续可走段有多宽。
	# 因为可走性定义在逻辑格层级（1 格 = 3 tile），最小值必然是 3。
	var tiles_w := gen.grid.tile_extents().x
	var tiles_h := gen.grid.tile_extents().y
	var min_h_run := 999999
	for ty in tiles_h:
		var run := 0
		for tx in tiles_w:
			if gen.grid.tile_is_walkable(Vector2i(tx, ty)):
				run += 1
			else:
				if run > 0:
					min_h_run = mini(min_h_run, run)
				run = 0
		if run > 0:
			min_h_run = mini(min_h_run, run)
	_check(min_h_run >= LogicalGrid.CELL_SIZE_TILES,
		"tile 级最小水平通行段 = %d tile（硬约束要求 >= %d）" % [min_h_run, LogicalGrid.CELL_SIZE_TILES])

	var min_v_run := 999999
	for tx in tiles_w:
		var run := 0
		for ty in tiles_h:
			if gen.grid.tile_is_walkable(Vector2i(tx, ty)):
				run += 1
			else:
				if run > 0:
					min_v_run = mini(min_v_run, run)
				run = 0
		if run > 0:
			min_v_run = mini(min_v_run, run)
	_check(min_v_run >= LogicalGrid.CELL_SIZE_TILES,
		"tile 级最小垂直通行段 = %d tile（硬约束要求 >= %d）" % [min_v_run, LogicalGrid.CELL_SIZE_TILES])

	# ── 逻辑格内的 3x3 tile 必须整块一致 ──
	var expansion_ok := true
	for y in gen.grid.height:
		for x in gen.grid.width:
			var cc := Vector2i(x, y)
			var expect := gen.grid.is_walkable(cc)
			var rr := gen.grid.cell_to_tile_rect(cc)
			for ty2 in range(rr.position.y, rr.position.y + rr.size.y):
				for tx2 in range(rr.position.x, rr.position.x + rr.size.x):
					if gen.grid.tile_is_walkable(Vector2i(tx2, ty2)) != expect:
						expansion_ok = false
	_check(expansion_ok, "逻辑格 -> tile 展开一致（无线级缝隙）")

	# ── 同 seed 完全可复现（T-32）──
	var gen2 := MapGenerator.new()
	gen2.generate(12345, reg.room_types, 26, 26)
	_check_eq(gen2.used_seed, gen.used_seed, "同 seed -> 同 used_seed")
	_check_eq(gen2.graph.rooms.size(), gen.graph.rooms.size(), "同 seed -> 同房间数")
	_check_eq(gen2.grid.walkable_count(), gen.grid.walkable_count(), "同 seed -> 同可走格数")
	_check_eq(gen2.to_ascii(), gen.to_ascii(), "同 seed -> 完全一致的地图")

	# ── 多 seed 播种都能成功（鲁棒性）──
	var ok_count := 0
	for s in [1, 7, 42, 999, 31337]:
		var g := MapGenerator.new()
		if g.generate(s, reg.room_types, 26, 26):
			ok_count += 1
	_check_eq(ok_count, 5, "5 个不同 seed 全部生成成功")

	# ── 敌人预算已分配 ──
	_check(gen.total_enemy_budget() > 0, "敌人预算总数 %d > 0" % gen.total_enemy_budget())
	_check(gen.spawn_room() != null, "能取到出生点房间")
	_check(gen.extract_rooms().size() >= 2, "能取到 >=2 个撤离点房间")


# ─────────────────── B 阶段：流场寻路 ───────────────────

func _test_flow_field() -> void:
	var g := LogicalGrid.new(15, 11)
	g.carve_rect(Rect2i(1, 1, 13, 9))              # 整块挖空
	g.carve_rect(Rect2i(7, 4, 1, 3), LogicalGrid.Cell.SOLID)   # 中间竖一堵墙

	var f := FlowField.new()
	f.load_from_grid(g)
	var target := Vector2i(12, 5)
	f.build(target)

	_check(f.valid, "流场构建有效")
	_check_eq(f.integration_at(target), 0, "目标格的 integration = 0")
	_check(f.is_reachable(Vector2i(2, 5)), "左侧格可达")

	# 不可达：把墙做成完全隔断
	var g2 := LogicalGrid.new(11, 11)
	g2.carve_rect(Rect2i(1, 1, 9, 9))
	g2.carve_rect(Rect2i(5, 1, 1, 9), LogicalGrid.Cell.SOLID)   # 竖贯全图
	var f2 := FlowField.new()
	f2.load_from_grid(g2)
	f2.build(Vector2i(8, 5))
	_check(not f2.is_reachable(Vector2i(2, 5)), "被墙隔断的格不可达")
	_check_eq(f2.get_direction(Vector2i(2, 5)), Vector2i.ZERO, "不可达格无方向")

	# ── 方向确实指向目标 ──
	var from := Vector2i(2, 5)
	var path := f.trace_path(from)
	_check(path.size() > 0, "能沿流场走出一条路径（%d 格）" % path.size())
	_check_eq(path[0], from, "路径起点正确")
	_check_eq(path[path.size() - 1], target, "路径终点是目标")

	# ── 每一步都缩短距离场（梯度正确性）──
	var monotone := true
	for i in range(path.size() - 1):
		if f.integration_at(path[i + 1]) >= f.integration_at(path[i]):
			monotone = false
			break
	_check(monotone, "路径上 integration 严格递减（梯度正确）")

	# ── 防贴角穿墙：对角移动不能穿过两面墙的夹缝 ──
	var g3 := LogicalGrid.new(9, 9)
	g3.carve_rect(Rect2i(1, 1, 7, 7))
	g3.set_cell(Vector2i(4, 4), LogicalGrid.Cell.SOLID)
	g3.set_cell(Vector2i(5, 4), LogicalGrid.Cell.SOLID)
	g3.set_cell(Vector2i(4, 5), LogicalGrid.Cell.SOLID)
	# (5,5) 可走，(4,4) 是墙 —— 从 (5,4) 到 (5,5) 不能对角穿过 (4,4)/(4,5) 的夹角
	var f3 := FlowField.new()
	f3.load_from_grid(g3)
	f3.build(Vector2i(7, 7))
	var d := f3.get_direction(Vector2i(5, 5))
	_check(d != Vector2i(-1, -1), "不允许从墙角对角穿过去")
	_check(f3.is_reachable(Vector2i(1, 1)), "绕行后仍可达")

	# ── 规模：大网格也能正确且快速完成（二叉堆，无 O(n^2) 退化）──
	var big := LogicalGrid.new(120, 120)
	big.carve_rect(Rect2i(1, 1, 118, 118))
	var fb := FlowField.new()
	fb.load_from_grid(big)
	var t0 := Time.get_ticks_usec()
	fb.build(Vector2i(118, 118))
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_check(fb.is_reachable(Vector2i(1, 1)), "120x120 网格可达")
	_check(ms < 2000.0, "120x120 构建耗时 %.1f ms（二叉堆无 O(n^2) 退化）" % ms)
	var p := fb.trace_path(Vector2i(1, 1), 1000)
	_check(p.size() > 100, "大网格路径长度 %d" % p.size())


# ─────────────────── B 阶段：流场缓存 ───────────────────

func _test_flow_field_manager() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var gen := MapGenerator.new()
	if not gen.generate(777, reg.room_types, 26, 26):
		_check(false, "前置地图生成失败")
		return

	var mgr := FlowFieldManager.new()
	mgr.setup(gen.grid)

	var spawn := gen.spawn_room()
	var extract := gen.extract_rooms()[0]
	if spawn == null or extract == null:
		_check(false, "取不到出生点/撤离点")
		return

	# 同一目标格反复询问 → 只构建一次
	for i in 20:
		mgr.direction_for(spawn.center, extract.center)
	_check_eq(mgr.build_count, 1, "同一目标格 20 次询问只构建 1 次")
	_check_eq(mgr.hit_count, 19, "命中 19 次")

	# 换目标格 → 新建
	mgr.direction_for(extract.center, spawn.center)
	_check_eq(mgr.build_count, 2, "换目标格后重建 1 次")
	_check_eq(mgr.field_count(), 2, "缓存里 2 份流场")

	# 失效后重建
	mgr.invalidate_all()
	_check_eq(mgr.field_count(), 0, "invalidate_all 清空缓存")
	mgr.direction_for(spawn.center, extract.center)
	_check_eq(mgr.build_count, 3, "失效后重新构建")

	# 方向可用性：出生点的敌人应当能朝撤离点走
	var d := mgr.direction_for(spawn.center, extract.center)
	_check(d != Vector2i.ZERO, "敌人能拿到朝目标的方向 %s" % str(d))

	# 缓存裁剪
	for i in 30:
		mgr.direction_for(spawn.center, Vector2i(i % gen.grid.width, i % gen.grid.height))
	mgr.trim_to(5)
	_check(mgr.field_count() <= 5, "trim_to(5) 后缓存 <= 5 份（实际 %d）" % mgr.field_count())

	# ── ⭐ 回归测试：连续空间推进绝不能漂进墙里 ──
	# 实测踩过两个坑，这里把它们钉死：
	#   ① 沿方向向量平移会漂进墙里然后永久卡死
	#   ② 对角移动的直线会擦过墙角
	var g2 := LogicalGrid.new(16, 12)
	g2.carve_rect(Rect2i(1, 1, 14, 10))
	# 造一个"墙角"：把 (6,6) 封死，(5,6) 与 (6,5) 留空
	g2.set_cell(Vector2i(6, 6), LogicalGrid.Cell.SOLID)
	g2.set_cell(Vector2i(8, 4), LogicalGrid.Cell.SOLID)
	g2.set_cell(Vector2i(8, 5), LogicalGrid.Cell.SOLID)
	g2.set_cell(Vector2i(9, 5), LogicalGrid.Cell.SOLID)

	var m2 := FlowFieldManager.new()
	m2.setup(g2)
	var goal := Vector2i(14, 10)

	# 从多个起点连续推进 400 步，全程必须待在可走格里
	var starts: Array[Vector2i] = [Vector2i(1, 1), Vector2i(1, 10), Vector2i(14, 1), Vector2i(4, 6), Vector2i(3, 3)]
	var escapees := 0
	var reached := 0
	for s in starts:
		var p := Ballistics.cell_center(s)
		if not g2.is_walkable(s):
			continue
		for _i in 400:
			p = m2.step_toward(p, goal, 3.0, 0.1)
			if not g2.is_walkable(Ballistics.cell_of(p)):
				escapees += 1
				break
		if Ballistics.cell_of(p) == goal:
			reached += 1
	_check_eq(escapees, 0, "5 个起点各推进 400 步，无一次漂进墙里")
	_check(reached >= 4, "%d/5 个起点成功走到目标格" % reached)

	# 单步也不应越界
	var p2 := Ballistics.cell_center(Vector2i(5, 6))
	var ok_step := true
	for _i in 200:
		p2 = m2.step_toward(p2, goal, 8.0, 0.1)   # 故意给很大的步长
		if not g2.is_walkable(Ballistics.cell_of(p2)):
			ok_step = false
			break
	_check(ok_step, "大跨步（0.8 格/步）下依然不漂进墙里")

	# 已经在目标格 -> 原地不动
	var at_goal := Ballistics.cell_center(goal)
	_check_eq(m2.step_toward(at_goal, goal, 5.0, 0.1), at_goal, "已在目标格则不动")
	_check(m2.at_target(at_goal, goal), "at_target 判定正确")





# ─────────────────── B 阶段：战斗 ───────────────────

func _open_grid(w: int = 12, h: int = 8) -> LogicalGrid:
	var g := LogicalGrid.new(w, h)
	g.carve_rect(Rect2i(1, 1, w - 2, h - 2))
	return g


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


func _test_perception() -> void:
	var g := _open_grid(14, 10)
	var reg := DataRegistry.new()
	reg.load_all("B")
	var scav: EnemyDef = reg.get_enemy("enemy_scav")

	# 正前方无遮挡 -> 看得见
	_check(Perception.can_see(g, Vector2(1.5, 5.5), Vector2.RIGHT, Vector2(6.5, 5.5), scav),
		"正前方 5 格 -> 看得见")
	# 背后 -> 看不见
	_check(not Perception.can_see(g, Vector2(6.5, 5.5), Vector2.RIGHT, Vector2(1.5, 5.5), scav),
		"背后 -> 看不见")
	# 超出视野距离 -> 看不见
	_check(not Perception.can_see(g, Vector2(1.5, 5.5), Vector2.RIGHT, Vector2(30.5, 5.5), scav),
		"超出视距 -> 看不见")

	# 中间加墙 -> 看不见
	g.set_cell(Vector2i(4, 5), LogicalGrid.Cell.SOLID)
	_check(not Perception.can_see(g, Vector2(1.5, 5.5), Vector2.RIGHT, Vector2(6.5, 5.5), scav),
		"隔墙 -> 看不见")
	g.set_cell(Vector2i(4, 5), LogicalGrid.Cell.FLOOR)
	_check(Perception.can_see(g, Vector2(1.5, 5.5), Vector2.RIGHT, Vector2(6.5, 5.5), scav),
		"拆墙后又能看见")

	# ── 听觉：走格子 BFS，穿墙有额外代价 ──
	var cost_open := Perception.hearing_cost(g, Vector2(1.5, 5.5), Vector2(5.5, 5.5))
	_check_eq(cost_open, 4, "直线 4 格空气 -> 代价 4")

	# 砌一堵竖墙把两点隔开
	for y in range(2, 8):
		g.set_cell(Vector2i(3, y), LogicalGrid.Cell.SOLID)
	var cost_wall := Perception.hearing_cost(g, Vector2(1.5, 5.5), Vector2(5.5, 5.5))
	_check(cost_wall > cost_open, "隔墙后代价变大（%d > %d）" % [cost_wall, cost_open])

	# can_hear：响度够就听得见
	_check(Perception.can_hear(g, Vector2(1.5, 5.5), Vector2(5.5, 5.5), 50.0), "响度 50 -> 听得见")
	_check(not Perception.can_hear(g, Vector2(1.5, 5.5), Vector2(5.5, 5.5), 1.0), "响度 1 -> 听不见")

	# 听到的范围是连通的格子集合
	var reach := Perception.hearing_reach(g, Vector2(1.5, 5.5), 3.0)
	_check(reach.size() > 0, "响度 3 影响 %d 格" % reach.size())


func _test_squad() -> void:
	var sq := Squad.new(1)
	_check_eq(sq.alert_level, 0.0, "初始警戒 0")
	_check(not sq.is_engaged(), "初始未交战")

	sq.report_contact(Vector2(5, 5), 10.0)
	_check_eq(sq.alert_level, 1.0, "报告接触后警戒拉满")
	_check(sq.is_engaged(), "进入交战")
	_check_eq(sq.last_known_pos, Vector2(5, 5), "记住最后已知位置")

	# 衰减
	sq.report_lost_contact(11.0)
	var before := sq.alert_level
	sq.tick(1.0, 11.0)
	_check(sq.alert_level < before, "失去接触后警戒衰减（%.3f -> %.3f）" % [before, sq.alert_level])

	# 阵亡会拉满警戒
	sq.alert_level = 0.0
	sq.report_casualty()
	_check_eq(sq.alert_level, 1.0, "同伴阵亡 -> 警戒拉满")
	_check_eq(sq.casualty_count, 1, "阵亡计数 1")

	# 警戒着色（art-pipeline §3.2）
	sq.report_contact(Vector2(1, 1), 20.0)
	var c := sq.alert_color()
	_check(c.r > c.g, "交战时着色偏红（r=%.2f g=%.2f）" % [c.r, c.g])

	# 声音报告只提升到 0.45
	var sq2 := Squad.new(2)
	sq2.report_noise(Vector2(3, 3), 5.0)
	_check(abs(sq2.alert_level - 0.45) < 0.001, "听到声音 -> 警戒 0.45")

	# 跨小队扩散：走格子，隔墙衰减
	var g := _open_grid(20, 12)
	var a := EnemyAgent.new(0, null, Vector2(2.5, 5.5))
	var b := EnemyAgent.new(1, null, Vector2(4.5, 5.5))
	var sq_a := Squad.new(10); sq_a.add_member(a)
	var sq_b := Squad.new(11); sq_b.add_member(b)
	var squads := [sq_a, sq_b]
	var n := Squad.spread_alert(g, Vector2(2.5, 5.5), squads, 10.0, 30.0)
	_check(n >= 2, "警戒扩散波及 %d 个小队" % n)
	_check(sq_b.alert_level > 0.0, "远处小队警戒被拉起（%.3f）" % sq_b.alert_level)


func _test_enemy_agent() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var g := _open_grid(20, 14)

	var gen := MapGenerator.new()
	gen.generate(2024, reg.room_types)
	var flows := FlowFieldManager.new()
	flows.setup(gen.grid)

	var scav: EnemyDef = reg.get_enemy("enemy_scav")
	var infected: EnemyDef = reg.get_enemy("enemy_infected")
	var rng := SimRng.new(11)

	# ── 初始 IDLE ──
	var e := EnemyAgent.new(0, scav, Vector2(2.5, 2.5))
	e.equip(reg.get_weapon("weapon_pistol"), 60)
	e.facing = Vector2.RIGHT
	_check_eq(e.state_name(), "IDLE", "初始 IDLE")
	_check(e.is_alive(), "初始存活")
	_check_eq(e.hp, scav.hp, "初始 HP = 定义值")

	# 视野外：保持 IDLE
	var targets := [{"id": "player", "pos": Vector2(200.5, 200.5), "hp": 100}]
	var ctx := {"grid": g, "flows": flows, "targets": targets, "rng": rng, "now": 0.0, "noises": []}
	e.tick(0.1, ctx)
	_check_eq(e.state_name(), "IDLE", "远处目标 -> 仍 IDLE")

	# ── 进入视野 -> COMBAT，并带上反应延迟 ──
	e.pos = Vector2(5.5, 5.5)
	e.facing = Vector2.RIGHT
	targets[0]["pos"] = Vector2(8.5, 5.5)
	e.tick(0.1, ctx)
	_check_eq(e.state_name(), "COMBAT", "看见目标 -> COMBAT")
	_check(e.reaction_timer > 0.0, "反应延迟计时 %.2f 秒（公平感关键）" % e.reaction_timer)
	_check(abs(e.reaction_timer - scav.reaction_time) < 0.5, "反应延迟约等于 reaction_time")

	# ── 反应延迟内不开火 ──
	var fired_before := e.shots_fired
	for _i in 3:
		e.tick(0.05, ctx)
	_check_eq(e.shots_fired, fired_before, "反应延迟内一枪没开")

	# ── 反应延迟过后会开火 ──
	for _i in 60:
		e.tick(0.05, ctx)
	_check(e.shots_fired > 0, "延迟过后开火了（%d 发）" % e.shots_fired)
	_check(e.damage_dealt >= 0, "累计造成伤害 %d" % e.damage_dealt)

	# ── 近战敌人在贴身后造成伤害 ──
	var m := EnemyAgent.new(1, infected, Vector2(5.5, 5.5))
	m.facing = Vector2.RIGHT
	var t2 := [{"id": "player", "pos": Vector2(6.2, 5.5), "hp": 100}]
	var ctx2 := {"grid": g, "flows": flows, "targets": t2, "rng": rng, "now": 0.0, "noises": []}
	m.tick(0.1, ctx2)                      # 发现目标
	m.reaction_timer = 0.0
	m.tick(0.1, ctx2)                      # 贴身攻击
	_check(t2[0]["hp"] < 100, "近战贴身造成伤害（HP %d）" % int(t2[0]["hp"]))
	_check_eq(m.attack_cooldown > 0.0, true, "攻击后进入冷却")

	# ── 受伤与死亡 ──
	var sq := Squad.new(7)
	var e3 := EnemyAgent.new(2, infected, Vector2(3.5, 3.5))
	sq.add_member(e3)
	_check(not e3.take_damage(10), "受伤但未死 -> 返回 false")
	_check_eq(e3.hp, infected.hp - 10, "HP 正确扣减")
	_check(e3.is_alive(), "还没死")
	_check(e3.take_damage(9999), "致死一击 -> 返回 true")
	_check(not e3.is_alive(), "被打死")
	_check_eq(e3.state_name(), "DEAD", "状态变 DEAD")
	_check_eq(sq.casualty_count, 1, "小队记录阵亡")
	_check(sq.alert_level >= 0.99, "阵亡后小队警戒拉满")

	# ── 视觉丢失 -> 搜索 ──
	var e4 := EnemyAgent.new(3, scav, Vector2(5.5, 5.5))
	e4.facing = Vector2.RIGHT
	var t4 := [{"id": "player", "pos": Vector2(9.5, 5.5), "hp": 100}]
	var ctx4 := {"grid": g, "flows": flows, "targets": t4, "rng": rng, "now": 0.0, "noises": []}
	e4.tick(0.1, ctx4)
	_check_eq(e4.state_name(), "COMBAT", "先进入交战")
	t4[0]["pos"] = Vector2(500.0, 500.0)   # 目标跑远
	e4.tick(0.1, ctx4)
	_check_eq(e4.state_name(), "SEARCH", "丢失视野 -> SEARCH")
	_check(e4.search_timer > 0.0, "搜索计时启动")

	# ── 流场移动：搜索时会朝最后已知位置移动 ──
	var e5 := EnemyAgent.new(4, scav, Vector2(2.5, 2.5))
	e5.state = EnemyAgent.State.SEARCH
	e5.last_seen_pos = Vector2(15.5, 10.5)
	e5.search_timer = 10.0
	e5._move_toward(flows, e5.last_seen_pos)
	_check(e5.move_dir != Vector2.ZERO, "朝着最后已知位置有移动方向 %s" % str(e5.move_dir))

	# ── 听觉：听到噪声进入 ALERT ──
	var e6 := EnemyAgent.new(5, scav, Vector2(4.5, 5.5))
	var ctx6 := {
		"grid": g, "flows": flows, "targets": [], "rng": rng, "now": 0.0,
		"noises": [{"pos": Vector2(6.5, 5.5), "loudness_m": 25.0}],
	}
	e6.tick(0.1, ctx6)
	_check_eq(e6.state_name(), "ALERT", "听到枪声 -> ALERT")


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
