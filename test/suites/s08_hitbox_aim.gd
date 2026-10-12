extends TestSuite

## 命中判定与视野
##
## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。


func register() -> void:
	_suite("真机修复3：#1 贴脸 hitbox", _test_hitbox_close_range)
	_suite("真机修复3：#4/#5 自动瞄准", _test_auto_aim)
	_suite("真机修复3：#5 视野锥随枪械变化", _test_weapon_aim_cone)
	_suite("真机修复4：命中判定无双重随机", _test_no_double_hit_roll)
	_suite("真机修复4：散布收缩 hitbox", _test_spread_radius_factor)
	_suite("白模：视野锥不透视", _test_cone_no_xray)


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
	# ⚠️ 视野锥的**绘制**已搬到 view/raid_drawer.gd（拆分上帝对象），
	#    但「开火用 visible 不用 has_lock」这条**逻辑**还在场景里 —— 分开查。
	#    （这已是本次重构中第 4 次遇到"源码文本断言因代码搬家而失效"：
	#      它把「代码在哪」和「代码对不对」绑在了一起。）
	var dr := FileAccess.get_file_as_string("res://view/raid_drawer.gd")
	_check(dr.contains("Ballistics.los_distance"), "锥体逐条射线做裁切")
	_check(dr.contains("screen_diag_cells"),
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
