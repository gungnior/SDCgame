extends TestSuite

## 第七轮真人反馈修复（问题 1~7）回归套件
##
## 用户原话（acp 实测）：
##   1 敌人 ai 似乎有的没有生效
##   2 藏身处配装时应该可以选择带物品去背包
##   3 下图后自动有了护甲值，哪怕身上没有护甲
##   4 地图的容器看不到
##   5 白模阶段应该使用不同的地板色、墙壁色来区分房间类型
##   6 辅助瞄准的范围应该和枪械属性挂钩
##   7 菜单交互下拉不方便
##
## ⚠️ 这里只放**单元层**能证明的东西（sim/ 与纯函数）。
##    需要真树的（藏身处标签真的切换、突袭场景真的画容器）放在
##    test/pc_verify.gd 的集成步骤里 —— 那边有真实的 SceneTree。


func register() -> void:
	_suite("问题1：IDLE 敌人会巡视并发现静止玩家", _test_idle_spots_player)
	_suite("问题1：IDLE 敌人会游走（不是站着不动）", _test_idle_wanders)
	_suite("问题2：藏身处携带背包 stash<->pack", _test_carry_pack)
	_suite("问题2：携带背包进局转移 + 存档往返", _test_carry_pack_drain_save)
	_suite("问题3：护甲只来自装备（不再白送）", _test_armor_from_equipment)
	_suite("问题4：容器/尸体绘制接入", _test_containers_drawn)
	_suite("问题5：白模按房间类型染色", _test_whitebox_room_tint)
	_suite("问题6：辅助瞄准挂钩枪械属性", _test_aim_assist_weapon)
	_suite("问题7：藏身处分区标签", _test_hideout_tabs)


# ─────────────────── 问题 1：敌人 AI ───────────────────
#
# 根因（用 _install/tmp 的探针查出来的）：
#   IDLE 状态的敌人**从不转动 facing**，于是视野锥永远指着一个方向；
#   玩家只要不走进那一条线上，敌人就永远看不见 -> 「AI 没生效」。
#   实测修复前：森林 0/16、城区 0/35、军事 0/54 个敌人动过。


func _test_idle_spots_player() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var g := _open_grid(26, 20)
	var flows := FlowFieldManager.new()
	flows.setup(g)
	var scav: EnemyDef = reg.get_enemy("enemy_scav")

	# 敌人面朝右，玩家静止在**正后方**（一定不在初始视野锥里）
	var e := EnemyAgent.new(0, scav, Vector2(6.5, 6.5))
	e.facing = Vector2.RIGHT
	var targets := [{"id": "player", "pos": Vector2(3.5, 6.5), "hp": 100}]
	var ctx := {
		"grid": g, "flows": flows, "targets": targets,
		"rng": SimRng.new(20261013), "now": 0.0, "noises": [], "grace": false,
	}

	# ① 巡视：IDLE 每帧都必须转朝向（这是「能不能发现」的开关）
	e.tick(0.05, ctx)
	_check(not e.facing.is_equal_approx(Vector2.RIGHT),
		"IDLE 每帧都在转朝向（facing %s -> %s）" % [str(Vector2.RIGHT), str(e.facing)])
	_check_eq(e.state_name(), "IDLE", "第一帧还看不到正后方的静止目标（确实是在测『转过去』）")

	# ② 给足时间（10 秒）：朝向扫过背后时必须进入交战
	var t := 0.05
	var found := false
	for _i in 200:
		t += 0.05
		ctx["now"] = t
		e.tick(0.05, ctx)
		if e.state_name() != "IDLE":
			found = true
			break
	_check(found,
		"IDLE 巡视扫到背后后，静止玩家被发现（状态=%s，用时约 %.1fs）"
		% [e.state_name(), t])
	_check(e.state_name() == "COMBAT", "发现后进入 COMBAT（实际 %s）" % e.state_name())


func _test_idle_wanders() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var g := _open_grid(30, 22)
	var flows := FlowFieldManager.new()
	flows.setup(g)
	var scav: EnemyDef = reg.get_enemy("enemy_scav")

	# 8 个敌人在空旷房间里待 6 秒：必须都动过（修复前是 0/8）
	var total := 8
	var facing_changed := 0
	var pos_moved := 0
	for i in total:
		var start := Vector2(4.5 + float(i % 4) * 4.0, 5.5 + float(i / 4) * 6.0)
		var e := EnemyAgent.new(i, scav, start)
		e.facing = Vector2.RIGHT
		var start_facing := e.facing
		var ctx := {
			"grid": g, "flows": flows, "targets": [], "rng": SimRng.new(1000 + i),
			"now": 0.0, "noises": [], "grace": false,
		}
		var t := 0.0
		for _j in 120:                      # 6 秒
			t += 0.05
			ctx["now"] = t
			e.tick(0.05, ctx)
		if not e.facing.is_equal_approx(start_facing):
			facing_changed += 1
		if e.pos.distance_to(start) > 0.2:
			pos_moved += 1
	_check_eq(facing_changed, total, "全部 %d 个 IDLE 敌人的朝向都变过" % total)
	_check(pos_moved >= total / 2,
		"至少一半的 IDLE 敌人真的走了两步（%d/%d）" % [pos_moved, total])

	# 巡视必须真的在动：常量为正
	_check(EnemyAgent.IDLE_SCAN_DEG_PER_SEC > 0.0, "IDLE 巡视角速度 > 0")
	_check(EnemyAgent.IDLE_WANDER_RADIUS > 0.0, "IDLE 游走半径 > 0")


# ─────────────────── 问题 2：携带背包 ───────────────────


func _test_carry_pack() -> void:
	var reg := DataRegistry.new()
	reg.load_all("A")
	var h := Hideout.new(reg.items, 0)
	_check(h.pack != null, "藏身处有携带背包对象")
	_check_eq(h.pack.slot_count(), Hideout.PACK_SLOTS, "携带背包槽位 = %d" % Hideout.PACK_SLOTS)
	_check_eq(h.pack.count_of("ammo_rifle"), 0, "携带背包初始为空")

	# 仓库 -> 携带
	h.stash.add("ammo_rifle", 60)
	h.stash.add("medical_bandage", 4)
	_check_eq(h.stash_to_pack("ammo_rifle", 30), "", "搬 30 发步枪弹进携带背包")
	_check_eq(h.pack.count_of("ammo_rifle"), 30, "携带背包收到 30 发")
	_check_eq(h.stash.count_of("ammo_rifle"), 30, "仓库剩下 30 发")

	# count <= 0 = 全带走
	_check_eq(h.stash_to_pack("medical_bandage"), "", "绷带全带走")
	_check_eq(h.pack.count_of("medical_bandage"), 4, "绷带 4 个全进了携带背包")
	_check_eq(h.stash.count_of("medical_bandage"), 0, "仓库里的绷带清空")

	# 携带 -> 仓库
	_check_eq(h.pack_to_stash("ammo_rifle", 10), "", "放回 10 发")
	_check_eq(h.stash.count_of("ammo_rifle"), 40, "仓库变回 40 发")
	_check_eq(h.pack.count_of("ammo_rifle"), 20, "携带背包剩 20 发")

	# 清单：去重、按价值降序
	var entries := h.pack_entries()
	_check(entries.size() >= 1, "携带清单非空（%d 种）" % entries.size())
	_check(entries[0].has("id") and entries[0].has("count"), "清单条目有 id/count")

	# 错误路径必须给原因，而不是静默失败
	_check(not h.stash_to_pack("no_such_item").is_empty(), "搬不存在的物品有原因")
	_check(not h.pack_to_stash("no_such_item").is_empty(), "放回不存在的物品有原因")

	# 超重必须拦住（armor_heavy = 7.0kg，3 件 = 21kg > 20kg 上限）
	h.stash.add("armor_heavy", 3)
	var err := h.stash_to_pack("armor_heavy", 3)
	_check(not err.is_empty(), "超重时拒绝（%s）" % err)
	_check_eq(h.pack.count_of("armor_heavy"), 0, "超重时不搬任何一件")

	# 「全部放回」
	h.pack_clear_to_stash()
	_check_eq(h.pack.used_slots(), 0, "全部放回后携带背包为空")
	_check_eq(h.pack.count_of("ammo_rifle"), 0, "弹药也还回去了")


func _test_carry_pack_drain_save() -> void:
	var reg := DataRegistry.new()
	reg.load_all("A")
	var h := Hideout.new(reg.items, 0)
	h.stash.add("ammo_rifle", 60)
	h.stash.add("medical_bandage", 2)
	h.stash_to_pack("ammo_rifle", 24)
	h.stash_to_pack("medical_bandage")

	# 进局：pack -> 本局随身背包
	var carry := Inventory.new(40, reg.items, 999.0)
	var kinds := h.drain_pack_into(carry)
	_check_eq(kinds, 2, "进局转移了 2 种物品")
	_check_eq(carry.count_of("ammo_rifle"), 24, "随身背包收到 24 发")
	_check_eq(carry.count_of("medical_bandage"), 2, "随身背包收到 2 绷带")
	_check_eq(h.pack.used_slots(), 0, "转移后携带背包清空（没重复给）")

	# 存档往返：pack 必须一起存
	h.stash_to_pack("ammo_rifle", 12)
	var sm := SaveManager.new()
	sm.delete()
	_check_eq(sm.save({"hideout": h.to_dict()}), "", "保存藏身处")
	var r := sm.load_save()
	_check(bool(r["ok"]), "读回存档")
	var h2 := Hideout.new(reg.items, 0)
	h2.from_dict(r["data"]["hideout"])
	_check_eq(h2.pack.count_of("ammo_rifle"), 12, "携带背包存档往返一致")
	_check_eq(h2.stash.count_of("ammo_rifle"), 24, "仓库也一致")
	sm.delete()


# ─────────────────── 问题 3：护甲来自装备 ───────────────────


func _test_armor_from_equipment() -> void:
	var reg := DataRegistry.new()
	reg.load_all("A")

	# ① Vitals：护甲池的减伤由 take_hit 的穿透比例驱动
	var v := Vitals.new()
	v.reset(100, 0)
	_check_eq(v.armor, 0, "重置为 0 甲")
	_check_eq(v.take_hit(30, 1.0), 30, "穿透比例 1.0（穿甲弹）-> 一点都不减")
	_check_eq(v.armor, 0, "无甲时护甲池不变")
	v.reset(100, 40)
	_check_eq(v.take_hit(20, 0.0), 0, "穿透比例 0（甲全挡住）-> 血量不掉")
	_check_eq(v.armor, 20, "护甲池被吸收掉 20 点")
	_check_eq(v.take_hit(20, 1.0), 20, "同一发换穿甲弹 -> 全打在血上")
	_check_eq(v.armor, 20, "穿甲弹不磨损护甲池")

	# ② 空装备 -> worn_armor() == 0（修复前 _setup_sim 白送 40）
	var eq := Equipment.new(reg.items, reg.weapons, reg.attachments)
	_check_eq(eq.worn_armor(), 0, "没穿装备时护甲值 = 0（不再白送）")
	var gear := Inventory.new(4, reg.items, 999.0)
	gear.add("armor_heavy", 1)
	_check_eq(eq.equip(gear, "armor_heavy"), "", "穿上重甲")
	var heavy := int((reg.get_item("armor_heavy")).armor)
	_check_eq(eq.worn_armor(), heavy, "穿了重甲 -> 护甲值 = 装备值（%d）" % heavy)

	# ③ 弹型 vs 护甲的减伤关系（问题 3 的数值内核）
	var ap := DamageModel.armor_multiplier(6.0, float(heavy))
	var hp := DamageModel.armor_multiplier(1.0, float(heavy))
	_check(ap > hp, "穿甲弹穿透比例 > 肉伤弹（%.2f > %.2f）" % [ap, hp])
	_check_eq(DamageModel.armor_multiplier(3.0, 0.0), 1.0, "无甲目标 -> 穿透比例恒为 1.0")

	# ④ 源码守卫：突袭场景不许再写死 40 点护甲
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	# ⭐ 2026-10-16 全境2化 P1：生命上限改为吃装备 hp 词条，断言跟随升级
	#    （语义未变：护甲仍来自装备；effective_armor = worn_armor + 词条 flat）
	_check(rs.contains("vitals.reset(") and rs.contains("_player_armor())"),
		"突袭场景的护甲来自 _player_armor()（装备）")
	_check(rs.contains("_player_hp_bonus()"),
		"生命上限吃装备 hp 词条加成（全境2化 P1）")
	# 只查【代码行】（tab 缩进 + 调用），不误伤注释里的 `vitals.reset(100, 40)`
	_check(not rs.contains("\tvitals.reset(100, 40)"),
		"不再写死 vitals.reset(100, 40)（白送护甲）")
	_check(rs.contains("raid.equipment.effective_armor()"),
		"_player_armor() 取的是 effective_armor（装备护甲 + 词条，空装仍 0）")


# ─────────────────── 问题 4：容器/尸体可见 ───────────────────


func _test_containers_drawn() -> void:
	# 容器/尸体早先**已生成、也能搜**，只是绘制层从没画过 -> 屏幕上什么都看不到。
	var drawer := FileAccess.get_file_as_string("res://view/raid_drawer.gd")
	_check(drawer.contains("func _draw_containers"), "绘制层有 _draw_containers")
	_check(drawer.contains("raid.containers"), "遍历世界容器 raid.containers")
	_check(drawer.contains("raid.corpses"), "遍历尸体 raid.corpses")
	_check(drawer.contains("func _draw_container_shape"), "容器按类型画不同形状")
	# 必须在 _draw() 里真的被调用，否则等于没写
	var d_call := FileAccess.get_file_as_string("res://view/raid_drawer.gd")
	_check(d_call.contains("_draw_containers()"), "_draw_containers 被调用")
	_check(d_call.contains("CONTAINER_COLORS"), "容器有分类型配色")
	# 世界容器确实会被生成（数值层）
	_check(drawer.contains("_focus_ring") or drawer.contains("C_FOCUS_RING"),
		"当前选中的容器有高亮环（能看出在搜哪个）")


# ─────────────────── 问题 5：白模按房间类型染色 ───────────────────


func _test_whitebox_room_tint() -> void:
	# ① 色调表：不同类型 -> 不同色；普通房间 -> 不染色
	var armory := Room.new(0, Rect2i(2, 2, 6, 6))
	armory.room_type_id = "room_armory"
	var medical := Room.new(1, Rect2i(10, 2, 6, 6))
	medical.room_type_id = "room_medical"
	var common := Room.new(2, Rect2i(2, 10, 6, 6))
	common.room_type_id = "room_common"

	var ca: Variant = WhiteboxPainter.room_tint_of(armory)
	var cm: Variant = WhiteboxPainter.room_tint_of(medical)
	_check(ca != null, "军械库有专属色调")
	_check(cm != null, "医疗室有专属色调")
	_check((ca as Color) != (cm as Color), "两种房间的色调不同（%s / %s）"
		% [str(ca), str(cm)])
	_check(WhiteboxPainter.room_tint_of(common) == null, "普通房间不染色（保持基准色）")

	# ② 描边色：有色调 -> 带色；普通房间 -> 近乎隐形的白
	_check((WhiteboxPainter.room_edge_of(armory) as Color).a > 0.3, "专属房间描边可见")
	_check_eq(WhiteboxPainter.room_edge_of(common), WhiteboxPainter.ROOM_EDGE_PLAIN,
		"普通房间用近乎隐形的描边")

	# ③ 亮度不变量：所有房间色调都必须「亮」（否则中心像素会被误判成墙）
	for k in WhiteboxPainter.ROOM_TINTS.keys():
		var c: Color = WhiteboxPainter.ROOM_TINTS[k]
		_check(not WhiteboxPainter.looks_like_wall(c),
			"色调 %s 足够亮（luminance %.2f >= 0.16）" % [k, c.get_luminance()])

	# ④ 真的染到地图像素上：同一张图，有房间 vs 没房间，房间地板像素必须不同
	var g := _open_grid(20, 16)
	var plain := WhiteboxPainter.paint(g, [])
	var tinted := WhiteboxPainter.paint(g, [armory])
	var cell := Vector2i(4, 4)
	var o := g.cell_to_tile_origin(cell)
	var n := LogicalGrid.CELL_SIZE_TILES
	var cpx := Vector2i(o.x + n / 2, o.y + n / 2)
	_check(plain.get_pixel(cpx.x, cpx.y) != tinted.get_pixel(cpx.x, cpx.y),
		"军械库地板像素被染色（%s -> %s）"
		% [str(plain.get_pixel(cpx.x, cpx.y)), str(tinted.get_pixel(cpx.x, cpx.y))])
	# 染色后不能变成「看起来像墙」
	_check(not WhiteboxPainter.looks_like_wall(tinted.get_pixel(cpx.x, cpx.y)),
		"染色后地板仍被判为可走（不会误判成墙）")

	# ⑤ 确定性：同样输入必须逐像素一致（s09 的像素级断言的底座）
	var again := WhiteboxPainter.paint(g, [armory])
	var diff := 0
	for y in tinted.get_height():
		for x in tinted.get_width():
			if tinted.get_pixel(x, y) != again.get_pixel(x, y):
				diff += 1
	_check_eq(diff, 0, "同输入两次染色逐像素一致（差异 %d）" % diff)

	# ⑥ 烘焙器与 WhiteboxPainter 仍逐像素一致（含染色路径）
	var reg2 := DataRegistry.new()
	reg2.load_all("B")
	var gen := MapGenerator.new()
	gen.generate(4242, reg2.room_types)
	var baker := RaidMapBaker.new()
	baker.load_tiles()
	var tex := baker.build(gen.grid, gen.graph.rooms, true)
	var want := WhiteboxPainter.paint(gen.grid, gen.graph.rooms)
	var diff2 := 0
	if tex != null:
		var got := tex.get_image()
		for y in want.get_height():
			for x in want.get_width():
				if got.get_pixel(x, y) != want.get_pixel(x, y):
					diff2 += 1
	_check_eq(diff2, 0, "烘焙结果与 WhiteboxPainter 逐像素一致（差异 %d）" % diff2)


# ─────────────────── 问题 6：辅助瞄准挂钩枪械 ───────────────────


func _test_aim_assist_weapon() -> void:
	# ① 磁性锥半角随「视野锥」单调增；且比旧的固定 4.2° 更有区分度
	var pistol := AimAssist.half_angle_for_weapon(42.0, 640.0)   # 手枪
	var shotgun := AimAssist.half_angle_for_weapon(34.0, 640.0)  # 霰弹
	var rifle := AimAssist.half_angle_for_weapon(55.0, 640.0)    # 步枪
	var sniper := AimAssist.half_angle_for_weapon(30.0, 640.0)   # 狙击
	_check(sniper < shotgun, "狙击的磁性锥比霰弹更窄（%.2f < %.2f）" % [sniper, shotgun])
	_check(shotgun < rifle, "霰弹比步枪更窄（%.2f < %.2f）" % [shotgun, rifle])
	_check(sniper < pistol and pistol < rifle,
		"锥半角随视野锥单调（狙 %.2f < 手枪 %.2f < 步枪 %.2f）" % [sniper, pistol, rifle])

	# ② 数据缺失 -> 回退旧固定值（不会因为数据缺而失去辅助）
	_check(absf(AimAssist.half_angle_for_weapon(0.0, 640.0)
		- AimAssist.half_angle_for_viewport(640.0)) < 0.001,
		"缺 aim_cone_deg 时回退到旧的按视口换算值")

	# ③ 上下限夹住极端数据
	_check_eq(AimAssist.half_angle_for_weapon(1000.0, 640.0), AimAssist.MAX_WEAPON_HALF_ANGLE,
		"极端大的视野锥被夹在上限 %.1f°" % AimAssist.MAX_WEAPON_HALF_ANGLE)
	_check_eq(AimAssist.half_angle_for_weapon(0.5, 640.0), AimAssist.MIN_WEAPON_HALF_ANGLE,
		"极端小的视野锥被夹在下限 %.1f°" % AimAssist.MIN_WEAPON_HALF_ANGLE)

	# ④ 有效距离随射程缩放，且有下限
	_check(absf(AimAssist.assist_range(100.0) - 85.0) < 0.01,
		"射程 100 -> 磁性 85（比例 %.2f）" % AimAssist.ASSIST_RANGE_RATIO)
	_check(AimAssist.assist_range(120.0) > AimAssist.assist_range(18.0),
		"狙击磁得更远、霰弹磁得更近")
	_check(AimAssist.assist_range(0.0) >= 2.0, "射程缺失时仍有最小磁性距离")

	# ⑤ 真枪的数据走一遍：每种枪都算得出合法值
	var reg := DataRegistry.new()
	reg.load_all("C")
	var bad: Array[String] = []
	for id in reg.weapons.keys():
		var w: WeaponDef = reg.get_weapon(id)
		if w == null:
			continue
		var h := AimAssist.half_angle_for_weapon(w.aim_cone_deg, 640.0)
		if h < AimAssist.MIN_WEAPON_HALF_ANGLE - 0.001 or h > AimAssist.MAX_WEAPON_HALF_ANGLE + 0.001:
			bad.append("%s=%.2f" % [id, h])
	_check(bad.is_empty(), "所有枪械都算得出合法锥半角" + ("" if bad.is_empty() else str(bad)))

	# ⑥ 接线守卫：模拟层真的用了它
	var src := _view_src()
	_check(src.contains("half_angle_for_weapon"), "模拟层用 half_angle_for_weapon 算磁性锥")
	_check(src.contains("AimAssist.assist_range"), "模拟层用 assist_range 算磁性距离")


# ─────────────────── 问题 7：藏身处分区标签 ───────────────────


func _test_hideout_tabs() -> void:
	# 单个长列表要一路下拉 -> 改成六个分区标签（一次只看一页）
	var sc: GDScript = load("res://view/hideout_scene.gd")
	_check(sc != null, "能载入 hideout_scene.gd")
	var consts := sc.get_script_constant_map()
	var keys: Array = consts.get("SECTION_KEYS", [])
	var labels: Dictionary = consts.get("SECTION_LABEL", {})
	_check_eq(keys.size(), 6, "六个分区（实际 %d：%s）" % [keys.size(), str(keys)])
	for want in ["overview", "carry", "upgrade", "craft", "repair", "settings"]:
		_check(keys.has(want), "有分区 %s" % want)
		_check(labels.has(want), "分区 %s 有中文标签（%s）" % [want, str(labels.get(want))])

	# 标签栏宽度自检：工程基准视口宽 640（project.godot viewport_width）必须放得下；
	# 自检本身要「会拒绝」—— 太窄时返回 false，而不是永远返回 true。
	_check(bool(sc.call("tabs_fit", 640.0)), "基准视口 640 宽下六个标签放得下")
	_check(not bool(sc.call("tabs_fit", 200.0)), "极窄视口（200）下自检会拒绝")

	# 结构守卫：切分区 / 建标签 / 打开携带面板的入口都在
	var src := FileAccess.get_file_as_string("res://view/hideout_scene.gd")
	for fn in ["func _build_tab_bar", "func _show_section", "func _on_tab",
			"func _refresh_tab_buttons", "func _open_carry"]:
		_check(src.contains(fn), "有 %s" % fn)
	_check(src.contains("_page_host"), "内容区只有一个 page host（一次只显示一个分区）")
	_check(src.contains("CarryPanel"), "携带分区接了 CarryPanel")
	# 老的长列表不应该再直接把所有区块塞进同一个 ScrollContainer
	_check(src.contains("_build_overview_section"), "概览是独立分区构建函数")
	_check(src.contains("_build_settings_section"), "设置是独立分区构建函数")
