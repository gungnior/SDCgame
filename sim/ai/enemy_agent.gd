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
	if prof != null:
		prof.mark("ai_see")
	var seen := _find_visible_target(grid, targets)
	if not seen.is_empty():
		var sp: Vector2 = seen["pos"]
		last_seen_pos = sp
		target_pos = sp
		if state != State.COMBAT:
			# 刚发现：进入反应延迟（reaction_time 决定公平感）
			reaction_timer = def.reaction_time
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
		if prof != null:
			prof.mark("ai_hear")
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
	if prof != null:
		prof.mark("ai_act")

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
			_combat(delta, targets, rng, seen, grid)
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

func _combat(delta: float, targets: Array, rng: SimRng, seen: Dictionary, grid: LogicalGrid) -> void:
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
		_fire_at(targets, dist, rng)
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


func _fire_at(targets: Array, dist: float, rng: SimRng) -> void:
	if weapon == null or not weapon.can_fire():
		return
	weapon.fire()
	shots_fired += 1
	attack_cooldown = def.attack_cooldown

	# 命中判定走 DamageModel 的概率部位模型（T-52）
	var extra := weapon.current_spread_deg() - weapon.def.spread_deg
	var hit := DamageModel.resolve_hit(weapon.def, dist, extra, rng)

	# 命中率：距离与散布影响"是否打中"
	var acc := DamageModel.accuracy_at(weapon.def, dist, extra)
	if rng.randf() > clampf(0.35 + acc * 0.6, 0.05, 0.95):
		return   # 打空

	weapon.mark_hit()
	var tgt := _nearest_target(targets)
	if not tgt.is_empty():
		_apply_damage(tgt, int(hit["damage"]))


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
