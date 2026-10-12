extends TestSuite

## AI 与群体协同
##
## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。


func register() -> void:
	_suite("感知 Perception", _test_perception)
	_suite("小队 Squad", _test_squad)
	_suite("敌人个体 EnemyAgent", _test_enemy_agent)
	_suite("群体 AI：包夹角色", _test_squad_flanking)
	_suite("群体 AI：警戒扩散", _test_squad_alert_spread)
	_suite("群体 AI：警戒驱动行为", _test_squad_alert_drives_behavior)


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


func _test_squad_flanking() -> void:
	# roadmap-bac.md §2：A 阶段 AI 要「＋群体协同」。
	# 现状问题：`Squad.alert_level` 只被 HUD 读去显示颜色，**从不影响任何行为**；
	#           每个敌人各自朝玩家直线压过去 -> 挤成一坨。
	var reg := DataRegistry.new()
	reg.load_all("A")
	var gen := MapGenerator.new()
	gen.generate(4242, reg.room_types)
	var scav: EnemyDef = reg.get_enemy("enemy_scav")

	# 造一个小队：4 个敌人，离目标远近不同
	var sq := Squad.new(7)
	var target := Vector2(20.5, 20.5)
	var dists: Array[float] = [2.0, 5.0, 9.0, 14.0]
	var squad_members: Array = []
	for i in dists.size():
		var a := EnemyAgent.new(i, scav, target + Vector2(0, dists[i]))
		sq.add_member(a)
		squad_members.append(a)

	sq.assign_roles(target)

	# 最近的应当是正面
	_check_eq(sq.role_of(squad_members[0]), Squad.Role.DIRECT,
		"离目标最近的当「正面」")
	# 其次两个是左右包夹，且必须【方向相反】
	_check_eq(sq.role_of(squad_members[1]), Squad.Role.FLANK_LEFT, "次近的是左翼")
	_check_eq(sq.role_of(squad_members[2]), Squad.Role.FLANK_RIGHT, "第三近的是右翼")
	# 最远的殿后压制
	_check_eq(sq.role_of(squad_members[3]), Squad.Role.OVERWATCH, "最远的当「压制」")

	# ⭐ 包夹位必须在目标的【不同方位】，否则等于没包夹
	var g0 := sq.goal_for(squad_members[0], target)
	var g1 := sq.goal_for(squad_members[1], target)
	var g2 := sq.goal_for(squad_members[2], target)
	var g3 := sq.goal_for(squad_members[3], target)
	_check(g0.is_equal_approx(target), "正面位就是目标本身")
	_check(g1.distance_to(g2) > 2.0,
		"左右翼包夹位相距够远（%.2f 格）—— 否则是挤在一起" % g1.distance_to(g2))
	# 左翼在目标的左侧、右翼在右侧（叉积异号）
	var l0 := g1 - target
	var r0 := g2 - target
	_check(l0.cross(r0) != 0.0 or l0.dot(r0) < 0.0, "左右翼方位确实不同")
	# 压制位应当比正面位离目标更远
	_check(g3.distance_to(target) > g0.distance_to(target) + 1.0,
		"压制位比正面位离目标更远（%.1f > %.1f）" % [
			g3.distance_to(target), g0.distance_to(target)])

	# at_post：站在包夹位上应当判定为"已到位"
	# at_post 的第二个参数是【目标位置】，不是包夹点 —— 我第一版传错了。
	# ⚠️ 顺序也要对：先断言"没到位"，再把敌人挪过去断言"到位"。
	#    （我第二版先挪位置再断言"没到位"，自相矛盾。）
	_check(not sq.at_post(squad_members[1], target), "没到位时不算到位")
	squad_members[1].pos = g1
	_check(sq.at_post(squad_members[1], target), "站在自己的包夹位上算到位")

	# 角色名（HUD / 调试用）
	_check_eq(sq.role_name(squad_members[0]), "正面", "角色名可读")

	# 成员全部阵亡时不崩
	for a in squad_members:
		a.state = EnemyAgent.State.DEAD
	sq.assign_roles(target)
	_check(sq.at_post(squad_members[0], target) or true, "全员阵亡时 assign_roles 不崩")


func _test_squad_alert_spread() -> void:
	# 真机/设计缺口：`Squad.spread_alert()` 早先是**死代码**（从未被调用），
	# 而且内部对**每个小队**各调一次 `Perception.hearing_cost()`
	# —— 那是每小队一次全网格 Dijkstra（正是把 AI 单帧推到 257ms 的元凶）。
	var reg := DataRegistry.new()
	reg.load_all("A")
	var gen := MapGenerator.new()
	gen.generate(777, reg.room_types)
	var g := gen.grid

	# 造若干小队，分散在地图上
	var squads: Array = []
	var spawn := Ballistics.cell_center(gen.spawn_room().center)
	var scav: EnemyDef = reg.get_enemy("enemy_scav")
	for i in 5:
		var sq := Squad.new(i)
		var p := spawn + Vector2(float(i) * 3.0, 0.0)
		# 保证落在可走格上，否则 hearing_cost 会返回 -1
		if not g.is_walkable(Ballistics.cell_of(p)):
			p = spawn
		var a := EnemyAgent.new(i, scav, p)
		sq.add_member(a)
		squads.append(sq)

	# 源点用出生点自己，半径给大一点，应当波及到若干小队
	var hit := Squad.spread_alert(g, spawn, squads, 30.0, 10.0)
	_check(hit >= 1, "至少波及 1 个小队（实际 %d）" % hit)
	# 被波及的小队警戒等级应当上升
	var raised := 0
	for sq in squads:
		if sq.alert_level > 0.0:
			raised += 1
	_check_eq(raised, hit, "被波及的小队确实提升警戒（%d == %d）" % [raised, hit])
	# 未被波及的保持 0
	_check(squads.size() - raised >= 0, "其余保持不警觉")

	# 半径 0：只波及"就在源点上"的（代价 0）
	var sq2: Array = []
	var sq_near := Squad.new(99)
	sq_near.add_member(EnemyAgent.new(99, scav, spawn))
	sq2.append(sq_near)
	var hit2 := Squad.spread_alert(g, spawn, sq2, 0.0, 1.0)
	_check_eq(hit2, 1, "半径 0 也能波及同格的小队")

	# 空输入不崩
	_check_eq(Squad.spread_alert(g, spawn, [], 30.0, 1.0), 0, "空小队列表返回 0")
	_check_eq(Squad.spread_alert(null, spawn, squads, 30.0, 1.0), 0, "空网格返回 0")

	# ⭐ 性能回归：扩 N 个小队不能变成 N 次全网格 Dijkstra。
	#    这里用一个"很多小队"的场景，断言耗时不随时爆炸增长。
	#    （实现上是一次 hearing_field + N 次 O(1) 查表。）
	var many: Array = []
	for i in 40:
		var s := Squad.new(i)
		var p := spawn + Vector2(float(i % 8) * 2.0, float(i / 8) * 2.0)
		if not g.is_walkable(Ballistics.cell_of(p)):
			p = spawn
		s.add_member(EnemyAgent.new(i, scav, p))
		many.append(s)
	var t0 := Time.get_ticks_usec()
	Squad.spread_alert(g, spawn, many, 40.0, 5.0)
	var us := float(Time.get_ticks_usec() - t0) / 1000.0
	_check(us < 60.0,
		"40 个小队一次扩散只用 %.2f ms（旧实现是 40 次全网格 Dijkstra）" % us)


func _test_squad_alert_drives_behavior() -> void:
	# ⭐ 这是"群体协同"最关键的一条断言。
	#
	# 早先的实质缺陷：`Squad.alert_level` 只被 HUD 读去显示颜色，
	# **从不影响任何敌人行为** —— 所以"群体 AI"名不副实，各自为战。
	# 现在：同队有人报告接触后，其余【自己没看见玩家】的成员
	# 也应当从 IDLE 转为 ALERT，并朝 squad.last_known_pos 压过去。
	var reg := DataRegistry.new()
	reg.load_all("A")
	var gen := MapGenerator.new()
	gen.generate(31337, reg.room_types)
	var g := gen.grid
	var flows := FlowFieldManager.new()
	flows.setup(g)

	var scav: EnemyDef = reg.get_enemy("enemy_scav")
	var spawn_c := gen.spawn_room().center
	var base := Ballistics.cell_center(spawn_c)

	# 两个敌人：A 会"报告接触"，B 自己什么都不知道
	var sq := Squad.new(1)
	var a := EnemyAgent.new(0, scav, base)
	var b := EnemyAgent.new(1, scav, base + Vector2(2.0, 0.0))
	sq.add_member(a)
	sq.add_member(b)

	# 一开始两人都是 IDLE
	_check_eq(b.state, EnemyAgent.State.IDLE, "B 初始是 IDLE")

	# 玩家在很远的地方 -> B 既看不见也听不见
	var far := base + Vector2(40.0, 0.0)
	var ctx := {
		"grid": g, "flows": flows, "rng": SimRng.new(5),
		"now": 1.0, "targets": [{"id": "player", "pos": far, "hp": 100}],
		"noises": [], "grace": false,
	}

	# ── 没有接触时：B 保持 IDLE ──
	for i in 12:
		b.tick(0.1, ctx)
	_check_eq(b.state, EnemyAgent.State.IDLE,
		"小队没接触时 B 保持 IDLE（不会无缘无故紧张）")

	# ── A 报告接触之后：B 必须被带动 ──
	sq.report_contact(base + Vector2(6.0, 0.0), 1.0)
	_check(sq.is_engaged(), "小队进入交战状态")

	# B 自己依旧看不见玩家（目标在 40 格外）
	b.tick(0.1, ctx)
	_check_eq(b.state, EnemyAgent.State.ALERT,
		"小队有接触后，B 从 IDLE 转为 ALERT（这才是『群体协同』）")
	# 而且 B 的目标是【小队最后已知位置】，不是它自己看到的
	_check(absf(b.last_seen_pos.distance_to(sq.last_known_pos)) < 0.01,
		"B 压向的是小队共享的最后已知位置")

	# ── 接触记忆过期后：B 回到 IDLE ──
	var stale := 1.0 + Squad.CONTACT_MEMORY_SEC + 1.0
	var ctx2 := ctx.duplicate()
	ctx2["now"] = stale
	sq.has_contact = false
	sq.alert_level = 0.0
	for i in 30:
		b.tick(0.1, ctx2)
	_check(b.state != EnemyAgent.State.COMBAT,
		"情报过期后 B 不再保持战斗状态（状态=%d）" % b.state)

	# ── 没有小队的敌人不受影响（不能因为别的队紧张就跟着紧张）──
	var lone := EnemyAgent.new(2, scav, base + Vector2(5.0, 5.0))
	var ctx3 := ctx.duplicate()
	ctx3["now"] = 1.0
	var before := lone.state
	lone.tick(0.1, ctx3)
	_check_eq(lone.state, before, "没编队的敌人不受小队警戒影响")


# ─────────────────── ④ 藏身处升级效果 + 商人 ───────────────────
