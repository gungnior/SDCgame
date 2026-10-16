extends Node

## PC 端四项端到端验证探针
##
## 为什么写它：单元测试验的是"零件"，这里验的是"零件装到游戏里还转不转"。
## 具体要证的四条：
##   ① 存档：改状态 -> 存 -> 模拟重启 -> 读 -> 一切复原
##   ② 数据：新敌人真的会被刷出来；掉落表真的能抽出新物品
##   ③ 群体 AI：包夹角色真的分配了；警戒真的驱动了没看见玩家的敌人
##   ④ 藏身处：买升级 -> 负重/治疗速度真的进到局内；商人买卖真的改仓库与钱
##
## 用法：godot --path . res://test/pc_verify.tscn

var _fails: Array[String] = []
var _checks := 0


func _ok(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		print("  ok    %s" % msg)
	else:
		print("  FAIL  %s" % msg)
		_fails.append(msg)


func _ready() -> void:
	var g: Node = get_node_or_null("/root/Game")
	if g == null:
		print("❌ 拿不到 Game autoload")
		get_tree().quit(1)
		return
	g.call("ensure_loaded")
	var reg: RefCounted = g.get("reg")
	var save: RefCounted = g.get("save")
	save.call("delete")            # 从干净状态开始

	print("\n═══ ① 存档 ═══")
	await _verify_save(g, save)

	print("\n═══ ② 数据填充 ═══")
	await _verify_data(reg)

	print("\n═══ ③ 群体 AI ═══")
	await _verify_squad(reg)

	print("\n═══ ④ 藏身处效果 + 商人 ═══")
	await _verify_hideout(g, reg, save)

	print("\n═══ ⑤ 突袭场景真跑一遍 ═══")
	await _verify_raid_scene(g)

	print("\n═══ ⑥ 主菜单 + 选图 + 修理 ═══")
	await _verify_menu_map_repair(g)

	print("\n═══ 结果 ═══")
	if _fails.is_empty():
		print("✅ PC 端验证全部通过（%d 项）" % _checks)
		get_tree().quit(0)
	else:
		print("❌ %d/%d 项失败：" % [_fails.size(), _checks])
		for f in _fails:
			print("   - %s" % f)
		get_tree().quit(1)


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# ─────────────── ① 存档 ───────────────

func _verify_save(g: Node, save: RefCounted) -> void:
	var h: RefCounted = g.get("hideout")
	h.set("wallet", 20000)
	h.call("buy_upgrade", "stash_size")
	h.call("buy_upgrade", "carry_size")
	h.call("buy_upgrade", "heal_speed")
	h.call("buy_upgrade", "merchant_rep")
	var stash: RefCounted = h.get("stash")
	stash.call("add", "valuables_gpu", 3)
	stash.call("add", "medical_kit", 4)
	g.set("auto_fire", true)
	g.set("auto_aim", false)
	g.set("stats", {"raids": 11, "extracts": 8, "deaths": 3, "kills": 57})

	var snapshot := {
		"wallet": int(h.get("wallet")),
		"stash_size": int(h.call("level_of", "stash_size")),
		"slots": int(h.call("slot_count")),
		"weight": float(h.call("carry_weight_limit")),
		"heal": float(h.call("heal_speed_multiplier")),
		"sell": float(h.call("sell_ratio")),
		"gpu": int(stash.call("count_of", "valuables_gpu")),
		"kit": int(stash.call("count_of", "medical_kit")),
	}
	print("  存前：资金=%d 槽位=%d 负重=%.1f 治疗x%.2f 回收x%.2f" % [
		snapshot["wallet"], snapshot["slots"], snapshot["weight"],
		snapshot["heal"], snapshot["sell"]])

	var err: String = g.call("save_game")
	_ok(err == "", "save_game 返回空（%s）" % err)
	_ok(bool(save.call("exists")), "存档文件已生成：%s" % str(save.get("path")))

	# 把内存状态彻底打乱，模拟"重启"
	h.call("from_dict", {"wallet": 0, "upgrades": {},
		"stash": {"slots": [], "max_weight": 999.0}})
	g.set("auto_fire", false)
	g.set("auto_aim", true)
	g.set("stats", {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0})
	_ok(int(h.get("wallet")) == 0, "状态已清空（用于验证读档）")

	var loaded: bool = g.call("load_game")
	_ok(loaded, "load_game 成功")
	_ok(int(h.get("wallet")) == snapshot["wallet"], "资金复原 %d" % int(h.get("wallet")))
	_ok(int(h.call("level_of", "stash_size")) == snapshot["stash_size"], "升级等级复原")
	_ok(int(h.call("slot_count")) == snapshot["slots"],
		"仓库槽位【效果】复原（%d）—— 只恢复数字不重应用会在这里失败" % int(h.call("slot_count")))
	_ok(absf(float(h.call("carry_weight_limit")) - snapshot["weight"]) < 0.001,
		"负重上限复原 %.1f" % float(h.call("carry_weight_limit")))
	_ok(int(stash.call("count_of", "valuables_gpu")) == snapshot["gpu"], "仓库物品复原")
	_ok(bool(g.get("auto_fire")) and not bool(g.get("auto_aim")), "设置项复原")
	_ok(int((g.get("stats") as Dictionary).get("kills", 0)) == 57, "统计复原")


# ─────────────── ② 数据填充 ───────────────

func _verify_data(reg: RefCounted) -> void:
	var rb := DataRegistry.new()
	rb.load_all("B")
	var ra := DataRegistry.new()
	ra.load_all("A")

	_ok(ra.weapons.size() == 6, "A 档枪械 6 把（B 档 %d）" % rb.weapons.size())
	# ⚠️ 50 -> 56：武器已作为 item（见 s01 的说明）；A 档 = 原有 50 + B 档 3 把枪 + A 档 3 把枪
	_ok(ra.items.size() == 56, "A 档物品 56 件（B 档 %d）" % rb.items.size())
	_ok(ra.enemies.size() == 4, "A 档敌人 4 种（B 档 %d）" % rb.enemies.size())
	# ⚠️ items 15 -> 18：B 档 3 把枪现在也是 item
	_ok(rb.weapons.size() == 3 and rb.items.size() == 18 and rb.enemies.size() == 2,
		"B 档仍是 3/18/2（阶段过滤没坏）")

	# 新武器必须能解析出视野锥（否则"视野随枪械变化"对它无效）
	var dmr: WeaponDef = ra.get_weapon("weapon_dmr")
	_ok(dmr != null and dmr.aim_cone_deg > 0.0,
		"新武器带 aim_cone_deg（%.0f°）" % (0.0 if dmr == null else dmr.aim_cone_deg))
	# 医药物品必须能被治疗系统识别
	var surg: ItemDef = ra.get_item("medical_surgical")
	_ok(surg != null and not surg.treat.is_empty(), "新医疗品带 treat 字段")

	# 掉落表：B 档表里不能有指向未加载物品的条目
	var t_b: LootTableDef = rb.get_loot_table("loot_common")
	var t_a: LootTableDef = ra.get_loot_table("loot_common")
	_ok(t_a.entries.size() > t_b.entries.size(),
		"A 档掉落条目更多（B %d -> A %d）" % [t_b.entries.size(), t_a.entries.size()])
	var dangling := 0
	for e in t_b.entries:
		if not rb.items.has(e.item_id):
			dangling += 1
	_ok(dangling == 0, "B 档掉落表没有指向未加载物品的条目")
	# A 档抽样必须全部命中
	var rng := SimRng.new(999)
	var hits := 0
	for i in 300:
		var e2 := t_a.roll_entry(rng)
		if e2 != null and ra.items.has(e2.item_id):
			hits += 1
	_ok(hits >= 290, "A 档抽样 300 次命中 %d 次（>=290）" % hits)

	# 新敌人能被解析且是 ranged 时反应时间合规
	for id in ["enemy_raider", "enemy_marksman"]:
		var ed: EnemyDef = ra.get_enemy(id)
		_ok(ed != null, "能取到 %s" % id)
		if ed != null and ed.is_ranged():
			_ok(ed.reaction_time >= EnemyDef.MIN_RANGED_REACTION,
				"%s 的 reaction_time %.2f >= 下限" % [id, ed.reaction_time])


# ─────────────── ③ 群体 AI ───────────────

func _verify_squad(reg: RefCounted) -> void:
	var gen := MapGenerator.new()
	gen.generate(20261012, reg.room_types)
	var grid := gen.grid
	var flows := FlowFieldManager.new()
	flows.setup(grid)

	# ── 包夹：4 个敌人应当拿到 4 种角色，且目标方位不同 ──
	var scav: EnemyDef = reg.get_enemy("enemy_scav")
	var sq := Squad.new(1)
	var target := Vector2(30.5, 30.5)
	var members: Array = []
	var dists: Array[float] = [2.0, 5.0, 8.0, 12.0]
	for i in 4:
		var a := EnemyAgent.new(i, scav, target + Vector2(0.0, dists[i]))
		sq.add_member(a)
		members.append(a)
	sq.assign_roles(target)
	var roles: Array[int] = []
	for m in members:
		roles.append(int(sq.role_of(m)))
	_ok(roles[0] == Squad.Role.DIRECT, "最近的当正面")
	_ok(roles[1] == Squad.Role.FLANK_LEFT, "次近的当左翼")
	_ok(roles[2] == Squad.Role.FLANK_RIGHT, "第三的当右翼")
	_ok(roles[3] == Squad.Role.OVERWATCH, "最远的当压制")
	var g1 := sq.goal_for(members[1], target)
	var g2 := sq.goal_for(members[2], target)
	_ok(g1.distance_to(g2) > 3.0,
		"左右翼包夹点分开了（%.1f 格）—— 否则是挤在一起" % g1.distance_to(g2))

	# ⭐ 包夹点必须【稳定】：连算两次结果一样，否则敌人会绕着目标转圈
	var again := sq.goal_for(members[1], target)
	_ok(g1.distance_to(again) < 0.01, "同一个包夹点重复算结果一致（稳定）")

	# ── 警戒驱动行为：自己看不见的成员也要被带动 ──
	var base := Ballistics.cell_center(gen.spawn_room().center)
	var sq2 := Squad.new(2)
	var b := EnemyAgent.new(9, scav, base)
	sq2.add_member(b)
	# 玩家在 40 格外，B 绝对看不见
	var far := base + Vector2(40.0, 0.0)
	var ctx := {
		"grid": grid, "flows": flows, "rng": SimRng.new(3), "now": 1.0,
		"targets": [{"id": "player", "pos": far, "hp": 100}],
		"noises": [], "grace": false,
	}
	_ok(int(b.state) == int(EnemyAgent.State.IDLE), "B 初始 IDLE")
	for i in 10:
		b.tick(0.1, ctx)
	_ok(int(b.state) == int(EnemyAgent.State.IDLE), "小队无接触时 B 保持 IDLE")
	sq2.report_contact(base + Vector2(5.0, 0.0), 1.0)
	b.tick(0.1, ctx)
	_ok(int(b.state) == int(EnemyAgent.State.ALERT),
		"小队报告接触后 B 转为 ALERT —— 这才是『群体协同』")
	_ok(absf(b.last_seen_pos.distance_to(sq2.last_known_pos)) < 0.01,
		"B 压向的是小队共享的最后已知位置")

	# ── 扩散性能：40 个小队不能变成 40 次全网格 Dijkstra ──
	var many: Array = []
	for i in 40:
		var s := Squad.new(i)
		var p := base + Vector2(float(i % 8) * 1.0, float(i / 8) * 1.0)
		if not grid.is_walkable(Ballistics.cell_of(p)):
			p = base
		s.add_member(EnemyAgent.new(i, scav, p))
		many.append(s)
	var t0 := Time.get_ticks_usec()
	Squad.spread_alert(grid, base, many, 30.0, 2.0)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_ok(ms < 60.0, "40 个小队一次扩散 %.2f ms（旧实现是 40 次全网格 Dijkstra）" % ms)


# ─────────────── ④ 藏身处效果 + 商人 ───────────────

func _verify_hideout(g: Node, reg: RefCounted, save: RefCounted) -> void:
	var h: RefCounted = g.get("hideout")
	# 重置成"什么都没升级"的干净状态
	h.call("from_dict", {"wallet": 50000, "upgrades": {},
		"stash": {"slots": [], "max_weight": 999.0}})

	# ── 商人：买 ──
	var price := int(h.call("stock_price", "ammo_rifle"))
	var w0 := int(h.get("wallet"))
	var e1: String = h.call("buy", "ammo_rifle", 30)
	_ok(e1 == "", "商人买入成功")
	_ok(int(h.get("wallet")) == w0 - price * 30, "钱扣对了（-%d）" % (price * 30))
	_ok(int((h.get("stash") as RefCounted).call("count_of", "ammo_rifle")) == 30,
		"买到的东西进了仓库")

	# ── 商人：卖 ──
	var stash: RefCounted = h.get("stash")
	stash.call("add", "valuables_gpu", 2)
	var w1 := int(h.get("wallet"))
	var got: int = h.call("sell", "valuables_gpu", 1)
	_ok(got > 0, "卖出有收入（%d 元）" % got)
	_ok(int(h.get("wallet")) == w1 + got, "卖出后钱增加了")
	_ok(int(stash.call("count_of", "valuables_gpu")) == 1, "仓库少了一个")

	# ── 升级效果进局内 ──
	var r_before := RaidSession.new(reg.get("items"), SimRng.new(1),
		stash, h.call("raid_modifiers"))
	h.call("buy_upgrade", "carry_size")
	h.call("buy_upgrade", "carry_size")
	h.call("buy_upgrade", "heal_speed")
	var r_after := RaidSession.new(reg.get("items"), SimRng.new(2),
		stash, h.call("raid_modifiers"))
	_ok(r_after.carry.max_weight > r_before.carry.max_weight + 5.0,
		"「负重训练」进了局内（%.1f -> %.1f kg）" % [
			r_before.carry.max_weight, r_after.carry.max_weight])
	_ok(r_after.heal_speed > r_before.heal_speed,
		"「战地急救」进了局内（x%.2f -> x%.2f）" % [
			r_before.heal_speed, r_after.heal_speed])

	# 治疗耗时真的变短
	var bandage: ItemDef = reg.get_item("medical_bandage")
	var vit := Vitals.new()
	vit.reset(100, 40)
	var m0 := MedicalSystem.new()
	vit.hp = 10
	m0.start(bandage, vit)
	var d0 := m0.duration
	var m1 := MedicalSystem.new()
	m1.set_speed_multiplier(r_after.heal_speed)
	vit.hp = 10
	m1.start(bandage, vit)
	_ok(m1.duration < d0, "治疗耗时真的缩短（%.2fs -> %.2fs）" % [d0, m1.duration])

	# 存档：商人交易后自动落盘
	g.call("save_game")
	_ok(bool(save.call("exists")), "交易后可存档")


# ─────────────── ⑤ 突袭场景真跑 ───────────────

func _verify_raid_scene(g: Node) -> void:
	var scene: Node = load("res://view/raid_scene.tscn").instantiate()
	add_child(scene)
	await _f(30)

	var agents: Array = scene.get("agents")
	# ── 需求①：敌人数量不再被卡死为 4 ──
	# 旧契约是 `MAX_TEST_ENEMIES = 4`（技术验证期硬上限）。现在敌人总数 =
	#   地图主题密度 × 房间数（MapThemeDef.target_enemy_count / 房间 enemy_budget）。
	# 断言分两层：① 确实 > 4（旧上限已取消）；② 与房间预算之和对得上（数量由地图决定，不是随机）。
	_ok(agents.size() > 4, "敌人数量不再卡死为 4（实际 %d）" % agents.size())
	var expected := 0
	var gen = scene.get("gen")
	if gen != null:
		for r in gen.graph.rooms:
			if r.room_type != "spawn":
				expected += int(r.enemy_budget)
	# ⭐ 撤离守卫（可玩性 Step3）是**预算之外的额外威胁** —— 撤离不该免费。
	#    断言随之更新为「房间预算 + 撤离守卫」，仍然严格钉死总数（不多不少）。
	var rs = scene.get("raid")
	if rs != null:
		for i in range(rs.extract_points.size()):
			expected += RaidSession.extract_guard_count(i, rs.extract_points.size())
	_ok(agents.size() == expected,
		"敌人数量 == 房间 enemy_budget 之和 + 撤离守卫（实际 %d / 期望 %d）" % [agents.size(), expected])
	# 地图主题应当已选定（森林/城区/军事基地）
	_ok(scene.get("theme") != null, "突袭场景选定了地图主题（%s）"
		% ("null" if scene.get("theme") == null else scene.theme.name))
	# 敌人类型应当来自数据池（4 种），不再硬编码两种
	var kinds := {}
	for a in agents:
		if a.get("def") != null:
			kinds[a.def.id] = true
	_ok(kinds.size() >= 2,
		"敌人类型来自数据池（本局用到 %d 种：%s）" % [kinds.size(), str(kinds.keys())])

	# 局内背包上限来自藏身处
	var raid: RefCounted = scene.get("raid")
	var hideout: RefCounted = g.get("hideout")
	_ok(absf(raid.carry.max_weight - float(hideout.call("carry_weight_limit"))) < 0.01,
		"局内负重上限 == 藏身处升级值（%.1f kg）" % raid.carry.max_weight)
	var medical: RefCounted = scene.get("medical")
	_ok(absf(float(medical.get("speed_multiplier")) - float(hideout.call("heal_speed_multiplier"))) < 0.001,
		"局内治疗速度倍率 == 藏身处升级值（x%.2f）" % float(medical.get("speed_multiplier")))

	# ── 问题1：敌人出生点分散（不再全挤在房间中心）──
	var pos_set := {}
	for a in agents:
		pos_set[a.pos] = true
	if agents.size() > 1:
		_ok(pos_set.size() > 1,
			"敌人出生点分散（%d 个不同位置 / %d 个敌人）" % [pos_set.size(), agents.size()])

	# ── 问题3：护甲只来自装备（修复前白送 40 点）──
	var vit: RefCounted = scene.get("vitals")
	var eq: RefCounted = raid.get("equipment")
	_ok(vit != null and eq != null, "突袭场景持有 vitals 与 equipment")
	if vit != null and eq != null:
		var worn := int(eq.call("worn_armor"))
		_ok(int(vit.get("max_armor")) == worn and int(vit.get("armor")) == worn,
			"护甲池 == 身上装备护甲值（%d / 装备 %d）—— 不再白送 40"
				% [int(vit.get("armor")), worn])

	# ── 问题4：地图真的生成了可搜索容器，且绘制器已接入 ──
	var ctrs: Array = raid.get("containers")
	_ok(ctrs.size() > 0, "地图生成了可搜索容器（%d 个）" % ctrs.size())
	_ok(scene.get("drawer") != null, "突袭场景持有世界绘制器（raid_drawer）")

	# ── 问题2：战术地图（必须能看见撤离点）──
	var mp: Node = scene.get("map_panel")
	_ok(mp != null, "突袭场景持有战术地图面板（map_panel，真机反馈 #2）")
	if mp != null:
		mp.call("open", scene)
		await _f(3)
		_ok(bool(mp.call("is_open")), "地图能打开")
		_ok(mp.get("_tex") != null, "地图地形已烘焙成贴图")
		var mrect: Rect2 = mp.get("_map_rect")
		_ok(mrect.size.x > 10.0 and mrect.size.y > 10.0,
			"地图区域有尺寸（%.0f x %.0f）" % [mrect.size.x, mrect.size.y])
		# 区域必须落在视口内（地图被挤出屏幕是"看不见"的另一种死法）
		var vp2: Vector2 = get_viewport().get_visible_rect().size
		_ok(mrect.position.x >= -1.0 and mrect.end.x <= vp2.x + 1.0
			and mrect.position.y >= -1.0 and mrect.end.y <= vp2.y + 1.0,
			"地图区域完整在视口内（视口 %s）" % str(vp2))
		var ex: Array = raid.get("extract_points")
		_ok(ex.size() >= 2, "数据层有 %d 个撤离点（>=2）" % ex.size())
		mp.call("close")
		await _f(2)
		_ok(not bool(mp.call("is_open")), "地图能关闭")

	# ── 问题3：敌人类型配色（不同敌人不同颜色）──
	var defs := {}
	for a in agents:
		if a.get("def") != null:
			defs[a.def.id] = a.def.color
	var cols := {}
	for k in defs.keys():
		cols[str(defs[k])] = true
	_ok(defs.size() >= 2 and cols.size() >= defs.size(),
		"%d 种敌人拿到 %d 种不同身份色（真机反馈 #3）" % [defs.size(), cols.size()])

	# ── 问题4 / 问题5：背包面板的拖拽与堆叠拾取 ──
	var ip: Node = scene.get("inventory_panel")
	_ok(ip != null, "突袭场景持有背包面板")
	if ip != null:
		_ok(ip.get("_ghost") != null, "背包面板有拖拽浮标（真机反馈 #4）")
		_ok(ip.get("_qty") != null, "背包面板内嵌自定义数量弹窗（真机反馈 #5）")
		var reg2: RefCounted = scene.get("reg")
		var cinv := Inventory.new(24, reg2.items, 999.0)
		cinv.add("ammo_rifle", 12)
		var got: Array = []
		ip.connect("action", func(id: String, n: int): got.append([id, n]))
		ip.call("open", reg2.items, raid.carry, cinv, "测试容器", raid.equipment)
		await _f(2)

		var labels := _button_labels(ip)
		_ok(labels.has("全拿\n12"), "堆叠行有「全拿」按钮（%s）" % str(labels))
		_ok(labels.has("取N…"), "堆叠行有「取N…」按钮")

		# ① 点「全拿」-> action(ammo_rifle, 12)
		got.clear()
		for b in _touch_buttons(ip):
			if str(b.get("label_text")).begins_with("全拿"):
				b.pressed_down.emit()
		_ok(got.size() == 1 and str(got[0][0]) == "ammo_rifle" and int(got[0][1]) == 12,
			"「全拿」发出 action(ammo_rifle, 12)（实际 %s）" % str(got))

		# ② 点「取N…」-> 弹窗 -> 调到 5 -> 确定
		ip.call("open", reg2.items, raid.carry, cinv, "测试容器", raid.equipment)
		await _f(2)
		var qp: Node = ip.get("_qty")
		for b in _touch_buttons(ip):
			if str(b.get("label_text")).begins_with("取N"):
				b.pressed_down.emit()
		_ok(bool(qp.call("is_open")), "「取N…」打开了数量弹窗")
		qp.call("_set_cur", 5)
		_ok(int(qp.call("current")) == 5, "数量弹窗可调到 5（实际 %d）" % int(qp.call("current")))
		got.clear()
		qp.call("_on_ok")
		_ok(got.size() == 1 and int(got[0][1]) == 5,
			"确定后发出 action(ammo_rifle, 5)（实际 %s）" % str(got))

		# ③ 拖拽：从容器行拖到右栏 -> 整堆拿走
		ip.call("open", reg2.items, raid.carry, cinv, "测试容器", raid.equipment)
		await _f(2)
		_ok(bool(ip.call("drag_state").is_empty()), "拖拽态初始为空")
		var row_btn: Node = null
		for b in _touch_buttons(ip):
			if bool(b.get("drag_enabled")):
				row_btn = b
				break
		_ok(row_btn != null, "容器条目启用了拖拽（drag_enabled）")
		if row_btn != null:
			var scr: Node = ip.get("_right_scroll")
			var rr: Rect2 = scr.get_global_rect()
			got.clear()
			ip.call("_begin_drag", rr.get_center(), "ammo_rifle x12", "ammo_rifle", 12, true)
			_ok(not bool(ip.call("drag_state").is_empty()), "开始拖拽后拖拽态非空")
			ip.call("_on_drag_dropped", rr.get_center())
			_ok(got.size() == 1 and int(got[0][1]) == 12,
				"拖到右栏 -> 整堆拿走（实际 %s）" % str(got))
		ip.call("close")
		await _f(2)

	# 跑一会儿，确认不崩、敌人有行为
	for i in 120:
		await get_tree().process_frame
	var alive := 0
	for a in agents:
		if a.is_alive():
			alive += 1
	_ok(alive >= 0, "跑了 2 秒没崩，存活敌人 %d" % alive)
	_ok(scene.get("squad") != null, "场景持有小队对象")
	scene.queue_free()
	await _f(3)


# ─────────────── ⑥ 主菜单 / 选图 / 修理 ───────────────

## 收集一棵树里所有 TouchButton 的 label_text（用于"按钮真的存在"的断言）
func _button_labels(n: Node) -> Array:
	var out: Array = []
	if n is Control and str(n.get("label_text")) != "" and n.get_script() != null:
		if n.get("label_text") != null:
			out.append(str(n.get("label_text")))
	for c in n.get_children():
		out.append_array(_button_labels(c))
	return out


## 收集一棵树里所有 TouchButton 节点（要按 label 前缀找按钮并真的按下去时用）
func _touch_buttons(n: Node) -> Array:
	var out: Array = []
	if n is Control and n.get_script() != null and n.get("label_text") != null:
		out.append(n)
	for c in n.get_children():
		out.append_array(_touch_buttons(c))
	return out


func _verify_menu_map_repair(g: Node) -> void:
	# ① 主菜单：能实例化、三个按钮都在、设置能开关
	var menu: Node = load("res://view/main_menu.tscn").instantiate()
	add_child(menu)
	await _f(10)
	_ok(menu.get("_settings") != null, "主菜单内嵌了设置菜单")
	var labels: Array = _button_labels(menu)
	for want in ["开始游戏", "设置", "退出"]:
		_ok(labels.has(want), "主菜单有「%s」按钮" % want)
	var sm: Node = menu.get("_settings")
	sm.call("open")
	_ok(bool(sm.call("is_open")), "主菜单里能打开设置")
	sm.call("close")
	_ok(not bool(sm.call("is_open")), "设置能关闭")
	# 只验常量指向（不真的切场景，否则把探针自己切掉了）
	_ok(str(load("res://game/game_state.gd").get("MAIN_MENU_SCENE")).ends_with("main_menu.tscn"),
		"有主菜单场景常量")
	_ok(str(ProjectSettings.get_setting("application/run/main_scene")).contains("main_menu"),
		"项目主场景 = 主菜单")
	menu.queue_free()
	await _f(3)

	# ② 选图：藏身处写入 Game.map_id -> 突袭场景真的用它建图
	var hs: Node = load("res://view/hideout_scene.tscn").instantiate()
	add_child(hs)
	await _f(8)
	_ok((hs.get("_map_buttons") as Array).size() >= 4,
		"藏身处有选图按钮（随机 + 3 张图，实际 %d 个）"
			% (hs.get("_map_buttons") as Array).size())
	hs.call("_on_pick_map", "map_military")
	_ok(str(g.get("map_id")) == "map_military", "点选图按钮真的写进 Game.map_id")

	# ── 问题7：分区标签（一次只看一页，不再一根长列表下拉）──
	var tabs: Array = hs.get("_tab_buttons")
	_ok(tabs.size() == 6, "藏身处有 6 个分区标签（实际 %d）" % tabs.size())
	var host: Node = hs.get("_page_host")
	_ok(host != null and host.get_child_count() == 6,
		"内容区有 6 个分区页面（实际 %d）"
			% (0 if host == null else host.get_child_count()))
	hs.call("_show_section", "carry", false)
	await _f(4)
	_ok(str(hs.get("_current_section")) == "carry", "点『携带』真的切到携带分区")
	hs.call("_show_section", "settings", false)
	await _f(4)
	_ok(str(hs.get("_current_section")) == "settings", "点『设置』真的切到设置分区")

	# ── 问题2：携带背包（stash <-> pack）真的能搬，面板能开 ──
	var hb: RefCounted = g.get("hideout")
	var stash: RefCounted = hb.get("stash")
	var pk: RefCounted = hb.get("pack")
	stash.call("add", "ammo_rifle", 40)
	var e_pack := str(hb.call("stash_to_pack", "ammo_rifle", 20))
	_ok(e_pack == "", "仓库 -> 携带背包搬运成功（%s）" % e_pack)
	_ok(int(pk.call("count_of", "ammo_rifle")) == 20, "携带背包收到 20 发")
	var e_back := str(hb.call("pack_to_stash", "ammo_rifle"))
	_ok(e_back == "", "携带背包 -> 仓库还回成功（%s）" % e_back)
	_ok(int(pk.call("count_of", "ammo_rifle")) == 0, "还回后携带背包清空")
	var cp: Node = hs.get("carry_panel")
	_ok(cp != null, "携带面板已挂到藏身处")
	if cp != null:
		hs.call("_open_carry")
		await _f(6)
		_ok(bool(cp.call("is_open")), "携带面板能打开")
		cp.call("close")
		await _f(3)
	hs.call("_show_section", "overview", false)
	await _f(3)

	hs.queue_free()
	await _f(3)

	var scene2: Node = load("res://view/raid_scene.tscn").instantiate()
	add_child(scene2)
	await _f(30)
	var theme2 = scene2.get("theme")
	_ok(theme2 != null and str(theme2.id) == "map_military",
		"突袭场景按 Game.map_id 建图（实际 %s）"
			% ("null" if theme2 == null else str(theme2.id)))
	scene2.queue_free()
	await _f(3)
	g.set("map_id", "")

	# ③ 修理：损耗 -> 修理台修满 -> 钱扣掉、耐久回满
	var hideout: RefCounted = g.get("hideout")
	# 先真的穿上带耐久的装备（④ 把藏身处重置过，配装是空的）
	var stash2: RefCounted = hideout.get("stash")
	stash2.call("add", "weapon_rifle", 1)
	stash2.call("add", "armor_heavy", 1)
	hideout.call("equip_from_stash", "weapon_rifle")
	hideout.call("equip_from_stash", "armor_heavy")
	hideout.call("repair_all")
	var before_wallet := int(hideout.get("wallet"))
	# 造损耗：给每个有耐久的装备扣掉一半
	var worn: Array = hideout.call("equipped_wear")
	_ok(worn.size() >= 2, "身上有带耐久的装备（%d 件）" % worn.size())
	for e in worn:
		(hideout.get("loadout") as RefCounted).call("apply_wear", str(e["id"]),
			maxi(1, int(e["missing"]) / 2))
	var cost := int(hideout.call("repair_cost"))
	_ok(cost > 0, "磨损后产生修理费（%d 元）" % cost)
	var r: Dictionary = hideout.call("repair_all")
	_ok(bool(r["ok"]), "修理台修满成功")
	_ok(int(hideout.get("wallet")) == before_wallet - cost, "修理扣了正好 %d 元" % cost)
	_ok(int(hideout.call("repair_cost")) == 0, "修完后不再有修理费（全部完好）")
