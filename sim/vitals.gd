class_name Vitals
extends RefCounted

## 人物状态 —— A 阶段范围（血量 / 护甲 / 流血）
##
## 依据 specs/feasibility.md §4：B 阶段砍到 3 项，饥饿脱水这类对快节奏搜打撤是噪音。
## 依据 specs/tech-stack.md T-52：不做部位血量，改由 DamageModel 决定"打哪更疼"。
##
## 纯 RefCounted，可 headless 单测。

enum Bleed { NONE, LIGHT, HEAVY }

const BLEED_DPS := {Bleed.NONE: 0.0, Bleed.LIGHT: 0.35, Bleed.HEAVY: 1.2}
const BLEED_NAME := {Bleed.NONE: "无", Bleed.LIGHT: "轻度流血", Bleed.HEAVY: "重度流血"}

## 护甲吸收比例（伤害的一部分先扣护甲）
const ARMOR_ABSORB := 0.55
## 超重对移速的惩罚（每超出 1 倍负重）
const OVERWEIGHT_SLOWDOWN := 0.45

var hp: int = 100
var max_hp: int = 100
var armor: int = 0
var max_armor: int = 0
var bleed: int = Bleed.NONE

var bleeding_accum: float = 0.0
var dead: bool = false

## 统计
var total_damage_taken: int = 0
var armor_absorbed: int = 0


func reset(h: int = 100, a: int = 0) -> void:
	max_hp = h
	hp = h
	max_armor = a
	armor = a
	bleed = Bleed.NONE
	bleeding_accum = 0.0
	dead = false
	total_damage_taken = 0
	armor_absorbed = 0


## 受伤。护甲先吸收一部分，剩余进 HP。返回实际掉的血。
func take_damage(amount: int) -> int:
	return _apply_damage(amount, ARMOR_ABSORB)


## 按【弹型穿透比例】结算一次受击 —— 弹型系统（穿甲/标准/肉伤）的落点。
##
## through_ratio 由 `DamageModel.armor_multiplier(pen, armor)` 得出（0~1）：
##   穿甲弹 pen 高 -> 接近 1 -> 护甲基本吃不到伤害；
##   肉伤弹 pen 低 -> 偏低  -> 护甲吃掉更多。
##
## ⚠️ 为什么另开一个方法而不改 take_damage：
##    旧方法写死 ARMOR_ABSORB=0.55，`s05`/`s10` 等既有测试直接按这个值断言。
##    保留旧签名 = 那批测试**逐字节不变**，新语义只在新路径上生效。
func take_hit(amount: int, through_ratio: float) -> int:
	var absorb := clampf(1.0 - through_ratio, 0.0, 1.0)
	return _apply_damage(amount, absorb)


## 受击结算的共同实现。absorb_ratio = 护甲吸收比例（0~1）。
func _apply_damage(amount: int, absorb_ratio: float) -> int:
	if dead or amount <= 0:
		return 0
	var dmg := amount

	if armor > 0:
		var absorbed := int(round(float(dmg) * absorb_ratio))
		absorbed = mini(absorbed, armor)
		armor -= absorbed
		armor_absorbed += absorbed
		dmg -= absorbed

	hp = maxi(0, hp - dmg)
	total_damage_taken += dmg
	if hp <= 0:
		dead = true
	return dmg


## 治疗。返回实际回复量。
func heal(amount: int) -> int:
	if amount <= 0 or dead:
		return 0
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before


## 修甲
func repair_armor(amount: int) -> int:
	if amount <= 0 or dead:
		return 0
	var before := armor
	armor = mini(max_armor, armor + amount)
	return armor - before


## 施加/加重流血
func apply_bleed(level: int) -> void:
	bleed = maxi(bleed, level)


func stop_bleed() -> void:
	bleed = Bleed.NONE
	bleeding_accum = 0.0


func is_bleeding() -> bool:
	return bleed != Bleed.NONE


## 当前每秒流血伤害
func bleed_dps() -> float:
	return float(BLEED_DPS.get(bleed, 0.0))


## 主循环：处理持续流血。返回本帧因流血掉的血。
func tick(delta: float) -> int:
	if dead or not is_bleeding():
		return 0
	bleeding_accum += bleed_dps() * delta
	var whole := int(floor(bleeding_accum))
	if whole <= 0:
		return 0
	bleeding_accum -= float(whole)
	hp = maxi(0, hp - whole)
	total_damage_taken += whole
	if hp <= 0:
		dead = true
	return whole


## 移动速度倍率：受伤、流血、超重都会拖慢
func speed_multiplier(weight_ratio: float = 0.0) -> float:
	if dead:
		return 0.0
	var m := 1.0
	# 血量过低会跛行
	var hp_ratio := float(hp) / maxf(1.0, float(max_hp))
	if hp_ratio < 0.3:
		m *= lerpf(0.6, 1.0, hp_ratio / 0.3)
	if bleed == Bleed.HEAVY:
		m *= 0.85
	if weight_ratio > 1.0:
		m *= clampf(1.0 - (weight_ratio - 1.0) * OVERWEIGHT_SLOWDOWN, 0.25, 1.0)
	return clampf(m, 0.1, 1.0)


func hp_ratio() -> float:
	return float(hp) / maxf(1.0, float(max_hp))


func armor_ratio() -> float:
	if max_armor <= 0:
		return 0.0
	return float(armor) / float(max_armor)


func status_text() -> String:
	var parts: Array[String] = []
	parts.append("HP %d/%d" % [hp, max_hp])
	if max_armor > 0:
		parts.append("护甲 %d/%d" % [armor, max_armor])
	if is_bleeding():
		parts.append(String(BLEED_NAME[bleed]))
	if dead:
		parts.append("已阵亡")
	return " | ".join(parts)


func _to_string() -> String:
	return "Vitals(%s)" % status_text()
