class_name LaneShotManager
extends RefCounted

## 固定弹道的**集合与结算** —— 敌人放进来，场景每帧 tick 一次
##
## 为什么伤害要「延后结算」：
##   改造前敌人是 hitscan，扣血就发生在开火那一帧；
##   现在弹道要飞，扣血必须发生在**前沿扫过玩家**的那一帧，
##   于是伤害先在管理器里攒着（pending_damage），由场景在本帧统一走
##   护甲结算（RaidScene._resolve_player_hit）—— 护甲逻辑仍然**只有一处**。
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。

## 上限保护：防止极端情况下（几十个敌人一起开火）数组无限增长
const MAX_SHOTS := 96

var shots: Array[LaneShot] = []
## 本帧命中玩家的总伤害（由场景结算后清零）
var pending_damage: int = 0
## 本帧命中的弹道（表现层/音效/遥测用）
var hits: Array[LaneShot] = []
## 本帧打到墙上的弹道终点（表现层用）
var impacts: Array[Vector2] = []
## 本帧被无敌帧挡下的伤害总量 —— 只用于提示与统计
var dodged_damage: int = 0


func clear() -> void:
	shots.clear()
	pending_damage = 0
	hits.clear()
	impacts.clear()
	dodged_damage = 0


func count() -> int:
	return shots.size()


## 放一条弹道出去。dir 会被归一化；length <= 0 时仍然登记（表现层看得见），但不结算。
func spawn(origin: Vector2, dir: Vector2, speed: float, damage: int, length: float,
		owner_id: int = -1, weapon_id: String = "", warn_sec: float = 0.0) -> LaneShot:
	if shots.size() >= MAX_SHOTS:
		shots.pop_front()
	var s := LaneShot.new()
	s.origin = origin
	s.dir = dir.normalized() if dir.length() > 0.0001 else Vector2.RIGHT
	s.speed = maxf(speed, 0.1)
	s.damage = maxi(damage, 0)
	s.length = maxf(length, 0.0)
	s.owner_id = owner_id
	s.weapon_id = weapon_id
	# 开火前预警：这段时间里弹道不动、不判定，只亮瞄准线（见 LaneShot 文件头）
	s.warn_sec = maxf(warn_sec, 0.0)
	s.warn_left = s.warn_sec
	shots.append(s)
	return s


## 推进所有弹道，并对玩家做命中判定。
##
## player_pos 传**当前帧的**玩家中心；玩家是否无敌由调用方决定
## （这里只给出几何结论 —— 无敌帧在场景那侧吞掉伤害）。
func tick(delta: float, player_pos: Vector2) -> void:
	hits.clear()
	impacts.clear()
	for i in range(shots.size() - 1, -1, -1):
		var s: LaneShot = shots[i]
		var r := s.advance(delta, player_pos)
		if bool(r["hit"]):
			pending_damage += s.damage
			hits.append(s)
		if s.done:
			if not s.hit_player:
				impacts.append(s.end_pos())
			shots.remove_at(i)


## 取走本帧攒下的伤害并清零（场景结算护甲用）。
func consume_damage() -> int:
	var d := pending_damage
	pending_damage = 0
	return d


## 本帧有没有一条弹道「即将」打到玩家（用于自动闪避）。
## lookahead_sec 是提前量：只关心「还来得及躲」的那一发。
## margin 用于给判定加一点余量（自动闪避应该稍微提前一点动）。
func incoming(player_pos: Vector2, lookahead_sec: float, margin: float = 0.0) -> LaneShot:
	var best: LaneShot = null
	var best_eta := INF
	for s in shots:
		if s.done or s.speed <= 0.0:
			continue
		# ⚠️ 必须用 total_eta（预警 + 飞行）：只算飞行的话，
		#    预警期间会被判成"已经在路上"，自动闪避会晚按一步。
		var eta := s.total_eta(player_pos)
		if eta == INF:
			continue                                  # 前沿已越过 / 静止弹道
		if s.perpendicular_distance(player_pos) > s.half_width + margin:
			continue                                  # 已经站在弹道外 -> 不用躲
		if eta <= lookahead_sec and eta < best_eta:
			best_eta = eta
			best = s
	return best


func _to_string() -> String:
	return "LaneShotManager(在飞 %d 条, 本帧待结算 %d)" % [shots.size(), pending_damage]
