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

## 近战进入攻击的距离（逻辑格）
const MELEE_RANGE_CELLS := 1.2
## 远程敌人希望保持的距离（逻辑格）
const RANGED_PREFERRED_MIN := 5.0
const RANGED_PREFERRED_MAX := 9.0
## 失去视野后继续搜索的时长
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

	# ── 感知：先看，再听 ──
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
		var noise := _find_audible_noise(grid, ctx.get("noises", []))
		if not noise.is_empty():
			var np: Vector2 = noise["pos"]
			last_seen_pos = np
			target_pos = np
			alert_timer = 6.0
			state = State.ALERT
			if squad != null:
				squad.report_noise(np, now)

	# ── 状态行为 ──
	match state:
		State.IDLE:
			move_dir = Vector2.ZERO
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
			_combat(delta, targets, rng, seen)
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


# ─────────────────── 感知 ───────────────────

func _find_visible_target(grid: LogicalGrid, targets: Array) -> Dictionary:
	for t in targets:
		var tp: Vector2 = t.get("pos", Vector2.ZERO)
		if Perception.can_see(grid, pos, facing, tp, def):
			return t
	return {}


func _find_audible_noise(grid: LogicalGrid, noises: Array) -> Dictionary:
	for nz in noises:
		var np: Vector2 = nz.get("pos", Vector2.ZERO)
		var loud: float = nz.get("loudness_m", 0.0)
		if Perception.hears_noise(grid, def, np, pos, loud):
			return nz
	return {}


# ─────────────────── 战斗 ───────────────────

func _combat(delta: float, targets: Array, rng: SimRng, seen: Dictionary) -> void:
	var dist := pos.distance_to(target_pos)

	if def.is_ranged():
		# 保持距离：太近后退、太远靠近、合适则原地
		var dir_to := (target_pos - pos)
		if dist > RANGED_PREFERRED_MAX:
			move_dir = dir_to.normalized()
		elif dist < RANGED_PREFERRED_MIN:
			move_dir = -dir_to.normalized()
		else:
			move_dir = Vector2.ZERO

		# 反应时间没走完不开火（这是"公平感"的关键）
		if reaction_timer > 0.0 or attack_cooldown > 0.0:
			return
		if seen.is_empty():
			return
		_fire_at(targets, dist, rng)
	else:
		# 近战：贴身
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
		move_dir = Vector2.ZERO
		return
	move_dir = Vector2(d).normalized()


func _to_string() -> String:
	return "Enemy#%d(%s, hp=%d, %s, pos=%s)" % [
		id, def.id if def else "?", hp, state_name(), str(pos.snapped(Vector2(0.1, 0.1)))]
