class_name AffixDef
extends RefCounted

## 装备词条定义（全境2化 Phase 1，2026-10-16）。
## 数据来源：data/gear_affixes.json · 契约：data/SCHEMA.md §12
##
## 三种词条类型（kind）：
##   pct      正向百分比：result = current * (1 + v)      （伤害/射速/射程/生命/移速）
##   pct_neg  负向百分比：result = current * (1 - v)      （装填时间/散布 —— 越低越好）
##   flat     直加：      result = current + v            （护甲值）
##
## field 的落点（ Equipment.build_loadout / effective_armor / vitals / 玩家移速四处消费）：
##   damage/rpm/reload_time/spread_deg/range_m -> Loadout.effective（武器，经 to_weapon_def）
##   armor   -> Equipment.effective_armor()
##   hp      -> raid_scene 建 vitals 时的生命上限
##   move_speed -> raid_scene 玩家移动速度
##
## 纯 RefCounted，可 headless 单测（D-06 / T-69）。

var id: String = ""
var name: String = ""            ## 中文名（UI 直接显示）
var field: String = ""           ## 目标字段（见文件头落点表）
var kind: String = "pct"         ## pct / pct_neg / flat
var min_value: float = 0.0       ## roll 下界（已按 kind 取正值）
var max_value: float = 0.0       ## roll 上界
var cats: Array = []             ## 适用类别（weapon/armor/backpack；helmet 在数据里同属 armor）


static func from_dict(d: Dictionary) -> AffixDef:
	var o := AffixDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.field = str(d.get("field", ""))
	o.kind = str(d.get("kind", "pct"))
	if not ["pct", "pct_neg", "flat"].has(o.kind):
		o.kind = "pct"
	var lo := maxf(0.0, float(d.get("min", 0.0)))
	var hi := maxf(0.0, float(d.get("max", 0.0)))
	if hi < lo:
		var t := lo
		lo = hi
		hi = t
	o.min_value = lo
	o.max_value = hi
	var cats: Array = d.get("cats", [])
	for c in cats:
		o.cats.append(str(c))
	return o


## 是否适用于某个物品类别
func fits(category: String) -> bool:
	if cats.is_empty():
		return true          # 没配 = 通用（向后兼容）
	return cats.has(category)


## 按品质强度倍率 roll 一个值（取正值，符号由 kind 在 apply_to 里处理）
func roll_value(rng: SimRng, power_mul: float = 1.0) -> float:
	if rng == null:
		return 0.0
	var v := rng.randf_range(min_value, max_value) * maxf(0.01, power_mul)
	# flat 词条（护甲）保持整数观感；pct 类保留两位小数足够展示
	if kind == "flat":
		return maxf(1.0, round(v))
	return snappedf(v, 0.01)


## 把 roll 出的值应用到当前数值上
func apply_to(current: float, rolled: float) -> float:
	match kind:
		"pct_neg":
			return current * (1.0 - clampf(rolled, 0.0, 0.95))
		"flat":
			return current + rolled
		_:                           # "pct"
			return current * (1.0 + rolled)


## 展示文本："武器伤害 +8%" / "装填速度 -9%" / "护甲强化 +2"
func describe(rolled: float) -> String:
	match kind:
		"flat":
			return "%s +%d" % [name, int(round(rolled))]
		"pct_neg":
			return "%s -%d%%" % [name, int(round(rolled * 100.0))]
		_:
			return "%s +%d%%" % [name, int(round(rolled * 100.0))]


func _to_string() -> String:
	return "AffixDef(%s %s %s)" % [id, name, kind]
