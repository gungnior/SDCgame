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
