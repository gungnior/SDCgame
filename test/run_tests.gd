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
