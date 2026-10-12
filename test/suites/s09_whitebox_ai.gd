extends TestSuite

## 白模一致性与性能回归
##
## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。


func register() -> void:
	_suite("地图烘焙器 RaidMapBaker", _test_map_baker)
	_suite("真机修复3：白模与碰撞一致", _test_whitebox_matches_collision)
	_suite("白模：可走格必须真的可达", _test_whitebox_reachability)
	_suite("真机修复3：#6 尸体战利品", _test_corpse_loot)
	_suite("真机修复3：#7 藏身处与设置", _test_game_state_settings)
	_suite("性能回归：听觉代价场缓存", _test_hearing_cache)
	# ⚠️ 原先【定义了但从未注册】—— 补上（见 test_kit.gd 的说明）
	_suite("补注册：corpse interaction visible", _test_corpse_interaction_visible)
	# ⚠️ 原先【定义了但从未注册】—— 补上（见 test_kit.gd 的说明）
	_suite("补注册：whitebox is default", _test_whitebox_is_default)


func _test_whitebox_matches_collision() -> void:
	# ⚠️ 真机反馈："黑色实心的墙可以直接通过，绿色实心的线有时候会挡路"
	#    根因（已查明）：房间描边早先画在 `room.rect` 的最外圈【瓦片】上，
	#    而 `map_generator` 把 `room.rect` **整块** carve 成 FLOOR ——
	#    于是绿线盖在可走格上，看起来像墙、实际能走。
	#    本测试用**像素级比对**把这个不一致钉死。
	var reg := DataRegistry.new()
	reg.load_all("B")
	var seeds: Array[int] = [11, 4242, 20261012, 777, 31337]
	var checked := 0
	for s in seeds:
		var gen := MapGenerator.new()
		if not gen.generate(s, reg.room_types):
			continue
		checked += 1
		var g := gen.grid
		var img := WhiteboxPainter.paint(g, gen.graph.rooms)
		var n := LogicalGrid.CELL_SIZE_TILES

		var mismatch := 0
		var first_bad := ""
		for cy in g.height:
			for cx in g.width:
				var cell := Vector2i(cx, cy)
				var o := g.cell_to_tile_origin(cell)
				# 取格子【正中心】的像素（描边只会在边缘，中心必须干净）
				var px := img.get_pixel(o.x + n / 2, o.y + n / 2)
				var paint_wall := WhiteboxPainter.looks_like_wall(px)
				var real_wall := not g.is_walkable(cell)
				if paint_wall != real_wall:
					mismatch += 1
					if first_bad == "":
						first_bad = "格 %s：画成%s，碰撞是%s" % [
							str(cell), "墙" if paint_wall else "可走",
							"墙" if real_wall else "可走"]
		_check_eq(mismatch, 0, "种子 %d：格子中心的「画成墙」与「碰撞是墙」完全一致%s"
			% [s, "" if mismatch == 0 else "（首个不一致：" + first_bad + "）"])

		# 房间边界格必须是【可走】的（这就是绿线曾经盖住的那些格子）
		var bad_room := 0
		for r in gen.graph.rooms:
			for y in range(r.rect.position.y, r.rect.position.y + r.rect.size.y):
				for x in range(r.rect.position.x, r.rect.position.x + r.rect.size.x):
					if not g.is_walkable(Vector2i(x, y)):
						bad_room += 1
		_check_eq(bad_room, 0, "种子 %d：room.rect 内全部可走（房间不含有碰撞的格子）" % s)

	_check(checked >= 4, "抽查了 %d 张地图" % checked)

	# 「看起来像墙」的判据本身也要稳：暗 = 墙，亮 = 可走
	_check(WhiteboxPainter.looks_like_wall(WhiteboxPainter.WB_WALL), "近黑色被判为墙")
	_check(not WhiteboxPainter.looks_like_wall(WhiteboxPainter.WB_FLOOR), "亮灰地板被判为可走")
	_check(not WhiteboxPainter.looks_like_wall(WhiteboxPainter.WB_CORRIDOR), "走廊被判为可走")
	_check(not WhiteboxPainter.looks_like_wall(WhiteboxPainter.WB_DOOR), "门被判为可走")

	# 描边不能盖在可走格的中心（只能出现在边缘）
	var g2 := MapGenerator.new()
	g2.generate(999, reg.room_types)
	var img2 := WhiteboxPainter.paint(g2.grid, g2.graph.rooms)
	_check_eq(img2.get_width(), g2.grid.width * LogicalGrid.CELL_SIZE_TILES,
		"白模图宽度 = 逻辑格宽 x 3")


func _test_map_baker() -> void:
	# 地图烘焙从 raid_scene.gd 抽到 view/raid_map_baker.gd（拆分上帝对象）。
	#
	# ⭐ 这是**确定性**验证：烘焙出来的纹理必须与 WhiteboxPainter.paint() 逐像素一致。
	#    （不能用截图 diff —— 每局地图种子是随机的，两张截图的像素本来就不一样。）
	var reg := DataRegistry.new()
	reg.load_all("A")
	var baker := RaidMapBaker.new()
	baker.load_tiles()

	for seed_ in [11, 4242, 20261012]:
		var gen := MapGenerator.new()
		if not gen.generate(seed_, reg.room_types):
			continue
		var g := gen.grid
		# ① 白模：必须与 WhiteboxPainter 的输出逐像素一致
		var tex := baker.build(g, gen.graph.rooms, true)
		_check(tex != null, "种子 %d：烘焙出纹理" % seed_)
		if tex == null:
			continue
		var got := tex.get_image()
		var want := WhiteboxPainter.paint(g, gen.graph.rooms)
		_check_eq(got.get_size(), want.get_size(),
			"种子 %d：尺寸与 WhiteboxPainter 一致 %s" % [seed_, str(want.get_size())])
		# 逐像素比对（尺寸一致才比）
		var diff := 0
		if got.get_size() == want.get_size():
			for y in want.get_height():
				for x in want.get_width():
					if got.get_pixel(x, y) != want.get_pixel(x, y):
						diff += 1
		_check_eq(diff, 0,
			"种子 %d：烘焙结果与 WhiteboxPainter 逐像素一致（差异 %d）" % [seed_, diff])

		# ② 美术 tile 模式也要能跑出图（不崩、尺寸对）
		var tex2 := baker.build(g, gen.graph.rooms, false)
		_check(tex2 != null and tex2.get_image().get_size() == g.tile_extents(),
			"种子 %d：美术 tile 模式尺寸正确" % seed_)

	# ③ tile_key_for 在**不烘焙**时也要能用
	#    （_floor_material() 靠它决定脚步音效；早先它依赖场景的 _room_at，
	#      抽出来时会漏掉 —— 所以 baker 必须自己记住当前地图）
	var gen2 := MapGenerator.new()
	gen2.generate(777, reg.room_types)
	baker.set_map(gen2.grid, gen2.graph.rooms)
	var k := baker.tile_key_for(gen2.spawn_room().center, true)
	_check(not k.is_empty(), "不烘焙也能取材质键：%s" % k)
	_check(k.begins_with("floor_"), "可走格给的是地面材质（%s）" % k)
	var kw := baker.tile_key_for(Vector2i(0, 0), false)
	_check(kw.begins_with("wall_"), "阻挡格给的是墙材质（%s）" % kw)

	# ④ 材质键必须落在真实存在的 tile 变体里（否则会画成空白）
	_check(baker.tile_key_for(gen2.spawn_room().center, true) in RaidMapBaker.TILE_NAMES,
		"材质键在 TILE_NAMES 里")
	_check(RaidMapBaker.TILE_PX == 16, "TILE_PX 仍是 16")


func _test_whitebox_reachability() -> void:
	# 真机反馈："流场有概率会和白模地图冲突，导致白模视觉上能走的地方，却走不了"
	#
	# 关键：**"看起来可走"必须等价于"玩家真的能走到"**。
	# 白模画的是 grid.is_walkable()，而玩家的碰撞也是 grid.is_walkable() ——
	# 两者同源，所以问题只可能出在**玩家的移动模型**上：
	# 碰撞只查【中心点】、且逐轴移动，
	# 于是被墙夹住的窄缝 / 对角墙角，视觉上像通道、实际进不去。
	# 这里用**和玩家完全相同的移动规则**做 BFS，断言所有可走格都真的可达。
	var reg := DataRegistry.new()
	reg.load_all("B")
	var seeds: Array[int] = [11, 777, 4242, 31337, 20261012, 99, 5000, 123456]
	var checked := 0
	var bad_total := 0
	var worst := ""
	for s in seeds:
		var gen := MapGenerator.new()
		if not gen.generate(s, reg.room_types):
			continue
		checked += 1
		var g := gen.grid
		var start := gen.spawn_room().center
		if not g.is_walkable(start):
			continue
		# 与 raid_scene._walkable / _tick_player 完全一致的规则
		var seen := {}
		var q: Array[Vector2i] = [start]
		seen[start] = true
		var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0),
			Vector2i(0, 1), Vector2i(0, -1)]
		while not q.is_empty():
			var cur: Vector2i = q.pop_back()
			for d in dirs:
				var nb := cur + d
				if seen.has(nb):
					continue
				if not g.is_walkable(nb):
					continue
				seen[nb] = true
				q.append(nb)
		# 统计：可走但不可达的格数
		var bad := 0
		var sample := ""
		for y in g.height:
			for x in g.width:
				var cell := Vector2i(x, y)
				if g.is_walkable(cell) and not seen.has(cell):
					bad += 1
					if sample == "":
						sample = str(cell)
		bad_total += bad
		if bad > 0 and worst == "":
			worst = "种子 %d：%d 个可走格到不了（例如 %s）" % [s, bad, sample]
	_check(checked >= 6, "抽查了 %d 张地图" % checked)
	_check_eq(bad_total, 0,
		"所有可走格从出生点都真的能走到（不可达格总数 %d）%s"
		% [bad_total, "" if bad_total == 0 else "；首个：" + worst])

	# 且出生点周围至少要有一定空间，否则开局就卡住
	var gen2 := MapGenerator.new()
	if gen2.generate(4242, reg.room_types):
		var g2 := gen2.grid
		var sp := gen2.spawn_room().center
		var open_n := 0
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if g2.is_walkable(sp + Vector2i(dx, dy)):
					open_n += 1
		_check(open_n >= 5, "出生点周围至少 5/9 格可走（实际 %d）" % open_n)


func _test_corpse_loot() -> void:
	# 真机反馈 #6：敌人死亡后战利品在【尸体里】，配合背包搜索
	var reg := DataRegistry.new()
	reg.load_all("B")
	var gen := MapGenerator.new()
	gen.generate(31337, reg.room_types)
	var raid := RaidSession.new(reg.items, SimRng.new(1), Inventory.new(40, reg.items, 999.0))
	raid.load_map(gen)
	raid.start(120.0)

	var drops := [{"item_id": "ammo_rifle", "count": 10},
		{"item_id": "medical_bandage", "count": 2}]
	var pos := raid.extract_points[0]
	var cid := raid.add_corpse(pos, "enemy_scav", drops)
	_check(cid >= 0, "登记了一具尸体")
	_check_eq(raid.corpses.size(), 1, "尸体列表 1 具")

	# 搜索范围
	var near := raid.corpse_near(pos + Vector2(0.5, 0.0))
	_check_eq(near, 0, "走到旁边能找到尸体")
	_check_eq(raid.corpse_near(pos + Vector2(20, 0)), -1, "太远找不到")

	# 搜索标记
	var got := raid.search_corpse(0)
	_check_eq(got.size(), 2, "搜到 2 堆物品")
	_check(bool(raid.corpses[0]["searched"]), "标记为已搜索")

	# 拿一部分
	var n := raid.take_from_corpse(0, "ammo_rifle", 4)
	_check_eq(n, 4, "拿走 4 发")
	_check_eq(raid.carry.count_of("ammo_rifle"), 4, "背包收到 4 发")
	_check_eq(int((raid.corpses[0]["drops"] as Array)[0]["count"]), 6, "尸体里剩 6 发")

	# 拿光
	var rest := raid.take_all_from_corpse(0)
	_check_eq(rest.size(), 0, "全部拿得下")
	_check(raid.carry.count_of("medical_bandage") >= 2, "绷带也拿到手")
	_check((raid.corpses[0]["drops"] as Array).is_empty(), "尸体已被搜空")

	# 搜空的尸体不再提示（避免按钮一直亮着）
	_check_eq(raid.corpse_near(pos), -1, "搜空的尸体不再提示")

	# 背包满时拿不下 —— 必须返回剩余而不是吞掉
	var small := RaidSession.new(reg.items, SimRng.new(2), Inventory.new(40, reg.items, 999.0))
	small.load_map(gen)
	small.start(120.0)
	small.carry = Inventory.new(1, reg.items, 999.0)     # 只 1 格
	small.add_corpse(pos, "enemy_scav", [{"item_id": "armor_heavy", "count": 3}])
	var rest2 := small.take_all_from_corpse(0)
	_check_eq(rest2.size(), 1, "背包放不下时返回剩余")
	_check_eq(int(rest2[0]["count"]), 2, "还剩 2 件没拿走")


func _test_game_state_settings() -> void:
	# #7：跨场景持久的设置项（藏身处 UI 里可切）
	var s: GDScript = load("res://game/game_state.gd")
	_check(s != null, "能载入 game_state.gd")
	_check(s.get("RAID_SCENE") != null, "有突袭场景路径")
	_check(s.get("HIDEOUT_SCENE") != null, "有藏身处场景路径")
	_check(ResourceLoader.exists("res://view/hideout_scene.tscn"), "藏身处场景文件存在")
	# 三个开关默认值
	var hints := FileAccess.get_file_as_string("res://game/game_state.gd")
	for key in ["auto_fire", "auto_aim", "vision_follows_lock"]:
		_check(hints.contains("var " + key), "有设置项 %s" % key)
	# 藏身处场景必须真的能拿到 Game（而不是自己 new 一个 Hideout）
	var hs := FileAccess.get_file_as_string("res://view/hideout_scene.gd")
	_check(hs.contains("Game.hideout"), "藏身处用 Game 里的持久实例")
	_check(hs.contains("Game.start_raid"), "有『出发』入口")
	# 突袭场景的「回藏身处」必须切场景，而不是重启战局（这是 #7 的原话）
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("hideout_requested.connect(_go_hideout)"),
		"回藏身处接的是切场景（不是 _restart）")
	_check(rs.contains("Game.go_to_hideout()"), "确实调用了切场景")


# ─────────────────── 用户 PC 实测反馈：子弹从敌人身上穿过去 ───────────────────


func _test_hearing_cache() -> void:
	# ⚠️ 背景（安卓 profiler 实测）：
	#   敌人 AI 阶段单帧冲到 **257 ms**。根因是每个敌人对每个噪声都跑一次
	#   全网格 Dijkstra（Perception.hearing_cost），并且每次都重新分配数组。
	#   本测试把这个坑钉死：缓存版必须显著快于逐次调用版。
	var reg := DataRegistry.new()
	reg.load_all("B")
	var gen := MapGenerator.new()
	_check(gen.generate(7777, reg.room_types), "地图生成成功")
	var g := gen.grid

	# ── 正确性：缓存查表 与 单次 Dijkstra 结果必须一致 ──
	var listener := Ballistics.cell_center(gen.spawn_room().center)
	var field := Perception.hearing_field(g, listener)
	_check(not field.is_empty(), "听觉场已构建")
	var probes: Array[Vector2i] = [
		gen.spawn_room().center,
		Vector2i(1, 1), Vector2i(g.width - 2, g.height - 2), Vector2i(g.width / 2, g.height / 2),
	]
	for c in probes:
		var p := Ballistics.cell_center(c)
		var a := Perception.cost_at(field, g, p)
		var b := Perception.hearing_cost(g, listener, p)
		_check_eq(a, b, "格 %s 的代价：场查表(%d) == Dijkstra(%d)" % [str(c), a, b])

	# 对称性（缓存能成立的前提）
	var n1 := Vector2i(3, 3)
	var n2 := Vector2i(g.width - 4, g.height - 4)
	var d_ab := Perception.hearing_cost(g, Ballistics.cell_center(n1), Ballistics.cell_center(n2))
	var d_ba := Perception.hearing_cost(g, Ballistics.cell_center(n2), Ballistics.cell_center(n1))
	_check_eq(d_ab, d_ba, "代价函数对称（%d == %d）—— 这是「从听者跑一次场」的前提" % [d_ab, d_ba])

	# ── 缓存命中行为 ──
	var cache := HearingFieldCache.new()
	var f1 := cache.field_for(g, listener)
	cache.field_for(g, listener)
	cache.field_for(g, listener)
	_check_eq(cache.builds, 1, "同格重复取场只构建 1 次")
	_check(cache.hits >= 2, "命中 %d 次" % cache.hits)
	# 移动半格（未跨格）不应重建
	cache.field_for(g, listener + Vector2(0.3, 0.3))
	_check_eq(cache.builds, 1, "未跨格不重建")
	# 跨格应重建
	cache.field_for(g, listener + Vector2(3.0, 0.0))
	_check_eq(cache.builds, 2, "跨格后重建")
	# 清空
	cache.clear()
	_check_eq(cache.size(), 0, "clear 后缓存为空")

	# ── 性能对比（本测试的核心价值：防性能回退）──
	var centre := Ballistics.cell_center(gen.spawn_room().center)
	var agents: Array = []
	var scav: EnemyDef = reg.get_enemy("enemy_scav")
	for i in 28:
		var a := EnemyAgent.new(i, scav, centre)
		agents.append(a)
	# 12 个噪声铺满地图（模拟交火中多个枪声 + 脚步）
	var noises: Array = []
	for i in 12:
		noises.append({
			"pos": Ballistics.cell_center(Vector2i(2 + i * 2, 2 + (i * 3) % (g.height - 4))),
			"loudness_m": 22.0,
		})

	# ① 逐次 Dijkstra（旧路径）：只跑 4 个敌人做代表，否则测试太慢
	var t0 := Time.get_ticks_usec()
	for i in 4:
		agents[i]._find_audible_noise(g, noises, null)
	var per_enemy_us := float(Time.get_ticks_usec() - t0) / 4.0

	# ② 缓存路径：28 个敌人（第 1 个构建场，其余全命中）
	var c2 := HearingFieldCache.new()
	var t1 := Time.get_ticks_usec()
	for a in agents:
		a._find_audible_noise(g, noises, c2)
	var cached_total_us := float(Time.get_ticks_usec() - t1)

	_check_eq(c2.builds, 1, "28 个敌人同格 -> 只构建 1 次场（实际 %d）" % c2.builds)
	# 缓存版 28 个敌人的总耗时必须低于旧版【4 个】敌人的总耗时
	_check(cached_total_us < per_enemy_us * 4.0,
		"缓存版 28 敌 %.2fms < 逐次版 4 敌 %.2fms —— 约 %.0f 倍加速"
		% [cached_total_us / 1000.0, per_enemy_us * 4.0 / 1000.0,
		   (per_enemy_us * 4.0) / maxf(1.0, cached_total_us)])

	# 听觉语义不能坏：贴脸开枪必须听得见，极远处必须听不见
	var near_field := Perception.hearing_field(g, centre)
	_check(Perception.can_hear_at(near_field, g, centre + Vector2(1, 0), 22.0),
		"1 格外的枪声听得见")
	_check(not Perception.can_hear_at(near_field, g, centre + Vector2(400, 400), 22.0),
		"400 格外听不见")


# ─────────────────── 真机反馈 #1：白模与碰撞必须一致 ───────────────────


func _test_corpse_interaction_visible() -> void:
	# 用户 PC 实测："和敌人尸体没法交互。（战利品系统呢）"
	# 尸体其实已经生成、也能搜 —— 问题是【没有可见入口】。
	var rh := FileAccess.get_file_as_string("res://view/raid_hud.gd")
	# ⚠️ `_spawn_corpse(tgt)` 随 _try_fire 搬到了 raid_sim_runner.gd。
	#    这是「行为存在」类断言 -> 用视图层合并源码查。
	_check(_view_src().contains("_spawn_corpse(tgt)"), "击杀后会生成尸体容器")
	# ⚠️ 尸体提示的绘制已搬到 view/raid_hud.gd（拆分上帝对象）。
	_check(rh.contains("corpse_label"), "HUD 有『附近有尸体』的提示")
	_check(rh.contains("func bag_key_hint"), "提示里带按键（触屏/PC 文案不同）")
	_check(rh.contains("raid.corpse_near(scene.player_pos)"), "每帧检测附近尸体")
	# SettingsMenu 不能和 Object._get 撞名（踩过一次编译失败）
	var sm := FileAccess.get_file_as_string("res://ui/settings_menu.gd")
	_check(not sm.contains("func _get("),
		"设置菜单没有定义 _get（会与 Object._get(StringName) 签名冲突）")


# ─────────────────── 本会话【第三次】栽的同一个坑 ───────────────────


func _test_whitebox_is_default() -> void:
	# 真机反馈："把默认地图换成白模"
	# （查证发现它**本来就是默认**，这个测试用来防止被改回去）
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("var render_mode := RENDER_WHITEBOX"),
		"默认渲染模式是白模")
	_check(rs.contains("const RENDER_WHITEBOX := 0"), "白模常量是 0")
	# 而且不能在任何地方被持久化/覆盖成美术模式
	_check(not rs.contains("render_mode = RENDER_ART\n\t\t_build_map_texture()\n\t_setup_sim"),
		"启动流程里不会强制切成美术模式")


# ─────────────────── 手机实测：音频被永久掐断 / HUD 读数自相矛盾 ───────────────────
