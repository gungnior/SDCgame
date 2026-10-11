class_name WeaponDef
extends RefCounted

## 枪械定义。数据来源：data/weapons.json
## 契约：data/SCHEMA.md §2
##
## 纯 RefCounted —— 见 ItemDef 的说明。

var id: String = ""
var name: String = ""
var name_en: String = ""
var category: String = "weapon"
var ammo_id: String = ""
var damage: int = 0
var rpm: int = 0
var mag_size: int = 1
var reload_time: float = 0.0
var spread_deg: float = 0.0
var range_m: int = 0
var recoil_v: float = 0.0
var recoil_h: float = 0.0
var weight: float = 0.0
var value: int = 0
var icon: String = ""
var stage: String = "B"


static func from_dict(d: Dictionary) -> WeaponDef:
	var o := WeaponDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.name_en = str(d.get("name_en", ""))
	o.category = str(d.get("category", "weapon"))
	o.ammo_id = str(d.get("ammo_id", ""))
	o.damage = int(d.get("damage", 0))
	o.rpm = int(d.get("rpm", 0))
	o.mag_size = int(d.get("mag_size", 1))
	o.reload_time = float(d.get("reload_time", 0.0))
	o.spread_deg = float(d.get("spread_deg", 0.0))
	o.range_m = int(d.get("range_m", 0))
	o.recoil_v = float(d.get("recoil_v", 0.0))
	o.recoil_h = float(d.get("recoil_h", 0.0))
	o.weight = float(d.get("weight", 0.0))
	o.value = int(d.get("value", 0))
	o.icon = str(d.get("icon", ""))
	o.stage = str(d.get("stage", "B"))
	return o


## 每秒发射次数（T-50 hitscan 判定的节流依据）
func shots_per_second() -> float:
	return float(rpm) / 60.0


## 两发之间的最小间隔（秒）
func shot_interval() -> float:
	if rpm <= 0:
		return INF
	return 60.0 / float(rpm)


func _to_string() -> String:
	return "WeaponDef(%s, dmg=%d, rpm=%d)" % [id, damage, rpm]
