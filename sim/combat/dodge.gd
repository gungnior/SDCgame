class_name DodgeState
extends RefCounted

## 闪避（dodge）—— 玩家的一次短距离快速位移 + 无敌帧
##
## 用户规格（本次需求原文）：
##   「角色可以进行闪避操作，闪避的距离为 1.5 倍人物身位。」
##   位移量取自 BodyMetrics.DODGE_DISTANCE（= 1.5 身位 = 1.35 逻辑格）。
##
## ── 为什么除了位移还要给无敌帧 ──
## 本作的走廊**恒宽 1 逻辑格**（LogicalGrid：CELL_SIZE_TILES = 3），
## 而人物判定宽度是 0.9 格 —— 在走廊里根本没有「侧移 1.35 格」的空间。
## 只靠位移的话，「闪避躲弹道」在占地图很大比例的走廊里**数学上不可能**。
## 所以：开阔处靠位移（1.5 身位 > 1 身位，一步就能离开弹道），
##       走廊里靠无敌帧（否则这个操作等于没用）。
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。

## 闪避动作时长（秒）。位移 = DODGE_DISTANCE，所以速度 = 位移 / 时长。
const DURATION := 0.18
## 冷却（秒）—— 闪避是「决策」，不能连按
const COOLDOWN := 0.85
## 无敌时长（秒）。略长于动作时长，保证起手与收尾都盖住。
const INVULN_SEC := 0.22

var timer: float = 0.0        ## > 0 表示正在闪避
var cooldown: float = 0.0
var invuln: float = 0.0       ## > 0 表示处于无敌帧
var dir: Vector2 = Vector2.RIGHT
var moved: float = 0.0        ## 本次闪避已经走过的距离

## 统计（遥测 / 测试）
var started: int = 0
var blocked_damage: int = 0


func reset() -> void:
	timer = 0.0
	cooldown = 0.0
	invuln = 0.0
	moved = 0.0
	dir = Vector2.RIGHT


func is_active() -> bool:
	return timer > 0.0


func is_invulnerable() -> bool:
	return invuln > 0.0


func can_start() -> bool:
	return timer <= 0.0 and cooldown <= 0.0


## 触发一次闪避。方向为零时朝右（调用方应保证给出方向）。
func start(direction: Vector2) -> bool:
	if not can_start():
		return false
	dir = direction.normalized() if direction.length() > 0.0001 else Vector2.RIGHT
	timer = DURATION
	invuln = maxf(INVULN_SEC, DURATION)
	cooldown = COOLDOWN
	moved = 0.0
	started += 1
	return true


func tick(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	invuln = maxf(0.0, invuln - delta)
	if timer > 0.0:
		timer = maxf(0.0, timer - delta)


## 本帧的位移向量（已按剩余距离截断）。
func step(delta: float) -> Vector2:
	if timer <= 0.0 or delta <= 0.0:
		return Vector2.ZERO
	var speed := BodyMetrics.DODGE_DISTANCE / DURATION
	var remain := maxf(0.0, BodyMetrics.DODGE_DISTANCE - moved)
	var dist := minf(speed * delta, remain)
	moved += dist
	return dir * dist


## 记下一次被无敌帧挡掉的伤害（只用于提示与统计）
func note_blocked(amount: int) -> void:
	blocked_damage += maxi(amount, 0)


func _to_string() -> String:
	return "DodgeState(active=%s, cd=%.2f, invuln=%.2f, dir=%s)" % [
		str(is_active()), cooldown, invuln, str(dir.snapped(Vector2(0.01, 0.01)))]
