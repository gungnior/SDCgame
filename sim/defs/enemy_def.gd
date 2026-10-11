class_name EnemyDef
extends RefCounted

## 敌人定义。数据来源：data/enemies.json
## 契约：data/SCHEMA.md §3
##
## 纯 RefCounted —— 见 ItemDef 的说明。

const ARCHETYPES := ["melee", "ranged"]

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
	return o


func is_ranged() -> bool:
	return archetype == "ranged"


## 视野锥半角的余弦值。用于 T-84 的纯数学粗筛：
##   dot(facing, to_target) > cos(half_angle)  零物理开销
func sight_cos_half_angle() -> float:
	return cos(deg_to_rad(float(sight_angle_deg) * 0.5))


func _to_string() -> String:
	return "EnemyDef(%s, %s, hp=%d)" % [id, archetype, hp]
