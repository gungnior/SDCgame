extends SceneTree

## B 阶段端到端演示 —— 完整跑一局「搜 → 打 → 撤」
##
## 运行：
##   godot --headless --path . --script res://test/sim_raid.gd
##
## 把地图生成 / 流场寻路 / 感知 / AI 状态机 / 战斗 / 背包 / 撤离结算
## 串成一条真实的回合，验证它们协同工作。


func _initialize() -> void:
	var reg := DataRegistry.new()
	if not reg.load_all("B"):
		print("数据加载失败")
		quit(1)
		return

	# ── ① 生成地图 ──
	var gen := MapGenerator.new()
	if not gen.generate(20261012, reg.room_types):
		print("地图生成失败")
		for e in gen.errors:
			print("  ", e)
		quit(1)
		return

	print("")
	print("╔══════════════════════════════════════════════════════╗")
	print("║  B 阶段端到端演示：一局完整的搜打撤                  ║")
	print("╚══════════════════════════════════════════════════════╝")
	print("")
	print("【① 地图】%s" % gen.summary())

	var spawn := gen.spawn_room()
	var extracts := gen.extract_rooms()
	print("        出生点 %s  ·  撤离点 %d 个" % [str(spawn.center), extracts.size()])

	# ── ② 流场 ──
	var flows := FlowFieldManager.new()
	flows.setup(gen.grid)
	print("【② 寻路】%s" % flows.stats())

	# ── ③ 回合开始 ──
	var rng := SimRng.new(777)
	var stash := Inventory.new(40, reg.items, 999.0)
	var raid := RaidSession.new(reg.items, rng, stash)
	raid.load_map(gen)
	raid.start(180.0)
	print("【③ 回合】%s" % raid.summary())

	# ── ④ 布置敌人：每个非出生房间放 def 允许的数量 ──
	var scav := reg.get_enemy("enemy_scav")
	var infected := reg.get_enemy("enemy_infected")
	var agents: Array = []
	var squad := Squad.new(1)
	var eid := 0
	for r in gen.graph.rooms:
		if r.room_type == "spawn":
			continue
		for i in r.enemy_budget:
			var d: EnemyDef = scav if (i % 2 == 0) else infected
			var a := EnemyAgent.new(eid, d, Ballistics.cell_center(r.center))
			if d.is_ranged():
				a.equip(reg.get_weapon("weapon_pistol"), 60)
			a.facing = Vector2(1, 0)
			squad.add_member(a)
			agents.append(a)
			eid += 1
	print("【④ 敌方】%d 名敌人，%s" % [agents.size(), squad])

	# ── ⑤ 模拟推进 ──
	var player_pos := Ballistics.cell_center(spawn.center)
	var player := {"id": "player", "pos": player_pos, "hp": 100}
	var targets := [player]
	var target_cell := extracts[0].center

	print("【⑤ 推进】玩家从出生点走向撤离点 %s" % str(target_cell))
	print("")

	var dt := 0.1
	var step := 0
	var noises: Array = []
	var max_steps := 2000
	var looted_rooms := {}
	var contact_reported := false

	while step < max_steps and not raid.is_over():
		step += 1
		var now := float(step) * dt

		# 玩家沿流场走
		# ⚠️ 必须用 sim 层的 step_toward（朝下一格中心走 + 防擦墙角）。
		#    之前写成「沿方向向量平移」，连续坐标会漂进墙里然后永久卡死 —— 实测踩过。
		var my_cell := Ballistics.cell_of(player_pos)
		player_pos = flows.step_toward(player_pos, target_cell, 2.5, dt)
		player["pos"] = player_pos

		# 到达一个房间就搜刮
		var room_here := _room_at(gen, my_cell)
		if room_here != null and not looted_rooms.has(room_here.id):
			looted_rooms[room_here.id] = true
			var table: LootTableDef = reg.get_loot_table(room_here.loot_table_id)
			if table != null:
				var res := raid.loot_container(table, room_here.depth, 1)
				# 搜刮会发出声响
				noises.append({"pos": player_pos, "loudness_m": 8.0})
				if step % 200 == 0:
					print("        [%5.1fs] 搜刮 %s：+%d 堆，价值 %d 元 | %s"
						% [now, room_here.room_type, res["drops"].size(), res["value"], raid.carry.summary()])

		# 敌人行动
		var ctx := {
			"grid": gen.grid, "flows": flows, "targets": targets,
			"rng": rng, "now": now, "noises": noises,
		}
		for a in agents:
			a.tick(dt, ctx)
		noises.clear()

		if not contact_reported and squad.is_engaged():
			contact_reported = true
			print("        [%5.1fs] ⚠ 被发现！小队进入交战，警戒 %.2f" % [now, squad.alert_level])

		raid.tick(dt, player_pos)

	print("")
	print("【⑥ 结果】")
	if raid.phase_name() == "EXTRACTED":
		print("        ✅ 撤离成功！用时 %.1f 秒，剩余 HP %d" % [raid.raid_seconds - raid.time_left, raid.hp])
	else:
		print("        ❌ %s（%s）" % [raid.phase_name(), raid.death_reason])

	var report := raid.settle()
	print("        搜刮容器     %d 个" % report["containers_looted"])
	print("        带出战利品   %d 堆，价值 %d 元" % [
		(report["brought_out"] as Array).size(), int(report["brought_out_value"])])
	print("        藏身处仓库   %s" % stash.summary())
	print("        流场缓存     %s" % flows.stats())

	var alive := 0
	var dead := 0
	for a in agents:
		if a.is_alive():
			alive += 1
		else:
			dead += 1
	print("        敌人        存活 %d / 阵亡 %d" % [alive, dead])
	print("")
	print("【⑦ 模拟规模】%d 步 x %.1fs = %.1f 秒游戏时间" % [step, dt, float(step) * dt])
	print("")

	quit(0)


func _room_at(gen: MapGenerator, cell: Vector2i) -> Room:
	for r in gen.graph.rooms:
		if r.rect.has_point(cell):
			return r
	return null
