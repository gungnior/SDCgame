class_name RarityDef
extends RefCounted

## 装备品质定义（全境2化 Phase 1，2026-10-16）。
## 数据来源：data/gear_rarity.json · 契约：data/SCHEMA.md §12
##
## 品质决定四件事：
##   · affix_count  词条数（0~4）
##   · power_mul    全属性强度倍率（连乘进每个词条 roll 出的值）
##   · score_mul    装备评分系数
##   · death_weight 死亡保留权重（与物品价值相乘后参与 DeathPolicy.plan_keep 排序）
##
## 纯 RefCounted —— 不引用 Node/Control，可 headless 单测（D-06 / T-69）。

var id: String = ""
var name: String = ""            ## 中文名（UI 直接显示，**不许英文占位**）
var color: String = ""           ## #rrggbb，UI 名称染色用
var affix_count: int = 0         ## 词条数 0~4
var power_mul: float = 1.0       ## 强度倍率（>0）
var score_mul: float = 1.0       ## 评分系数（>0）
var death_weight: float = 1.0    ## 死亡保留权重（>0）
var drop_weight: int = 0         ## 世界生成 roll 权重（0 = 不自然掉落）


static func from_dict(d: Dictionary) -> RarityDef:
	var o := RarityDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.color = str(d.get("color", ""))
	o.affix_count = clampi(int(d.get("affix_count", 0)), 0, 4)
	o.power_mul = maxf(0.01, float(d.get("power_mul", 1.0)))
	o.score_mul = maxf(0.01, float(d.get("score_mul", 1.0)))
	o.death_weight = maxf(0.01, float(d.get("death_weight", 1.0)))
	o.drop_weight = maxi(0, int(d.get("drop_weight", 0)))
	return o


## 该品质的十六进制颜色是否合法（数据契约校验用）
func has_valid_color() -> bool:
	return color.is_valid_html_color()


func _to_string() -> String:
	return "RarityDef(%s %s, affix=%d)" % [id, name, affix_count]
