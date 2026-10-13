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
## ── 2026-10-13 真机反馈 #1：辅助瞄准太强，要加"视野锥" ──
##
## 用户原话：
##   "辅助瞄准太强，玩家需要加上视野锥 —— 辅助瞄准现在甚至可以
##    玩家在看上面辅助会自动锁定到下方敌人。"
##
## 根因（读代码确认）：
##   判定是「角度锥 **OR** 实体半径」两条通路取其一。近距离时垂距
##   `perp = |aim × dir| × dist` 会趋近 0，于是**半径通路无条件放行** ——
##   哪怕目标在正后方（夹角 ~180°）。`AimAssist.pick` 至少还有
##   `COUNTER_UNLOCK_DEG` 兜底，而 `AutoAim.scan_nearest`（常驻视野扫描、
##   决定锁定与自动射击）**连这个兜底都没有** ——
##   所以玩家朝上瞄，脚边偏下的敌人照样被锁上。
##
## 修法：引入一个**玩家视野锥硬门限** `PLAYER_VISION_HALF_DEG`。
##   它是"玩家能注意到目标"的绝对上限，半径通路只能在**这个锥内**放宽，
##   永远不能越过它。锥的大小 = 枪械视野锥 ∩ 门限（见 effective_cone_deg），
##   所以"换枪视野跟着变"依然成立，只是不再能让视野膨胀到身后。
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

## ── 与枪械属性挂钩（2026-10-13 真机反馈 #6）──
#
# 用户原话："辅助瞄准的范围应该和枪械属性挂钩"。
# 实测确认：改之前子弹磁性写死 `BASE_HALF_ANGLE_DEG = 4.2°` ——
# **换什么枪辅助范围都一模一样**，而枪械的 `aim_cone_deg`（视野锥）
# 只被 AutoAim（自动瞄准/自动射击）用到，磁性这条路径完全没读它。
#
# 现在磁性锥由枪械自己的视野锥推导：`aim_cone_deg × WEAPON_CONE_RATIO`。
#   霰弹枪 cone 34~35° -> 磁性约 4.1°（贴脸散射武器，本来就该糊上去）
#   步枪   cone 55°    -> 磁性约 6.6°（中庸）
#   狙击枪 cone 30°    -> 磁性约 3.6°（越精确的枪，辅助越克制）
const WEAPON_CONE_RATIO := 0.12
## 磁性锥半角的上下限（防止极端数据把辅助做得过强/完全失效）
const MIN_WEAPON_HALF_ANGLE := 2.0
const MAX_WEAPON_HALF_ANGLE := 7.5
## 磁性生效距离 = 枪械有效射程 × 这个比例。
## 留一点余量：射程边缘本来就打不动，磁性跟着收一收，
## 免得出现"准心磁到了 90 格外的敌人、这一枪却根本够不着"的割裂感。
const ASSIST_RANGE_RATIO := 0.85

## ── 玩家视野锥硬门限（2026-10-13 真机反馈 #1）──
#
# 任何辅助（磁性 pick / 视野扫描 scan_nearest）**一律不许**作用在
# 夹角超过这个值的敌人身上 —— 包括"因为贴得近"而走半径通路的情况。
# 这是"玩家在看上面，辅助却锁到下方敌人"的直接修法。
#
# 40° 的来历：既有武器数据里最宽的视野锥是步枪 55°，最窄狙击 30°。
# 取 40° 让"换枪视野不同"依然可见（30~40 会不同），
# 同时把半锥角从 55°（=110° 全视场）压到 40°（=80° 全视场）——
# 背后的目标彻底出局，而"贴脸偏心 0.4 格"（21.8°）这类正当场景仍命中。
const PLAYER_VISION_HALF_DEG := 40.0


## 这个夹角是否在玩家视野锥内（辅助的绝对门限）。
static func within_vision_cone(angle_deg: float) -> bool:
	return angle_deg <= PLAYER_VISION_HALF_DEG


## 有效视野锥半角 = 枪械视野锥 ∩ 玩家视野锥门限。
##
## **必须由绘制与逻辑共用同一个值**，否则玩家会看到"锥画得比实际能锁的大"，
## 这正是"看着能打却打不到"的又一种来源。
static func effective_cone_deg(weapon_cone_deg: float) -> float:
	if weapon_cone_deg <= 0.0:
		return PLAYER_VISION_HALF_DEG
	return minf(weapon_cone_deg, PLAYER_VISION_HALF_DEG)


## 按视口尺寸换算锥半角。
## 手机竖屏/小视口下同样的一圈像素代表更大的角，固定角度会过强。
static func half_angle_for_viewport(viewport_width: float) -> float:
	if viewport_width <= 0.0:
		return BASE_HALF_ANGLE_DEG
	var scale := clampf(REF_VIEWPORT_WIDTH / viewport_width, 0.55, 1.6)
	return BASE_HALF_ANGLE_DEG * scale


## 由**枪械的视野锥**推导磁性锥半角（真机反馈 #6）。
## aim_cone_deg 来自 data/weapons.json（`WeaponDef.aim_cone_deg`）。
## 缺数据（<= 0）时回退到旧的固定值，保证不会因为数据缺失而失去辅助。
static func half_angle_for_weapon(aim_cone_deg: float, viewport_width: float) -> float:
	if aim_cone_deg <= 0.0:
		return half_angle_for_viewport(viewport_width)
	var base := clampf(aim_cone_deg * WEAPON_CONE_RATIO,
		MIN_WEAPON_HALF_ANGLE, MAX_WEAPON_HALF_ANGLE)
	if viewport_width <= 0.0:
		return base
	var scale := clampf(REF_VIEWPORT_WIDTH / viewport_width, 0.55, 1.6)
	return base * scale


## 磁性的有效距离（由枪械射程推导）。见 ASSIST_RANGE_RATIO。
static func assist_range(weapon_range_m: float) -> float:
	return maxf(2.0, weapon_range_m * ASSIST_RANGE_RATIO)


## 挑一个磁性目标。
##
## 参数：
##   origin       射手位置（世界/格子坐标，与 targets 同系）
##   aim_dir      玩家瞄准方向（单位向量，未经辅助）
##   push         瞄准摇杆推力 0~1（低于 MIN_PUSH 直接返回空 —— 回中即失效）
##   targets      [{id, pos, faction, alive}, ...]  —— **必须带 faction**
##   grid         LogicalGrid，用于遮挡检查
##   half_angle   磁性锥半角（度），用 half_angle_for_weapon() 算。
##                ⚠️ 它只是"射线加粗的粗细"；真正的绝对上限是
##                PLAYER_VISION_HALF_DEG（视野锥），两条通路都在它之内。
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
		var angle_deg := rad_to_deg(acos(clampf(dot, -1.0, 1.0)))

		# ── 视野锥硬门限（真机反馈 #1）──
		# 半径通路（贴脸放宽）只在锥内生效；一旦越过门限就**一律出局**，
		# 哪怕它近在脚边。这就是"朝上瞄却锁到下方敌人"的修法。
		if not within_vision_cone(angle_deg):
			continue

		# 射线到实体中心的垂距（格）。角度判定在近距离不可靠，必须配合它。
		var perp := absf(aim.cross(dir_t)) * dist
		# 目标自身的半径（可被数据覆盖，例如大体型敌人）
		var tr := float(t.get("radius", hit_radius))
		if dot < cos_limit and perp > tr:
			continue                     # 锥内，但既不在磁性锥、也不在 hitbox 内

		# ── 约束 3：视线/遮挡检查 ──
		if grid != null and not Ballistics.has_line_of_sight(grid, origin, tp):
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
