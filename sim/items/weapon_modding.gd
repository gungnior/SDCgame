class_name WeaponModding
extends RefCounted

## 枪械改装 —— 把配件装到枪上，产出【有效的战斗数值】
##
## 依据 specs/feasibility.md D-08：
##   第一版只改数值 + 锚点外观叠加，不做视觉变形。
##
## 依据 specs/roadmap-bac.md §3：A 阶段每把枪 2 个插槽，C 阶段完整。
##
## 设计要点：不改动 WeaponDef 本体（数据是只读真源），而是产出一个 Loadout 快照。
## 纯 RefCounted，可 headless 单测。

## A 阶段每把枪开放的插槽数
const SLOTS_A := 2
const SLOTS_C := 4
## 允许的字段（防止配件写出危险字段）
const MODIFIABLE := [
	"damage", "rpm", "mag_size", "reload_time", "spread_deg",
	"range_m", "recoil_v", "recoil_h", "weight", "noise_m",
]
## 数值下限（避免出现负数伤害这类荒谬结果）
const FLOORS := {
	"damage": 1.0,
	"rpm": 20.0,
	"mag_size": 1.0,
	"reload_time": 0.3,
	"spread_deg": 0.0,
	"range_m": 3.0,
	"recoil_v": 0.0,
	"recoil_h": 0.0,
	"weight": 0.05,
	"noise_m": 0.0,
}


## 改装结果：一把枪的完整有效数值 + 用了哪些配件
class Loadout extends RefCounted:
	var weapon: WeaponDef = null
	var attachments: Dictionary = {}      ## slot -> AttachmentDef
	var effective: Dictionary = {}        ## 字段 -> 数值
	var free_slots: Array[String] = []

	static func create(w: WeaponDef, slot_limit: int) -> Loadout:
		var l := Loadout.new()
		l.weapon = w
		l.effective = {
			"damage": float(w.damage),
			"rpm": float(w.rpm),
			"mag_size": float(w.mag_size),
			"reload_time": w.reload_time,
			"spread_deg": w.spread_deg,
			"range_m": float(w.range_m),
			"recoil_v": w.recoil_v,
			"recoil_h": w.recoil_h,
			"weight": w.weight,
			"noise_m": 0.0,
		}
		# 按 AttachmentDef.SLOTS 的顺序取前 slot_limit 个作为可用插槽
		var all: Array = AttachmentDef.SLOTS
		for i in mini(slot_limit, all.size()):
			l.free_slots.append(all[i])
		return l

	func total_weight() -> float:
		var w: float = effective["weight"]
		return w

	func extra_value() -> int:
		var v := 0
		for s in attachments:
			v += (attachments[s] as AttachmentDef).value
		return v

	## 转成一份 WeaponDef 副本（供 DamageModel / WeaponState 使用）
	func to_weapon_def() -> WeaponDef:
		var w := WeaponDef.new()
		w.id = weapon.id
		w.name = weapon.name
		w.name_en = weapon.name_en
		w.category = weapon.category
		w.ammo_id = weapon.ammo_id
		w.damage = int(round(effective["damage"]))
		w.rpm = int(round(effective["rpm"]))
		w.mag_size = int(round(effective["mag_size"]))
		w.reload_time = effective["reload_time"]
		w.spread_deg = effective["spread_deg"]
		w.range_m = int(round(effective["range_m"]))
		w.recoil_v = effective["recoil_v"]
		w.recoil_h = effective["recoil_h"]
		w.weight = effective["weight"]
		w.value = weapon.value + extra_value()
		w.icon = weapon.icon
		w.stage = weapon.stage
		return w

	## 相对裸枪的改动摘要（供 UI 显示 +/-）
	func diff() -> Dictionary:
		var base := {
			"damage": float(weapon.damage), "rpm": float(weapon.rpm),
			"mag_size": float(weapon.mag_size), "reload_time": weapon.reload_time,
			"spread_deg": weapon.spread_deg, "range_m": float(weapon.range_m),
			"recoil_v": weapon.recoil_v, "recoil_h": weapon.recoil_h,
			"weight": weapon.weight, "noise_m": 0.0,
		}
		var d := {}
		for k in effective:
			var delta: float = effective[k] - float(base.get(k, 0.0))
			if absf(delta) > 0.0001:
				d[k] = delta
		return d

	func summary() -> String:
		var names: Array[String] = []
		for s in attachments:
			names.append((attachments[s] as AttachmentDef).name)
		return "%s [%s] dmg=%d rpm=%d mag=%d 散布=%.2f 射程=%d" % [
			weapon.name,
			"无配件" if names.is_empty() else " + ".join(names),
			int(round(effective["damage"])), int(round(effective["rpm"])),
			int(round(effective["mag_size"])), effective["spread_deg"],
			int(round(effective["range_m"])),
		]


## 建一个 Loadout
static func create_loadout(weapon: WeaponDef, slot_limit: int = SLOTS_A) -> Loadout:
	if weapon == null:
		return null
	return Loadout.create(weapon, slot_limit)


## 装一个配件。返回错误字符串，空串表示成功。
static func attach(loadout: Loadout, att: AttachmentDef) -> String:
	if loadout == null or att == null:
		return "参数为空"
	if not att.is_valid_slot():
		return "配件插槽非法：%s" % att.slot
	if not loadout.free_slots.has(att.slot):
		return "该枪没有 '%s' 插槽（可用：%s）" % [att.slot, str(loadout.free_slots)]
	if loadout.attachments.has(att.slot):
		return "该插槽已占用"
	_apply(loadout, att, 1.0)
	loadout.attachments[att.slot] = att
	return ""


## 卸一个配件。返回被卸下的配件或 null。
static func detach(loadout: Loadout, slot: String) -> AttachmentDef:
	if loadout == null or not loadout.attachments.has(slot):
		return null
	var att: AttachmentDef = loadout.attachments[slot]
	_apply(loadout, att, -1.0)
	loadout.attachments.erase(slot)
	return att


static func _apply(loadout: Loadout, att: AttachmentDef, sign: float) -> void:
	for field in att.mods:
		if not MODIFIABLE.has(field):
			continue          # 未知字段直接忽略（防脏数据）
		var cur: float = float(loadout.effective.get(field, 0.0))
		var delta := float(att.mods[field]) * sign
		var nv := cur + delta
		var floor_v: float = float(FLOORS.get(field, -999999.0))
		loadout.effective[field] = maxf(floor_v, nv)


## 自动为目标挑一套"最优"配件（简单的贪心：优先降散布、降后坐、加弹匣）
## 供 AI 装备使用；不做复杂评分，够用即可。
static func auto_fit(loadout: Loadout, pool: Dictionary) -> int:
	var fitted := 0
	for slot in loadout.free_slots:
		if loadout.attachments.has(slot):
			continue
		var best: AttachmentDef = null
		var best_score := -INF
		for id in pool:
			var a: AttachmentDef = pool[id]
			if a.slot != slot:
				continue
			var score := -float(a.mods.get("spread_deg", 0.0)) * 10.0 \
				- float(a.mods.get("recoil_v", 0.0)) * 6.0 \
				- float(a.mods.get("recoil_h", 0.0)) * 4.0 \
				+ float(a.mods.get("mag_size", 0.0)) * 0.5 \
				+ float(a.mods.get("damage", 0.0)) * 1.0
			if score > best_score:
				best_score = score
				best = a
		if best != null and attach(loadout, best) == "":
			fitted += 1
	return fitted
