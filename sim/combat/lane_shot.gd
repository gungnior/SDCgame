class_name LaneShot
extends RefCounted

## 一条**固定弹道** —— 敌人远程攻击的表现与判定
##
## 用户规格（本次需求原文）：
##   「敌人的攻击为固定弹道，宽度为两倍人物判定身位，会固定锁定人物为中心，
##     即人物两侧的弹道均为 1 格人物身位。」
##
## 与改造前（hitscan + 掷骰子决定是否命中）的关键差别：
##   · **方向在开火瞬间锁死**（dir 一旦定下就不再改）—— 「固定弹道」，不走追踪
##   · **宽度是几何实体**（半宽 = 1 身位）—— 站在弹道外就是打不到，不看运气
##   · **命中在「前沿扫过」的那一刻结算** —— 于是飞行时间就是玩家的闪避窗口
##
## 坐标约定与 Ballistics 一致：逻辑格单位的浮点坐标。
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。

## 弹速（逻辑格 / 秒）。
## ⚠️ 这个值是「闪避窗口」的唯一旋钮：飞行时间 = 距离 / 速度。
##    11 格/秒时，6 格外的敌人给你约 0.55 秒 —— 足够做一次 0.18 秒的闪避。
const DEFAULT_SPEED := 11.0

var origin: Vector2 = Vector2.ZERO
## 开火瞬间锁定的方向（单位向量）。固定弹道 = 这个值之后**永不改变**。
var dir: Vector2 = Vector2.RIGHT
## 半宽（逻辑格）。两侧各 1 身位 -> 总宽 2 身位。
var half_width: float = BodyMetrics.LANE_HALF_WIDTH
var speed: float = DEFAULT_SPEED
var damage: int = 0
## 这条弹道能飞多远（开火时按射程与墙提前算好，含撞墙截断）
var length: float = 0.0
## 已经飞过的距离（前沿位置 = origin + dir * traveled）
var traveled: float = 0.0
var done: bool = false
## 已经命中过玩家（一条弹道只结算一次）
var hit_player: bool = false
## 所属敌人 id / 武器 id（表现层与遥测用）
var owner_id: int = -1
var weapon_id: String = ""


func remaining() -> float:
	return maxf(0.0, length - traveled)


## 弹道前沿的世界位置
func head_pos() -> Vector2:
	return origin + dir * traveled


func end_pos() -> Vector2:
	return origin + dir * length


## 玩家中心到弹道**中心线**的垂距（逻辑格）。> half_width 即「站在弹道外」。
func perpendicular_distance(p: Vector2) -> float:
	return absf((p - origin).cross(dir))


## 玩家在弹道上的投影距离（从开火点算起）。< 0 表示在敌人背后。
func projection_distance(p: Vector2) -> float:
	return (p - origin).dot(dir)


## 推进一帧。返回 {hit, finished, head}。
##
## 命中条件（两条同时满足）：
##   ① 玩家中心到中心线的垂距 <= 半宽（几何上站在弹道里）
##   ② 前沿本帧**扫过**了玩家的投影位置（prev <= t <= next）—— 这就是「子弹飞过」
##      ⚠️ 只有 ② 才能让「先站在弹道里、子弹飞到前闪开」变成真正的躲开。
func advance(delta: float, player_pos: Vector2) -> Dictionary:
	var out := {"hit": false, "finished": false, "head": head_pos()}
	if done:
		out["finished"] = true
		return out
	var prev := traveled
	var next := minf(traveled + speed * maxf(delta, 0.0), length)
	traveled = next

	if not hit_player:
		var t := projection_distance(player_pos)
		if t >= prev and t <= next and perpendicular_distance(player_pos) <= half_width:
			hit_player = true
			out["hit"] = true

	if traveled >= length - 0.0001:
		done = true
		out["finished"] = true
	out["head"] = head_pos()
	return out


func _to_string() -> String:
	return "LaneShot(owner=%d, dir=%s, traveled=%.2f/%.2f, half=%.2f, dmg=%d%s)" % [
		owner_id, str(dir.snapped(Vector2(0.01, 0.01))), traveled, length,
		half_width, damage, " [done]" if done else ""]
