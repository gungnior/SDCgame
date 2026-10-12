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

## 把警戒扩散到附近的小队。
## 返回被波及的小队数。
##
## ⚠️ 性能：早先对**每个小队**各调一次 `Perception.hearing_cost()` ——
##    那是**每小队一次全网格 Dijkstra**，正是之前把 AI 单帧推到 257ms 的元凶。
##    现在改成：**从声源跑一次 `hearing_field()`**，然后对所有小队做 O(1) 查表。
##    N 次 Dijkstra -> 1 次。
##
## 另外：本方法早先**从未被调用**（死代码）。
##    现在由 raid_scene 在"有成员报告接触"时调用。
static func spread_alert(grid: LogicalGrid, source_pos: Vector2, squads: Array,
		radius_cost: float, now: float,
		wall_penalty: int = Perception.DEFAULT_WALL_PENALTY) -> int:
	if grid == null or squads.is_empty():
		return 0
	var field := Perception.hearing_field(grid, source_pos, wall_penalty)
	if field.is_empty():
		return 0
	var n := 0
	var emitted := {}                  # 同一个小队只扩散一次（免得 A 传 B、B 又传 A）
	for s in squads:
		if s == null or s.members.is_empty():
			continue
		if emitted.has(s):
			continue
		emitted[s] = true
		var anchor = s.members[0]
		var p: Vector2 = anchor.get("pos")
		var cost := Perception.cost_at(field, grid, p)
		if cost < 0:
			continue
		if float(cost) <= radius_cost:
			# 距离越远，警戒等级越低（隔着墙会额外衰减，因为 cost 里含墙罚）
			var falloff := 1.0 - clampf(float(cost) / maxf(1.0, radius_cost), 0.0, 1.0)
			s.alert_level = maxf(s.alert_level, ALERT_ON_CONTACT * falloff)
			if not s.has_contact:
				s.last_known_pos = source_pos
				s.last_known_time = now
			n += 1
	return n


# ─────────────────── 包夹（角色分工）───────────────────
#
# 依据 roadmap-bac.md §2：A 阶段的 AI 要「＋群体协同」。
# 现状是每个敌人**各自朝玩家直线压过去** —— 会挤成一坨，且完全没有战术感。
#
# 设计：给每名成员分一个【角色】，角色决定它该站到目标的哪个方位：
#   DIRECT       正面顶上去（最近的那个，负责吸引火力）
#   FLANK_LEFT   从左侧绕，站到目标的侧后方
#   FLANK_RIGHT  从右侧绕
#   OVERWATCH    不上前，保持射程压制（血量低/射速慢的当这个最合适）

enum Role { DIRECT, FLANK_LEFT, FLANK_RIGHT, OVERWATCH }

## 包夹的侧向夹角与半径（世界单位 = 逻辑格）
const FLANK_ANGLE_DEG := 58.0
const FLANK_RADIUS := 3.2
## 殿后位离目标多远（用远程偏好的上限）
const OVERWATCH_DIST := 7.0

## 成员 -> 角色
var roles: Dictionary = {}
## 成员 -> 分配角色那一刻的"接近方向"（单位向量）
##
## ⚠️ 必须缓存这个方向，不能每次用"敌人当前位置到目标"实时算 ——
##    那条方向会随着敌人移动而变，包夹点于是跟着转，
##    敌人会绕着目标兜圈子**永远到不了位**（测试直接抓出来了）。
##    缓存后包夹点在两次重分之间是固定的，敌人才走得到。
var _approach: Dictionary = {}
## 上一次分配角色时的成员数（人数变了要重分）
var _roles_for_count: int = -1


## 按"谁离目标近"重新分配角色。成员增删或目标大改时调用。
##
## 分配策略（简单但有效）：
##   最近的 1 个 -> DIRECT（正面顶）
##   次近的 2 个 -> FLANK_LEFT / FLANK_RIGHT（左右包夹）
##   其余        -> OVERWATCH（拉远压制）
func assign_roles(target_pos: Vector2) -> void:
	var alive := alive_members()
	if alive.is_empty():
		roles.clear()
		_approach.clear()
		_roles_for_count = 0
		return
	# 按到目标的距离升序
	alive.sort_custom(func(a, b):
		return Vector2(a.get("pos")).distance_to(target_pos) \
			< Vector2(b.get("pos")).distance_to(target_pos))
	# ⚠️ 顺序数组：第 4 位必须是 OVERWATCH。
	#    我第一版写成了 [DIRECT, FLANK_LEFT, FLANK_RIGHT, FLANK_LEFT, FLANK_RIGHT]，
	#    于是第 4 名成员拿到的还是"左翼" —— 测试直接抓出来了。
	var order: Array[Role] = [Role.DIRECT, Role.FLANK_LEFT, Role.FLANK_RIGHT, Role.OVERWATCH]
	roles.clear()
	_approach.clear()
	for i in alive.size():
		var a = alive[i]
		roles[a] = order[i] if i < order.size() else Role.OVERWATCH
		var to_t: Vector2 = target_pos - Vector2(a.get("pos"))
		_approach[a] = to_t.normalized() if to_t.length() > 0.01 else Vector2.RIGHT
	_roles_for_count = alive.size()


func role_of(a) -> Role:
	return roles.get(a, Role.DIRECT) as Role


## 这名成员该前往的位置（目标方位上的一个包夹点）。
## 没有角色信息时返回 target_pos（退化成"直冲"，不会卡住）。
func goal_for(a, target_pos: Vector2) -> Vector2:
	var r := role_of(a)
	if r == Role.DIRECT:
		return target_pos
	# 用分配角色时缓存的方向；没有就退回实时方向
	var dir: Vector2 = _approach.get(a, Vector2.ZERO)
	if dir == Vector2.ZERO:
		var to_t: Vector2 = target_pos - Vector2(a.get("pos"))
		if to_t.length() < 0.01:
			return target_pos
		dir = to_t.normalized()
	match r:
		Role.FLANK_LEFT:
			return target_pos - dir.rotated(deg_to_rad(FLANK_ANGLE_DEG)) * FLANK_RADIUS
		Role.FLANK_RIGHT:
			return target_pos - dir.rotated(-deg_to_rad(FLANK_ANGLE_DEG)) * FLANK_RADIUS
		Role.OVERWATCH:
			return target_pos - dir * OVERWATCH_DIST
	return target_pos


## 该成员是否已经站到自己的包夹位附近（到位后就地开火，别再乱跑）
func at_post(a, target_pos: Vector2, tol: float = 1.4) -> bool:
	return Vector2(a.get("pos")).distance_to(goal_for(a, target_pos)) <= tol


func role_name(a) -> String:
	match role_of(a):
		Role.DIRECT: return "正面"
		Role.FLANK_LEFT: return "左翼"
		Role.FLANK_RIGHT: return "右翼"
		Role.OVERWATCH: return "压制"
	return "?"

