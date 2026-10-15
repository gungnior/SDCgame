extends TestSuite

## 肉鸽局内规则变体 RunModifiers（2026-10-16 · 拥有者拍板转向「肉鸽 × 自动战斗 × 搜打撤」）
##
## 背景：三要素盘点 —— 搜打撤 ✅、自动战斗 ✅（player_autopilot + enemy_agent）、
## 肉鸽 ❌ 从零开始。地图结构已 seed 随机 + 主题随机，故第一块肉鸽机制做
## **规则变体层**（roguelite 的"每局带一两个变数"）：`sim/run_modifiers.gd` +
## `data/run_modifiers.json`，view 层（raid_scene）roll 后接入 enemy_density 与
## 容器抽取次数，HUD 开局一行显示。
##
## 本套件钉死六件事：
##   ① roll 确定性（同 seed 同结果 —— T-32 可复现纪律）；
##   ② 互斥组一局不重样（roll 200 次采样）；
##   ③ 因子连乘正确（多组同时生效时各自连乘、互不串组）；
##   ④ 空数据/坏条目安全（缺表、空数组、缺 id 都不炸，退化为无变体）；
##   ⑤ 数据契约（id 唯一 / group 非空 / 倍率 > 0 / 中文名在）；
##   ⑥ 源码结构防污染回归（raid_scene 必须 clone() 后再乘 density ——
##      reg.get_map() 是共享实例，直接乘会污染全局 registry）。


func register() -> void:
	_suite("roll 确定性：同 seed 两次 roll 结果一致", _test_roll_deterministic)
	_suite("互斥组：200 个 seed 采样，同组变体一局最多一个", _test_group_exclusive)
	_suite("因子连乘：多组同时生效时各组独立连乘", _test_factor_multiply)
	_suite("空数据安全：缺表/空数组/坏条目退化为无变体", _test_empty_safe)
	_suite("数据契约：run_modifiers.json 字段齐全且 id 唯一", _test_data_contract)
	_suite("源码结构：theme 先 clone 再乘 density（防共享污染）", _test_source_clone)


# ─────────────── ① 确定性 ───────────────

func _test_roll_deterministic() -> void:
	var defs := _load_defs()
	_check(defs.size() == 4, "数据表应加载出 4 个变体，实际 %d" % defs.size())
	var a := RunModifiers.roll(SimRng.new(12345), defs, 1, 2)
	var b := RunModifiers.roll(SimRng.new(12345), defs, 1, 2)
	_check_eq(a.summary(), b.summary(), "同 seed 两次 roll 的变体摘要必须一致")
	var c := RunModifiers.roll(SimRng.new(999), defs, 1, 2)
	_check(a.summary() != "" , "至少 roll 出 1 个变体（count_min=1）")
	# 不同 seed 大概率不同（不强制 —— 概率断言会 flaky，只记录）
	if a.summary() == c.summary():
		print("[s27] 备注：两个 seed 恰好 roll 出同一组变体（小概率事件，非 bug）")


# ─────────────── ② 互斥组 ───────────────

func _test_group_exclusive() -> void:
	var defs := _load_defs()
	for i in range(200):
		var r := SimRng.new(1000 + i * 7919)
		var mods := RunModifiers.roll(r, defs, 1, 2)
		var groups: Array[String] = []
		for m in mods.active:
			groups.append(m.group)
		_check_eq(groups.size(), _unique_count(groups),
			"seed %d：同组变体出现了多次 %s" % [1000 + i * 7919, str(groups)])
		_check(mods.active.size() <= 2, "最多 2 个变体（count_max=2）")


# ─────────────── ③ 因子连乘 ───────────────

func _test_factor_multiply() -> void:
	# 手工构造两组各一个变体，验证连乘与跨组独立
	var defs: Array = [
		{"id": "a", "name": "甲", "group": "g1", "enemy_density_mul": 1.5, "loot_rolls_mul": 2.0},
		{"id": "b", "name": "乙", "group": "g2", "enemy_density_mul": 1.2, "loot_rolls_mul": 0.5},
	]
	var mods := RunModifiers.new()
	mods.active.append(RunModifiers.ModifierInstance.from_dict(defs[0]))
	mods.active.append(RunModifiers.ModifierInstance.from_dict(defs[1]))
	_check_eq(mods.enemy_density_mul(), 1.5 * 1.2, "敌人数因子应连乘 1.5×1.2")
	_check_eq(mods.loot_rolls_mul(), 2.0 * 0.5, "容器因子应连乘 2.0×0.5（不串组）")
	_check_eq(mods.summary(), "甲 · 乙", "摘要按 id 排序稳定输出")
	# 无变体 = 恒等因子（调用方零分支）
	var none := RunModifiers.new()
	_check(none.is_empty(), "空集合 is_empty()")
	_check_eq(none.enemy_density_mul(), 1.0, "无变体时敌人数因子为 1.0")
	_check_eq(none.loot_rolls_mul(), 1.0, "无变体时容器因子为 1.0")
	_check_eq(none.summary(), "", "无变体时摘要为空串")


# ─────────────── ④ 空数据安全 ───────────────

func _test_empty_safe() -> void:
	var from_null := RunModifiers.roll(null, [], 1, 2)
	_check(from_null.is_empty(), "rng 为 null 时安全返回空集合")
	var from_empty := RunModifiers.roll(SimRng.new(1), [], 1, 2)
	_check(from_empty.is_empty(), "空数据表安全返回空集合")
	# 坏条目（缺 id / 缺 group）必须被跳过，不炸
	var bad: Array = [
		{"name": "无 id", "group": "g"},
		{"id": "no_group", "name": "无组"},
		"我不是对象",
	]
	var mods := RunModifiers.roll(SimRng.new(42), bad, 1, 2)
	_check(mods.is_empty(), "全部条目坏 -> 空集合，不崩")
	# count_max 超过可用组数时应夹紧，不重复抽同组
	var one_group: Array = [{"id": "only", "name": "唯一", "group": "solo"}]
	var one := RunModifiers.roll(SimRng.new(7), one_group, 1, 3)
	_check_eq(one.active.size(), 1, "只有 1 组时最多抽 1 个（夹紧，不重复）")


# ─────────────── ⑤ 数据契约 ───────────────

func _test_data_contract() -> void:
	var defs := _load_defs()
	_check_eq(defs.size(), 4, "Phase 1 固定 4 个变体")
	var seen: Array[String] = []
	var groups: Array[String] = []
	for d in defs:
		var mid: String = str(d.get("id", ""))
		var g: String = str(d.get("group", ""))
		var nm: String = str(d.get("name", ""))
		_check(mid != "", "每条必须有 id")
		_check(g != "", "%s 必须有 group" % mid)
		_check(nm != "", "%s 必须有中文名（HUD 直接显示）" % mid)
		_check(float(d.get("enemy_density_mul", 1.0)) > 0.0, "%s 敌人数倍率 > 0" % mid)
		_check(float(d.get("loot_rolls_mul", 1.0)) > 0.0, "%s 容器倍率 > 0" % mid)
		_check(not seen.has(mid), "id 唯一：%s" % mid)
		seen.append(mid)
		if not groups.has(g):
			groups.append(g)
	_check_eq(groups.size(), 2, "Phase 1 两个互斥组（enemy / loot）")


# ─────────────── ⑥ 源码结构：防共享污染回归 ───────────────

func _test_source_clone() -> void:
	var src := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(src.find("theme = theme.clone()") >= 0,
		"raid_scene 必须对 theme clone() 后再乘 density —— reg.get_map() 是共享实例，" +
		"直接乘 enemy_density 会污染全局 registry（后续每局累积倍率）")
	_check(src.find("RunModifiers.roll(_rng, reg.run_modifiers, 1, 2)") >= 0,
		"raid_scene 应按 seed 驱动的 _rng roll 变体（T-32 可复现）")
	var hud := FileAccess.get_file_as_string("res://view/raid_hud.gd")
	_check(hud.find("本局变体") >= 0, "HUD 应显示本局变体行")


# ─────────────── 辅助 ───────────────

func _load_defs() -> Array:
	var reg := DataRegistry.new()
	var ok := reg.load_all("C")
	if not ok:
		print("[s27] load_all 报错：%s" % str(reg.errors))
	return reg.run_modifiers


func _unique_count(arr: Array) -> int:
	var seen: Array = []
	for v in arr:
		if not seen.has(v):
			seen.append(v)
	return seen.size()
