class_name DamageModel
extends RefCounted

## 伤害与部位模型
##
## 依据 specs/tech-stack.md T-52：
##   ⚠️ 【不要做「爆头」】。2D 俯视里没有真正的垂直维度，硬做爆头体验很差。
##   改为俯视专属的「部位 / 弱点」模型：命中部位由【瞄准精度 + 距离】概率决定，
##   倍率走数据，玩家能感知到"打得准就更疼"。
##
## 纯静态方法，无状态，可 headless 单测。

const PART_HEAD := "head"
const PART_TORSO := "torso"
const PART_LIMB := "limb"

## 部位伤害倍率
const MULT := {
	PART_HEAD: 2.0,
	PART_TORSO: 1.0,
	PART_LIMB: 0.7,
}

## 距离衰减：超过有效射程后仍能造成伤害，但最少保留这个比例
const MIN_FALLOFF := 0.40


## 由武器与该发子弹的散布（含后坐力）算"瞄准精度"，0~1。
static func accuracy_at(weapon: WeaponDef, distance_m: float, extra_spread_deg: float = 0.0) -> float:
	if weapon == null:
		return 0.0
	var range_m := maxf(1.0, float(weapon.range_m))
	var falloff := 1.0 - clampf(distance_m / range_m, 0.0, 1.0)
	var spread := weapon.spread_deg + extra_spread_deg
	var spread_penalty := clampf(1.0 - spread / 12.0, 0.05, 1.0)
	return clampf(falloff * spread_penalty, 0.0, 1.0)


## 概率决定命中部位。accuracy 越高，头/弱点概率越大。
static func pick_part(rng: SimRng, accuracy: float) -> String:
	var a := clampf(accuracy, 0.0, 1.0)
	var w_head := 4.0 + 30.0 * a          # 4% ~ 34%
	var w_torso := 60.0
	var w_limb := 36.0 - 14.0 * a         # 36% ~ 22%
	var parts := [PART_HEAD, PART_TORSO, PART_LIMB]
	var idx := rng.weighted_index([w_head, w_torso, w_limb])
	if idx < 0:
		return PART_TORSO
	return parts[idx]


## 结算一发子弹的伤害
static func resolve(weapon: WeaponDef, distance_m: float, part: String) -> int:
	if weapon == null:
		return 0
	var range_m := maxf(1.0, float(weapon.range_m))
	var t := clampf(distance_m / range_m, 0.0, 1.5)
	var falloff := lerpf(1.0, MIN_FALLOFF, clampf(t, 0.0, 1.0))
	var mult := float(MULT.get(part, 1.0))
	return maxi(1, int(round(float(weapon.damage) * mult * falloff)))


## 一次完整的命中结算：先定部位，再算伤害。
## 返回 {part: String, multiplier: float, damage: int, accuracy: float}
static func resolve_hit(weapon: WeaponDef, distance_m: float, extra_spread_deg: float, rng: SimRng) -> Dictionary:
	var acc := accuracy_at(weapon, distance_m, extra_spread_deg)
	var part := pick_part(rng, acc)
	return {
		"part": part,
		"multiplier": float(MULT.get(part, 1.0)),
		"damage": resolve(weapon, distance_m, part),
		"accuracy": acc,
	}


## 一组伤害的时间-杀伤预期（供平衡调参用，不参与运行时判定）
static func expected_damage_per_second(weapon: WeaponDef, distance_m: float) -> float:
	if weapon == null or weapon.rpm <= 0:
		return 0.0
	var sps := float(weapon.rpm) / 60.0
	var acc := accuracy_at(weapon, distance_m)
	var avg_mult := (
		float(MULT[PART_HEAD]) * (4.0 + 30.0 * acc)
		+ float(MULT[PART_TORSO]) * 60.0
		+ float(MULT[PART_LIMB]) * (36.0 - 14.0 * acc)
	) / 100.0
	return resolve(weapon, distance_m, PART_TORSO) * avg_mult * sps


## 打死一个敌人需要几发（期望值）
static func shots_to_kill(weapon: WeaponDef, enemy: EnemyDef, distance_m: float) -> float:
	var dps := expected_damage_per_second(weapon, distance_m)
	if dps <= 0.0:
		return INF
	var sps := float(weapon.rpm) / 60.0
	if sps <= 0.0:
		return INF
	var per_shot := dps / sps
	if per_shot <= 0.0:
		return INF
	return float(enemy.hp) / per_shot


# ─────────────────── 弹药 vs 护甲（2026-10-13）───────────────────
#
# 这是"穿甲弹 / 肉伤弹"取舍的**唯一落点**：
#   对有甲目标 —— pen（穿甲值）越高越有效。0.25 是下界，
#                  保证"打不穿也能磨"，不会出现 0 伤害的挫败感。
#   对无甲目标 —— flesh（肉伤倍率）越高越有效。
# 于是：AP 弹 pen 高 flesh 低 -> 专打有甲；HP 弹反之 -> 专打无甲。
# 标准弹居中 = 万金油。数值与契约见 data/SCHEMA.md §1「弹药弹型」。

## 穿甲系数：0.25 ~ 1.0。目标无甲时恒为 1.0。
static func armor_multiplier(pen: float, target_armor: float) -> float:
	if target_armor <= 0.0:
		return 1.0
	return 0.25 + 0.75 * clampf(pen / target_armor, 0.0, 1.0)


## 把"基础伤害"按【弹药弹型 + 目标护甲】结算成最终伤害。
## ammo 为 null（老数据/未指定）时退化为"无弹型加成"，保持向后兼容。
static func resolve_vs_armor(base_damage: int, ammo: ItemDef, target_armor: float) -> int:
	if base_damage <= 0:
		return 0
	var flesh := 1.0
	var pen := 0.0
	if ammo != null:
		flesh = ammo.flesh_mult()
		pen = ammo.pen
	return maxi(1, int(round(float(base_damage) * flesh * armor_multiplier(pen, target_armor))))


## 带弹药的完整命中结算：先定部位算基础伤害，再过弹药/护甲。
## 返回在 resolve_hit 的基础上多出：{"ammo": id, "armor": 目标护甲}
static func resolve_hit_with_ammo(weapon: WeaponDef, ammo: ItemDef, distance_m: float,
		extra_spread_deg: float, target_armor: float, rng: SimRng) -> Dictionary:
	var hit := resolve_hit(weapon, distance_m, extra_spread_deg, rng)
	hit["damage"] = resolve_vs_armor(int(hit["damage"]), ammo, target_armor)
	hit["ammo"] = "" if ammo == null else ammo.id
	hit["armor"] = target_armor
	return hit


## 对某个敌人的期望"几发打死"，考虑弹型与护甲。供平衡调参。
static func shots_to_kill_vs_armor(weapon: WeaponDef, ammo: ItemDef, enemy: EnemyDef,
		distance_m: float) -> float:
	if weapon == null or enemy == null or weapon.rpm <= 0:
		return INF
	var per_shot := float(resolve_vs_armor(weapon.damage, ammo, float(enemy.armor)))
	if per_shot <= 0.0:
		return INF
	return float(enemy.hp) / per_shot
