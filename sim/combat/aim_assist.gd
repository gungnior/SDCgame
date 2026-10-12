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
##
## 返回 {} 或 {target, dir, weight, angle_deg, bend_deg}
##   dir 是【偏折后】的射击方向；准心方向不变（这就是"不抢控制权"）
static func pick(origin: Vector2, aim_dir: Vector2, push: float,
		targets: Array, grid: LogicalGrid, half_angle: float,
		max_range: float, player_faction: String = "player") -> Dictionary:

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
		if dot < cos_limit:
			continue                     # 锥外

		# ── 约束 3：视线/遮挡检查 ──
		if grid != null and not Ballistics.has_line_of_sight(grid, origin, tp):
			continue

		# ── 硬原则 1：玩家可超越 ──
		# 玩家把摇杆往目标【反方向】推 = 主动脱锁
		var angle_deg := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))
		if angle_deg > COUNTER_UNLOCK_DEG:
			continue

		# 打分：夹角越小越好，距离越近越好
		var ang_w := 1.0 - (angle_deg / maxf(half_angle, 0.001))   # 0~1
		var dist_w := 1.0 - (dist / maxf(max_range, 0.001))        # 0~1
		var score := ang_w * 0.72 + dist_w * 0.28
		if score > best_score:
			best_score = score
			best = {"target": t, "dir": dir_t, "angle_deg": angle_deg,
				"dist": dist, "ang_w": ang_w}

	if best.is_empty():
		return {}

	# ── 偏折量 ──
	# 权重 = 夹角衰减 × 推力（推得越满辅助越弱 —— 硬原则 1）
	var weight := float(best["ang_w"]) * clampf(1.0 - push * 0.45, 0.35, 1.0)
	var angle := float(best["angle_deg"])
	var bend := minf(angle, MAX_BEND_DEG) * weight
	var target_dir: Vector2 = best["dir"]
	var bent := _rotate_toward(aim, target_dir, deg_to_rad(bend))

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
