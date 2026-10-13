class_name AutoAim
extends RefCounted

## 锥形视野 + 锁定 + 自动瞄准/自动射击 —— **纯逻辑**
##
## 用户规格（真机反馈 #5，原文）：
##   「玩家会有一个锥形视野（配合玩家瞄准方向可以运动的），
##     这个视野会随着枪械具体数值来变化，在这个视野内发现了敌人，会有 2 种功能：
##      ① 玩家可以在 ui 交互上开启自动射击，优先锁定射击离玩家近的敌人
##      ② 在不开起自动射击的时候，会自动瞄准到敌人
##         （玩家可以开启是否视野跟随锁定敌人），由玩家手动开火」
##
## 移动端的取舍（用户原话）："移动端适合做减法而不是加法" ——
## 所以把这套辅助做成**显式的两个开关**，而不是藏在手感里。
##
## 纯 RefCounted，可 headless 单测。

## 目标暂时离开视野后仍保持锁定的时间（秒）。
## 没有这个"锁定粘性"，敌人一走动就会疯狂切换目标，准心会抖。
const LOCK_GRACE := 1.2
## 默认目标半径（与 AimAssist 保持一致）
const DEFAULT_RADIUS := AimAssist.DEFAULT_HIT_RADIUS

## 当前锁定的目标 id（-1 = 无）
var locked_id := -1
var locked_pos := Vector2.ZERO
## 锁定粘性倒计时
var _grace := 0.0
## 统计（测试/调试）
var switch_count := 0


func reset() -> void:
	locked_id = -1
	locked_pos = Vector2.ZERO
	_grace = 0.0
	switch_count = 0


func has_lock() -> bool:
	return locked_id >= 0


## 在锥形视野里找【最近的】敌人。
##
## 与 AimAssist.pick 的区别：
##   · AimAssist 是"开火那一刻把射线加粗"（子弹磁性），判定窄
##   · 本函数是"常驻的视野扫描"，锥角大（由枪械决定），用于锁定与自动射击
##
## 返回 {} 或 {target, dist, pos}
static func scan_nearest(origin: Vector2, aim_dir: Vector2, half_angle_deg: float,
		max_range: float, targets: Array, grid: LogicalGrid,
		player_faction: String = "player",
		radius: float = DEFAULT_RADIUS) -> Dictionary:
	if aim_dir == Vector2.ZERO or targets.is_empty():
		return {}
	var aim := aim_dir.normalized()
	# ── 视野锥是【绝对上限】（真机反馈 #1）──
	# 即使调用方传了更大的锥角，也不许超过玩家视野锥门限。
	# 早先这里完全没有角度上限 —— 近距离的"半径通路"会把背后/脚下的
	# 敌人一起放行，于是"朝上瞄却锁到下方敌人"。
	var cone := minf(half_angle_deg, AimAssist.PLAYER_VISION_HALF_DEG)
	var cos_limit := cos(deg_to_rad(cone))

	var best: Dictionary = {}
	var best_dist := INF

	for t in targets:
		if not (t is Dictionary):
			continue
		# 目标筛选（不能锁同伴/中立）
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
		# 视野锥硬门限：越过就出局，无论多近。
		if not AimAssist.within_vision_cone(angle_deg):
			continue
		var perp := absf(aim.cross(dir_t)) * dist
		var tr := float(t.get("radius", radius))
		# 锥内：角度锥 OR 实体半径 —— 近距离必须靠半径，否则贴脸永远锁不上
		if dot < cos_limit and perp > tr:
			continue

		# 视线遮挡
		if grid != null and not Ballistics.has_line_of_sight(grid, origin, tp):
			continue

		# ⭐ 用户要求：**优先锁定最近的敌人**
		if dist < best_dist:
			best_dist = dist
			best = {"target": t, "dist": dist, "pos": tp}

	return best


## 每帧更新锁定状态。
## 返回 {target, dist, pos, changed, has_lock, visible}
##
## ⚠️ `visible` 和 `has_lock` 是【两件事】，必须分开：
##   · has_lock：锁定还在（含 1.2 秒粘性）—— 用来**平滑瞄准**，避免准心抖
##   · visible ：**这一帧真的看得见**（有视线、在锥内）—— 用来决定**能不能开火**
##
## 早先只有 has_lock，于是"自动射击"会在敌人躲到墙后**继续朝墙打 1.2 秒**
## （用户实测："会导致透视到敌人对墙开火"）。
## 修法就是让开火判定用 visible，而不是 has_lock。
func update(dt: float, origin: Vector2, aim_dir: Vector2, half_angle_deg: float,
		max_range: float, targets: Array, grid: LogicalGrid,
		player_faction: String = "player",
		radius: float = DEFAULT_RADIUS) -> Dictionary:

	var found := scan_nearest(origin, aim_dir, half_angle_deg, max_range,
		targets, grid, player_faction, radius)

	var changed := false
	if not found.is_empty():
		var new_id := int(found["target"].get("id", -1))
		if new_id != locked_id:
			changed = true
			switch_count += 1
		locked_id = new_id
		locked_pos = found["pos"]
		_grace = LOCK_GRACE
		return {"target": found["target"], "dist": found["dist"],
			"pos": found["pos"], "changed": changed,
			"has_lock": true, "visible": true}

	# 没找到：靠粘性再撑一会儿（否则准心会疯狂切换）
	if locked_id >= 0:
		_grace -= dt
		if _grace > 0.0:
			# ⚠️ 粘性期间 has_lock=true 但 **visible=false** —— 绝不允许开火
			return {"target": {}, "dist": -1.0, "pos": locked_pos,
				"changed": false, "has_lock": true, "visible": false}
		# 粘性耗尽 -> 真正脱锁
		locked_id = -1
		_grace = 0.0
		changed = true

	return {"target": {}, "dist": -1.0, "pos": Vector2.ZERO,
		"changed": changed, "has_lock": false, "visible": false}


## 从当前方向朝目标转过去，带角度上限（避免瞬间甩头）。
## 返回新的方向。
static func turn_toward(from: Vector2, to: Vector2, max_deg: float) -> Vector2:
	if from == Vector2.ZERO:
		return to.normalized() if to != Vector2.ZERO else Vector2.RIGHT
	if to == Vector2.ZERO:
		return from
	var a := from.angle()
	var b := to.angle()
	var diff := wrapf(b - a, -PI, PI)
	var step := clampf(diff, -deg_to_rad(max_deg), deg_to_rad(max_deg))
	return Vector2.from_angle(a + step)
