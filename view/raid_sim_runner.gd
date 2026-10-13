class_name RaidSimRunner
extends RefCounted

## 模拟调度 —— 从 `view/raid_scene.gd` 抽出来
##
## 搬来的是四个**调用图闭合**的函数：
##   tick_player -> update_auto_aim / try_fire
##   tick_enemies
## （`update_auto_aim` 与 `try_fire` 只被前两个调用，所以一起搬才闭合。）
##
## ─── 这解决的是什么问题 ───
## `raid_scene.gd` 曾 1676 行，50% 的提交都要改它。
## 调 AI / 战斗手感 和 场景搭建 / UI 胶水 挤在同一个文件里，
## 两个人没法同时开工。现在前者在这个文件里，后者在场景里。
##
## ⚠️ 说清楚：这是**冲突面削减**，**不是内聚性改进** ——
##    本模块仍然通过 `scene.xxx` 读写同样的状态，耦合没变，
##    只是把"往哪儿写代码"分开了。
##
## ─── 为什么这个抽取可以被严格验证 ───
## 固定地图种子 + 固定 delta 后，第 300 帧的**像素**能验证**整个模拟**：
## 只要 tick 的行为有一点点不同，实体位置就会变，像素就不同。
## 这比验证渲染抽取还强（渲染只看一帧，模拟是累积的）。

## 宿主场景（RaidScene）。无类型：duck typing 读场景自定义成员。
var scene = null


func tick_player(delta: float) -> void:
	# 设置菜单打开时冻结玩家输入（摇杆/键盘都可能还在推着）
	if scene.game_paused:
		scene._move_input = Vector2.ZERO
		scene._firing = false
		return
	var prev = scene.player_pos

	# ── 每帧重置【玩家侧】流场预算 ──
	# 玩家的自动寻路用**自己的** FlowFieldManager：与敌人共用一本预算会互相挤占
	# （敌人那边每帧最多建 1 个场，玩家再抢一个就会让敌人退化成「朝目标直走」）。
	if scene.player_flows != null:
		scene.player_flows.begin_frame()

	# ── 闪避计时（位移在下面的移动分支里生效）──
	if scene.dodge != null:
		scene.dodge.tick(delta)

	# ── 自动作战：弹道来袭就闪避 ──
	var autopilot_on: bool = Game != null and Game.autopilot
	if autopilot_on:
		_try_auto_dodge()

	# 移动（治疗中不能动 —— reference-teardown §9 的取舍）
	# ⚠️ 闪避期间位移由闪避决定，**不与常规移动叠加** —— 否则「1.5 身位」就不准了。
	if scene.dodge != null and scene.dodge.is_active():
		_apply_player_step(scene.dodge.step(delta))
		scene.player_facing = scene.dodge.dir
		scene._move_input = Vector2.ZERO
	elif not scene.medical.is_treating():
		scene._move_input = scene._read_move_input()
		# ── 自动作战（2026-10-13 用户需求）──
		# 开着时由 PlayerAutopilot 决定往哪走，并**覆盖**摇杆/键盘输入 ——
		# 手动输入一律让位，避免人机抢方向盘。
		if autopilot_on and scene.autopilot != null:
			_tick_autopilot(delta)
		if scene._move_input != Vector2.ZERO:
			var step = scene._move_input.normalized() * scene.PLAYER_SPEED * scene.vitals.speed_multiplier(scene.raid.carry.weight_ratio()) * delta
			# 分轴碰撞：哪个轴撞墙就只撤销那个轴（闪避走的是同一个函数）
			_apply_player_step(step)
			scene.player_facing = scene._move_input.normalized()
			# 脚步：按节奏播放 + 发出声响给 AI 听觉
			# ⚠️ 2026-10-13：静步已删除 —— 脚步声**恒定**发出（不再有"无声慢走"）。
			scene._step_accum += delta * scene._move_input.length()
			var interval = 0.46 * lerpf(1.35, 1.0, clampf(scene.vitals.speed_multiplier(scene.raid.carry.weight_ratio()), 0.0, 1.0))
			if scene._step_accum >= interval:
				scene._step_accum = 0.0
				scene.noises.append({"pos": scene.player_pos, "loudness_m": scene.NOISE_QUIET})
				if Sfx != null:
					Sfx.play("step_%s" % scene._floor_material())
	else:
		scene._move_input = Vector2.ZERO

	# ── 瞄准方向 ──
	# ⚠️ 2026-10-13：**视角摇杆已按用户要求删除** —— 触屏端不再有瞄准输入，
	#    瞄准只来自「自动锁定」（AutoAim，全向）与桌面鼠标。
	if scene._mouse_aiming():
		var world = scene.get_global_mouse_position() / scene.CELL_PX
		var d = world - scene.player_pos
		if d.length() > 0.15:
			scene.player_aim = d.normalized()
			scene.player_facing = scene.player_aim
	elif scene._move_input != Vector2.ZERO:
		scene.player_facing = scene._move_input.normalized()

	# 换弹完成音（检测状态跳变）
	var was_reloading = scene.player_weapon.is_reloading()
	scene.player_weapon.tick(delta)
	if was_reloading and not scene.player_weapon.is_reloading():
		if Sfx != null:
			Sfx.play("reload_done")

	# ── 锥形视野 + 锁定 + 自动瞄准/自动射击（真机反馈 #4/#5）──
	update_auto_aim(delta)

	# 治疗推进
	if scene.medical.is_treating():
		var res = scene.medical.tick(delta, scene.vitals)
		if bool(res.get("done", false)):
			scene.raid.carry.remove(scene.medical.active_item_id if scene.medical.active_item_id != "" else "medical_bandage", 1)

	# 开火：键盘或触屏开火按钮（两者并联）
	# ⚠️ 早先只读 _firing（键盘），触屏开火按钮的 is_down 根本没人读 ——
	#    表现为"必须按屏幕任意处才能开火"（真机反馈）。
	# ⚠️ 2026-10-13：触屏开火键已删除 —— 手机端完全依赖「自动开火」（AutoAim 锁定即可开火）。
	var want_fire = scene._firing
	if want_fire and not scene.medical.is_treating():
		try_fire()

	# 流血
	if scene.vitals.tick(delta) > 0:
		pass


func try_fire() -> void:
	if not scene.player_weapon.can_fire():
		if scene.player_weapon.ammo_in_mag <= 0:
			if Sfx != null:
				Sfx.play("reload_empty")
			scene.player_weapon.start_reload()
			if Sfx != null:
				Sfx.play("reload_start")
		return

	scene.player_weapon.fire()
	# ── 装备损耗（2026-10-13）：每次开火磨损武器 1 点 ──
	# 磨损不改变能不能开火（那样会突然卡壳），只让伤害缓慢下降 —— 见
	# Equipment.weapon_damage_factor()（最低 ×0.6）。
	if scene.raid != null and scene.raid.equipment != null:
		scene.raid.equipment.wear_slot("weapon", 1)
	# 开枪声很大
	scene.noises.append({"pos": scene.player_pos, "loudness_m": scene.NOISE_LOUD})
	Tel.mark("fire")

	var w = scene.player_weapon.def

	# ── 枪械表现：音效 + 枪口火光 + 抛壳 ──
	Tel.mark("fire_sfx")
	if Sfx != null:
		Sfx.play("gun_%s_player" % scene._weapon_kind(w))
	Tel.mark("fire_fx")
	if scene.fx != null:
		# ⚠️ 不再喷枪口火光粒子 —— 火光已经由 _draw() 的星形多边形画了，
		#    粒子是重复的。真机实测：CPUParticles2D.restart() 在移动端很贵
		#    （enemy_fx 阶段测到过 25ms），能省一次就省一次。
		var side = Vector2(-scene.player_aim.y, scene.player_aim.x)
		scene.fx.burst("casing", scene.player_pos + side * 0.22 + scene.player_aim * 0.1, side, 1.0)
	# 自己开枪只给最轻的 kick（spec §7.3：不能每枪都大震）
	Tel.mark("fire_feel")
	Feel.hit("player_shoot")

	# ── 子弹磁性（T-56 首选：射线加粗，**不改准心**）──
	Tel.mark("fire_aim")
	var push = scene._aim_push()
	# ── 辅助范围与【枪械属性】挂钩（真机反馈 #6）──
	# 磁性锥 = 枪械视野锥 × 比例（狙击更窄、霰弹更宽）；
	# 磁性距离 = 枪械有效射程 × 比例。换枪 -> 辅助跟着变，不再是一个写死的常数。
	var half_angle = AimAssist.half_angle_for_weapon(w.aim_cone_deg,
		scene.get_viewport_rect().size.x)
	# ── 散布的作用：**收缩有效 hitbox**，而不是事后另掷一次随机数 ──
	# 见下方命中判定处的说明（真机反馈："子弹从他身上穿过去了"）。
	var extra_seed = scene.player_weapon.current_spread_deg() - w.spread_deg
	var eff_radius = AimAssist.DEFAULT_HIT_RADIUS * scene._spread_radius_factor(extra_seed)
	var assist = AimAssist.pick(scene.player_pos, scene.player_aim, push,
		scene._aim_targets(), scene.gen.grid, half_angle,
		AimAssist.assist_range(float(w.range_m)), "player", eff_radius)
	var shot_dir = scene.player_aim
	var tgt: EnemyAgent = null
	if not assist.is_empty():
		shot_dir = assist["dir"]
		tgt = assist["target"].get("agent")
	Tel.mark("fire_damage")

	var dist = float(w.range_m)
	if tgt != null:
		dist = scene.player_pos.distance_to(tgt.pos)

	var extra = scene.player_weapon.current_spread_deg() - w.spread_deg
	var acc = DamageModel.accuracy_at(w, dist, extra)
	# ⚠️⚠️ 这里【绝对不能再掷骰子】。
	#
	# 早先的写法是：AimAssist 找到目标 -> 再 `randf() <= 0.30 + acc*0.7` 决定是否命中。
	# 后果就是用户实测到的："准心明明在她身上，子弹却从她身上穿过去了" ——
	# 因为那一发恰好没过随机数，于是走 else 分支把曳光打到墙上。
	#
	# **双重判定本身就是错的**：pick() 已经做完了全部检查
	# （锥 / hitbox / 视线遮挡 / 射程 / 阵营），它返回目标 = 这一枪就是命中的。
	# 散布/精度改由 `_spread_radius_factor()` 在**进入 pick 之前**收缩有效 hitbox ——
	# 这样"瞄得准就真的打得中"，而散布大的枪仍然更难命中，逻辑只有一处。
	var shot_to = scene.player_pos + shot_dir * minf(maxf(dist, 2.0), float(w.range_m))

	if tgt != null:
		scene.player_weapon.mark_hit()
		# ── 弹药弹型 + 目标护甲（2026-10-13）──
		# 用【当前装的弹种】对【目标的护甲值】结算：
		#   穿甲弹打有甲单位更疼、肉伤弹打无甲单位更疼（见 data/SCHEMA.md §1）。
		var ammo: ItemDef = scene._player_ammo()
		var hit = DamageModel.resolve_hit_with_ammo(
			w, ammo, dist, extra, float(tgt.def.armor), scene._rng)
		# 武器磨损折损（全新 1.0 -> 完全损坏 0.6）
		var dmg = int(round(float(hit["damage"]) * scene._weapon_wear_factor()))
		var part = str(hit.get("part", DamageModel.PART_TORSO))
		var died = tgt.take_damage(dmg)
		scene.raid.damage_dealt += dmg
		shot_to = tgt.pos

		# ── 反馈分级（spec §7.3 的核心原则）──
		var lvl = "light"
		if died:
			lvl = "kill"
		elif part == DamageModel.PART_HEAD:
			lvl = "crit"
		elif dmg >= int(0.28 * float(w.damage) * 2.0):
			lvl = "heavy"
		Feel.hit(lvl, tgt.pos, scene.player_pos)
		if scene.fx != null:
			scene.fx.burst("blood_crit" if lvl == "crit" or lvl == "kill" else "blood",
				tgt.pos, shot_dir)
			if died:
				scene.fx.burst("kill", tgt.pos, shot_dir)
		if died:
			scene.raid.register_kill()
			# 真机反馈 #6：战利品进【尸体容器】而不是散落在地上，配合背包搜索
			scene._spawn_corpse(tgt)
			Tel.emit("kill", {"enemy": tgt.def.id, "part": part, "dmg": dmg,
				"dist": snappedf(dist, 0.1), "kills": scene.raid.enemies_killed})
	else:
		# 打空：子弹打到墙或射程边缘
		var wall: Variant = Ballistics.first_blocking_cell(scene.gen.grid, scene.player_pos, shot_to)
		if wall != null:
			shot_to = Vector2(wall.x + 0.5, wall.y + 0.5)
		if scene.fx != null:
			scene.fx.burst("impact", shot_to, -shot_dir)
		if Sfx != null and scene.player_pos.distance_to(shot_to) < 34.0:
			Sfx.play_at("hit_concrete", shot_to, scene.player_pos, 4.0, 22.0)

	scene.bullets.append({"from": scene.player_pos, "to": shot_to, "ttl": scene.TRACER_TTL, "own": true})
	scene.muzzle_flash.append({"pos": scene.player_pos, "dir": shot_dir, "ttl": 0.07})


## 武器类别 -> 音效后缀（gun_{kind}_player / _enemy）


func tick_enemies(delta: float) -> void:
	# 每帧重置流场构建预算。
	# ⚠️ 真机 profiler 实测：不限制时，玩家一移动会让多个敌人同帧各自建流场，
	#    AI 的 act 阶段冲到 32ms。现在每帧最多建 1 个，其余敌人本帧直走。
	scene.flows.begin_frame()
	# 出生宽限期：开局这几秒敌人不索敌（让玩家先看清地形）
	# 实测：没有它时玩家 3.3 秒就死，0 击杀（安卓真机遥测）
	var grace = scene._time < scene.GRACE_SECONDS
	var ctx = {
		"grid": scene.gen.grid,
		"scene.flows": scene.flows,
		"targets": [{"id": "player", "pos": scene.player_pos, "hp": scene.vitals.hp}],
		"rng": scene._rng,
		"now": scene._time,
		"scene.noises": scene.noises if not grace else [],
		"grace": grace,
		"hearing_cache": scene._hearing_cache,
		# 固定弹道：敌人把弹道交给它，伤害延后到「前沿扫过玩家」那一帧（见 LaneShotManager）
		"lane_shots": scene.lane_shots,
		# 性能探针（鸭子类型）—— 让 AI 内部也能打阶段标记，
		# 而 sim/ 不必依赖 Tel autoload
		"prof": Tel,
	}
	# ⚠️ 听觉：**按「噪声」建代价场**，而不是按敌人。
	#    噪声每帧只有 1~3 个且位置固定 -> 缓存命中率极高；
	#    敌人有 20+ 个且一直在动 -> 按敌人建场会不断重建。
	#    于是 28 个场/帧 变成 2~3 个场/帧，其余全是 O(1) 查表。
	#    （安卓 profiler 实测：未优化时 AI 阶段单帧 257ms）
	#    直接挂在噪声字典上，agent 侧接口不变（没有 field 时自动走退化路径）。
	if not grace:
		for nz in scene.noises:
			nz["field"] = scene._hearing_cache.field_for(scene.gen.grid, nz.get("pos", Vector2.ZERO))
	for a in scene.agents:
		if not a.is_alive():
			continue
		a.tick(delta, ctx)

		# ── 敌人开火的表现：枪声（mid distance 版，自带距离感）+ 枪口火光 ──
		var prev: int = int(scene._prev_shots.get(a.id, 0))
		if a.shots_fired > prev:
			scene._prev_shots[a.id] = a.shots_fired
			# 目前所有远程敌人都装的手枪（见 _setup_sim 的 equip 调用）
			var kind = scene._weapon_kind(a.weapon.def) if a.weapon != null else "pistol"
			Tel.mark("enemy_sfx")
			if Sfx != null:
				Sfx.play_at("gun_%s_enemy" % kind, a.pos, scene.player_pos, 7.0, 30.0)
			Tel.mark("enemy_fx")
			# 敌人枪口火光同样只靠 _draw 的多边形，不喷粒子（见上）
			# ⚠️ 2026-10-13：敌人不再画「瞬时曳光」—— 改由 LaneShotManager 的
			#    **固定弹道**绘制（一条看得见、躲得开的走廊 + 飞行弹头）。
			#    只保留枪口火光：它是「敌人开火了」的第一眼信号。
			scene.muzzle_flash.append({"pos": a.pos, "dir": a.facing, "ttl": 0.06})
	Tel.mark("enemy_done")

	# 敌人造成的伤害回写到 vitals
	var target_hp = int((ctx["targets"][0] as Dictionary)["hp"])
	if target_hp < scene.vitals.hp:
		_apply_player_damage(scene.vitals.hp - target_hp)

	# ── 固定弹道结算（2026-10-13 用户需求）──
	# 敌人不再「开火即扣血」：弹道要飞，扣血发生在前沿扫过玩家的那一帧。
	if scene.lane_shots != null:
		scene.lane_shots.tick(delta, scene.player_pos)
		for hit_pos in scene.lane_shots.impacts:
			if scene.fx != null:
				scene.fx.burst("impact", hit_pos, Vector2.UP)
		var lane_damage = scene.lane_shots.consume_damage()
		if lane_damage > 0:
			if scene.dodge != null and scene.dodge.is_invulnerable():
				# 无敌帧：这一发被闪开了（走廊里唯一可行的躲法，见 DodgeState 的说明）
				scene.dodge.note_blocked(lane_damage)
				if Sfx != null:
					Sfx.play("ui_confirm")
			else:
				_apply_player_damage(lane_damage)

	scene.noises.clear()
	scene.squad.tick(delta, scene._time)

	# ── 群体协同：包夹角色分配 + 跨小队警戒扩散 ──
	# 角色要跟着"谁离得近"变，所以每隔一小段时间重分一次
	# （每帧排一次太浪费，4 个成员排 0.4 秒一次完全够）。
	if scene.squad.is_engaged():
		scene._roles_cooldown -= delta
		if scene._roles_cooldown <= 0.0:
			scene._roles_cooldown = scene.SQUAD_ROLES_INTERVAL
			scene.squad.assign_roles(scene.player_pos)
			if Tel != null:
				var parts: Array[String] = []
				for a in scene.agents:
					if a.is_alive():
						parts.append(scene.squad.role_name(a))
				Tel.emit("squad_roles", {"roles": parts,
					"alert": snappedf(scene.squad.alert_level, 0.01)})


## 锥形视野 / 锁定 / 自动瞄准 / 自动射击
##
## 规格见 sim/combat/auto_aim.gd 的注释（用户真机反馈 #5 原文）。
## 三个开关都在 Game（跨场景持久）里：
##   auto_fire          自动射击（锁定最近敌人并自动开火）
##   auto_aim           未开自动射击时，准心自动对准锁定目标
##   vision_follows_lock 视野锥跟随锁定目标（而不是只跟摇杆）
func update_auto_aim(delta: float) -> void:
	# 自动作战：锁定改为**全向**（用户需求「自动锁定敌人进行攻击」）。
	# 手动模式下仍受视野锥硬门限约束 —— 那条约束是给「人瞄」的公平性保障，
	# 自动作战没有「瞄准方向」这个概念，所以只保留视线与阵营两条硬原则。
	var autopilot_on: bool = Game != null and Game.autopilot
	var w = scene.player_weapon.def
	# ⚠️ 用场景的**有效**视野锥（= 枪械锥 ∩ 玩家视野锥门限），不要直接用
	#    w.aim_cone_deg —— 否则逻辑能锁的范围会和画出来的锥不一致
	#    （真机反馈 #1："朝上瞄却锁到下方敌人"就是这么漏出来的）。
	var cone = scene.aim_cone_deg()
	var rng_max = float(w.range_m)

	# 视野锥的朝向：跟随锁定时用锁定方向，否则用玩家瞄准方向
	var cone_dir = scene.player_aim
	if Game != null and Game.vision_follows_lock and scene.auto_aim.has_lock():
		var to_lock: Vector2 = scene.auto_aim.locked_pos - scene.player_pos
		if to_lock.length() > 0.01:
			cone_dir = to_lock.normalized()

	scene._lock_info = scene.auto_aim.update(delta, scene.player_pos, cone_dir, cone,
		rng_max, scene._aim_targets(), scene.gen.grid, "player",
		AutoAim.DEFAULT_RADIUS, autopilot_on)

	# ① 自动瞄准：把准心平滑转到锁定目标
	#    自动作战时无条件开启（否则「自动锁定」只是锁上、枪口不跟过去）
	if Game != null and (Game.auto_aim or autopilot_on) and scene.auto_aim.has_lock():
		var to_t: Vector2 = scene.auto_aim.locked_pos - scene.player_pos
		if to_t.length() > 0.01:
			# 每秒最多转 AUTO_AIM_TURN_DEG 度 —— 避免"瞬移式"甩枪（手感很假）
			scene.player_aim = AutoAim.turn_toward(scene.player_aim, to_t, scene.AUTO_AIM_TURN_DEG * delta)
			if autopilot_on:
				scene.player_facing = scene.player_aim

	# ② 自动射击：**必须当前可见**（不能用锁定粘性）
	#
	# ⚠️ 用户实测："会导致透视到敌人对墙开火"。
	#    粘性（1.2 秒）是为了让【瞄准】不抖，但敌人躲到墙后时
	#    has_lock 仍为 true -> 自动射击会朝墙打满 1.2 秒。
	#    所以这里判定用 `visible`（这一帧真有视线），不是 has_lock。
	if Game != null and (Game.auto_fire or autopilot_on) and bool(scene._lock_info.get("visible", false)):
		if not scene.medical.is_treating():
			try_fire()



# ═══════════════ 自动作战 / 闪避 / 固定弹道的落地（2026-10-13）═══════════════
#
# 决策都在 sim/ 里（PlayerAutopilot / DodgeState / LaneShotManager，可 headless 单测），
# 这里只负责把决策**接到场景上**：读场景状态、写玩家位置、结算护甲、播表现。
# 这是本项目既有的分工（「AI / 战斗手感调参在 raid_sim_runner.gd」）。

## 玩家位移：分轴碰撞（哪个轴撞墙就只撤销那个轴）。
## 常规移动与闪避共用它 —— 这样「闪避穿墙」在结构上不可能发生。
func _apply_player_step(step: Vector2) -> void:
	if step == Vector2.ZERO:
		return
	var try_x = Vector2(scene.player_pos.x + step.x, scene.player_pos.y)
	if scene._walkable(try_x):
		scene.player_pos.x = try_x.x
	var try_y = Vector2(scene.player_pos.x, scene.player_pos.y + step.y)
	if scene._walkable(try_y):
		scene.player_pos.y = try_y.y


## 自动作战：问一次决策（寻路 / 搜刮 / 交战），把结果落到玩家身上。
func _tick_autopilot(delta: float) -> void:
	var ap: PlayerAutopilot = scene.autopilot
	var ctx := {
		"grid": scene.gen.grid,
		"flows": scene.player_flows,
		"player_pos": scene.player_pos,
		"enemies": _autopilot_enemies(),
		"containers": _autopilot_containers(),
		"corpses": _autopilot_corpses(),
		"now": scene._time,
	}
	var decision := ap.update(delta, ctx)
	scene._move_input = decision.get("move", Vector2.ZERO)
	var loot: Dictionary = decision.get("loot", {})
	if not loot.is_empty():
		_autopilot_loot(loot)


func _autopilot_enemies() -> Array:
	var out: Array = []
	for a in scene.agents:
		if not a.is_alive():
			continue
		out.append({"pos": a.pos, "alive": true})
	return out


func _autopilot_containers() -> Array:
	var out: Array = []
	for c in scene.raid.containers:
		out.append({"pos": c.pos, "done": c.is_done()})
	return out


func _autopilot_corpses() -> Array:
	var out: Array = []
	for c in scene.raid.corpses:
		out.append({
			"pos": c.get("pos", Vector2.ZERO),
			"done": (c.get("drops", []) as Array).is_empty(),
		})
	return out


## 走到搜索目标旁边 -> 自动把里面的东西全部拿走。
## ⚠️ 不打开背包面板：面板会冻结模拟与输入，而自动作战要一路走到底。
##    背包塞不下就拉黑这个目标一会儿，免得在同一个箱子前面反复尝试。
func _autopilot_loot(req: Dictionary) -> void:
	var kind := str(req.get("kind", ""))
	var idx := int(req.get("index", -1))
	if idx < 0:
		return
	var rest: Array = []
	if kind == "container":
		rest = scene.raid.take_all_from_container(idx)
	else:
		rest = scene.raid.take_all_from_corpse(idx)
	scene.autopilot.note_done(kind, idx)
	var leftover := 0
	for d in rest:
		leftover += int(d.get("count", 0))
	if leftover > 0:
		scene.autopilot.blacklist(kind, idx)
		scene._toast("背包已满，先跳过这个搜索目标")
	elif Sfx != null:
		Sfx.play("pickup")


## 自动闪避的提前量（秒）：弹道还要多久到达，决定了「来不来得及躲」。
const AUTO_DODGE_LOOKAHEAD := 0.30


## 自动闪避：弹道即将命中时，朝**垂直弹道方向**闪开。
## 走廊里两侧都是墙（_walkable 两边都 false）—— 位移会被碰撞吃掉，
## 真正救命的是 DodgeState 的无敌帧（原因见那个文件的说明）。
func _try_auto_dodge() -> void:
	if scene.dodge == null or scene.lane_shots == null:
		return
	if not scene.dodge.can_start():
		return
	var shot: LaneShot = scene.lane_shots.incoming(scene.player_pos,
		AUTO_DODGE_LOOKAHEAD, BodyMetrics.BODY_WIDTH * 0.5)
	if shot == null:
		return
	var side := Vector2(-shot.dir.y, shot.dir.x)
	if not scene._walkable(scene.player_pos + side * 0.6):
		side = -side
	if scene.dodge.start(side):
		if Sfx != null:
			Sfx.play("ui_click")


## 玩家受伤的**唯一**入口（近战回写与固定弹道两条通道都走这里）。
## 护甲结算仍然只有一处：RaidScene._resolve_player_hit。
func _apply_player_damage(dealt: int) -> void:
	if dealt <= 0:
		return
	var applied = scene._resolve_player_hit(dealt)
	if scene.medical.should_interrupt(applied):
		scene.medical.cancel()
	if applied <= 0:
		return
	var heavy = applied >= 20
	scene.vitals.apply_bleed(Vitals.Bleed.HEAVY if heavy else Vitals.Bleed.LIGHT)
	# ── 自己受伤：大闪白 + 大震动，但【零 hitstop】（不打断操作）──
	Feel.hit("player_hurt", scene.player_pos, scene.player_pos)
	Feel.flash_damage(0.45 if heavy else 0.28)
	if heavy:
		if applied >= 35 and Sfx != null:
			Sfx.play("hurt_heavy")
