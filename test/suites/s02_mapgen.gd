extends TestSuite

## 地图生成与寻路
##
## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。


func register() -> void:
	_suite("逻辑网格 LogicalGrid", _test_logical_grid)
	_suite("房间图 RoomGraph", _test_room_graph)
	_suite("地图生成器 MapGenerator", _test_map_generator)
	_suite("流场寻路 FlowField", _test_flow_field)
	_suite("流场缓存 FlowFieldManager", _test_flow_field_manager)


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

	# 换目标格 → 新建（⚠️ 必须跨帧：每帧最多建 1 个流场，见 MAX_BUILDS_PER_FRAME）
	mgr.begin_frame()
	mgr.direction_for(extract.center, spawn.center)
	_check_eq(mgr.build_count, 2, "换目标格后重建 1 次")
	_check_eq(mgr.field_count(), 2, "缓存里 2 份流场")

	# 失效后重建
	mgr.invalidate_all()
	_check_eq(mgr.field_count(), 0, "invalidate_all 清空缓存")
	mgr.begin_frame()
	mgr.direction_for(spawn.center, extract.center)
	_check_eq(mgr.build_count, 3, "失效后重新构建")

	# 方向可用性：出生点的敌人应当能朝撤离点走
	var d := mgr.direction_for(spawn.center, extract.center)
	_check(d != Vector2i.ZERO, "敌人能拿到朝目标的方向 %s" % str(d))

	# ── ⭐ 每帧构建预算（真机性能优化的关键）──
	# ⚠️ 没有它时：玩家一移动，多个敌人同帧各自建流场，AI 的 act 阶段冲到 32ms
	var mgr2 := FlowFieldManager.new()
	mgr2.setup(gen.grid)
	# 取一个与出生点/撤离点都不同的房间，否则缓存命中和新建会混在一起（踩过）
	var cells: Array[Vector2i] = [spawn.center, extract.center]
	for r in gen.graph.rooms:
		if r.center != spawn.center and r.center != extract.center:
			cells.append(r.center)
			break
	mgr2.begin_frame()
	# ⚠️ 必须数【构建次数】，不能数"返回非空" ——
	#    预算用尽时 field_for 会返回**旧场**（仍然绕墙，
	#    这正是不让敌人顶墙的关键），它非空但并没有新建。
	#    （"数非空返回"这个错我在第一次修预算时就犯过一次。）
	var before_n := mgr2.build_count
	for c in cells:
		mgr2.field_for(c)
	var built := mgr2.build_count - before_n
	_check_eq(built, 1, "同一帧内最多只建 1 个流场（实际 %d）" % built)
	_check_eq(mgr2.defer_count, cells.size() - 1, "其余 %d 次被推迟" % (cells.size() - 1))
	# 被推迟时必须拿到【旧场】而不是 null —— 否则调用方会退化成无视墙的直走
	mgr2.begin_frame()
	var stale := mgr2.field_for(Vector2i(1, 1))
	_check(stale != null, "预算用尽时返回旧场（不是 null），保证仍然绕墙")
	# 下一帧应当能继续建（注意：要数「构建次数」而不是「返回非空」——
	# 已缓存的格子返回非空但不构建，我第一版断言就写错了）
	mgr2.begin_frame()
	var before := mgr2.build_count
	for c in cells:
		mgr2.field_for(c)
	_check_eq(mgr2.build_count - before, 1, "下一帧再建 1 个")
	# 已经建好的场不再受预算限制（缓存命中永远可用）
	mgr2.begin_frame()
	_check(mgr2.field_for(cells[0]) != null, "已缓存的场不受预算限制")
	_check(mgr2.field_for(cells[1]) != null, "已缓存的场不受预算限制（第 2 个）")

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
