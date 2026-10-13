class_name MissionSystem
extends RefCounted

## 任务系统**框架**（C 阶段）
##
## ⚠️ 本轮**只搭框架，不写具体任务内容**（拥有者明确要求）。
##   理由：任务是"内容"，应在核心循环稳定后再填；但**框架与 schema 要在
##   A/C 架构里一次定死**（roadmap-bac.md §1 约束 1/2：目录按 C 划、schema 一次定死），
##   否则将来加任务就要改代码结构。
##
## ─── 设计（三条，都是为了"加内容不改框架"）───
## 1. **数据驱动**：任务内容全在 `data/missions.json`，本文件只管状态机与进度。
## 2. **事件驱动推进**：`notify(type, amount)` —— 框架**不关心事件从哪来**，
##    （击杀 / 搜刮 / 撤离 / 制造…都由模拟层上报）。将来加新目标类型**不用改本文件**。
## 3. **奖励外部结算**：完成时发 `mission_completed` 信号，由调用方发钱/发物品。
##    框架**不直接持有 Inventory / Hideout** —— 保持纯 RefCounted、可 headless 单测
##    （D-06 / T-69）。
##
## 任务数据结构（data/missions.json 的每一项）：
##   {
##     "id": "m_demo", "name": "...", "stage": "C",
##     "objectives": [ {"type": "kill", "need": 3}, {"type": "extract", "need": 1} ],
##     "reward": {"wallet": 500, "items": [{"item_id": "...", "count": 1}]}
##   }
##   type 是**自由字符串**，框架只做字符串匹配 —— 这就是"加类型不改框架"的关键。

signal mission_completed(mission_id: String)

## 状态：未接取 / 进行中 / 已完成（已领奖）
const S_LOCKED := "locked"
const S_ACTIVE := "active"
const S_DONE := "done"

var _defs: Dictionary = {}      ## mission_id -> Dictionary（原始数据）
var _state: Dictionary = {}     ## mission_id -> 状态字符串
var _counts: Dictionary = {}    ## mission_id -> Array[int]（每个目标当前计数）


func _init(defs: Dictionary = {}) -> void:
	_defs = defs
	for id in _defs:
		_state[id] = S_LOCKED
		_counts[id] = []


func mission_count() -> int:
	return _defs.size()


func ids() -> Array:
	return _defs.keys()


func state_of(mission_id: String) -> String:
	return str(_state.get(mission_id, S_LOCKED))


func is_active(mission_id: String) -> bool:
	return state_of(mission_id) == S_ACTIVE


func is_done(mission_id: String) -> bool:
	return state_of(mission_id) == S_DONE


func def_of(mission_id: String) -> Dictionary:
	return _defs.get(mission_id, {})


## 接取任务。已在进行的不能重复接。
func start(mission_id: String) -> bool:
	if not _defs.has(mission_id):
		return false
	if state_of(mission_id) == S_ACTIVE:
		return false
	_state[mission_id] = S_ACTIVE
	var objs: Array = def_of(mission_id).get("objectives", [])
	var arr: Array[int] = []
	for _o in objs:
		arr.append(0)
	_counts[mission_id] = arr
	return true


## 上报一次事件，推进所有**进行中**任务里 type 匹配的目标。
## 例：击杀一个敌人 -> notify("kill")；撤离成功 -> notify("extract")
func notify(type: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	for id in _defs:
		if state_of(id) != S_ACTIVE:
			continue
		var objs: Array = def_of(id).get("objectives", [])
		var counts: Array = _counts.get(id, [])
		var changed := false
		for i in objs.size():
			var o: Dictionary = objs[i]
			if str(o.get("type", "")) != type:
				continue
			if i >= counts.size():
				counts.resize(i + 1)
			counts[i] = int(counts[i]) + amount
			changed = true
		if changed:
			_counts[id] = counts
			if _all_met(id):
				_state[id] = S_DONE
				mission_completed.emit(id)


## 每个目标的 [当前, 需求]，供 UI 显示 "2/3"
func progress_of(mission_id: String) -> Array:
	var objs: Array = def_of(mission_id).get("objectives", [])
	var counts: Array = _counts.get(mission_id, [])
	var out: Array = []
	for i in objs.size():
		var o: Dictionary = objs[i]
		var have: int = int(counts[i]) if i < counts.size() else 0
		out.append([have, int(o.get("need", 1))])
	return out


func _all_met(mission_id: String) -> bool:
	for p in progress_of(mission_id):
		if int(p[0]) < int(p[1]):
			return false
	return true
