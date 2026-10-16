class_name GearGen
extends RefCounted

## 装备生成器（全境2化 Phase 1，2026-10-16）—— roll 品质 / 词条 / 评分。
##
## ⭐ 所有随机走**注入的 SimRng**（T-32 纪律：全局随机无法复现，同 seed 整局可复现）。
##
## gear 数据结构（随背包槽位 / Equipment 槽位流动，见 Inventory.add_with_gear）：
##   {
##     "rarity": "rare",                              # RarityDef.id
##     "affixes": [{"id": "aff_weapon_dmg", "value": 0.08}, ...]
##   }
##   · 无 gear（null）或 affixes 为空 = 普通品质零词条 = 与 2026-10-16 之前的行为一致
##     （向后兼容：老存档、商店货、转移丢失都不改变数值）
##
## 纯静态、无状态，可 headless 单测（D-06 / T-69）。

## 类别基础分（装备评分的底座）。未列出的类别取 50。
const BASE_SCORE := {
	"weapon": 120, "armor": 70, "helmet": 50, "backpack": 60,
}

## 每个词条给评分的加成系数（6%）
const AFFIX_SCORE_BONUS := 0.06


## 按 drop_weight 抽一个品质。rarities 为空时返回 null（调用方应回退到无 gear）。
static func roll_rarity(rng: SimRng, rarities: Array) -> RarityDef:
	if rng == null or rarities.is_empty():
		return null
	var weights: Array = []
	for r in rarities:
		var rd: RarityDef = r as RarityDef
		weights.append(0 if rd == null else rd.drop_weight)
	var idx := rng.weighted_index(weights)
	if idx < 0 or idx >= rarities.size():
		return null
	return rarities[idx] as RarityDef


## 按 id 找品质定义（找不到返回 null）
static func find_rarity(rarities: Array, id: String) -> RarityDef:
	for r in rarities:
		var rd: RarityDef = r as RarityDef
		if rd != null and rd.id == id:
			return rd
	return null


## 生成一件装备的 gear。
## [param category] 物品类别（weapon/armor/backpack；helmet 数据层同属 armor）
## 返回 {"rarity": String, "affixes": Array[Dictionary]}；rarities 为空返回 {}。
static func roll_gear(rng: SimRng, rarities: Array, affixes: Array,
		category: String) -> Dictionary:
	var r := roll_rarity(rng, rarities)
	if r == null:
		return {}
	var picked: Array = _pick_affix_defs(rng, affixes, category, r.affix_count)
	var rolled: Array = []
	for a in picked:
		var ad: AffixDef = a as AffixDef
		rolled.append({"id": ad.id, "value": ad.roll_value(rng, r.power_mul)})
	return {"rarity": r.id, "affixes": rolled}


## 从词条池里**不重复**抽 n 个适用该类别的定义（部分 Fisher-Yates 洗牌）。
## 池子不够时有多少抽多少（不炸）。
static func _pick_affix_defs(rng: SimRng, affixes: Array, category: String,
		n: int) -> Array:
	if rng == null or n <= 0:
		return []
	var pool: Array = []
	for a in affixes:
		var ad: AffixDef = a as AffixDef
		if ad != null and ad.fits(category):
			pool.append(ad)
	var out: Array = []
	var k := mini(n, pool.size())
	for _i in range(k):
		var j := rng.randi_range(out.size(), pool.size() - 1)
		var tmp = pool[out.size()]
		pool[out.size()] = pool[j]
		pool[j] = tmp
		out.append(pool[out.size()])
	return out


## 装备评分：基础分 × 品质系数 × (1 + 6% × 词条数)。
## rarity 传 null 时按 power_mul=1/score_mul=1 处理（无 gear 装备也有分，方便统一显示）。
static func score_of(gear: Dictionary, category: String,
		rarity: RarityDef = null) -> int:
	var base: float = float(BASE_SCORE.get(category, 50))
	var smul := 1.0
	var n := 0
	if not gear.is_empty():
		n = int((gear.get("affixes", []) as Array).size())
		if rarity != null:
			smul = rarity.score_mul
	elif rarity != null:
		smul = rarity.score_mul
	return int(round(base * smul * (1.0 + AFFIX_SCORE_BONUS * float(n))))


## 摘要文本："稀有 · 武器伤害+8%, 射速+5%"（无词条时只给品质名）。
## [param affix_table] AffixDef 数组（按 id 查名字；查不到的词条跳过不编）。
static func summary(gear: Dictionary, rarity: RarityDef = null,
		affix_table: Array = []) -> String:
	if gear.is_empty():
		return "普通" if rarity == null else rarity.name
	var head := rarity.name if rarity != null else "普通"
	var parts: Array[String] = []
	for e in (gear.get("affixes", []) as Array):
		if not (e is Dictionary):
			continue
		var ad := find_affix(affix_table, str((e as Dictionary).get("id", "")))
		if ad == null:
			continue
		parts.append(ad.describe(float((e as Dictionary).get("value", 0.0))))
	if parts.is_empty():
		return head
	return head + " · " + ", ".join(parts)


## 按 id 找词条定义（找不到返回 null）
static func find_affix(affix_table: Array, id: String) -> AffixDef:
	for a in affix_table:
		var ad: AffixDef = a as AffixDef
		if ad != null and ad.id == id:
			return ad
	return null
