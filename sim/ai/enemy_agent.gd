class_name EnemyAgent
extends RefCounted

## 敌人个体：状态机 + 效用评分 + 流场移动
##
## 依据 specs/tech-stack.md §4.6/§4.7：
##   ⚠️ 不用 GOAP / 行为树起步 —— AI 生成的行为树代码难调试，出 bug 时像黑盒。
##   用【状态机 + 效用评分】更可控、更好单测。
##
## 感知两级粗筛（T-84）：距离²+点积 → 格子遮挡
## 移动用共享流场（T-81），不各自跑 A*
## reaction_time 是公平感的关键数值（reference-teardown.md §7）
##
## ── 2026-10-13 用户需求：远程攻击改成【固定弹道】──
## 用户原文：「敌人的攻击为固定弹道，宽度为两倍人物判定身位，会固定锁定人物为中心，
##            即人物两侧的弹道均为 1 格人物身位。」
## 于是 _fire_at 从 hitscan + 掷骰子改成放出一条 LaneShot：
##   · 方向在开火瞬间锁死（不追踪）   · 半宽 = 1 身位（两侧各 1 身位）
##   · 命中在「前沿扫过目标」时结算 -> 飞行时间就是玩家的闪避窗口
## 数值来源统一在 BodyMetrics（不许在这里写死 0.9）。
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。

enum State { IDLE, ALERT, COMBAT, SEARCH, DEAD }

const STATE_NAME := {
	State.IDLE: "IDLE",
	State.ALERT: "ALERT",
	State.COMBAT: "COMBAT",
	State.SEARCH: "SEARCH",
	State.DEAD: "DEAD",
}

## ── IDLE 行为：巡视 + 轻量游走（2026-10-13 修「敌人 AI 不生效」）──
#
# ⚠️ 这是本轮真机反馈 #1 的**根因修复**，先把证据写在这里：
#
#   诊断脚本 `_install/tmp/ai_probe.gd` 复刻了 raid_scene 的生成 + 逐帧 tick：
#     · 玩家站着不动 30 秒：森林 0/16、城区 0/35、军事基地 0/54 个敌人
#       **没有任何一个**改变过位置或状态（全部 IDLE）。
#     · 把每个敌人的 facing 强行指向玩家再跑 3 秒：立刻有敌人进 COMBAT。
#   => 视野锥完全由 `facing` 决定，而 IDLE 时**朝向从不改变** ——
#      于是除非玩家恰好走进某个敌人出生时的那个固定朝向里，
#      这个敌人这辈子都不会发现玩家 = 玩家眼里的"雕像敌人 / AI 没生效"。
#
#   修法两条，都便宜且**完全确定性**（rng 一律走注入的 SimRng，见 T-32）：
#     ① 巡视：IDLE 时按固定角速度转朝向 -> 约 5.8 秒扫满一圈
#     ② 游走：每隔几秒在附近挑一个**可走格**走两步，房间不再死气沉沉
## 巡视角速度（度/秒）
const IDLE_SCAN_DEG_PER_SEC := 62.0
## 两次游走之间的间隔（秒，随机区间）
const IDLE_WANDER_MIN_SEC := 2.6
const IDLE_WANDER_MAX_SEC := 5.4
## 游走半径（逻辑格）—— 刻意很小，让敌人留在自己的房间里
const IDLE_WANDER_RADIUS := 2.6
## 抵达判定容差（逻辑格）
const IDLE_ARRIVE_TOL := 0.35

## 近战进入攻击的距离（逻辑格）
const MELEE_RANGE_CELLS := 1.2
## 远程敌人希望保持的距离（逻辑格）
const RANGED_PREFERRED_MIN := 5.0
const RANGED_PREFERRED_MAX := 9.0
## 失去视野后继续搜索的时长
## 被【同队】的接触/噪声惊动后，压向最后已知位置的持续时间
const SQUAD_ALERT_DURATION := 7.0
const SEARCH_DURATION := 8.0

## ⭐ 可玩性 Step4 + 平衡轮（2026-10-16）：**已经惊动过的敌人反应更快**。
## 设计意图：第一次撞见要"愣一下"（那是公平感），但既然已经交火或听到动静，
## 后面就不该每次都重新愣 —— 否则玩家打完一轮就能白嫖一整个反应窗口，
## 潜行与莽撞在代价上毫无区别。
## ⚠️ 已拍板（平衡轮）：惊动后反应 = 45% 基线。配合下方敌人倍率上调，
##    让"被抓包"的代价真实化（门 1 难度偏低的缺口之一）。
const ALERTED_REACTION_MUL := 0.45
## 敌人命中修正（度）：从散布里扣掉，缓解"远距离根本打不中人"。
## 门 1 硬证据：拾荒者杀玩家要 7.5 秒，玩家杀拾荒者只要 0.3 秒（碾压约 25 倍）。
## ⚠️ 已拍板（平衡轮 2026-10-16）：+1.5° 修正 —— 手枪(1.5°)归零散布、步枪(0.8°)更稳，
##    让敌人威胁从"几乎打不中"变成"被抓包会掉血"。实战仍受可闪避弹道稀释。
const AIM_SPREAD_BONUS_DEG := 1.5

var id: int = 0
var def: EnemyDef = null
var pos: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.RIGHT
var hp: int = 1
var state: int = State.IDLE

var squad: Squad = null
var weapon: WeaponState = null

var reaction_timer: float = 0.0     ## >0 表示"发现了但还没开火"（公平感）
var attack_cooldown: float = 0.0
var search_timer: float = 0.0
var alert_timer: float = 0.0
var target_pos: Vector2 = Vector2.ZERO   ## 当前想去的位置
var last_seen_pos: Vector2 = Vector2.ZERO
var move_dir: Vector2 = Vector2.ZERO

## IDLE 巡视/游走状态（见文件头的说明）
var idle_timer: float = 0.0              ## 距离下次挑游走点的秒数
var idle_left: float = 0.0               ## 本次游走的剩余时长
var wander_target: Vector2 = Vector2.ZERO
var wandering: bool = false

## 统计（测试与调参用）
var shots_fired: int = 0
var damage_dealt: int = 0


func _init(eid: int = 0, d: EnemyDef = null, start: Vector2 = Vector2.ZERO) -> void:
	id = eid
	def = d
	pos = start
	target_pos = start
	last_seen_pos = start
	if def != null:
		hp = def.hp


func set_squad(s: Squad) -> void:
	squad = s


func is_alive() -> bool:
	return state != State.DEAD


func state_name() -> String:
	return STATE_NAME.get(state, "?")


## 装上武器。远程敌人必须装，否则 _fire_at() 会直接返回（打不出子弹）。
func equip(w: WeaponDef, reserve: int = 60) -> void:
	weapon = WeaponState.new(w, reserve)


## 受伤。返回值语义：【true = 这一下把它打死了】，不是"是否受到了伤害"。
func take_damage(amount: int) -> bool:
	if not is_alive():
		return false
	hp -= amount
	if hp <= 0:
		hp = 0
		state = State.DEAD
		move_dir = Vector2.ZERO
		if squad != null:
			squad.report_casualty()
		return true
	return false


## 主循环。
## ctx 需要提供：
##   grid   : LogicalGrid
##   flows  : FlowFieldManager
##   targets: Array（元素是 {id, pos, hp}，元素被原地修改以施加伤害）
##   rng    : SimRng
##   now    : float（秒）
func tick(delta: float, ctx: Dictionary) -> void:
	if not is_alive() or def == null:
		return

	var grid: LogicalGrid = ctx.get("grid")
	var flows: FlowFieldManager = ctx.get("flows")
	var targets: Array = ctx.get("targets", [])
	var rng: SimRng = ctx.get("rng")
	var now: float = ctx.get("now", 0.0)

	reaction_timer = maxf(0.0, reaction_timer - delta)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if weapon != null:
		weapon.tick(delta)

	# ── ⭐ 出生宽限期 ──
	# 实测（安卓真机 + 遥测）：玩家 3.3 秒就死了，0 击杀。
	# 原因：出生安全区只挡住了【生成位置】，没挡住【视野】——
	#   scav 视距 22 格，而地图只有 27x27，出生点几乎全图都在敌人视野内。
	#   5 个敌人同时开火 => 约 4.5 次命中/秒 => 15 发打死 => 3.3 秒。
	#   计算：100HP + 40 护甲 ≈ 挨 15 发；15 / 4.5 = 3.3 秒（与实测吻合）。
	# 所以开局给一段"敌人还没注意到你"的时间，让玩家能先看清地形。
	if bool(ctx.get("grace", false)):
		if state == State.COMBAT or state == State.ALERT:
			state = State.IDLE
		return

	# ── 感知：先看，再听 ──
	# prof：可选的性能探针（由调用方从 ctx 传入）。
	# 用鸭子类型而不是直接引用 Tel autoload —— 否则 sim/ 会依赖视图层，
	# 导致 headless 测试编译失败（实测踩过：Identifier not found: Sfx）。
	var prof: Variant = ctx.get("prof")
	_mark_prof(prof, "ai_see")
	var seen := _find_visible_target(grid, targets)
	if not seen.is_empty():
		var sp: Vector2 = seen["pos"]
		last_seen_pos = sp
		target_pos = sp
		if state != State.COMBAT:
			# 刚发现：进入反应延迟（reaction_time 决定公平感）
			reaction_timer = def.reaction_time * reaction_mul()
			state = State.COMBAT
			if squad != null:
				squad.report_contact(sp, now)
	elif state == State.COMBAT:
		# 失去视野 → 转为搜索
		state = State.SEARCH
		search_timer = SEARCH_DURATION
		if squad != null:
			squad.report_lost_contact(now)

	# ── 听觉（只在非交战时才需要，交战中已经知道位置）──
	if state != State.COMBAT and state != State.SEARCH:
		_mark_prof(prof, "ai_hear")
		var noise := _find_audible_noise(grid, ctx.get("noises", []),
			ctx.get("hearing_cache"))
		if not noise.is_empty():
			var np: Vector2 = noise["pos"]
			last_seen_pos = np
			target_pos = np
			alert_timer = 6.0
			state = State.ALERT
			if squad != null:
				squad.report_noise(np, now)
	_mark_prof(prof, "ai_act")

	# ── ⭐ 小组警戒扩散：别人发现了，我也该压过去 ──
	#
	# 这就是"群体协同"的落地。早先 `Squad.alert_level` 只被 HUD 读去显示颜色，
	# **从不影响任何敌人行为** —— 所以"群体 AI"实际上只是各自为战。
	# 现在：同队有人报告接触/噪声后，其余成员即使自己没看见，
	# 也会朝 squad.last_known_pos 压过去。
	if state == State.IDLE and squad != null:
		var fresh := (now - squad.last_known_time) <= Squad.CONTACT_MEMORY_SEC
		if fresh and (squad.has_contact or squad.is_alerted()):
			last_seen_pos = squad.last_known_pos
			target_pos = squad.last_known_pos
			alert_timer = SQUAD_ALERT_DURATION
			state = State.ALERT

	# ── 状态行为 ──
	match state:
		State.IDLE:
			_idle(delta, flows, rng, grid)
		State.ALERT:
			alert_timer -= delta
			_move_toward(flows, target_pos)
			if alert_timer <= 0.0:
				state = State.IDLE
				move_dir = Vector2.ZERO
		State.SEARCH:
			search_timer -= delta
			_move_toward(flows, last_seen_pos)
			if search_timer <= 0.0:
				state = State.IDLE
				move_dir = Vector2.ZERO
		State.COMBAT:
			_combat(delta, targets, rng, seen, grid, ctx)
		State.DEAD:
			pass

	# ── 位移（表现层只读 move_dir 与 pos）──
	if move_dir != Vector2.ZERO:
		pos += move_dir * def.move_speed * delta
		facing = facing.lerp(move_dir, 0.35).normalized()
	elif not seen.is_empty():
		var to_t: Vector2 = (seen["pos"] - pos)
		if not to_t.is_zero_approx():
			facing = to_t.normalized()


# ─────────────────── IDLE（巡视 + 游走）───────────────────
#
# 见文件头「IDLE 行为」的说明。两件事都在这里做：
#   ① 转朝向（视野锥扫起来）—— 这是"敌人能不能发现玩家"的开关
#   ② 偶尔在附近走两步 —— 这是"房间看起来有没有人"的观感来源
#
# ⚠️ 巡视**必须放在感知之后**（tick 里的顺序：感知 -> 状态行为）。
#    否则会出现"玩家明明走进视野、却被本帧的巡视转开了"的随机感。
func _idle(delta: float, flows: FlowFieldManager, rng: SimRng, grid: LogicalGrid) -> void:
	# ① 巡视：游走时才让朝向交给移动方向（见 tick 末尾）
	if not wandering:
		facing = facing.rotated(deg_to_rad(IDLE_SCAN_DEG_PER_SEC) * delta)
		if facing.is_zero_approx():
			facing = Vector2.RIGHT

	# ② 游走：正在走 -> 到点或超时就停
	if wandering:
		idle_left -= delta
		if idle_left <= 0.0 or pos.distance_to(wander_target) <= IDLE_ARRIVE_TOL:
			wandering = false
			move_dir = Vector2.ZERO
			return
		_move_toward(flows, wander_target)
		return

	# ③ 站着不动：等冷却，到点就挑一个新目标
	move_dir = Vector2.ZERO
	if rng == null or grid == null:
		return                  # 没有 rng/grid（部分单测的 ctx 很简陋）-> 只巡视，不游走
	idle_timer -= delta
	if idle_timer > 0.0:
		return
	idle_timer = rng.randf_range(IDLE_WANDER_MIN_SEC, IDLE_WANDER_MAX_SEC)
	var t := _pick_wander_cell(grid, rng)
	if t == Vector2.ZERO:
		return                  # 四面都是墙（角落）-> 这次放弃，下次再说
	wander_target = t
	wandering = true
	idle_left = rng.randf_range(IDLE_WANDER_MIN_SEC, IDLE_WANDER_MAX_SEC)


## 在附近挑一个**可走**格作为游走目标。找不到返回 Vector2.ZERO。
##
## ⚠️ 半径故意小（IDLE_WANDER_RADIUS）：敌人应该"在自己的房间里踱步"，
##    而不是慢慢漂到地图另一头（那会让房间空掉，反而更像 AI 坏了）。
func _pick_wander_cell(grid: LogicalGrid, rng: SimRng) -> Vector2:
	var base := Ballistics.cell_of(pos)
	for _i in 12:
		var ang := rng.randf_range(0.0, TAU)
		var rad := rng.randf_range(1.0, IDLE_WANDER_RADIUS)
		var c := Vector2i(base.x + int(round(cos(ang) * rad)),
			base.y + int(round(sin(ang) * rad)))
		if c == base:
			continue
		if grid.is_walkable(c):
			return Ballistics.cell_center(c)
	return Vector2.ZERO


# ─────────────────── 感知 ───────────────────

func _find_visible_target(grid: LogicalGrid, targets: Array) -> Dictionary:
	for t in targets:
		var tp: Vector2 = t.get("pos", Vector2.ZERO)
		if Perception.can_see(grid, pos, facing, tp, def):
			return t
	return {}


func _find_audible_noise(grid: LogicalGrid, noises: Array,
		cache: HearingFieldCache = null) -> Dictionary:
	if noises.is_empty():
		return {}
	# ⭐ 首选路径：噪声侧已经预先建好代价场（场景每帧挂在 noise["field"] 上），
	#    这里对每个噪声只做一次 O(1) 查表。
	#    （安卓 profiler 实测：不这样做时单帧 AI 阶段 257ms）
	if noises[0].get("field") != null:
		for nz in noises:
			var f: PackedInt32Array = nz.get("field")
			if f.is_empty():
				continue
			var loud: float = float(nz.get("loudness_m", 0.0))
			var reach := minf(float(def.hear_range_m), loud) if def != null else loud
			if Perception.can_hear_at(f, grid, pos, reach):
				return nz
		return {}

	# 退化路径（测试/工具）：单次全图 Dijkstra。**只对第一个噪声做**，避免退化爆炸。
	var nz0: Dictionary = noises[0]
	var np0: Vector2 = nz0.get("pos", Vector2.ZERO)
	var loud0: float = float(nz0.get("loudness_m", 0.0))
	var reach0 := minf(float(def.hear_range_m), loud0) if def != null else loud0
	if cache != null:
		var field := cache.field_for(grid, np0)
		return nz0 if Perception.can_hear_at(field, grid, pos, reach0) else {}
	var f0 := Perception.hearing_field(grid, np0)
	return nz0 if Perception.can_hear_at(f0, grid, pos, reach0) else {}


# ─────────────────── 战斗 ───────────────────

func _combat(delta: float, targets: Array, rng: SimRng, seen: Dictionary, grid: LogicalGrid,
		ctx: Dictionary) -> void:
	var dist := pos.distance_to(target_pos)

	# ── ⭐ 包夹：不直接冲玩家，而是冲自己那个"包夹位" ──
	#
	# 早先每个敌人**各自朝玩家直线压过去** -> 挤成一坨，毫无战术感。
	# 现在由 Squad 分发角色（正面 / 左翼 / 右翼 / 压制），
	# 每个人赶赴目标方位上的一个点，形成交叉火力。
	# 没有小队时退化为原来的直冲。
	var goal := target_pos
	if squad != null:
		goal = squad.goal_for(self, target_pos)
		# ⭐ W-06：包夹点可能落在墙里（1 格宽走廊里 ±58°×3.2 偏移会进墙带）。
		#    远程 _combat 直接施加 move_dir，不查墙 → 侧翼逻辑坐标穿进墙格。
		#    把目标点夹到最近的可行走逻辑格，保证直线移动目标永远合法。
		if grid != null:
			goal = _snap_walkable(grid, goal)

	if def.is_ranged():
		# 保持距离：太近后退、太远靠近、合适则原地
		var dir_to := (goal - pos)
		var d_goal := dir_to.length()
		if d_goal > RANGED_PREFERRED_MAX * 0.5:
			move_dir = dir_to.normalized()
		elif dist < RANGED_PREFERRED_MIN:
			# 玩家贴脸了：即使要后退也优先拉开，否则等于送
			move_dir = -(target_pos - pos).normalized()
		else:
			move_dir = Vector2.ZERO

		# 反应时间没走完不开火（这是"公平感"的关键）
		if reaction_timer > 0.0 or attack_cooldown > 0.0:
			return
		if seen.is_empty():
			return
		_fire_at(targets, dist, rng, ctx, grid)
	else:
		# 近战：贴身。有包夹位就先绕到包夹位，到位了再扑
		var to_goal := goal - pos
		if squad != null and not squad.at_post(self, target_pos):
			move_dir = to_goal.normalized() if to_goal.length() > 0.0001 else Vector2.ZERO
			return
		move_dir = (target_pos - pos).normalized() if dist > 0.0001 else Vector2.ZERO
		if dist <= MELEE_RANGE_CELLS and attack_cooldown <= 0.0 and reaction_timer <= 0.0:
			attack_cooldown = def.attack_cooldown
			_deal_damage_to_nearest(targets, def.damage)


## ⭐ 已被惊动时反应更快（可玩性 Step4）。ALERTED_REACTION_MUL 待平衡专家定夺。
func reaction_mul() -> float:
	if squad != null and (squad.has_contact or squad.is_alerted()):
		return ALERTED_REACTION_MUL
	return 1.0


func _fire_at(targets: Array, dist: float, rng: SimRng, ctx: Dictionary,
		grid: LogicalGrid) -> void:
	if weapon == null or not weapon.can_fire():
		return
	var tgt := _nearest_target(targets)
	if tgt.is_empty():
		return                                  # 没有目标就不放弹道（省一条无主弹道）

	# ── 同时开火节流（B 方案，2026-10-13）──
	# 配额不足就**这一帧不开火**：不消耗武器冷却、不计 shots_fired，下个 tick 再试。
	# 放在 weapon.fire() **之前**，为了让节流表现为"延迟"而不是"打空"。
	# lane_shots 是 sim 层自己的类（有 class_name）→ 强类型接，`as` 失败得 null
	# （调用方没给/给错类型时自然落进下方兼容路径，与改造前行为一致）。
	var throttle := ctx.get("lane_shots") as LaneShotManager
	if throttle != null and not throttle.can_spawn():
		return

	weapon.fire()
	shots_fired += 1
	attack_cooldown = def.attack_cooldown

	# 伤害与部位仍走 DamageModel 的概率部位模型（T-52）
	# ⭐ 敌人命中修正（可玩性 Step4）：散布减去 AIM_SPREAD_BONUS_DEG。
	#    远距离散布是敌人"打不中人"的主因 —— 门 1 实测拾荒者杀玩家要 7.5 秒。
	var extra := weapon.current_spread_deg() - weapon.def.spread_deg - AIM_SPREAD_BONUS_DEG
	var hit := DamageModel.resolve_hit(weapon.def, dist, extra, rng)
	var damage := int(hit["damage"])

	# ── 兼容路径 ──
	# 没有弹道管理器的调用方（headless 单测 / 工具脚本）保持改造前的即时结算，
	# 否则「没有管理器」会退化成敌人完全打不出伤害 —— 那是更难查的坑。
	#
	# ⚠️ 移除条件（AGENTS.md §4.5「兜底必须写移除条件」）：
	#    当 `test/suites/s25_auto_combat.gd::_test_enemy_lane_fire` 里那条
	#    「没有管理器也照常开火」的兼容用例被删掉时（意味着所有调用方都必带 lane_shots），
	#    连同本分支一起删除，并让"缺 manager"成为显式错误。
	var mgr := ctx.get("lane_shots") as LaneShotManager
	if mgr == null:
		var acc := DamageModel.accuracy_at(weapon.def, dist, extra)
		if rng.randf() > clampf(0.35 + acc * 0.6, 0.05, 0.95):
			return   # 打空
		weapon.mark_hit()
		_apply_damage(tgt, damage)
		return

	# ── 固定弹道（2026-10-13 用户需求）──
	# 方向 = 开火瞬间指向目标中心，之后**永不改变**（不追踪、不修正）；
	# 命中在弹道前沿「扫过目标」时结算（见 LaneShotManager），不是开火这一帧。
	var tp: Vector2 = tgt.get("pos", Vector2.ZERO)
	var to_t := tp - pos
	if to_t.length() <= 0.0001:
		return
	var dir := to_t.normalized()
	# 弹道长度 = min(武器射程, 撞墙前的距离)。墙不会动，所以开火时算一次就够。
	var length := float(weapon.def.range_m)
	if grid != null:
		length = minf(length, Ballistics.los_distance(grid, pos, dir, length))
	# ── 开火前预警（A 方案，2026-10-13）──
	# 预警按「弹道真正要飞多远」反推：贴脸自动获得更长预警，远处几乎不加。
	var reach := minf(length, to_t.length())
	var warn := LaneShot.warn_for(reach, LaneShot.DEFAULT_SPEED)
	mgr.spawn(pos, dir, LaneShot.DEFAULT_SPEED, damage, length, id, weapon.def.id, warn)


## 性能探针打点（**受控的鸭子类型**，2026-10-16 收口）。
##
## 为什么不是强类型接口：探针实体是 Tel autoload（Node），而 sim/ 不能依赖 autoload
## （headless 测试编译不过 —— 实测踩过 `Identifier not found: Sfx`）。
## 两层防护取代原先散落四处的 `if prof != null`：
##   ① 非 Object（基本类型/字典）直接跳过；
##   ② 没有 mark 方法的对象也跳过 —— 打点是**诊断**不是逻辑，不因它炸掉 AI tick。
func _mark_prof(prof: Variant, phase: String) -> void:
	if prof is Object and prof.has_method("mark"):
		prof.mark(phase)


func _nearest_target(targets: Array) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for t in targets:
		var d: float = pos.distance_to(t.get("pos", Vector2.ZERO))
		if d < bd:
			bd = d
			best = t
	return best


func _deal_damage_to_nearest(targets: Array, amount: int) -> void:
	var tgt := _nearest_target(targets)
	if not tgt.is_empty():
		_apply_damage(tgt, amount)


## 目标字典原地减血（调用方负责把 hp<=0 的目标移出列表）
func _apply_damage(target: Dictionary, amount: int) -> void:
	if amount <= 0:
		return
	var cur := int(target.get("hp", 0))
	target["hp"] = maxi(0, cur - amount)
	damage_dealt += amount


# ─────────────────── 移动 ───────────────────

## 把任意目标点夹到最近的可行走逻辑格中心（W-06）。
## 防止包夹点落在墙里时敌人直线朝墙移动、逻辑坐标穿进墙格。
func _snap_walkable(grid: LogicalGrid, p: Vector2) -> Vector2:
	var c := Ballistics.cell_of(p)
	if grid.is_walkable(c):
		return p
	for r in range(1, 8):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue  # 只看外环
				var nc := Vector2i(c.x + dx, c.y + dy)
				if grid.is_walkable(nc):
					return Vector2(nc.x + 0.5, nc.y + 0.5)
	return p  # 极端情况找不到可走格：退回原值（不抛异常）

func _move_toward(flows: FlowFieldManager, goal: Vector2) -> void:
	if flows == null:
		move_dir = Vector2.ZERO
		return
	var my_cell := Ballistics.cell_of(pos)
	var goal_cell := Ballistics.cell_of(goal)
	if my_cell == goal_cell:
		move_dir = Vector2.ZERO
		return
	var d := flows.direction_for(my_cell, goal_cell)
	if d == Vector2i.ZERO:
		# ── 真拿不到方向才会走到这里 ──
		#
		# ⚠️ 注意：**流场预算用尽不再走这条路** —— FlowFieldManager 会复用
		#    最近一次建好的场，旧场仍然是**绕墙的**。
		#    所以这里只剩「目标不可达」一种情况。
		#
		# ⚠️ 而"朝目标直走"是**无视墙体**的。早先把它当预算回退用，
		#    结果敌人贴着墙硬顶、卡在墙角 —— 用户描述成
		#    "流场和白模地图冲突，视觉上能走的地方却走不了"
		#    （地图本身没问题：可达性测试对 8 张图断言 0 个不可达格；
		#      是**我为了压 AI 单帧耗时加的预算，把路径能力降级了**）。
		#    现在只当最后手段，并且**先确认前方真的能走**，否则沿墙滑动。
		var to := goal - pos
		if to.length() <= 0.01:
			move_dir = Vector2.ZERO
			return
		var want := to.normalized()
		if _cell_step_ok(flows, my_cell, want):
			move_dir = want
			return
		# 前方是墙：沿墙滑动（挑一个能走的侧向），别再顶墙
		var side := Vector2(-want.y, want.x)
		if _cell_step_ok(flows, my_cell, side):
			move_dir = side
		elif _cell_step_ok(flows, my_cell, -side):
			move_dir = -side
		else:
			move_dir = Vector2.ZERO
		return
	move_dir = Vector2(d).normalized()


## 朝 dir 迈一格，落点是不是可走？（用于"别顶墙"的局部规避）
func _cell_step_ok(flows: FlowFieldManager, from_cell: Vector2i, dir: Vector2) -> bool:
	if dir.length_squared() < 0.000001:
		return false
	var step := Vector2i(int(signf(dir.x)), int(signf(dir.y)))
	if step == Vector2i.ZERO:
		return false
	return flows.is_walkable_cell(from_cell + step)


func _to_string() -> String:
	return "Enemy#%d(%s, hp=%d, %s, pos=%s)" % [
		id, def.id if def else "?", hp, state_name(), str(pos.snapped(Vector2(0.1, 0.1)))]
