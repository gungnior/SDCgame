extends SceneTree

## feel_probe.gd —— 「手感」实测（headless，走**真实代码路径**）
##
## 为什么要有它：
##   手感最终要在真机上定，但「预警够不够、飞行多久、侧闪躲不躲得开」这些
##   **是几何与计时的确定性问题**，可以在 PC 上用真实代码量出来。
##   本探针不模拟、不近似：它直接调 EnemyAgent → LaneShotManager → LaneShot，
##   读到的时间就是游戏里的时间。
##
## 运行：
##   godot --headless --path . --script res://test/feel_probe.gd
## 退出码恒为 0（测量工具，不是门槛）。

const DT := 1.0 / 60.0
const RANGES := [3.0, 4.0, 6.0, 8.0, 12.0]

var _reg: DataRegistry = null
var _scav: EnemyDef = null


func _initialize() -> void:
	_reg = DataRegistry.new()
	_reg.load_all("B")
	_scav = _reg.get_enemy("enemy_scav")

	print("")
	print("=== 手感实测：走真实代码路径（EnemyAgent -> LaneShotManager -> LaneShot）===")
	print("弹速 %.1f 格/秒 | 弹道半宽 %.2f 格（总宽 %.2f = 2 身位）| 闪避 %.2f 格 / %.2f 秒 | 无敌 %.2f 秒" % [
		LaneShot.DEFAULT_SPEED, BodyMetrics.LANE_HALF_WIDTH, BodyMetrics.LANE_WIDTH,
		BodyMetrics.DODGE_DISTANCE, DodgeState.DURATION, DodgeState.INVULN_SEC])
	print("预警公式：warn = clamp(%.2f - 飞行时间, %.2f, %.2f)" % [
		LaneShot.MIN_REACTION_SEC, LaneShot.WARN_MIN, LaneShot.WARN_MAX])
	print("")
	print("预定距离 | 实际距离 | 预警(s) | 飞行(s) | 总反应(s) | 站着不动     | 预警一结束就侧闪")
	print("---------|----------|---------|---------|-----------|--------------|----------------")
	for d in RANGES:
		_run_case(d)
	print("")
	print("=== 贴脸专测：直接放一条弹道（距离精确，排除 AI 走位干扰）===")
	print("距离(格) | 预警(s) | 飞行(s) | 总反应(s) | 站着不动   | 侧闪(不给无敌帧) | 无敌帧是否也在窗口")
	print("---------|---------|---------|-----------|------------|------------------|-------------------")
	for d in [2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 12.0]:
		_synth_case(d)
	print("")
	print("注：侧闪按「0.18 秒内横移 1.35 格（1.5 身位）」模拟真实闪避动作，且**不给无敌帧**——")
	print("    也就是说这是最坏情况；实战里还有 0.22 秒无敌帧兜底。")
	print("")
	quit(0)


func _run_case(intended: float) -> void:
	var g := LogicalGrid.new(64, 8)
	g.carve_rect(Rect2i(1, 1, 62, 6))
	var flows := FlowFieldManager.new()
	flows.setup(g)
	var rng := SimRng.new(20261013)
	var e := EnemyAgent.new(0, _scav, Vector2(2.5, 3.5))
	e.equip(_reg.get_weapon("weapon_pistol"), 60)
	e.facing = Vector2.RIGHT
	var px := 2.5 + intended
	var ppos := Vector2(px, 3.5)
	var targets := [{"id": "player", "pos": ppos, "hp": 1000000}]
	var mgr := LaneShotManager.new()
	var ctx := {
		"grid": g, "flows": flows, "targets": targets, "rng": rng,
		"now": 0.0, "noises": [], "lane_shots": mgr,
	}

	# 等敌人开出第一枪（最多 12 秒）
	var t := 0.0
	var shot: LaneShot = null
	for _i in 720:
		ctx["now"] = t
		e.tick(DT, ctx)
		t += DT
		if mgr.count() > 0:
			shot = mgr.shots[0]
			break
	if shot == null:
		print("%8.1f | 12 秒内没开火 —— 无法测量" % intended)
		return

	var origin := shot.origin
	var dir := shot.dir
	var speed := shot.speed
	var damage := shot.damage
	var length := shot.length
	var warn := shot.warn_sec
	var proj := shot.projection_distance(ppos)
	var flight := proj / maxf(speed, 0.01)

	# ── A：站着不动，量到命中 ──
	var m1 := LaneShotManager.new()
	m1.spawn(origin, dir, speed, damage, length, 0, "w", warn)
	var hit_at := -1.0
	var ta := 0.0
	while m1.count() > 0 and ta < 6.0:
		m1.tick(DT, ppos)
		ta += DT
		if hit_at < 0.0 and m1.pending_damage > 0:
			hit_at = ta
	var idle_txt := "未命中(异常)" if hit_at < 0.0 else "%.2f s 命中" % hit_at

	# ── B：预警一结束就侧闪（最坏情况：不给无敌帧）──
	var m2 := LaneShotManager.new()
	m2.spawn(origin, dir, speed, damage, length, 0, "w", warn)
	var side := Vector2(-dir.y, dir.x) * BodyMetrics.DODGE_DISTANCE
	var start := ppos
	var tb := 0.0
	var since := -1.0
	while m2.count() > 0 and tb < 6.0:
		if since < 0.0 and m2.shots[0].warn_left <= 0.0:
			since = 0.0
		elif since >= 0.0:
			since += DT
		if since >= 0.0:
			var k := clampf(since / DodgeState.DURATION, 0.0, 1.0)
			ppos = start + side * k
		m2.tick(DT, ppos)
		tb += DT
	var dodge_txt := "躲开了" if m2.pending_damage == 0 else "仍被命中"

	print("%8.1f | %8.2f | %7.3f | %7.3f | %9.3f | %-12s | %s" % [
		intended, proj, warn, flight, warn + flight, idle_txt, dodge_txt])


## 精确距离专测：直接放一条弹道，测「站着不动」与「预警一结束就侧闪」。
func _synth_case(d: float) -> void:
	var speed := LaneShot.DEFAULT_SPEED
	var warn := LaneShot.warn_for(d, speed)
	var origin := Vector2(2.5, 3.5)
	var dir := Vector2.RIGHT
	var ppos := origin + dir * d
	var length := d + 2.0
	var flight := d / speed

	# A：站着不动
	var m1 := LaneShotManager.new()
	m1.spawn(origin, dir, speed, 18, length, 0, "w", warn)
	var hit_at := -1.0
	var t := 0.0
	while m1.count() > 0 and t < 6.0:
		m1.tick(DT, ppos)
		t += DT
		if hit_at < 0.0 and m1.pending_damage > 0:
			hit_at = t
	var idle := "未中(异常)" if hit_at < 0.0 else "%.2f s 命中" % hit_at

	# B：预警一结束就侧闪（0.18 秒横移 1.5 身位，且不给无敌帧 = 最坏情况）
	var m2 := LaneShotManager.new()
	m2.spawn(origin, dir, speed, 18, length, 0, "w", warn)
	var side := Vector2(-dir.y, dir.x) * BodyMetrics.DODGE_DISTANCE
	var start := ppos
	var tb := 0.0
	var since := -1.0
	while m2.count() > 0 and tb < 6.0:
		if since < 0.0 and m2.shots[0].warn_left <= 0.0:
			since = 0.0
		elif since >= 0.0:
			since += DT
		if since >= 0.0:
			ppos = start + side * clampf(since / DodgeState.DURATION, 0.0, 1.0)
		m2.tick(DT, ppos)
		tb += DT
	var dodge := "躲开了" if m2.pending_damage == 0 else "仍被命中"
	var iframe := "是" if flight <= DodgeState.INVULN_SEC else "否（靠位移）"

	print("%8.1f | %7.3f | %7.3f | %9.3f | %-10s | %-16s | %s" % [
		d, warn, flight, warn + flight, idle, dodge, iframe])
