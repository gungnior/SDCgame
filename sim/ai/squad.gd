class_name Squad
extends RefCounted

## 小队黑板 —— specs/tech-stack.md §4.7（T-83）
##
##   ⚠️ 诚实结论：Godot 生态【没有】成熟的战斗小队协同 AI 库，必须自研。
##   行为树/黑板提供的是承载结构，不是战术本身。
##
## 本类实现三件事：
##   1. 共享黑板：警戒等级、玩家最后已知位置与时间、阵亡成员
##   2. 警戒等级扩散 —— 【走格子 BFS，不走直线】，复用 Perception.hearing_cost
##      这样"隔墙传声衰减"天然正确
##   3. 警戒衰减：没人报告接触就慢慢放松
##
## 纯 RefCounted，可 headless 单测。

const ALERT_DECAY_PER_SEC := 0.055
const ALERT_ON_CONTACT := 1.0
const ALERT_ON_NOISE := 0.45
const CONTACT_MEMORY_SEC := 12.0

var id: int = 0
var alert_level: float = 0.0
var last_known_pos: Vector2 = Vector2.ZERO
var last_known_time: float = -99999.0
var has_contact: bool = false
var lost_contact_time: float = -99999.0
var casualty_count: int = 0

## 成员（EnemyAgent）。用无类型数组避免与 EnemyAgent 的循环类型依赖。
var members: Array = []


func _init(sid: int = 0) -> void:
	id = sid


func add_member(a) -> void:
	if not members.has(a):
		members.append(a)
		if a.has_method("set_squad"):
			a.set_squad(self)


func alive_members() -> Array:
	var out: Array = []
	for m in members:
		if m.get("state") != null and m.state != EnemyAgent.State.DEAD:
			out.append(m)
	return out


## 有成员报告接触（看见玩家）
func report_contact(pos: Vector2, now: float) -> void:
	alert_level = ALERT_ON_CONTACT
	last_known_pos = pos
	last_known_time = now
	has_contact = true


## 有成员听到声音（没看见）
func report_noise(pos: Vector2, now: float) -> void:
	alert_level = maxf(alert_level, ALERT_ON_NOISE)
	# 只有比已知位置更新的情报才覆盖
	if now - last_known_time > 0.0 or not has_contact:
		last_known_pos = pos
		last_known_time = now


func report_lost_contact(now: float) -> void:
	has_contact = false
	lost_contact_time = now


func report_casualty() -> void:
	casualty_count += 1
	alert_level = ALERT_ON_CONTACT   # 同伴死了，必定拉满警戒


func tick(delta: float, now: float) -> void:
	if not has_contact:
		alert_level = maxf(0.0, alert_level - ALERT_DECAY_PER_SEC * delta)
	# 情报过期后清空最后已知位置
	if now - last_known_time > CONTACT_MEMORY_SEC:
		has_contact = false


func is_engaged() -> bool:
	return has_contact


func is_alerted() -> bool:
	return alert_level > 0.3


## 警戒等级对应的"警戒着色"（art-pipeline.md §3.2：放松=灰白/警觉=黄/交战=红）
func alert_color() -> Color:
	if has_contact:
		return Color(1.0, 0.25, 0.25)      # 交战
	if alert_level > 0.3:
		return Color(1.0, 0.78, 0.30)      # 警觉
	return Color(0.75, 0.78, 0.82)         # 放松


func _to_string() -> String:
	return "Squad#%d(成员=%d, 警戒=%.2f, 有接触=%s, 阵亡=%d)" % [
		id, members.size(), alert_level, str(has_contact), casualty_count]


# ─────────────────── 跨小队警戒扩散 ───────────────────

## 把警戒扩散到附近的小队。【走格子 BFS，不走直线】。
## 返回被波及的小队数。
static func spread_alert(grid: LogicalGrid, source_pos: Vector2, squads: Array,
		radius_cost: float, now: float, wall_penalty: int = Perception.DEFAULT_WALL_PENALTY) -> int:
	var n := 0
	for s in squads:
		if s == null or s.members.is_empty():
			continue
		var anchor = s.members[0]
		var p: Vector2 = anchor.get("pos")
		var cost := Perception.hearing_cost(grid, source_pos, p, wall_penalty)
		if cost < 0:
			continue
		if float(cost) <= radius_cost:
			# 距离越远，警戒等级越低
			var falloff := 1.0 - clampf(float(cost) / maxf(1.0, radius_cost), 0.0, 1.0)
			s.alert_level = maxf(s.alert_level, ALERT_ON_CONTACT * falloff)
			if not s.has_contact:
				s.last_known_pos = source_pos
				s.last_known_time = now
			n += 1
	return n
