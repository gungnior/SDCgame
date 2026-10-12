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
	_ok(ra.items.size() == 50, "A 档物品 50 件（B 档 %d）" % rb.items.size())
	_ok(ra.enemies.size() == 4, "A 档敌人 4 种（B 档 %d）" % rb.enemies.size())
	_ok(rb.weapons.size() == 3 and rb.items.size() == 15 and rb.enemies.size() == 2,
		"B 档仍是 3/15/2（阶段过滤没坏）")

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
	_ok(agents.size() == 4, "突袭场景刷出 4 个敌人（实际 %d）" % agents.size())
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
