class_name AimAssist
extends RefCounted

## 子弹磁性（bullet magnetism）—— 触屏射击辅助瞄准
##
## 依据 specs/tech-stack.md §7.7（T-56，**本条修正 T-13**）：
##
##   > **优先做「子弹磁性」（hitscan 射线加粗），而不是角度吸附。**
##
##   为什么不吸附准心：**不改准心、对输入映射零干扰**；
##   而且我们是 hitscan（T-50），**实现成本极低**。
##   角度吸附很容易让玩家觉得"被抢枪"。
##
## **两条硬原则**（spec 原文）：
##   1. **辅助强度必须可被玩家超越**——玩家把摇杆推到底主动转向时，辅助应减弱/关闭
##   2. **搜打撤必须做目标筛选**——不能自动吸附中立 NPC 或同伴
##
## 另外三条约束：
##   · 只在"玩家正在推瞄准摇杆"时生效、**回中立即失效**
##   · FOV 门限**按屏幕尺寸换算**（手机视口小，固定 90° 会过强）
##   · 加**视线/遮挡检查**
##
## 纯静态、纯逻辑，可 headless 单测。

## 基础锥半角（度）。这是"射线加粗"的粗细，不是准心吸附范围。
const BASE_HALF_ANGLE_DEG := 4.2
## 视口宽参考值：门限按 (参考宽 / 实际宽) 缩放
const REF_VIEWPORT_WIDTH := 640.0
## 摇杆推力低于此值视为"回中" -> 立即失效
const MIN_PUSH := 0.22
## 玩家主动反向拨杆超过这个角度 -> 脱锁（把控制权还给玩家）
const COUNTER_UNLOCK_DEG := 62.0
## 单次射击最大偏折角（防止"子弹拐弯"过于离谱）
const MAX_BEND_DEG := 6.0
## 默认实体半径（世界单位 = 逻辑格）。
## 0.45 格 ≈ 21.6 世界像素，比敌人画出来的圆（半径 9px）宽松一倍多 ——
## 这是**故意的**：移动端触屏瞄准精度远低于鼠标，判定要给足余量。
## 真机反馈 #1"贴脸很难命中"就是判定太严导致的。
const DEFAULT_HIT_RADIUS := 0.45
## 单次射击的最大【横向】偏折量（格）。
## 用横向距离而不是角度来限制 —— 见 pick() 里的说明。
const MAX_BEND_CELLS := 0.55
## 偏折权重的下限。命中判定由 pick() 决定，dir 只用来画曳光；
## 若权重塌到接近 0，会出现"判定命中但曳光飞向别处"的矛盾观感（测试抓到过）。
const MIN_BEND_WEIGHT := 0.55


## 按视口尺寸换算锥半角。
## 手机竖屏/小视口下同样的一圈像素代表更大的角，固定角度会过强。
static func half_angle_for_viewport(viewport_width: float) -> float:
	if viewport_width <= 0.0:
		return BASE_HALF_ANGLE_DEG
	var scale := clampf(REF_VIEWPORT_WIDTH / viewport_width, 0.55, 1.6)
	return BASE_HALF_ANGLE_DEG * scale


## 挑一个磁性目标。
##
## 参数：
##   origin       射手位置（世界/格子坐标，与 targets 同系）
##   aim_dir      玩家瞄准方向（单位向量，未经辅助）
##   push         瞄准摇杆推力 0~1（低于 MIN_PUSH 直接返回空 —— 回中即失效）
##   targets      [{id, pos, faction, alive}, ...]  —— **必须带 faction**
##   grid         LogicalGrid，用于遮挡检查
##   half_angle   锥半角（度），用 half_angle_for_viewport() 算
##   max_range    有效射程（与世界坐标同单位）
##   player_faction 玩家阵营，用于目标筛选
##   hit_radius   **实体半径**（世界单位）。见下方说明。
##
## ⚠️ hit_radius 是修"贴脸打不中"的关键（真机反馈 #1）：
##    早先只用【角度锥】判定，而角度在近距离会爆炸式放大：
##    敌人在 1 格外偏 0.3 格 = 17°，远超 4.2° 的锥半角 -> 永远打不中。
##    所以判定改成 **角度锥 OR 射线到实体中心的垂距 <= hit_radius**，
##    这才是真正意义上的 hitbox。
##
## 返回 {} 或 {target, dir, weight, angle_deg, bend_deg}
##   dir 是【偏折后】的射击方向；准心方向不变（这就是"不抢控制权"）
static func pick(origin: Vector2, aim_dir: Vector2, push: float,
		targets: Array, grid: LogicalGrid, half_angle: float,
		max_range: float, player_faction: String = "player",
		hit_radius: float = DEFAULT_HIT_RADIUS) -> Dictionary:

	if push < MIN_PUSH or aim_dir == Vector2.ZERO or targets.is_empty():
		return {}
	var aim := aim_dir.normalized()
	var cos_limit := cos(deg_to_rad(half_angle))

	var best: Dictionary = {}
	var best_score := -INF

	for t in targets:
		if not (t is Dictionary):
			continue
		# ── 硬原则 2：目标筛选（不能吸附中立 NPC 或同伴）──
		if str(t.get("faction", "enemy")) == player_faction:
			continue
		if not bool(t.get("alive", true)):
			continue

		var tp: Vector2 = t.get("pos", Vector2.ZERO)
		var to_t := tp - origin
		var dist := to_t.length()
		if dist <= 0.01 or dist > max_range:
			continue

		var dir_t := to_t / dist
		var dot := aim.dot(dir_t)
		# 射线到实体中心的垂距（格）。角度判定在近距离不可靠，必须配合它。
		var perp := absf(aim.cross(dir_t)) * dist
		# 目标自身的半径（可被数据覆盖，例如大体型敌人）
		var tr := float(t.get("radius", hit_radius))
		if dot < cos_limit and perp > tr:
			continue                     # 既不在锥内、也不在 hitbox 内

		# ── 约束 3：视线/遮挡检查 ──
		if grid != null and not Ballistics.has_line_of_sight(grid, origin, tp):
			continue

		# ── 硬原则 1：玩家可超越 ──
		# 玩家把摇杆往目标【反方向】推 = 主动脱锁
		var angle_deg := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
		if angle_deg > COUNTER_UNLOCK_DEG:
			continue

		# 打分：夹角越小越好、越接近实体中心越好、距离越近越好
		# ⚠️ ang_w 必须夹到 0~1 —— 近距离的目标是【靠 hitbox】进来的，
		#    它的夹角会远大于 half_angle，不夹的话权重会变成负数（实测踩过）。
		var ang_w := clampf(1.0 - (angle_deg / maxf(half_angle, 0.001)), 0.0, 1.0)
		var rad_w := clampf(1.0 - (perp / maxf(tr, 0.001)), 0.0, 1.0)
		var center_w := maxf(ang_w, rad_w)
		var dist_w := 1.0 - (dist / maxf(max_range, 0.001))        # 0~1
		var score := center_w * 0.72 + dist_w * 0.28
		if score > best_score:
			best_score = score
			best = {"target": t, "dir": dir_t, "angle_deg": angle_deg,
				"dist": dist, "ang_w": center_w}

	if best.is_empty():
		return {}

	# ── 偏折量 ──
	# 权重 = 居中程度 × 推力（推得越满辅助越弱 —— 硬原则 1）
	#
	# ⚠️ 权重必须设下限。命中判定是由本函数【接受目标】决定的，
	#    而 dir 只用来画曳光 —— 若权重塌到接近 0，会出现
	#    "判定命中了、但曳光明显朝别处飞"的矛盾观感（测试抓到过：权重 0.08）。
	#    所以给一个 0.55 的下限，保证曳光至少大致指向目标。
	#
	# ⚠️ 上限必须用【横向距离】而不是【角度】。
	#    只限角度会在近距离出问题：1 格外偏 0.3 格 = 17°，而角度上限只有 6°，
	#    于是永远差几度打不中 —— 这正是真机反馈"贴脸很难命中"的根因之一。
	#    改成限制"射线在目标处的横向偏移 <= MAX_BEND_CELLS"后，
	#    近距离自动允许更大的角度（1 格时可偏 33°），远距离仍然很克制（10 格时仅 3°）。
	var push_w := clampf(1.0 - push * 0.45, 0.35, 1.0)
	var weight := maxf(MIN_BEND_WEIGHT, float(best["ang_w"])) * push_w
	var angle := float(best["angle_deg"])
	var d_now: float = maxf(float(best["dist"]), 0.25)
	var max_bend_rad := asin(clampf(MAX_BEND_CELLS / d_now, 0.0, 0.95))
	var bend := minf(deg_to_rad(angle), max_bend_rad) * weight
	var target_dir: Vector2 = best["dir"]
	var bent := _rotate_toward(aim, target_dir, bend)

	return {
		"target": best["target"],
		"dir": bent,
		"weight": weight,
		"angle_deg": angle,
		"bend_deg": bend,
		"dist": best["dist"],
	}


## 把 from 朝 to 转最多 max_rad（不越过 to）
static func _rotate_toward(from: Vector2, to: Vector2, max_rad: float) -> Vector2:
	var a := from.angle()
	var b := to.angle()
	var diff := wrapf(b - a, -PI, PI)
	var step := clampf(diff, -max_rad, max_rad)
	return Vector2.from_angle(a + step)


## 用推力量估计"玩家是否在主动反向拨杆"。
## stick_dir 是摇杆原始方向（未辅助），assisted_dir 是辅助后方向。
## 返回 true 表示应当脱锁。
static func is_counter_pushing(stick_dir: Vector2, assisted_dir: Vector2) -> bool:
	if stick_dir == Vector2.ZERO or assisted_dir == Vector2.ZERO:
		return false
	var a := rad_to_deg(acos(clampf(stick_dir.normalized().dot(assisted_dir.normalized()), -1.0, 1.0)))
	return a > COUNTER_UNLOCK_DEG


## 射线加粗的"命中判定"版本：给定瞄准方向与锥角，返回锥内被磁性拉中的目标。
## 与 pick() 的区别：这个直接回答"这一枪算不算中"，供伤害结算用。
static func resolve_shot(origin: Vector2, aim_dir: Vector2, push: float,
		targets: Array, grid: LogicalGrid, half_angle: float,
		max_range: float, player_faction: String = "player") -> Dictionary:
	return pick(origin, aim_dir, push, targets, grid, half_angle, max_range, player_faction)
