class_name EnemyDef
extends RefCounted

## 敌人定义。数据来源：data/enemies.json
## 契约：data/SCHEMA.md §3
##
## 纯 RefCounted —— 见 ItemDef 的说明。

const ARCHETYPES := ["melee", "ranged"]

## 敌人配色的默认值（数据缺 color 时用）。
const DEFAULT_COLOR := Color(0.62, 0.66, 0.72)

## 远程敌人的反应时间下限。低于此值会被玩家感知为「不公平」。
## 依据：specs/reference-teardown.md §7 —— reaction_time 是决定公平感的关键数值。
const MIN_RANGED_REACTION := 0.25

var id: String = ""
var name: String = ""
var name_en: String = ""
var archetype: String = "melee"
var hp: int = 1
var move_speed: float = 0.0
var sight_range_m: int = 0
var sight_angle_deg: int = 90
var hear_range_m: int = 0
var reaction_time: float = 0.0
var give_up_dist_m: int = 0
var damage: int = 1
var attack_cooldown: float = 1.0
var loot_value_avg: int = 0
var sprite: String = ""
var stage: String = "B"

## 护甲值 0~10（2026-10-13）。**0 = 无甲**。
## 这是"穿甲弹 vs 肉伤弹"要对抗的那个值：
##   有甲单位 -> 穿甲弹(高 pen)优势；无甲单位 -> 肉伤弹(高 flesh)优势。
## 与 armor_id（死后掉落的护甲物品）是两回事：那个是战利品，这个是战斗数值。
var armor: int = 0

## ── 敌人携带的装备（C 阶段「敌人装备系统」）──
## 敌人死后这些会**掉进尸体**，玩家可以从尸体上拿到枪 / 护甲（见
## `view/raid_scene.gd::_spawn_corpse`）—— 这是"打敌人换装备"这条循环的来源。
## ⚠️ 存的是 **weapon_id**（武器不是 item）与 **item_id**（护甲/头盔是 item）。
var weapon_id: String = ""
var armor_id: String = ""
var helmet_id: String = ""

## ── 类型配色（2026-10-13 真机反馈 #3：不同敌人要有不同特征颜色）──
#
# 用户原话："不同的敌人需要有不同的特征（颜色），现有的系统是敌人会警戒然后变色"。
#
# 问题在于：敌人身上**只有一条颜色通道**，而它被"警戒状态"占满了
# （放松灰 / 警觉黄 / 交战红）。于是"感染体"和"重装暴徒"看起来一模一样，
# 玩家分不清面前是谁，只能读状态。
#
# 现在把两条信息拆到两个通道：
#   · **填充色 = 类型身份**（本字段，来自 data/enemies.json 的 `color`）
#   · **外圈环 = 警戒状态**（view/raid_drawer.gd 画）
# 数据缺 `color` 时按 id 稳定派生（同一 id 永远同一色），不会退化成一片灰。
var color: Color = DEFAULT_COLOR


static func from_dict(d: Dictionary) -> EnemyDef:
	var o := EnemyDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.name_en = str(d.get("name_en", ""))
	o.archetype = str(d.get("archetype", "melee"))
	o.hp = int(d.get("hp", 1))
	o.move_speed = float(d.get("move_speed", 0.0))
	o.sight_range_m = int(d.get("sight_range_m", 0))
	o.sight_angle_deg = int(d.get("sight_angle_deg", 90))
	o.hear_range_m = int(d.get("hear_range_m", 0))
	o.reaction_time = float(d.get("reaction_time", 0.0))
	o.give_up_dist_m = int(d.get("give_up_dist_m", 0))
	o.damage = int(d.get("damage", 1))
	o.attack_cooldown = float(d.get("attack_cooldown", 1.0))
	o.loot_value_avg = int(d.get("loot_value_avg", 0))
	o.sprite = str(d.get("sprite", ""))
	o.stage = str(d.get("stage", "B"))
	o.weapon_id = str(d.get("weapon_id", ""))
	o.armor_id = str(d.get("armor_id", ""))
	o.helmet_id = str(d.get("helmet_id", ""))
	o.armor = int(d.get("armor", 0))
	o.color = _parse_color(str(d.get("color", "")), o.id)
	return o


## 数据缺 color 时按 id 稳定派生一个颜色 ——
## 保证"任何敌人都有可区分的身份色"，而不是全挤在同一个灰上。
static func color_from_id(id: String) -> Color:
	if id.is_empty():
		return DEFAULT_COLOR
	var h := float(abs(hash(id)) % 360) / 360.0
	return Color.from_hsv(h, 0.55, 0.72)


## 解析 "#rrggbb" / "#rrggbbaa"；非法或空 -> 按 id 派生（绝不报错、绝不黑块）。
static func _parse_color(s: String, id: String) -> Color:
	var t := s.strip_edges()
	if t.is_empty():
		return color_from_id(id)
	if not t.begins_with("#"):
		t = "#" + t
	if not Color.html_is_valid(t):
		return color_from_id(id)
	return Color.html(t)


## 该敌人是否有护甲（有甲 -> 穿甲弹更有效）
func has_armor() -> bool:
	return armor > 0


func is_ranged() -> bool:
	return archetype == "ranged"


## 视野锥半角的余弦值。用于 T-84 的纯数学粗筛：
##   dot(facing, to_target) > cos(half_angle)  零物理开销
func sight_cos_half_angle() -> float:
	return cos(deg_to_rad(float(sight_angle_deg) * 0.5))


func _to_string() -> String:
	return "EnemyDef(%s, %s, hp=%d)" % [id, archetype, hp]
