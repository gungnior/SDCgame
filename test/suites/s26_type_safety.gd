extends TestSuite

## sim/view 边界类型安全（2026-10-16 · WorkBuddy）
##
## 背景：`progress-report.md` 技术债第 2 条的残存部分 —— `enemy_agent` 用 Variant
## 鸭子类型消费 `ctx.get("lane_shots")`（`LaneShotManager` 明明有 class_name），
## 方法名拼错要到运行时、以"敌人不开火"这种难查的形式才暴露。
##
## 本轮改动（`sim/ai/enemy_agent.gd`，行为不变，只收类型）：
##   ① 两处 lane_shots 改 `as LaneShotManager` 强类型 —— `as` 失败得 null，
##      自然落进既有兼容路径（缺失/错类型都与改造前一致）；
##   ② prof 四处散落的 `if prof != null` 收口成 `_mark_prof()`，
##      加 `is Object + has_method("mark")` 两层防护。
##
## 本套件钉死四件事：强类型后三条路径（正常/缺失/错类型）行为不变、
## 正确的鸭子探针仍照常打点（防护没有误伤）、prof 传错对象不炸 tick、
## 源码结构防回流。


func register() -> void:
	_suite("lane_shots 强类型：正常路径照常出弹道", _test_lane_shot_typed_ok)
	_suite("lane_shots 强类型：缺失走兼容路径", _test_lane_shot_missing_fallback)
	_suite("lane_shots 强类型：错类型不崩且降级", _test_lane_shot_wrong_type)
	_suite("prof 防护：错对象不炸 / 对的对象照常打点", _test_prof_guard)
	_suite("源码结构（防回流）", _test_source_guards)


## 造一个待机中的拾荒者（反应/冷却清零，targets 里放一个 10 格外的玩家）。
func _make_agent() -> EnemyAgent:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var scav: EnemyDef = reg.get_enemy("enemy_scav")
	var e := EnemyAgent.new(0, scav, Vector2(2.5, 3.5))
	e.equip(reg.get_weapon("weapon_pistol"), 60)
	e.facing = Vector2.RIGHT
	e.reaction_timer = 0.0
	e.attack_cooldown = 0.0
	return e


func _ctx_with(grid: LogicalGrid, flows: FlowFieldManager, rng: SimRng) -> Dictionary:
	return {"grid": grid, "flows": flows,
		"targets": [{"id": "player", "pos": Vector2(12.5, 3.5), "hp": 100}],
		"rng": rng, "now": 0.0, "noises": []}


func _test_lane_shot_typed_ok() -> void:
	var g := _open_grid(16, 10)
	var flows := FlowFieldManager.new()
	flows.setup(g)
	var e := _make_agent()
	var mgr := LaneShotManager.new()
	var ctx := _ctx_with(g, flows, SimRng.new(20261016))
	ctx["lane_shots"] = mgr
	for _i in 240:
		e.tick(0.05, ctx)
	_check(mgr.count() > 0, "强类型后弹道照常生成（as 转换没把正常路径弄坏）")
	_check_eq(e.shots_fired > 0, true, "敌人确实开火了")


func _test_lane_shot_missing_fallback() -> void:
	var g := _open_grid(16, 10)
	var flows := FlowFieldManager.new()
	flows.setup(g)
	var e := _make_agent()
	var ctx := _ctx_with(g, flows, SimRng.new(20261016))
	# 注意：不带 "lane_shots" 键
	for _i in 120:
		e.tick(0.05, ctx)
	_check(e.shots_fired > 0, "没有管理器也照常开火（兼容路径保留）")
	var targets: Array = ctx["targets"]
	var tgt: Dictionary = targets[0]
	_check_eq(int(tgt["hp"]) < 100, true, "兼容路径造成即时伤害（hp 下降）")


func _test_lane_shot_wrong_type() -> void:
	var g := _open_grid(16, 10)
	var flows := FlowFieldManager.new()
	flows.setup(g)
	var e := _make_agent()
	var ctx := _ctx_with(g, flows, SimRng.new(20261016))
	# 给错类型：一个没有 can_spawn/spawn 的普通 RefCounted。
	# 改造前（鸭子类型）会在 can_spawn() 上运行时错误；现在 as 失败得 null，
	# 与"缺失"同等对待 —— 降级而不是炸掉。
	ctx["lane_shots"] = RefCounted.new()
	for _i in 120:
		e.tick(0.05, ctx)
	_check(e.shots_fired > 0, "错类型的 lane_shots 不炸 tick，降级到兼容路径")


## 文件内小类：一个"正确的"鸭子探针（有 mark 方法）。
class FakeProbe:
	extends RefCounted
	var marks: Array[String] = []

	func mark(phase: String) -> void:
		marks.append(phase)


func _test_prof_guard() -> void:
	var g := _open_grid(16, 10)
	var flows := FlowFieldManager.new()
	flows.setup(g)
	var e := _make_agent()
	var ctx := _ctx_with(g, flows, SimRng.new(20261016))

	# ① 错对象：没有 mark 方法的 RefCounted —— 不得炸 tick
	ctx["prof"] = RefCounted.new()
	for _i in 60:
		e.tick(0.05, ctx)
	_check(true, "prof 是没有 mark 方法的对象时不炸（能跑到这里即证明）")

	# ② 对的对象：鸭子探针照常被打点（防护没有误伤正常路径）
	var e2 := _make_agent()
	var probe := FakeProbe.new()
	var ctx2 := _ctx_with(g, flows, SimRng.new(20261016))
	ctx2["prof"] = probe
	for _i in 60:
		e2.tick(0.05, ctx2)
	_check(probe.marks.size() > 0, "正确的鸭子探针仍被打点（marks=%d）" % probe.marks.size())
	_check(probe.marks.has("ai_see"), "感知阶段标记在（ai_see）")


func _test_source_guards() -> void:
	var ea := FileAccess.get_file_as_string("res://sim/ai/enemy_agent.gd")
	_check(ea.contains("as LaneShotManager"), "lane_shots 强类型消费（不许回到裸 Variant）")
	_check(ea.contains("var throttle := ctx.get(\"lane_shots\") as LaneShotManager"),
		"节流查询同样强类型")
	_check(ea.contains("var mgr := ctx.get(\"lane_shots\") as LaneShotManager"),
		"弹道生成同样强类型")
	_check(not ea.contains("var mgr: Variant = ctx.get(\"lane_shots\")"),
		"旧的裸 Variant 接法已移除")
	_check(ea.contains("func _mark_prof"), "prof 打点收口成单函数")
	_check(ea.contains("has_method(\"mark\")"), "prof 有 has_method 防护（不再裸调 mark）")
