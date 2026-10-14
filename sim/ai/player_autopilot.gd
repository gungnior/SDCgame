class_name PlayerAutopilot
extends RefCounted

## 玩家自动作战 —— 寻路 / 搜刮 / 交战的**纯逻辑**决策
##
## 用户规格（本次需求原文）：
##   「玩家在地图里自动寻路，遇到物品容器会自动搜索、拾取其中的物品，遇见敌人会自动攻击。」
##
## 本类只做【决策】，不碰场景、不碰节点：
##   · move        这一帧想往哪走（由场景走分轴碰撞与移速）
##   · loot        {kind, index} —— 到点了，请场景去搜这个容器/尸体
##   · has_target / target_pos —— 给自动锁定用（真正的锁定在 AutoAim）
##
## 决策优先级（按用户列举的顺序 + 搜打撤的常识）：
##   ① COMBAT  看得见敌人 -> 先打（逼近/拉开到交战距离）
##   ② LOOT    有没搜完的容器或尸体 -> 走过去，到点自动搜
##   ③ IDLE    都没有 -> 原地待机
##
## ⚠️ 寻路必须走**流场**（T-81），不许直线穿墙：
##    这是敌人的既有做法，玩家复用同一套，避免出现第二套寻路。
##    流场由场景持有（player_flows），本类只问方向。
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。

enum Mode { IDLE, LOOT, COMBAT }

const MODE_NAME := {
	Mode.IDLE: "IDLE",
	Mode.LOOT: "LOOT",
	Mode.COMBAT: "COMBAT",
}

## 与敌人的理想交战距离（逻辑格）：远了靠近、近了拉开、中间稳住
const STANDOFF_MIN := 3.0
const STANDOFF_MAX := 8.0
## 主动接敌的最大距离（超过就当没看见，先去搜东西）
const ENGAGE_MAX := 16.0
## 走到离目标多近就算「到了」，可以开搜（必须小于 RaidSession.container_near 的 1.4）
const LOOT_ARRIVE := 1.0
## 卡住判定：这么久没有明显靠近 -> 把这个目标拉黑，换下一个
const STUCK_TIMEOUT := 2.2
const STUCK_EPS := 0.08
## 拉黑时长（秒）
const BLACKLIST_SEC := 8.0

var mode: int = Mode.IDLE
var goal: Vector2 = Vector2.ZERO
var goal_kind: String = ""
var goal_index: int = -1
var has_target: bool = false
var target_pos: Vector2 = Vector2.ZERO

var _time: float = 0.0
var _stuck: float = 0.0
var _best_dist: float = INF
var _key_cache: String = ""
var _blacklist: Dictionary = {}      ## "c:3" -> 解禁时刻


func reset() -> void:
	mode = Mode.IDLE
	goal = Vector2.ZERO
	goal_kind = ""
	goal_index = -1
	has_target = false
	_blacklist.clear()
	_key_cache = ""
	_stuck = 0.0
	_best_dist = INF


func mode_name() -> String:
	return MODE_NAME.get(mode, "?")


## 场景搜完一个目标后通知一声（免得多走一步冤枉路）
func note_done(kind: String, index: int) -> void:
	if kind == goal_kind and index == goal_index:
		goal_kind = ""
		goal_index = -1
		_key_cache = ""
		_stuck = 0.0
		_best_dist = INF


func blacklist(kind: String, index: int, seconds: float = BLACKLIST_SEC) -> void:
	_blacklist["%s:%d" % [_prefix(kind), index]] = _time + seconds


func is_blacklisted(kind: String, index: int) -> bool:
	return _blacklist.has("%s:%d" % [_prefix(kind), index])


static func _prefix(kind: String) -> String:
	return "c" if kind == "container" else "k"


## 主决策。ctx 需要：
##   grid, flows, player_pos, enemies[{pos,alive}], containers[{pos,done}], corpses[{pos,done}], now
func update(delta: float, ctx: Dictionary) -> Dictionary:
	_time = float(ctx.get("now", _time + delta))
	_expire_blacklist()

	var out := {
		"move": Vector2.ZERO, "mode": "IDLE", "mode_id": Mode.IDLE,
		"goal": Vector2.ZERO, "goal_kind": "", "goal_index": -1,
		"loot": {}, "has_target": false, "target_pos": Vector2.ZERO,
	}
	var grid: LogicalGrid = ctx.get("grid")
	var flows: FlowFieldManager = ctx.get("flows")
	var me: Vector2 = ctx.get("player_pos", Vector2.ZERO)
	if grid == null:
		return out

	# ── ① 战斗优先：看得见、且在接敌范围内的最近敌人 ──
	var enemy := _pick_enemy(ctx, grid, me)
	if not enemy.is_empty():
		var ep: Vector2 = enemy["pos"]
		var d := me.distance_to(ep)
		mode = Mode.COMBAT
		has_target = true
		target_pos = ep
		goal = ep
		goal_kind = "enemy"
		goal_index = -1
		_key_cache = ""
		var mv := Vector2.ZERO
		if d > STANDOFF_MAX:
			mv = _step_dir(flows, me, ep)
		elif d < STANDOFF_MIN:
			var away := me - ep
			if away.length() > 0.001:
				mv = away.normalized()          # 太近就后退（直线远离，分轴碰撞兜底防穿墙）
		out["move"] = mv
		out["mode"] = mode_name()
		out["mode_id"] = mode
		out["goal"] = goal
		out["has_target"] = true
		out["target_pos"] = ep
		return out

	has_target = false

	# ── ② 搜刮：最近的、没搜完的容器 / 尸体 ──
	var loot := _pick_loot(ctx, me)
	if not loot.is_empty():
		var lp: Vector2 = loot["pos"]
		var ld: float = loot["dist"]
		mode = Mode.LOOT
		goal = lp
		goal_kind = str(loot["kind"])
		goal_index = int(loot["index"])
		_track_stuck(delta, me, goal, goal_kind, goal_index)
		out["goal"] = goal
		out["goal_kind"] = goal_kind
		out["goal_index"] = goal_index
		out["mode"] = mode_name()
		out["mode_id"] = mode
		if ld <= LOOT_ARRIVE:
			out["loot"] = loot
			out["move"] = Vector2.ZERO
		else:
			out["move"] = _step_dir(flows, me, lp)
		return out

	# ── ③ 无事可做 ──
	mode = Mode.IDLE
	goal_kind = ""
	goal_index = -1
	out["mode"] = mode_name()
	out["mode_id"] = mode
	return out


# ─────────────────── 目标挑选 ───────────────────

## 最近的可交战敌人：活、在接敌距离内、**有直线视野**（没视野就打不到）。
func _pick_enemy(ctx: Dictionary, grid: LogicalGrid, me: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := ENGAGE_MAX
	for e in ctx.get("enemies", []):
		if not (e is Dictionary):
			continue
		if not bool(e.get("alive", true)):
			continue
		var p: Vector2 = e.get("pos", Vector2.ZERO)
		var d := me.distance_to(p)
		if d > bd:
			continue
		if not Ballistics.has_line_of_sight(grid, me, p):
			continue
		bd = d
		best = {"pos": p, "dist": d}
	return best


## 最近的可搜目标。容器与尸体一视同仁（都是「搜索目标」）。
## 距离用**欧氏距离**先粗筛（O(n) 且够用），真正的绕墙由流场负责；
## 到不了的目标会被卡住判定拉黑，不会把自动作战钉死在一个死角上。
func _pick_loot(ctx: Dictionary, me: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for i in (ctx.get("containers", []) as Array).size():
		var c: Dictionary = ctx["containers"][i]
		if bool(c.get("done", false)):
			continue
		if is_blacklisted("container", i):
			continue
		var p: Vector2 = c.get("pos", Vector2.ZERO)
		var d := me.distance_to(p)
		if d < bd:
			bd = d
			best = {"kind": "container", "index": i, "pos": p, "dist": d}
	for j in (ctx.get("corpses", []) as Array).size():
		var k: Dictionary = ctx["corpses"][j]
		if bool(k.get("done", false)):
			continue
		if is_blacklisted("corpse", j):
			continue
		var p2: Vector2 = k.get("pos", Vector2.ZERO)
		var d2 := me.distance_to(p2)
		if d2 < bd:
			bd = d2
			best = {"kind": "corpse", "index": j, "pos": p2, "dist": d2}
	return best


# ─────────────────── 移动 ───────────────────

## 朝目标走一格：问流场要方向；同一格内就直接朝点走。
func _step_dir(flows: FlowFieldManager, me: Vector2, target: Vector2) -> Vector2:
	var my := Ballistics.cell_of(me)
	var tc := Ballistics.cell_of(target)
	if my == tc:
		var to := target - me
		return to.normalized() if to.length() > 0.001 else Vector2.ZERO
	if flows != null:
		var d := flows.direction_for(my, tc)
		if d != Vector2i.ZERO:
			return Vector2(d).normalized()
	# 流场拿不到方向（目标不可达 / 预算用尽退化成旧场）：直线兜底
	#
	# ⚠️ 移除条件（AGENTS.md §4.5）：当 FlowFieldManager 能保证
	#    「目标可达时必有方向、不可达时能被调用方提前判掉」之后，删掉这个兜底。
	#    它现在唯一的作用是"别在原地卡死"；直线本身穿不了墙（分轴碰撞兜着）。
	var fallback := target - me
	return fallback.normalized() if fallback.length() > 0.001 else Vector2.ZERO


# ─────────────────── 卡住判定 ───────────────────

func _track_stuck(delta: float, me: Vector2, g: Vector2, kind: String, index: int) -> void:
	var key := "%s:%d" % [_prefix(kind), index]
	if key != _key_cache:
		_key_cache = key
		_stuck = 0.0
		_best_dist = INF
	var d := me.distance_to(g)
	if d < _best_dist - STUCK_EPS:
		_best_dist = d
		_stuck = 0.0
		return
	_stuck += delta
	if _stuck >= STUCK_TIMEOUT:
		# 到不了（被墙隔开 / 在封锁区）：拉黑，换下一个目标
		blacklist(kind, index)
		_stuck = 0.0
		_best_dist = INF
		_key_cache = ""
		goal_kind = ""
		goal_index = -1


func _expire_blacklist() -> void:
	if _blacklist.is_empty():
		return
	var dead: Array = []
	for k in _blacklist.keys():
		if float(_blacklist[k]) <= _time:
			dead.append(k)
	for k in dead:
		_blacklist.erase(k)


func _to_string() -> String:
	return "PlayerAutopilot(%s, goal=%s, %s#%d)" % [
		mode_name(), str(goal.snapped(Vector2(0.1, 0.1))), goal_kind, goal_index]
