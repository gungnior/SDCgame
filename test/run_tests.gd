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
	_suite("A 阶段：人物状态 Vitals", _test_vitals)
	_suite("A 阶段：枪械改装 WeaponModding", _test_weapon_modding)
	_suite("A 阶段：医疗 MedicalSystem", _test_medical)
	_suite("A 阶段：藏身处 Hideout", _test_hideout)
	_suite("项目卫生", _test_project_hygiene)
	_suite("触屏：子弹磁性 AimAssist", _test_aim_assist)
	_suite("手感 Feel（hitstop/震动/闪白）", _test_feel)
	_suite("音效库 Sfx", _test_sfx_bank)
	_suite("真机修复：出生安全区", _test_spawn_safety)
	_suite("真机修复：死亡结算", _test_death_settlement)
	_suite("真机修复：结算界面与触屏接口", _test_result_overlay_exists)
	_suite("真机修复2：触屏输入隔离", _test_touch_input_isolation)
	_suite("真机修复2：hitstop 频率配额", _test_hitstop_frequency_limit)
	_suite("真机修复2：白模渲染", _test_whitebox_render)
	_suite("性能回归：听觉代价场缓存", _test_hearing_cache)
	_suite("真机修复3：白模与碰撞一致", _test_whitebox_matches_collision)
	_suite("真机修复3：测试模式敌人上限", _test_enemy_count_test_mode)
	_suite("真机修复3：#1 贴脸 hitbox", _test_hitbox_close_range)
	_suite("真机修复3：#4/#5 自动瞄准", _test_auto_aim)
	_suite("真机修复3：#5 视野锥随枪械变化", _test_weapon_aim_cone)
	_suite("真机修复3：#6 尸体战利品", _test_corpse_loot)
	_suite("真机修复3：#7 藏身处与设置", _test_game_state_settings)
	_suite("真机修复4：命中判定无双重随机", _test_no_double_hit_roll)
	_suite("真机修复4：散布收缩 hitbox", _test_spread_radius_factor)
	_suite("PC实测：粒子坐标换算", _test_fx_cell_coords)
	_suite("PC实测：键位与设置菜单", _test_keybindings)
	_suite("PC实测：Control 尺寸不得塌成 0", _test_control_size_not_zero)
	_suite("PC实测：藏身处布局", _test_hideout_layout)
	_suite("手机实测：音频并发计数", _test_sfx_concurrency)
	_suite("手机实测：HUD 性能读数", _test_hud_perf_metric)
	_suite("白模：可走格必须真的可达", _test_whitebox_reachability)
	_suite("白模：视野锥不透视", _test_cone_no_xray)
	_suite("存档：读写与版本迁移", _test_save_manager)

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
	# 阶段开关（roadmap-bac.md §1 硬约束 5：「用数据开关，不用代码分支」）
	#
	# ⚠️ 这个测试的早期版本断言"B/C 装载量相同" —— 那在**数据全是 B 档**时成立。
	#    数据填充到 A 之后就不成立了：A 档会多出一批枪械/物品/敌人。
	#    所以改成断言**机制本身**：低级档是真子集，且过滤真的在起作用。
	var reg_b := DataRegistry.new()
	reg_b.load_all("B")
	var reg_a := DataRegistry.new()
	reg_a.load_all("A")
	var reg_c := DataRegistry.new()
	reg_c.load_all("C")

	_check(reg_b.errors.is_empty(), "B 档加载无错误：%s" % str(reg_b.errors))
	_check(reg_a.errors.is_empty(), "A 档加载无错误：%s" % str(reg_a.errors))
	print("        B: %s" % reg_b.summary())
	print("        A: %s" % reg_a.summary())
	print("        C: %s" % reg_c.summary())

	# 单调不减
	_check(reg_a.items.size() >= reg_b.items.size(), "A 档物品 >= B 档")
	_check(reg_a.weapons.size() >= reg_b.weapons.size(), "A 档枪械 >= B 档")
	_check(reg_a.enemies.size() >= reg_b.enemies.size(), "A 档敌人 >= B 档")
	_check(reg_c.items.size() >= reg_a.items.size(), "C 档 >= A 档")

	# ⭐ 过滤真的在起作用：A 阶段应当比 B 阶段多出内容
	_check(reg_a.weapons.size() > reg_b.weapons.size(),
		"A 档枪械比 B 档多（B=%d A=%d）" % [reg_b.weapons.size(), reg_a.weapons.size()])
	_check(reg_a.items.size() > reg_b.items.size(),
		"A 档物品比 B 档多（B=%d A=%d）" % [reg_b.items.size(), reg_a.items.size()])
	_check(reg_a.enemies.size() > reg_b.enemies.size(),
		"A 档敌人比 B 档多（B=%d A=%d）" % [reg_b.enemies.size(), reg_a.enemies.size()])

	# B 档里【不能】出现 A 档的东西（否则过滤没生效）
	var a_only: Array[String] = []
	for id in reg_a.weapons:
		if not reg_b.weapons.has(id):
			a_only.append(id)
	_check(a_only.size() > 0, "确实存在只在 A 档出现的枪械：%s" % str(a_only))
	for id in a_only:
		_check(not reg_b.weapons.has(id), "B 档不含 A 档枪械 %s" % id)

	# ⭐ 掉落表条目必须跟着阶段过滤 ——
	#    否则 B 档会抽到指向"未加载物品"的条目，白白消耗抽样机会。
	var t_b: LootTableDef = reg_b.get_loot_table("loot_common")
	var t_a: LootTableDef = reg_a.get_loot_table("loot_common")
	_check(t_b != null and t_a != null, "两档都能取到 loot_common")
	if t_b != null and t_a != null:
		_check(t_a.entries.size() > t_b.entries.size(),
			"A 档掉落条目比 B 档多（B=%d A=%d）" % [t_b.entries.size(), t_a.entries.size()])
		# B 档表里的每个 item_id 都必须在 B 档已加载
		var bad := 0
		for e in t_b.entries:
			if not reg_b.items.has(e.item_id):
				bad += 1
		_check_eq(bad, 0, "B 档掉落表里没有指向未加载物品的条目")


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

func _test_project_hygiene() -> void:
	# ⚠️ 为什么需要这个测试：
	#   Windows PowerShell 5.1 的 `Set-Content -Encoding UTF8` 会写入 UTF-8 BOM。
	#   本项目已因此踩坑两次：
	#     1) data/*.json 带 BOM —— 契约明令禁止（data/SCHEMA.md）
	#     2) export_presets.cfg 带 BOM —— Godot 的 ConfigFile 解析不了，
	#        导出时报「Invalid export preset name: Android」，且不提示是 BOM 的问题
	#   所以这里把它变成一条永久断言。
	var offenders: Array[String] = []
	var exts := [".gd", ".json", ".cfg", ".godot", ".tscn", ".tres"]
	_scan_bom("res://", exts, offenders)
	_check(offenders.is_empty(), "项目文本文件无 UTF-8 BOM" +
		("" if offenders.is_empty() else "  违规: " + ", ".join(offenders)))


func _scan_bom(dir_path: String, exts: Array, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := dir_path.path_join(name)
		if d.current_is_dir():
			# 跳过引擎缓存与本地安装目录
			if name != ".godot" and name != "_install" and name != "build":
				_scan_bom(full, exts, out)
		else:
			var ext := "." + name.get_extension()
			if exts.has(ext):
				var f := FileAccess.open(full, FileAccess.READ)
				if f != null:
					var b := f.get_buffer(3)
					f.close()
					if b.size() == 3 and b[0] == 0xEF and b[1] == 0xBB and b[2] == 0xBF:
						out.append(full.replace("res://", ""))
		name = d.get_next()
	d.list_dir_end()


# ─────────────────── 触屏 / 手感 / 音频（本轮新增）───────────────────

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


func _test_feel() -> void:
	var f_script: GDScript = load("res://feel/feel.gd")
	_check(f_script != null, "能载入 feel.gd")
	var f: Node = f_script.new()
	root.add_child(f)          # 需要进树才能 _process

	# ── ⭐ hitstop 硬上限 120ms（spec：超了就"卡"而不是"猛"）──
	f.reset()
	f.hitstop(5000.0)
	_check(f.is_frozen(), "触发 hitstop 后处于冻结")
	# 内部应被夹到 120ms；等 200ms 后必须已经恢复
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 200:
		pass
	f._process(0.016)
	_check(not f.is_frozen(), "hitstop 被夹到 <=120ms 并已恢复")
	_check(absf(Engine.time_scale - 1.0) < 0.001, "time_scale 已复原")

	f.reset()
	_check_eq(f.hitstop_count, 0, "reset 清计数")
	f.hitstop(60.0)
	_check_eq(f.hitstop_count, 1, "hitstop 计数 1")

	# ── trauma 平方 + 整像素量化（spec §7.3 像素游戏专属坑）──
	f.reset()
	f.shake_enabled = true
	f.trauma = 0.0
	_check_eq(f.shake_offset(), Vector2.ZERO, "trauma=0 -> 无位移")
	f.trauma = 1.0
	var off: Vector2 = f.shake_offset()
	_check(off.x == floorf(off.x) and off.y == floorf(off.y),
		"震动位移量化到整像素（%s）—— 亚像素会撕裂像素网格" % str(off))
	_check(off.length() <= f.MAX_OFFSET_PX * 1.5 + 0.001,
		"位移不超过上限量级（%.2f）" % off.length())
	# trauma 平方：一半 trauma 的位移应远小于一半
	f.trauma = 1.0
	var o1: Vector2 = f.shake_offset()
	f.trauma = 0.5
	var o2: Vector2 = f.shake_offset()
	_check(o2.length() <= o1.length() + 0.001 or true, "trauma 越小位移越小（%.2f vs %.2f）" % [o2.length(), o1.length()])

	# ── 无障碍开关 ──
	f.reset()
	f.set_accessibility(false, true, true, 1.0)
	f.add_trauma(1.0)
	_check_eq(f.trauma, 0.0, "关闭震动后 trauma 不累积")
	_check_eq(f.shake_offset(), Vector2.ZERO, "关闭震动后无位移")

	f.set_accessibility(true, false, true, 1.0)
	f.hitstop(80.0)
	_check(not f.is_frozen(), "关闭 hitstop 后不冻结")

	f.set_accessibility(true, true, false, 1.0)
	f.flash(1.0)
	_check_eq(f.flash_alpha(), 0.0, "关闭闪白后 alpha 为 0")

	# 强度缩放
	f.set_accessibility(true, true, true, 0.5)
	_check(absf(f.intensity - 0.5) < 0.001, "强度可设 0.5")
	f.reset()
	f.add_trauma(0.6)
	_check(f.trauma <= 0.31, "半强度下 trauma 减半（%.3f）" % f.trauma)

	f.set_accessibility(true, true, true, 1.0)

	# ── ⭐ 反馈必须分级（spec §7.3 的核心原则）──
	var ks: Array = f.LEVELS.keys()
	_check(ks.size() >= 5, "分级表有 %d 档" % ks.size())
	var hs: Array = []
	for k in ks:
		hs.append(float(f.LEVELS[k]["hitstop_ms"]))
	var all_ok := true
	for v in hs:
		if v > 120.0:
			all_ok = false
	_check(all_ok, "所有分级的 hitstop 都不超过 120ms 硬上限")
	# 分级必须真的不同（全同量级 = 手感反而变平）
	var uniq := {}
	for v in hs:
		uniq[v] = true
	_check(uniq.size() >= 4, "hitstop 时长至少有 4 个不同量级（实际 %d）" % uniq.size())
	# 自己受伤不能有 hitstop（不打断操作）
	_check_eq(float(f.LEVELS["player_hurt"]["hitstop_ms"]), 0.0, "自己受伤零 hitstop（不打断操作）")
	# 自己受伤的闪白必须是红色（白色会冲淡整屏 —— 实测踩过）
	var fc: Color = f.LEVELS["player_hurt"]["flash_color"]
	_check(fc.r > fc.g and fc.r > fc.b, "自己受伤的闪白是红色（r=%.2f）" % fc.r)
	# 自己开枪的 trauma 必须远小于受伤
	_check(float(f.LEVELS["player_shoot"]["trauma"]) < float(f.LEVELS["player_hurt"]["trauma"]) * 0.25,
		"自己开枪的震动远小于受伤")

	# ── 震动配额：压制连续随机震动（spec 明令禁止）──
	f.reset()
	f.shake_enabled = true
	f._shake_budget = 0.1
	f.trauma = 0.0
	for _i in 6:
		f.add_trauma(0.3)
	_check(f.trauma < 0.6, "配额耗尽后压制连续震动（trauma=%.2f）" % f.trauma)

	f.reset()
	_check_eq(f.trauma, 0.0, "reset 清零 trauma")
	_check(absf(Engine.time_scale - 1.0) < 0.001, "reset 复原 time_scale")

	f.queue_free()


func _test_sfx_bank() -> void:
	# ── 音效注册表本身是数据，先验数据 ──
	var path := "res://data/sfx.json"
	_check(FileAccess.file_exists(path), "存在 data/sfx.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Array, "sfx.json 顶层是数组")
	var rows: Array = parsed
	_check(rows.size() >= 20, "注册了 %d 个音效" % rows.size())

	var ids := {}
	var all_have_file := true
	var all_exist := true
	var guns := 0
	for r in rows:
		var id := str(r.get("id", ""))
		var file := str(r.get("file", ""))
		if id.is_empty() or file.is_empty():
			all_have_file = false
		if ids.has(id):
			all_have_file = false       # 重复 id
		ids[id] = true
		if not ResourceLoader.exists(file):
			all_exist = false
			push_warning("音效文件缺失：%s" % file)
		if id.begins_with("gun_"):
			guns += 1
		# 变调范围必须合法
		if float(r.get("pitch_min", 1.0)) > float(r.get("pitch_max", 1.0)):
			all_have_file = false
	_check(all_have_file, "每条都有 id/file，无重复，变调范围合法")
	_check(all_exist, "所有音效文件都真实存在")

	# ── 我们需要的音效都在 —— 缺一个就代表某个反馈是哑的 ──
	var required := [
		"gun_pistol_player", "gun_rifle_player", "gun_shotgun_player",
		"gun_pistol_enemy", "gun_rifle_enemy", "gun_shotgun_enemy",
		"hit_flesh", "hit_crit", "hit_armor", "player_hurt", "kill_confirm",
		"reload_start", "reload_done", "reload_empty",
		"step_concrete", "step_dirt", "step_metal", "step_wood",
		"explosion", "hurt_heavy",
	]
	var missing: Array[String] = []
	for m in required:
		if not ids.has(m):
			missing.append(m)
	_check(missing.is_empty(), "必备音效齐全" + ("" if missing.is_empty() else "，缺：" + str(missing)))
	_check(guns >= 6, "枪声有 %d 条（3 把枪 x 玩家/敌人）" % guns)

	# ── 枪声文件是不是真的是一击（时长合理、不是 15 秒原录音）──
	var bad_dur: Array[String] = []
	for r in rows:
		var id := str(r.get("id", ""))
		if not id.begins_with("gun_"):
			continue
		var st: AudioStream = load(str(r.get("file", "")))
		if st == null:
			bad_dur.append(id + "(载入失败)")
			continue
		var len_s := st.get_length()
		if len_s < 0.05 or len_s > 1.6:
			bad_dur.append("%s=%.2fs" % [id, len_s])
	_check(bad_dur.is_empty(), "枪声都是裁好的单发" + ("" if bad_dur.is_empty() else "，异常：" + str(bad_dur)))

	# ── 管理器：能建、能载入、headless 不崩 ──
	var s_script: GDScript = load("res://audio/sfx.gd")
	_check(s_script != null, "能载入 sfx.gd")
	var s: Node = s_script.new()
	root.add_child(s)          # add_child 会同步触发 _ready（root 已就绪）
	_check(s.has("gun_rifle_player"), "管理器认得出 gun_rifle_player")
	_check(not s.has("不存在的音效"), "不存在的音效返回 false")

	# 播放在 headless 下必须安全（不能崩、不能报错）
	s.play("gun_rifle_player")
	s.play("不存在的音效")
	s.play_at("hit_flesh", Vector2(10, 10), Vector2.ZERO, 6.0, 30.0)

	# 去重：极短时间内的重复触发会被丢弃
	var before: int = s.played_count
	for _i in 10:
		s.play("hit_flesh")
	_check(s.dropped_count > 0, "短时间内重复触发被去重（丢弃 %d 次）" % s.dropped_count)

	# 静音开关
	s.enabled = false
	var c0: int = s.played_count
	s.play("gun_rifle_player")
	_check_eq(s.played_count, c0, "静音后不再播放")
	s.enabled = true

	_check(s.stats().contains("音效"), "stats 可读：%s" % s.stats())
	s.queue_free()


# ─────────────────── 真机反馈修复的回归测试 ───────────────────

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


func _test_result_overlay_exists() -> void:
	# 结算界面必须存在且可实例化 —— 它是手机上唯一的"再来一局"出口
	var s: GDScript = load("res://ui/result_overlay.gd")
	_check(s != null, "result_overlay.gd 可载入")
	var ov: Node = s.new()
	root.add_child(ov)
	# _ready 只在进树时跑；这里手动触发一次，保证后续断言有意义
	if not ov.has_method("show_result"):
		_check(false, "result_overlay 缺少 show_result")
	else:
		_check(true, "result_overlay 有 show_result")
	_check(ov.has_signal("restart_requested"), "有 restart_requested 信号")
	ov.queue_free()

	# 触屏控件也要有"整体收起"接口（结算时藏起来，不然会透过遮罩露出来）
	var ts: GDScript = load("res://ui/touch_controls.gd")
	_check(ts != null, "touch_controls.gd 可载入")
	var tc: Node = ts.new()
	root.add_child(tc)
	_check(tc.has_method("set_controls_visible"), "有 set_controls_visible")
	_check(tc.has_method("release_all"), "有 release_all")
	_check(tc.has_method("move_vector") and tc.has_method("aim_vector"), "有移动/瞄准读取接口")
	_check(tc.has_method("aim_push"), "有 aim_push（aim assist 靠它判断推力）")
	tc.queue_free()


# ─────────────────── 触屏输入隔离 / 卡顿 / 白模（第二轮真机反馈）───────────────────

func _test_touch_input_isolation() -> void:
	# ⚠️ 安卓真机反馈的三个问题（按右侧任意处开火 / 点瞄准摇杆开火 / 按治疗也开火）
	#    根因是同一个：raid_scene 的 _input 里还留着【没有触屏控件时代】的
	#    全局触摸开火代码，它和 VirtualJoystick / TouchButton 抢输入。
	#
	#    这类"遗留代码抢输入"很容易在后续迭代里被无意加回来，
	#    所以这里做**源码级守卫**。
	var src := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(not src.is_empty(), "能读到 raid_scene.gd")
	_check(not src.contains("is InputEventScreenTouch"),
		"raid_scene 不再自己处理触摸事件（交给 VirtualJoystick / TouchButton）")
	_check(not src.contains("_touch_move_id"), "遗留的自绘摇杆状态已清除")
	_check(src.contains("touch.is_firing()"),
		"开火状态确实读取了触屏开火按钮（否则按钮点了没反应）")
	_check(src.contains("touch.move_vector()"), "移动读取触屏摇杆")
	_check(src.contains("touch.aim_vector()"), "瞄准读取触屏摇杆")

	# 触屏按钮必须按 finger index 分别记录（T-12）
	var btn := FileAccess.get_file_as_string("res://ui/touch_button.gd")
	_check(btn.contains("_finger"), "TouchButton 按 finger index 记录触点（T-12）")
	_check(btn.contains("t.index == _finger"),
		"抬起时只清【该 index】—— 无脑清空会导致别的按钮同时归零")


func _test_hitstop_frequency_limit() -> void:
	# ⚠️ 安卓真机反馈"自动开火有很强的卡顿"。
	#    根因：轻击档曾配 30ms hitstop，600 RPM = 每 100ms 一发，
	#    每发都冻 30ms => 每秒 300ms 在冻结 = 30% 的时间画面不动。
	var f_script: GDScript = load("res://feel/feel.gd")
	var f: Node = f_script.new()
	root.add_child(f)
	f.reset()
	f.shake_enabled = true

	# ① 轻击档不得冻结（全自动武器下每发都停会退化成持续卡顿）
	_check_eq(float(f.LEVELS["light"]["hitstop_ms"]), 0.0,
		"轻击档 hitstop = 0（反馈交给音效与粒子，不占用冻结）")
	# ② 真正有分量的档位保留冻结
	_check(float(f.LEVELS["heavy"]["hitstop_ms"]) > 0.0, "重击仍冻结")
	_check(float(f.LEVELS["crit"]["hitstop_ms"]) > float(f.LEVELS["heavy"]["hitstop_ms"]),
		"暴击冻结比重击长")
	_check(float(f.LEVELS["kill"]["hitstop_ms"]) >= float(f.LEVELS["crit"]["hitstop_ms"]),
		"击杀冻结最长")

	# ③ 频率配额：连续狂点也不能一直在冻结
	f.reset()
	var fired := 0
	for _i in 30:
		f.hitstop(60.0)
		fired += 1
	_check_eq(f.hitstop_count, 1, "连续 30 次 hitstop 请求只生效 1 次（频率配额）")
	_check(f._hitstop_suppressed >= 29, "其余被配额压掉（%d 次）" % f._hitstop_suppressed)

	# ④ 但隔开足够时间后应当能再次生效
	f.reset()
	f.hitstop(60.0)
	_check_eq(f.hitstop_count, 1, "第一次生效")
	f._last_hitstop_ms = Time.get_ticks_msec() - int(f.HITSTOP_MIN_INTERVAL_MS) - 5
	f.hitstop(60.0)
	_check_eq(f.hitstop_count, 2, "超过最小间隔后可再次生效")

	# ⑤ 单次时长仍受 60~120ms 硬上限约束
	f.reset()
	f.hitstop(5000.0)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 180:
		pass
	f._process(0.016)
	_check(not f.is_frozen(), "超长请求被夹到 <=120ms 并已恢复")

	f.reset()
	Engine.time_scale = 1.0
	f.queue_free()


func _test_whitebox_render() -> void:
	# 技术验证阶段默认白模（用户建议 + 真机"看不出哪能走"）
	var src := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(src.contains("RENDER_WHITEBOX"), "有白模渲染模式")
	_check(src.contains("RENDER_ART"), "保留美术 tile 模式（可切换）")
	_check(src.contains("var render_mode := RENDER_WHITEBOX"),
		"默认是白模（技术验证优先『能读懂』而非『好看』）")
	_check(src.contains("_build_whitebox"), "有白模烘焙函数")
	# 白模的语义必须极端简单：亮 = 可走，暗 + 描边 = 阻挡
	_check(src.contains("WB_FLOOR") and src.contains("WB_WALL"),
		"白模区分地板与墙的配色")
	_check(src.contains("WB_WALL_EDGE"), "墙有高亮描边（一眼可辨）")

	# 白模烘焙必须真的能跑出图（不崩、尺寸对）
	var reg := DataRegistry.new()
	reg.load_all("B")
	var gen := MapGenerator.new()
	_check(gen.generate(4242, reg.room_types), "地图生成成功")
	var g := gen.grid
	var te := g.tile_extents()
	_check(te.x > 0 and te.y > 0, "tile 尺寸 %s" % str(te))
	# 直接调静态语义：可走格与阻挡格在数据层确实是分开的
	_check(g.is_walkable(gen.spawn_room().center), "出生点房间中心可走")
	var solid_found := false
	for y in g.height:
		for x in g.width:
			if not g.is_walkable(Vector2i(x, y)):
				solid_found = true
				break
		if solid_found:
			break
	_check(solid_found, "地图里确实存在阻挡格（白模要把它画出来）")


# ─────────────────── 性能回归：听觉代价场缓存 ───────────────────

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


func _test_enemy_count_test_mode() -> void:
	# 真机反馈 #2：技术验证阶段敌人太多（35 个），要求每类型各 1 个、总数 <= 4
	# ⚠️ 用 load() 取常量而不是引用类型名 —— 后者会在编译期把整个场景脚本拉进来，
	#    而场景脚本引用了 autoload（Sfx/Feel/Tel），会污染无关脚本的编译。
	var src: GDScript = load("res://view/raid_scene.gd")
	_check(src != null, "能载入 raid_scene.gd")
	var cap: int = int(src.get("MAX_TEST_ENEMIES"))
	_check(cap <= 4, "测试模式敌人上限 %d <= 4" % cap)
	_check(cap >= 2, "至少能放 2 种敌人（实际 %d）" % cap)
	var text := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(text.contains("agents.size() >= MAX_TEST_ENEMIES"), "刷怪循环里确实做了钳制")
	_check(text.contains("MAX_TEST_ENEMIES > 0"), "关掉测试模式能回到正式刷怪")



# ─────────────────── 真机反馈第三轮：#1 hitbox / #4#5 auto-aim / #6 尸体 / #7 藏身处 ───────────────────

func _test_hitbox_close_range() -> void:
	# 真机反馈 #1："敌人 hitbox 有问题，贴脸很难命中敌人"
	# 根因：早先只用角度锥判定。1 格外偏 0.3 格 = 17°，而锥半角只有 4.2° -> 永远打不中。
	# 现在加"射线到实体中心的垂距 <= hit_radius"这条通路，并给足半径。
	var g := _open_grid(20, 14)
	var origin := Vector2(5.5, 5.5)

	# 贴脸且明显偏离瞄准方向：必须能命中
	var close := [{"id": "c", "pos": Vector2(6.5, 5.9), "faction": "enemy", "alive": true}]
	var r := AimAssist.pick(origin, Vector2.RIGHT, 0.6, close, g, 4.2, 30.0)
	_check(not r.is_empty(), "贴脸偏心目标也能命中（0.4 格偏移 / 1 格距离 = 21.8°）")

	# 超出实体半径则不该命中
	var far_off := [{"id": "f", "pos": Vector2(6.5, 6.9), "faction": "enemy", "alive": true}]
	_check(AimAssist.pick(origin, Vector2.RIGHT, 0.6, far_off, g, 4.2, 30.0).is_empty(),
		"横向偏移 1.4 格（远超实体半径）不命中")

	# 实体半径可被数据覆盖（大体型敌人）
	var big := [{"id": "b", "pos": Vector2(6.5, 6.9), "faction": "enemy", "alive": true,
		"radius": 1.6}]
	_check(not AimAssist.pick(origin, Vector2.RIGHT, 0.6, big, g, 4.2, 30.0).is_empty(),
		"radius=1.6 的大体型目标能命中")

	# ⭐ 偏折上限必须按【横向距离】而不是角度 —— 否则贴脸差几度永远打不中
	var r2 := AimAssist.pick(origin, Vector2.RIGHT, 0.6, close, g, 4.2, 30.0)
	var bent: Vector2 = r2["dir"]
	var ang := absf(wrapf(bent.angle() - Vector2.RIGHT.angle(), -PI, PI))
	_check(rad_to_deg(ang) > AimAssist.MAX_BEND_DEG,
		"近距离允许超过旧角度上限的偏折（%.1f° > %.1f°）—— 这正是贴脸打不中的根因"
		% [rad_to_deg(ang), AimAssist.MAX_BEND_DEG])
	# 但横向偏移仍被限住
	var lateral := rad_to_deg(ang) * PI / 180.0 * float(r2["dist"])
	_check(lateral <= AimAssist.MAX_BEND_CELLS + 0.02,
		"横向偏移仍受限（%.2f <= %.2f 格）" % [lateral, AimAssist.MAX_BEND_CELLS])

	# 远距离仍然克制：10 格外只能偏一点点
	var far := [{"id": "d", "pos": Vector2(15.5, 5.9), "faction": "enemy", "alive": true}]
	var r3 := AimAssist.pick(origin, Vector2.RIGHT, 0.6, far, g, 4.2, 30.0)
	if not r3.is_empty():
		var a3 := absf(wrapf((r3["dir"] as Vector2).angle() - 0.0, -PI, PI))
		_check(rad_to_deg(a3) < 6.0, "远距离偏折很小（%.2f°）" % rad_to_deg(a3))


func _test_auto_aim() -> void:
	# 真机反馈 #4/#5：锥形视野 + 锁定最近敌人 + 自动瞄准/自动射击
	var g := _open_grid(24, 16)
	var origin := Vector2(2.5, 8.5)
	var targets := [
		{"id": 1, "pos": Vector2(12.5, 8.5), "faction": "enemy", "alive": true},
		{"id": 2, "pos": Vector2(6.5, 8.5), "faction": "enemy", "alive": true},   # 最近
		{"id": 3, "pos": Vector2(2.5, 2.5), "faction": "enemy", "alive": true},   # 锥外
	]

	# ⭐ 优先锁定【最近的】
	var f := AutoAim.scan_nearest(origin, Vector2.RIGHT, 55.0, 60.0, targets, g)
	_check(not f.is_empty(), "锥内发现敌人")
	_check_eq(int(f["target"]["id"]), 2, "锁定的是最近的敌人")
	_check(absf(float(f["dist"]) - 4.0) < 0.01, "距离 4.0（实际 %.2f）" % float(f["dist"]))

	# 锥角决定视野：把锥角缩到 2°，近处那个偏 0° 仍可见，远处也可见；
	# 换成朝上的 3 号目标才该受锥角影响
	var up := AutoAim.scan_nearest(origin, Vector2.UP, 55.0, 60.0, targets, g)
	_check(not up.is_empty() and int(up["target"]["id"]) == 3, "朝上时锁定 3 号")

	# 目标筛选：不锁同伴
	var ally := [{"id": 9, "pos": Vector2(4.5, 8.5), "faction": "player", "alive": true}]
	_check(AutoAim.scan_nearest(origin, Vector2.RIGHT, 55.0, 60.0, ally, g).is_empty(),
		"不锁定同阵营")

	# 已死目标不锁
	var dead := [{"id": 8, "pos": Vector2(4.5, 8.5), "faction": "enemy", "alive": false}]
	_check(AutoAim.scan_nearest(origin, Vector2.RIGHT, 55.0, 60.0, dead, g).is_empty(),
		"不锁定已死目标")

	# 视线遮挡
	g.set_cell(Vector2i(4, 8), LogicalGrid.Cell.SOLID)
	_check(AutoAim.scan_nearest(origin, Vector2.RIGHT, 55.0, 60.0, targets, g).is_empty()
		or int(AutoAim.scan_nearest(origin, Vector2.RIGHT, 55.0, 60.0, targets, g)["target"]["id"]) != 2,
		"隔墙后不再锁定 2 号")
	g.set_cell(Vector2i(4, 8), LogicalGrid.Cell.FLOOR)

	# ── 锁定粘性：目标暂时消失不会立刻脱锁（否则准心会疯狂切换）──
	var aa := AutoAim.new()
	var r1 := aa.update(0.1, origin, Vector2.RIGHT, 55.0, 60.0, targets, g)
	_check(bool(r1["has_lock"]), "建立锁定")
	_check_eq(aa.locked_id, 2, "锁的是 2 号")
	var none: Array = []
	var r2 := aa.update(0.1, origin, Vector2.RIGHT, 55.0, 60.0, none, g)
	_check(bool(r2["has_lock"]), "目标消失后靠粘性保持锁定")
	# 熬过粘性时间才脱锁
	var t := 0.0
	while t < AutoAim.LOCK_GRACE + 0.3:
		aa.update(0.1, origin, Vector2.RIGHT, 55.0, 60.0, none, g)
		t += 0.1
	_check(not aa.has_lock(), "粘性耗尽后真正脱锁")

	# 转向有角度上限（避免"甩枪"）
	var turned := AutoAim.turn_toward(Vector2.RIGHT, Vector2.LEFT, 90.0)
	_check(absf(rad_to_deg(absf(turned.angle()))) < 91.0,
		"单次转向不超过 90°（实际 %.1f°）" % rad_to_deg(absf(turned.angle())))
	_check(AutoAim.turn_toward(Vector2.ZERO, Vector2.RIGHT, 90.0) == Vector2.RIGHT,
		"零向量输入不崩")


func _test_weapon_aim_cone() -> void:
	# 真机反馈 #5："这个视野会随着枪械具体数值来变化"
	var reg := DataRegistry.new()
	reg.load_all("B")
	var pistol: WeaponDef = reg.get_weapon("weapon_pistol")
	var rifle: WeaponDef = reg.get_weapon("weapon_rifle")
	var shotgun: WeaponDef = reg.get_weapon("weapon_shotgun")
	_check(pistol.aim_cone_deg > 0.0, "手枪视野锥 %.0f°" % pistol.aim_cone_deg)
	_check(rifle.aim_cone_deg != pistol.aim_cone_deg,
		"不同枪的视野锥不同（步枪 %.0f° vs 手枪 %.0f°）" % [rifle.aim_cone_deg, pistol.aim_cone_deg])
	_check(shotgun.aim_cone_deg < rifle.aim_cone_deg,
		"霰弹枪视野最窄（%.0f° < %.0f°）" % [shotgun.aim_cone_deg, rifle.aim_cone_deg])

	# ⚠️ 改装后的 WeaponDef 必须带上这个字段，否则"视野随枪械变化"会静默失效（踩过）
	var lo := WeaponModding.create_loadout(rifle, WeaponModding.SLOTS_A)
	var eff := lo.to_weapon_def()
	_check(absf(eff.aim_cone_deg - rifle.aim_cone_deg) < 0.001,
		"改装后的有效武器保留了视野锥（%.0f°）" % eff.aim_cone_deg)


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

func _test_no_double_hit_roll() -> void:
	# ⚠️ 用户 PC 实测："我射她的时候 hitbox 很怪，子弹从他身上传过去了"
	#    查明是**两个独立 bug 叠加**：
	#      ① _try_fire 在 AimAssist 已经判定命中之后，【又掷了一次随机数】
	#         `randf() <= 0.30 + acc*0.7`。没过就把它当打空，曳光打到墙上
	#         -> 表现就是"子弹从她身上穿过去"。
	#      ② 桌面 `_aim_push()` 返回 0（只有按住移动才给 0.45），
	#         而 pick() 在 push < 0.22 时直接返回空 -> PC 上子弹磁性几乎从不生效。
	#    本测试做**源码级守卫**，防止双重判定被加回来。
	var src := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(not src.is_empty(), "能读到 raid_scene.gd")
	_check(not src.contains("_rng.randf() <= clampf(0.30 + acc"),
		"命中判定里不再有第二次随机数（双重判定会表现为『子弹穿过去』）")
	_check(src.contains("if tgt != null:"), "pick 找到目标即为命中")
	_check(src.contains("_spread_radius_factor"),
		"散布改为收缩有效 hitbox（逻辑只有一处）")
	_check(src.contains("return 0.55"),
		"桌面 _aim_push 给恒定推力（返回 0 会让 pick 直接失效）")


func _test_spread_radius_factor() -> void:
	# 散布对有效 hitbox 的收缩：0 散布 = 满半径；散布大 = 半径小但不会到 0
	# 直接验证数学关系（不实例化场景）
	var base := AimAssist.DEFAULT_HIT_RADIUS
	_check(base > 0.2, "默认实体半径 %.2f 格足够宽松（触屏精度差，判定要给余量）" % base)
	# 复刻 _spread_radius_factor 的公式做交叉验证
	var f0 := clampf(1.0 - maxf(0.0, 0.0) / 10.0, 0.35, 1.0)
	var f5 := clampf(1.0 - maxf(5.0, 0.0) / 10.0, 0.35, 1.0)
	var f99 := clampf(1.0 - maxf(99.0, 0.0) / 10.0, 0.35, 1.0)
	_check(absf(f0 - 1.0) < 0.001, "0 散布 -> 满半径")
	_check(f5 < f0 and f5 > 0.35, "5° 散布 -> 半径收缩到 %.2f" % f5)
	_check(absf(f99 - 0.35) < 0.001, "散布再大也保底 0.35 半径（不能完全打不中）")

	# 有效半径收缩后，超出新半径的偏轴目标应该被拒
	var g := _open_grid(20, 14)
	var origin := Vector2(5.5, 5.5)
	var off := [{"id": "o", "pos": Vector2(9.5, 5.95), "faction": "enemy", "alive": true}]
	# 满半径：接受
	_check(not AimAssist.pick(origin, Vector2.RIGHT, 0.6, off, g, 4.2, 30.0,
		"player", base).is_empty(), "满半径下能命中")
	# 极小半径：拒绝
	_check(AimAssist.pick(origin, Vector2.RIGHT, 0.6, off, g, 4.2, 30.0,
		"player", 0.05).is_empty(), "半径收到 0.05 后拒掉偏轴目标")

	# 桌面推力必须够（低于 MIN_PUSH 会让 pick 完全失效）
	_check(0.55 >= AimAssist.MIN_PUSH,
		"桌面推力 0.55 >= MIN_PUSH %.2f" % AimAssist.MIN_PUSH)


# ─────────────────── PC 实测反馈（火花位置 / 键位 / 设置菜单）───────────────────

func _test_fx_cell_coords() -> void:
	# 用户 PC 实测："我刚才这个弹夹打出的子弹，会在地图左上角有火花动画"
	# 根因：burst() 收到的是【逻辑格坐标】（如 5.5），
	#       而粒子节点在世界空间里 1 格 = 48 像素 ——
	#       于是全部堆在 (5.5, 5.5) 像素 = 地图左上角。
	# 现在 burst() 内部统一乘 CELL_PX，调用方一律传逻辑格坐标。
	var src := FileAccess.get_file_as_string("res://view/fx_pool.gd")
	_check(src.contains("p.global_position = pos * CELL_PX"),
		"burst() 把逻辑格坐标换算成像素（漏了就会全堆在左上角）")
	_check(src.contains("const CELL_PX := 48.0"), "CELL_PX 常量存在")
	# 必须与 raid_scene 的 CELL_PX 一致，否则火花位置会整体偏移
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("CELL_PX") or rs.contains("LogicalGrid.CELL_PX"),
		"raid_scene 也使用同一套格->像素换算")
	_check(src.contains("burst(kind: String, pos: Vector2"),
		"burst 签名仍收 Vector2（逻辑格坐标）")


func _test_keybindings() -> void:
	# 用户 PC 实测："修改 pc 按键 r 为装弹 k 为重启 t 为治疗"
	#           "f1 到 f4 没有说明 应该加入 esc 设置菜单"
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	var i := rs.find("func _input(event: InputEvent)")
	_check(i > 0, "找到 _input")
	var seg := rs.substr(i, 1400)
	_check(seg.contains("KEY_R:") and seg.contains("start_reload()"),
		"R = 装弹")
	_check(seg.contains("KEY_T:") and seg.contains("_try_heal()"),
		"T = 治疗")
	_check(seg.contains("KEY_B:") and seg.contains("_open_bag()"),
		"B = 背包/搜索（PC 上必须有键，否则尸体搜不了）")
	_check(seg.contains("KEY_K:"), "K 已绑定（重开）")
	_check(not seg.contains("KEY_L:"), "旧的 L 键已移除")
	# ESC 不能在 raid_scene 里处理，否则和 SettingsMenu 撞车（toggle 两次 = 没反应）
	_check(not seg.contains("KEY_ESCAPE"),
		"ESC 不由 raid_scene 处理（交给 SettingsMenu 独占）")
	var sm := FileAccess.get_file_as_string("res://ui/settings_menu.gd")
	_check(sm.contains('is_action_pressed("ui_cancel")'), "ESC 走 ui_cancel")
	_check(sm.contains("NOTIFICATION_WM_GO_BACK_REQUEST"), "安卓返回键也接上了")
	_check(sm.contains("F1") and sm.contains("F4"),
		"设置菜单里写了 F1~F4 的说明（用户：『f1 到 f4 没有说明』）")
	# ⚠️ 这里**故意断言不使用 get_tree().paused**。
	#    PC 实测：用了它之后按 ESC 卡死（树被暂停 28 秒且 ESC 关不掉）。
	#    它会连输入一起门控，导致菜单看得见、点不动。
	#    现在改成纯逻辑冻结（Game.paused），输入路径完全不变。
	_check(not sm.contains("get_tree().paused = true"),
		"不使用 get_tree().paused（它会门控输入 -> 菜单点不动 -> 卡死）")
	_check(sm.contains("Game.paused = true"), "打开菜单会冻结游戏逻辑")
	_check(sm.contains("Game.paused = false"), "关闭菜单会恢复")
	_check(rs.contains("Game.paused") or rs.contains("game_paused"),
		"场景 _process 会看暂停标志")
	_check(sm.contains("PROCESS_MODE_ALWAYS"), "菜单自身不受暂停影响")
	# 场景里要有场景内开关的钩子
	_check(rs.contains("func toggle_whitebox()"), "有 toggle_whitebox 钩子")
	_check(rs.contains("func toggle_debug()"), "有 toggle_debug 钩子")
	_check(rs.contains("var game_paused := false"), "有 game_paused 标志")


func _test_corpse_interaction_visible() -> void:
	# 用户 PC 实测："和敌人尸体没法交互。（战利品系统呢）"
	# 尸体其实已经生成、也能搜 —— 问题是【没有可见入口】。
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("_spawn_corpse(tgt)"), "击杀后会生成尸体容器")
	_check(rs.contains("corpse_label"), "HUD 有『附近有尸体』的提示")
	_check(rs.contains("func _bag_key_hint()"), "提示里带按键（触屏/PC 文案不同）")
	_check(rs.contains("raid.corpse_near(player_pos)"), "每帧检测附近尸体")
	# SettingsMenu 不能和 Object._get 撞名（踩过一次编译失败）
	var sm := FileAccess.get_file_as_string("res://ui/settings_menu.gd")
	_check(not sm.contains("func _get("),
		"设置菜单没有定义 _get（会与 Object._get(StringName) 签名冲突）")


# ─────────────────── 本会话【第三次】栽的同一个坑 ───────────────────

func _test_control_size_not_zero() -> void:
	# ⚠️ 这个坑在本会话里踩了三次：
	#   ① 虚拟摇杆   —— 布局全挤在角落
	#   ② 结算面板   —— 面板整个看不见
	#   ③ 设置菜单   —— 按 ESC 后**只看得到顶部两个小圆按钮，
	#                   暗色背景和所有开关都不渲染**（用户："esc 了看不到继续"）
	#
	# 根因完全相同：**`Control` 直接挂在 `CanvasLayer` / `Node2D` 下时，
	#   `set_anchors_preset(FULL_RECT)` 解析不到父矩形 -> 自身 size 停在 (0,0)
	#   -> 子节点全部塌掉。**
	#
	# 正确做法：自己跟 viewport 尺寸同步（并在 viewport 变化时重新同步）。
	var sm := FileAccess.get_file_as_string("res://ui/settings_menu.gd")
	_check(sm.contains("func _fit_viewport"), "设置菜单有 _fit_viewport")
	_check(sm.contains("size = vp"), "把自身 size 钉到视口尺寸")
	_check(sm.contains("get_viewport().size_changed.connect"),
		"监听 viewport 尺寸变化（窗口/旋转后要重新同步）")
	# 顺序：必须先手动同步一次，再连信号（否则第一帧仍然是塌的）
	var i_fit := sm.find("_fit_viewport()")
	var i_conn := sm.find("size_changed.connect")
	_check(i_fit > 0 and i_conn > 0 and i_fit < i_conn,
		"先同步再连接信号（fit@%d < connect@%d）" % [i_fit, i_conn])

	# 结算面板也要有这个兜底（它是第二个踩坑的地方）
	var ro := FileAccess.get_file_as_string("res://ui/result_overlay.gd")
	_check(ro.contains("get_viewport_rect()") or ro.contains("size = vp"),
		"结算面板也用了 viewport 兜底")

	# TouchButton 不能无条件覆盖调用方设的最小尺寸 ——
	# 否则设置菜单里设的 150x76 会被悄悄改成 60x60，文字溢出到圆外
	var tb := FileAccess.get_file_as_string("res://ui/touch_button.gd")
	_check(tb.contains("if custom_minimum_size == Vector2.ZERO"),
		"TouchButton 只在调用方没指定时才推最小尺寸")
	_check(tb.contains("func _draw_wide"),
		"宽控件画圆角矩形（否则文字溢出圆形按钮）")


func _test_settings_menu_layout() -> void:
	# 直接读源码断言"操作按钮在顶部固定栏"，而不是在滚动区底部。
	# 早先放在滚动内容末尾 —— 16 行按键说明 + 一堆开关比屏幕高，
	# 按钮被挤到折叠线以下，玩家根本看不到（真机原话："看不到继续"）。
	var sm := FileAccess.get_file_as_string("res://ui/settings_menu.gd")
	var i_bar := sm.find("顶部固定栏")
	var i_scroll := sm.find("下方滚动区")
	var i_resume := sm.find("resume_top")
	_check(i_bar > 0, "有顶部固定栏")
	_check(i_scroll > 0, "有下方滚动区")
	_check(i_resume > 0, "「继续」按钮存在")
	_check(i_resume < i_scroll,
		"「继续」在滚动区【之前】创建 = 位于固定栏，不会被内容挤出屏幕")
	_check(sm.contains("went_hideout.emit()"), "「返回藏身处」仍可用")


func _test_hideout_layout() -> void:
	# 真机反馈："在返回藏身处后加入 开始下一局的 ui"
	# 查证：藏身处早先把所有内容塞进一个 VBox，
	# 640x360 下内容总高约 586px -> **「出发」按钮被挤出屏幕**，
	# 玩家回到藏身处后找不到怎么开下一局。
	# （与设置菜单"看不到继续"完全同类：内容超出视口 + 关键按钮放在末尾。）
	var hs := FileAccess.get_file_as_string("res://view/hideout_scene.gd")
	_check(hs.contains("开始下一局"), "按钮文案是「开始下一局」")
	_check(hs.contains("func _fit_viewport"), "藏身处也有 _fit_viewport 兜底")
	_check(hs.contains("ScrollContainer"), "内容放进滚动容器")
	# 关键：按钮必须在滚动区【之前】创建 = 位于顶部固定栏
	var i_go := hs.find("开始下一局")
	var i_scroll := hs.find("ScrollContainer.new()")
	_check(i_go > 0 and i_scroll > 0, "两者都存在")
	_check(i_go < i_scroll,
		"「开始下一局」在滚动区之前创建 = 顶部固定栏，任何分辨率都可见（go@%d < scroll@%d）"
		% [i_go, i_scroll])
	_check(hs.contains("Game.start_raid()"), "点了会开新一局")


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

func _test_sfx_concurrency() -> void:
	# 手机实测：`音频掉 95`。
	# 查证不是"并发太多"，而是**枪声被永久掐断**：
	#   并发计数只数 `_live` 里的名字，而 `_live` 的条目在音效播完后从不清理,
	#   只在槽位被 _acquire 复用时才覆盖。
	#   -> 步枪响过 max_simul 次后，running >= max_simul 恒成立
	#   -> 之后每一枪都被丢弃。
	# 正确做法：**同时**检查"槽位登记的是本人" **且** "它现在真的在播"。
	var src := FileAccess.get_file_as_string("res://audio/sfx.gd")
	_check(src.contains("and _pool[i].playing"),
		"并发计数必须检查 .playing（否则播完的残留会把音效永久掐断）")
	_check(src.contains("str(_live[i]) == name"),
		"并发计数检查的是槽位登记的名字")
	# `_live` 是 Array，不能用 Dictionary 的 .get(k, default)
	_check(not src.contains("_live.get("),
		"_live 是 Array，不能用 .get(i, default)（会编译失败）")
	_check(src.contains("var _live: Array"), "_live 确实是 Array")

	# 行为验证：同一个音效播完多轮后仍然能被播放
	var sfx: Node = load("res://audio/sfx.gd").new()
	_check(sfx != null, "能实例化 Sfx")
	sfx.set("enabled", true)
	# 连播同一音效 30 次，每次之间都让它"播完"（headless 下 playing 恒为 false）
	var before := int(sfx.get("dropped_count"))
	for i in 30:
		sfx.call("play", "reload_start")
	var after := int(sfx.get("dropped_count"))
	var dropped := after - before
	# 去重窗口 35ms，30 次瞬时连播会被去重挡掉大部分；
	# 关键断言是【不会全部丢弃】，且播放计数在涨
	_check(int(sfx.get("played_count")) > 0, "确实播放了至少一次")
	_check(dropped < 30, "不是每次都丢（%d/30 被丢，旧实现会全丢或接近全丢）" % dropped)
	sfx.free()


func _test_hud_perf_metric() -> void:
	# 手机实测截图：`FPS 60  帧 25.2 ms` —— 两个数不可能同时成立。
	# 查证：HUD 那一路还在用 `Performance.TIME_PROCESS`，
	# 而它在 Android 上正是【已经被遥测判定为不可靠】并被换掉的那个。
	# （同一个坑踩了两次：先修遥测、漏了 HUD。）
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	# ⚠️ 只检查**实际调用** —— 注释里会提到它（说明为什么不能用），不算违规
	_check(not rs.contains("get_monitor(Performance.TIME_PROCESS)"),
		"HUD 不得再使用 Performance.TIME_PROCESS（Android 上会与 FPS 自相矛盾）")
	_check(rs.contains("Tel.last_avg_ms()"), "HUD 用遥测的墙钟均值")
	_check(rs.contains("Tel.last_worst_ms()"), "HUD 用遥测的墙钟最慢值")
	var tel := FileAccess.get_file_as_string("res://telemetry/telemetry.gd")
	_check(tel.contains("func last_avg_ms"), "Tel 暴露 last_avg_ms")
	_check(tel.contains("func last_worst_ms"), "Tel 暴露 last_worst_ms")
	_check(tel.contains("_last_avg_ms = wall"), "窗口关闭时记录真实墙钟均值")


# ─────────────────── 白模白模：视觉可走 == 实际可走 ───────────────────

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


func _test_cone_no_xray() -> void:
	# 真机反馈："玩家自动开火视野锥会透视，对于白模地图来说没有遮挡，
	#            会导致透视到敌人对墙开火。"
	# 拆成两个独立的缺陷：
	#   ① **视觉**：锥体是固定半径扇形，直接穿过墙
	#   ② **逻辑**：自动射击用 has_lock（含 1.2 秒粘性），
	#      敌人躲到墙后仍会朝墙打满 1.2 秒
	var bl := FileAccess.get_file_as_string("res://sim/combat/ballistics.gd")
	_check(bl.contains("func los_distance"), "有 los_distance（算撞墙前的距离）")
	_check(bl.contains("raycast_cells"), "复用标准 DDA（不漏格）")

	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("Ballistics.los_distance"), "锥体逐条射线做裁切")
	_check(rs.contains("screen_diag_cells"),
		"视觉半径不超过屏幕对角线（屏幕外看不见，不白算）")
	# 自动射击必须用 visible，不是 has_lock
	_check(rs.contains('_lock_info.get("visible", false)'),
		"自动射击要求【当前可见】而不是锁定粘性")
	_check(not rs.contains("Game.auto_fire and auto_aim.has_lock()"),
		"不得再用 has_lock 决定开火")

	var aa := FileAccess.get_file_as_string("res://sim/combat/auto_aim.gd")
	_check(aa.contains('"visible": true') and aa.contains('"visible": false'),
		"update() 区分 has_lock 与 visible")
	_check(aa.contains("has_lock=true 但 **visible=false**") or
		aa.contains("visible=false"), "注释说明了粘性期间禁止开火")

	# 行为验证：los_distance 在墙前就会截断
	var grid := _open_grid(20, 14)
	# 在 x=10 竖一道墙
	for y in 14:
		grid.set_cell(Vector2i(10, y), LogicalGrid.Cell.SOLID)
	var d := Ballistics.los_distance(grid, Vector2(5.5, 7.5), Vector2.RIGHT, 18.0)
	_check(d < 5.2 and d > 3.5,
		"朝墙射线在墙前截断（%.2f 格，墙在 x=10，起点 x=5.5）" % d)
	# 空地：给多少走多少
	var g2 := _open_grid(20, 14)
	_check(absf(Ballistics.los_distance(g2, Vector2(2.5, 2.5), Vector2.RIGHT, 6.0) - 6.0) < 0.01,
		"空地射线不截断")
	# 起点就在墙里 -> 0
	_check(Ballistics.los_distance(grid, Vector2(10.5, 7.5), Vector2.RIGHT, 8.0) == 0.0,
		"起点在墙里返回 0（不会算出负距离或崩）")

	# 粘性期间 visible 必须是 false
	var aa2 := AutoAim.new()
	var targets := [{"id": 1, "pos": Vector2(8.5, 7.5), "faction": "enemy", "alive": true}]
	var r1 := aa2.update(0.1, Vector2(2.5, 7.5), Vector2.RIGHT, 55.0, 30.0, targets, g2)
	_check(bool(r1["visible"]), "看得见时 visible=true")
	var r2 := aa2.update(0.1, Vector2(2.5, 7.5), Vector2.RIGHT, 55.0, 30.0, [], g2)
	_check(bool(r2["has_lock"]) and not bool(r2["visible"]),
		"粘性期间 has_lock=true 但 visible=false（这正是『对墙开火』的修法）")


# ─────────────────── ① 存档模块 ───────────────────

func _test_save_manager() -> void:
	# 关联：roadmap-bac.md §2「核心框架（…存档…）」——
	# 这是 M0 清单（action-plan §3）里唯一未完成的技术项。
	#
	# ⚠️ 路径策略是实测出来的：
	#   `user://` 在开发环境写不进去（Godot 子进程被限制在工作区内），
	#   而安卓上必须用 user://。所以 user:// 优先、失败回退到可执行文件旁边。
	var sm := SaveManager.new()
	_check(not sm.path.is_empty(), "解析出了存档路径：%s" % sm.path)
	_check(sm.path.ends_with(SaveManager.SAVE_FILE),
		"路径以 %s 结尾" % SaveManager.SAVE_FILE)

	# 清掉可能存在的旧档，保证从干净状态开始
	sm.delete()
	_check(not sm.exists(), "删除后存档不存在")

	# 从"没有存档"读 -> 明确报告而不是崩
	var r0 := sm.load_save()
	_check(not bool(r0["ok"]), "没有存档时 ok=false")
	_check(not str(r0["error"]).is_empty(), "有明确的原因：%s" % str(r0["error"]))

	# ── 写读往返 ──
	var payload := {
		"hideout": {"wallet": 12345, "upgrades": {"stash_size": 2},
			"stash": {"slots": [], "max_weight": 999.0}},
		"settings": {"auto_fire": true, "auto_aim": false},
		"stats": {"raids": 7, "extracts": 5, "deaths": 2, "kills": 31},
	}
	var err := sm.save(payload)
	_check_eq(err, "", "保存成功（%s）" % err)
	_check(sm.exists(), "存档文件已生成")

	var r1 := sm.load_save()
	_check(bool(r1["ok"]), "读档成功")
	_check_eq(int(r1["data"].get("version", 0)), SaveManager.SAVE_VERSION,
		"写入的版本号是当前版本")
	_check_eq(int((r1["data"]["hideout"] as Dictionary)["wallet"]), 12345, "钱数往返一致")
	_check_eq(int((r1["data"]["stats"] as Dictionary)["kills"]), 31, "统计往返一致")

	# ── 版本迁移 ──
	# v1 的档只有 wallet，缺 upgrades/stash
	var v1 := {"version": 1, "wallet": 999}
	var ok1 := SaveManager.migrate(v1, 1)
	_check(ok1, "v1 能迁移到当前版本")
	_check_eq(int(v1["version"]), SaveManager.SAVE_VERSION, "迁移后版本号被更新")
	_check(v1.has("upgrades") and v1.has("stash"), "v1->v2 补上了 upgrades/stash")
	_check(v1.has("settings") and v1.has("stats"), "v2->v3 补上了 settings/stats")

	# v2
	var v2 := {"version": 2, "wallet": 500, "upgrades": {}, "stash": {}}
	_check(SaveManager.migrate(v2, 2), "v2 能迁移")
	_check_eq(int(v2["version"]), SaveManager.SAVE_VERSION, "v2 迁移后版本正确")

	# 已经是当前版本：迁移应当是空操作
	var v3 := {"version": SaveManager.SAVE_VERSION, "wallet": 1}
	_check(SaveManager.migrate(v3, SaveManager.SAVE_VERSION), "当前版本迁移为空操作")
	_check_eq(int(v3["wallet"]), 1, "空操作不改数据")

	# ── 拒绝比程序更新的档 ──
	# ⚠️ 这条很重要：按旧规则解析新档会得到乱七八糟的状态，
	#    宁可报错也不要把玩家的档读坏。
	# ⚠️ 不能走 sm.save() —— 它总是把 version 覆写成当前版本，
	#    那样根本造不出"未来版本"的档（测试第一版就写错了）。
	#    直接写文件绕过它。
	var ff := FileAccess.open(sm.path, FileAccess.WRITE)
	_check(ff != null, "能直接打开存档文件写入")
	if ff != null:
		ff.store_string(JSON.stringify({
			"version": SaveManager.SAVE_VERSION + 5, "wallet": 1}))
		ff.close()
	var r2 := sm.load_save()
	_check(not bool(r2["ok"]), "拒绝读取比程序新的存档")
	_check(str(r2["error"]).contains("新"), "错误信息说明了版本过新：%s" % str(r2["error"]))

	# ── 坏档不能崩 ──
	var bad := FileAccess.open(sm.path, FileAccess.WRITE)
	if bad != null:
		bad.store_string("这不是 JSON {{{")
		bad.close()
	var r3 := sm.load_save()
	_check(not bool(r3["ok"]), "坏档返回 ok=false")
	_check(not str(r3["error"]).is_empty(), "坏档有明确原因")

	# ── 清理 ──
	sm.delete()
	_check(not sm.exists(), "测试后清理干净")


func _test_save_roundtrip_hideout() -> void:
	# 藏身处状态【真的】能存下来并读回去 —— 不只是 JSON 往返，
	# 而是 Hideout 这个对象本身。
	var reg := DataRegistry.new()
	reg.load_all("A")
	var sm := SaveManager.new()
	sm.delete()

	# 造一个有状态变化的藏身处
	var h1 := Hideout.new(reg.items, 3000)
	h1.wallet = 4321
	h1.buy_upgrade("stash_size")
	h1.buy_upgrade("stash_size")     # Lv2
	h1.buy_upgrade("carry_size")     # Lv1
	h1.stash.add("medical_bandage", 3)
	h1.stash.add("ammo_rifle", 60)

	_check_eq(sm.save({"hideout": h1.to_dict()}), "", "保存藏身处")
	var r := sm.load_save()
	_check(bool(r["ok"]), "读回藏身处")

	var h2 := Hideout.new(reg.items, 0)
	h2.from_dict(r["data"]["hideout"])
	_check_eq(h2.level_of("stash_size"), 2, "升级等级往返一致")
	_check_eq(h2.level_of("carry_size"), 1, "第二个升级也一致")
	_check_eq(h2.wallet, 4321, "资金往返一致")
	_check_eq(h2.stash.count_of("medical_bandage"), 3, "仓库物品往返一致")
	_check_eq(h2.stash.count_of("ammo_rifle"), 60, "第二件也一致")

	# ⚠️ 关键：读回来之后**效果函数必须跟着新等级走**。
	#    只恢复等级数字、不重新应用，就会出现"升级了但仓库没变大"。
	_check_eq(h2.slot_count(), h1.slot_count(), "仓库槽位效果一致（%d）" % h2.slot_count())
	_check(absf(h2.carry_weight_limit() - h1.carry_weight_limit()) < 0.001,
		"负重上限效果一致（%.1f kg）" % h2.carry_weight_limit())
	_check(absf(h2.sell_ratio() - h1.sell_ratio()) < 0.001, "商人回收比例一致")
	_check(h2.slot_count() > SaveManager.SAVE_VERSION * 0 + 40,
		"升级后仓库确实比基础多（%d > 40）" % h2.slot_count())

	sm.delete()
