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


