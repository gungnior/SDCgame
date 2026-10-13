extends TestSuite

## 自动作战 / 固定弹道 / 闪避（2026-10-13 用户需求）
##
## 用户规格原文：
##   「玩家的攻击方式改为自动锁定敌人进行攻击；玩家角色在地图里自动寻路；
##     遇到物品容器会自动搜索、拾取其中的物品；遇见敌人会自动攻击。
##     敌人的攻击为固定弹道，宽度为两倍人物判定身位，会固定锁定人物为中心，
##     即人物两侧的弹道均为 1 格人物身位。角色可以进行闪避操作，
##     闪避的距离为 1.5 倍人物身位。」
##
## 本套件把那几条逐条钉死：身位换算、弹道几何、延后结算、
## 自动决策（交战/搜刮）、闪避位移，以及「代码不许回流」的接线断言。


func register() -> void:
	_suite("身位换算 BodyMetrics", _test_body_metrics)
	_suite("固定弹道 LaneShot", _test_lane_shot_geometry)
	_suite("弹道管理器 LaneShotManager", _test_lane_shot_manager)
	_suite("敌人开火 -> 固定弹道", _test_enemy_lane_fire)
	_suite("自动作战 PlayerAutopilot", _test_autopilot)
	_suite("闪避 DodgeState", _test_dodge)
	_suite("接线（防回流）", _test_wiring)
	_suite("开火前预警 Telegraph", _test_telegraph)


## 造一条弹道：起点 / 方向 / 弹速 / 伤害。半宽与长度用默认值（长度给足）。
func _lane(origin: Vector2, dir: Vector2, speed: float, damage: int) -> LaneShot:
	var s := LaneShot.new()
	s.origin = origin
	s.dir = dir.normalized()
	s.speed = speed
	s.damage = damage
	s.length = 40.0
	return s


# ─────────────────── ① 身位换算 ───────────────────

func _test_body_metrics() -> void:
	# 「人物判定身位」= 判定体的宽度（直径）。这是全局唯一换算来源。
	_check_eq(BodyMetrics.HIT_RADIUS, AimAssist.DEFAULT_HIT_RADIUS,
		"判定半径与瞄准辅助同源（%.2f 格）" % BodyMetrics.HIT_RADIUS)
	_check(absf(BodyMetrics.BODY_WIDTH - 0.9) < 0.0001,
		"1 个身位 = 0.9 逻辑格（实测 %.3f）" % BodyMetrics.BODY_WIDTH)
	# 用户原文：「宽度为两倍人物判定身位」「人物两侧的弹道均为 1 格人物身位」
	_check(absf(BodyMetrics.LANE_HALF_WIDTH - BodyMetrics.BODY_WIDTH) < 0.0001,
		"弹道半宽 = 1 身位 —— 人物两侧各 1 身位")
	_check(absf(BodyMetrics.LANE_WIDTH - BodyMetrics.BODY_WIDTH * 2.0) < 0.0001,
		"弹道总宽 = 2 倍人物判定身位（%.3f 格）" % BodyMetrics.LANE_WIDTH)
	# 用户原文：「闪避的距离为 1.5 倍人物身位」
	_check(absf(BodyMetrics.DODGE_DISTANCE - BodyMetrics.BODY_WIDTH * 1.5) < 0.0001,
		"闪避位移 = 1.5 倍身位（%.3f 格）" % BodyMetrics.DODGE_DISTANCE)
	_check(BodyMetrics.dodge_clears_lane(),
		"闪避位移 > 脱离弹道所需距离 —— 否则「闪避躲弹道」在数学上不成立")


# ─────────────────── ② 弹道几何 ───────────────────

func _test_lane_shot_geometry() -> void:
	# ① 站在弹道外（垂距 > 半宽）：打不到 —— 这是"看几何"而不是"看运气"
	var s := _lane(Vector2(2.5, 2.5), Vector2.RIGHT, 10.0, 12)
	var outside := s.advance(0.5, Vector2(4.5, 2.5 + BodyMetrics.LANE_HALF_WIDTH + 0.05))
	_check(not bool(outside["hit"]), "站在弹道外 -> 打不到")

	# ② 站在弹道里：前沿扫过的那一刻命中
	var s2 := _lane(Vector2(2.5, 2.5), Vector2.RIGHT, 10.0, 12)
	var hit := s2.advance(0.2, Vector2(4.5, 2.5))      # 前沿 0 -> 2.0，玩家 t=2.0
	_check(bool(hit["hit"]), "站在弹道里 -> 前沿扫过即命中")
	_check_eq(s2.damage, 12, "伤害随弹道携带（延后结算）")

	# ③ 固定弹道：不会因为目标横向移动而追踪
	var s3 := _lane(Vector2(2.5, 2.5), Vector2.RIGHT, 10.0, 12)
	var dir0 := s3.dir
	s3.advance(0.1, Vector2(6.5, 6.5))
	_check(s3.dir == dir0, "方向在开火瞬间锁死（固定弹道，不追踪）")

	# ④ 子弹飞过之后再站回线上 -> 不算命中（"走过弹道"能骗过判定）
	var s4 := _lane(Vector2(2.5, 2.5), Vector2.RIGHT, 10.0, 12)
	s4.advance(0.5, Vector2(4.5, 5.5))
	_check(not s4.hit_player, "这一帧玩家不在弹道里 -> 没中")
	var late := s4.advance(0.1, Vector2(4.5, 2.5))
	_check(not bool(late["hit"]), "前沿已经越过 -> 站回线上也不算命中")

	# ⑤ 一条弹道只结算一次
	var s5 := _lane(Vector2(2.5, 2.5), Vector2.RIGHT, 10.0, 12)
	s5.advance(0.2, Vector2(4.5, 2.5))
	var again := s5.advance(0.4, Vector2(6.5, 2.5))
	_check(not bool(again["hit"]), "同一条弹道不会重复结算")

	# ⑥ 飞完即结束（表现层据此收掉这条弹道）
	var s6 := LaneShot.new()
	s6.origin = Vector2.ZERO
	s6.dir = Vector2.RIGHT
	s6.speed = 10.0
	s6.length = 3.0
	var fin := s6.advance(0.5, Vector2(50.5, 50.5))
	_check(bool(fin["finished"]), "到达 length -> 弹道结束")
	_check(s6.done, "结束标记已置位")


# ─────────────────── ③ 弹道管理器 ───────────────────

func _test_lane_shot_manager() -> void:
	var mgr := LaneShotManager.new()
	mgr.spawn(Vector2(1.5, 1.5), Vector2.RIGHT, 10.0, 9, 6.0, 7, "weapon_pistol")
	_check_eq(mgr.count(), 1, "弹道被登记")
	_check_eq(mgr.shots[0].half_width, BodyMetrics.LANE_HALF_WIDTH, "半宽默认取 1 身位")

	mgr.tick(0.1, Vector2(30.5, 30.5))                 # 玩家在很远 -> 不中
	_check_eq(mgr.consume_damage(), 0, "没命中就不该有待结算伤害")
	mgr.tick(0.2, Vector2(3.5, 1.5))                  # 前沿 1.0 -> 3.0，玩家 t=2.0
	_check_eq(mgr.pending_damage, 9, "命中后伤害进入待结算队列")
	_check_eq(mgr.consume_damage(), 9, "consume_damage 取走伤害")
	_check_eq(mgr.pending_damage, 0, "取走后清零（不会重复扣）")
	for _i in 40:
		mgr.tick(0.05, Vector2(30.5, 30.5))
	_check_eq(mgr.count(), 0, "飞完的弹道会被移除（不会无限堆积）")

	# 预警：自动闪避据此决定「现在该不该滚」
	var mgr2 := LaneShotManager.new()
	mgr2.spawn(Vector2(1.5, 1.5), Vector2.RIGHT, 10.0, 5, 20.0, 0, "w")
	_check(mgr2.incoming(Vector2(5.5, 1.5), 0.5) != null,
		"弹道即将命中 -> 给出预警（自动闪避用）")
	_check(mgr2.incoming(Vector2(5.5, 3.5), 0.5) == null,
		"站在弹道外 -> 不预警（不需要躲）")
	_check(mgr2.incoming(Vector2(5.5, 1.5), 0.01) == null,
		"来不及躲（eta 超出提前量）-> 不预警")


# ─────────────────── ④ 敌人开火 ───────────────────

func _test_enemy_lane_fire() -> void:
	var g := _open_grid(16, 10)
	var flows := FlowFieldManager.new()
	flows.setup(g)
	var reg := DataRegistry.new()
	reg.load_all("B")
	var scav: EnemyDef = reg.get_enemy("enemy_scav")
	var rng := SimRng.new(20261013)

	var e := EnemyAgent.new(0, scav, Vector2(2.5, 3.5))
	e.equip(reg.get_weapon("weapon_pistol"), 60)
	e.facing = Vector2.RIGHT
	var targets := [{"id": "player", "pos": Vector2(12.5, 3.5), "hp": 100}]
	var mgr := LaneShotManager.new()
	var ctx := {"grid": g, "flows": flows, "targets": targets, "rng": rng,
		"now": 0.0, "noises": [], "lane_shots": mgr}

	var first: LaneShot = null
	for _i in 240:
		e.tick(0.05, ctx)
		if first == null and mgr.count() > 0:
			first = mgr.shots[0]
	_check(e.shots_fired > 0, "有弹道管理器时照常开火（%d 发）" % e.shots_fired)
	_check_eq(int(targets[0]["hp"]), 100,
		"开火当帧不扣血 —— 伤害延后到弹道命中（这是「可以躲开」的前提）")
	_check(first != null, "弹道交给了 LaneShotManager")
	if first != null:
		_check(absf(first.half_width - BodyMetrics.LANE_HALF_WIDTH) < 0.0001,
			"弹道半宽 = 1 倍人物身位")
		_check(first.length > 0.0, "弹道长度由射程与墙决定（%.2f 格）" % first.length)
		_check(first.speed > 0.0, "弹速为正（飞行时间 = 闪避窗口）")

	# ── 兼容路径：没有管理器时保持改造前的即时结算（单测/工具用）──
	var e2 := EnemyAgent.new(1, scav, Vector2(2.5, 3.5))
	e2.equip(reg.get_weapon("weapon_pistol"), 60)
	e2.facing = Vector2.RIGHT
	var t2 := [{"id": "player", "pos": Vector2(12.5, 3.5), "hp": 100}]
	var ctx2 := {"grid": g, "flows": flows, "targets": t2, "rng": SimRng.new(7),
		"now": 0.0, "noises": []}
	for _i in 240:
		e2.tick(0.05, ctx2)
	_check(e2.shots_fired > 0, "没有管理器也照常开火（%d 发）" % e2.shots_fired)


# ─────────────────── ⑤ 自动作战 ───────────────────

func _test_autopilot() -> void:
	var g := _open_grid(16, 10)
	var flows := FlowFieldManager.new()
	flows.setup(g)
	var ap := PlayerAutopilot.new()

	# ① 看得见敌人 -> 交战，并给出方向
	var ctx := {"grid": g, "flows": flows, "player_pos": Vector2(2.5, 3.5),
		"enemies": [{"pos": Vector2(12.5, 3.5), "alive": true}],
		"containers": [], "corpses": [], "now": 0.0}
	var d := ap.update(0.05, ctx)
	_check_eq(str(d["mode"]), "COMBAT", "看见敌人 -> 交战模式")
	_check(bool(d["has_target"]), "给出锁定目标（交给 AutoAim）")
	_check((d["move"] as Vector2).x > 0.5, "朝敌人移动（dx=%.2f）" % (d["move"] as Vector2).x)

	# ② 没有敌人、有没搜完的容器 -> 去搜刮
	var ctx2 := {"grid": g, "flows": flows, "player_pos": Vector2(2.5, 3.5),
		"enemies": [], "containers": [{"pos": Vector2(12.5, 3.5), "done": false}],
		"corpses": [], "now": 0.1}
	var d2 := ap.update(0.05, ctx2)
	_check_eq(str(d2["mode"]), "LOOT", "没有敌人但有容器 -> 搜刮模式")
	_check((d2["move"] as Vector2).x > 0.5, "朝容器移动")

	# ③ 走到容器旁边 -> 输出搜刮请求（由场景执行，不打开面板）
	var ctx3 := {"grid": g, "flows": flows, "player_pos": Vector2(12.2, 3.5),
		"enemies": [], "containers": [{"pos": Vector2(12.5, 3.5), "done": false}],
		"corpses": [], "now": 0.2}
	var d3 := ap.update(0.05, ctx3)
	_check(not (d3["loot"] as Dictionary).is_empty(), "到点 -> 输出搜刮请求")
	_check_eq(int((d3["loot"] as Dictionary)["index"]), 0, "请求的是 0 号容器")

	# ④ 容器都搜完了 -> 待机（不去乱走）
	var ctx4 := {"grid": g, "flows": flows, "player_pos": Vector2(12.2, 3.5),
		"enemies": [], "containers": [{"pos": Vector2(12.5, 3.5), "done": true}],
		"corpses": [], "now": 0.3}
	var d4 := ap.update(0.05, ctx4)
	_check_eq(str(d4["mode"]), "IDLE", "没有可搜目标 -> 待机")
	_check((d4["move"] as Vector2) == Vector2.ZERO, "待机时不乱走")

	# ⑤ 到不了的目标会被拉黑，不会把自动作战钉死在死角
	var ap2 := PlayerAutopilot.new()
	ap2.blacklist("container", 3)
	_check(ap2.is_blacklisted("container", 3), "拉黑生效")
	_check(not ap2.is_blacklisted("container", 4), "只拉黑指定目标")


# ─────────────────── ⑥ 闪避 ───────────────────

func _test_dodge() -> void:
	var d := DodgeState.new()
	_check(d.can_start(), "初始可闪避")
	_check(not d.is_invulnerable(), "初始没有无敌帧")
	_check(d.start(Vector2.RIGHT), "闪避触发成功")
	_check(d.is_active(), "进入闪避状态")
	_check(d.is_invulnerable(), "闪避期间有无敌帧（走廊里唯一可行的躲法）")

	var total := Vector2.ZERO
	var guard := 0
	while d.is_active() and guard < 600:
		guard += 1
		total += d.step(1.0 / 60.0)
		d.tick(1.0 / 60.0)
	_check(absf(total.length() - BodyMetrics.DODGE_DISTANCE) < 0.001,
		"累计位移 = 1.5 倍身位（%.3f 格）" % total.length())
	_check(not d.can_start(), "冷却期内不能连按（闪避是决策，不是连滚）")
	for _i in 60:
		d.tick(1.0 / 60.0)
	_check(d.can_start(), "冷却结束 -> 可以再次闪避")

	var d2 := DodgeState.new()
	_check(d2.start(Vector2.ZERO), "零方向也能触发（不崩）")
	_check(d2.dir == Vector2.RIGHT, "零方向 -> 退化为朝右")
	d2.note_blocked(9)
	_check_eq(d2.blocked_damage, 9, "被无敌帧挡下的伤害被记账")


# ─────────────────── ⑦ 接线（防回流）───────────────────

func _test_wiring() -> void:
	# 行为存在 -> 查整个视图层（代码在层内搬运不会误报）
	var vsrc := _view_src()
	_check(vsrc.contains("_apply_player_step"),
		"常规移动与闪避共用同一个位移函数（闪避因此不会穿墙）")
	_check(vsrc.contains("scene.lane_shots"), "视图层接了固定弹道")
	_check(vsrc.contains("func _try_dodge"), "有闪避入口")

	# 结构关系 -> 查具体文件（防回流）
	var ea := FileAccess.get_file_as_string("res://sim/ai/enemy_agent.gd")
	_check(ea.contains("lane_shots"), "敌人开火走固定弹道（不再开火即扣血）")
	var aa := FileAccess.get_file_as_string("res://sim/combat/auto_aim.gd")
	_check(aa.contains("omni"), "锁定支持全向扫描（自动作战用）")
	var gs := FileAccess.get_file_as_string("res://game/game_state.gd")
	_check(gs.contains("var autopilot"), "Game 有 autopilot 设置项（跨场景持久）")
	_check(gs.contains("\"autopilot\""), "autopilot 进存档")
	var bm := FileAccess.get_file_as_string("res://sim/combat/body_metrics.gd")
	_check(bm.contains("DODGE_DISTANCE") and bm.contains("LANE_HALF_WIDTH"),
		"身位换算集中在 BodyMetrics（不许各处写死 0.9）")
	var tc := FileAccess.get_file_as_string("res://ui/touch_controls.gd")
	_check(tc.contains("dodge_pressed"), "触屏有闪避按钮（移动端要能按到）")
	_check(tc.contains("CROSS_ARM_RATIO") and tc.contains("CROSS_MARGIN_RATIO"),
		"右半屏是十字键位（2026-10-13 UI 重做）")
	var ri := FileAccess.get_file_as_string("res://view/raid_input.gd")
	_check(ri.contains("KEY_SHIFT"), "键盘有闪避键位（Shift）")


# ─────────────────── ⑧ 开火前预警（A 方案，2026-10-13）───────────────────

func _test_telegraph() -> void:
	# 用户需求：A「开火前预警（0.12~0.18s 瞄准线）」，解决贴脸必中。
	# 规则：warn = clamp(MIN_REACTION_SEC - 飞行时间, WARN_MIN, WARN_MAX)。
	var w_close := LaneShot.warn_for(3.0)
	var w_mid := LaneShot.warn_for(6.0)
	var w_far := LaneShot.warn_for(20.0)
	_check(w_close >= LaneShot.WARN_MIN and w_close <= LaneShot.WARN_MAX,
		"近距离预警落在 [%.2f, %.2f] 内（3 格）" % [LaneShot.WARN_MIN, LaneShot.WARN_MAX])
	_check(w_close > w_far, "越近预警越长 —— 公平性由公式保证，不靠手调")
	_check(absf(w_far - LaneShot.WARN_MIN) < 0.0001, "远处贴到下限")
	_check(w_mid > 0.0, "中距离也有预警")
	var flight3 := 3.0 / LaneShot.DEFAULT_SPEED
	_check(w_close + flight3 >= LaneShot.MIN_REACTION_SEC - 0.0001,
		"3 格：预警 + 飞行 >= 最低总反应时间 %.2f" % LaneShot.MIN_REACTION_SEC)

	# 预警期间：弹道不动、不做命中判定
	var s := _lane(Vector2(2.5, 2.5), Vector2.RIGHT, 10.0, 9)
	s.warn_sec = 0.15
	s.warn_left = 0.15
	_check(s.is_warning(), "开火瞬间处于预警状态")
	var during := s.advance(0.10, Vector2(3.5, 2.5))
	_check(not bool(during["hit"]), "预警期间站在弹道上也不判定")
	_check_eq(s.traveled, 0.0, "预警期间弹道不动")
	_check(s.is_warning(), "0.10 秒后仍在预警")
	# 预警余 0.05 在本帧耗尽，余下 0.25 秒继续飞行 = 2.5 格（不浪费一帧）
	var after := s.advance(0.30, Vector2(6.5, 2.5))
	_check(not s.is_warning(), "预警结束 -> 进入飞行")
	_check(s.traveled > 0.0, "预警走完的那一帧就开始飞（余量不浪费）")
	_check(not bool(after["hit"]), "还没扫到玩家 -> 未命中")
	var hit := s.advance(0.20, Vector2(6.5, 2.5))
	_check(bool(hit["hit"]), "前沿扫过玩家 -> 命中")

	# 自动闪避必须把预警算进 eta，否则会晚按一步
	var m := LaneShotManager.new()
	m.spawn(Vector2(1.5, 1.5), Vector2.RIGHT, 10.0, 5, 20.0, 0, "w", 0.15)
	var shot: LaneShot = m.shots[0]
	_check(shot.is_warning(), "管理器登记时带上了预警")
	var eta := shot.total_eta(Vector2(5.5, 1.5))
	_check(eta > 0.15, "eta 含预警")
	_check(m.incoming(Vector2(5.5, 1.5), 0.60) != null, "预警中的弹道同样算即将命中")

	# 接线守卫
	var ea := FileAccess.get_file_as_string("res://sim/ai/enemy_agent.gd")
	_check(ea.contains("warn_for"), "敌人开火时按距离算预警")
	_check(_view_src().contains("is_warning"), "绘制区分预警与飞行两态")
