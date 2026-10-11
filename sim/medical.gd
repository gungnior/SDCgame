class_name MedicalSystem
extends RefCounted

## 医疗系统 —— A 阶段
##
## 依据 specs/reference-teardown.md §9：治疗要【有耗时】，且治疗时不能移动/射击，
## 这样"什么时候治"才成为一个真实的战术取舍。
##
## 治疗参数走数据（items.json 的 medical 条目带 `treat` 字段）：
##   treat = { "hp": 回复量, "time": 耗时秒, "bleed": 是否止血, "armor": 修甲量 }
##
## 纯 RefCounted，可 headless 单测。

## 治疗中受到的额外惩罚倍率（被打断的风险）
const INTERRUPT_DAMAGE_MULT := 1.15

var active_item_id: String = ""
var duration: float = 0.0
var elapsed: float = 0.0
var _active: Dictionary = {}

## 统计
var treatments_done: int = 0
var total_healed: int = 0


func is_treating() -> bool:
	return duration > 0.0


func progress() -> float:
	if duration <= 0.0:
		return 0.0
	return clampf(elapsed / duration, 0.0, 1.0)


func remaining() -> float:
	return maxf(0.0, duration - elapsed)


## 开始治疗。返回错误串（空串 = 成功）。
func start(item: ItemDef, vitals: Vitals) -> String:
	if is_treating():
		return "正在治疗中"
	if item == null:
		return "物品为空"
	if vitals == null or vitals.dead:
		return "无法治疗"
	if item.category != "medical":
		return "不是医疗物品：%s" % item.category
	var treat: Dictionary = item.treat
	if treat.is_empty():
		return "该物品没有治疗数据"
	if not _would_help(treat, vitals):
		return "当前状态下用这个没有意义"

	active_item_id = item.id
	_active = treat
	duration = maxf(0.1, float(treat.get("time", 2.0)))
	elapsed = 0.0
	return ""


func _would_help(treat: Dictionary, vitals: Vitals) -> bool:
	var hp_gain := int(treat.get("hp", 0))
	var can_heal := hp_gain > 0 and vitals.hp < vitals.max_hp
	var can_stop := bool(treat.get("bleed", false)) and vitals.is_bleeding()
	var can_armor := int(treat.get("armor", 0)) > 0 and vitals.armor < vitals.max_armor
	return can_heal or can_stop or can_armor


## 推进治疗。返回 {healed: int, stopped_bleed: bool, armor: int, done: bool}
func tick(delta: float, vitals: Vitals) -> Dictionary:
	var out := {"healed": 0, "stopped_bleed": false, "armor": 0, "done": false}
	if not is_treating() or vitals == null:
		return out
	if vitals.dead:
		cancel()
		return out

	elapsed += delta
	if elapsed < duration:
		return out

	# 生效
	var hp_gain := int(_active.get("hp", 0))
	if hp_gain > 0:
		out["healed"] = vitals.heal(hp_gain)
		total_healed += int(out["healed"])
	if bool(_active.get("bleed", false)) and vitals.is_bleeding():
		vitals.stop_bleed()
		out["stopped_bleed"] = true
	var armor_gain := int(_active.get("armor", 0))
	if armor_gain > 0:
		out["armor"] = vitals.repair_armor(armor_gain)

	treatments_done += 1
	out["done"] = true
	_reset()
	return out


## 被打断（受伤 / 移动 / 切枪）
func cancel() -> void:
	_reset()


func _reset() -> void:
	active_item_id = ""
	duration = 0.0
	elapsed = 0.0
	_active = {}


## 受伤时是否应当被打断治疗（重击打断，轻伤不打断）
func should_interrupt(damage: int) -> bool:
	return damage >= 15


func status_text() -> String:
	if not is_treating():
		return "未治疗"
	return "治疗 %s 中 %.0f%%（剩 %.1fs）" % [active_item_id, progress() * 100.0, remaining()]


func _to_string() -> String:
	return "MedicalSystem(%s)" % status_text()
