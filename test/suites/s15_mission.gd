extends TestSuite

## 任务系统框架测试（C 阶段，本轮只搭框架不写内容）
##
## ⚠️ 因为 `data/missions.json` 目前是空的（框架先行、内容待填），
##    这里用**合成任务**驱动框架，验证的是**框架本身**，不依赖任何真实任务内容。
##    将来填了真实任务，本测试仍应通过（它测的是状态机与事件推进，不是内容）。
##
## 覆盖：接取 / 事件推进 / 多目标 / 类型不匹配不推进 / 完成发信号 / 重复接取 /
##      未接取的任务不被推进 / 空数据不炸。

func register() -> void:
	_suite("任务框架：接取与推进", _test_start_and_notify)
	_suite("任务框架：多目标与完成", _test_multi_objective_done)
	_suite("任务框架：未接取不推进、重复接取", _test_guard_rules)
	_suite("任务框架：空数据不炸", _test_empty_defs)


func _mk_defs() -> Dictionary:
	return {
		"m_synth": {
			"id": "m_synth", "name": "合成任务", "stage": "C",
			"objectives": [{"type": "kill", "need": 3},
				{"type": "extract", "need": 1}],
			"reward": {"wallet": 500, "items": []},
		},
	}


func _test_start_and_notify() -> void:
	var ms := MissionSystem.new(_mk_defs())
	_check_eq(ms.mission_count(), 1, "载入 1 条任务定义")
	_check(ms.state_of("m_synth") == MissionSystem.S_LOCKED, "初始未接取")

	_check(ms.start("m_synth"), "接取成功")
	_check(ms.is_active("m_synth"), "接取后为进行中")

	ms.notify("kill")
	ms.notify("kill")
	var p := ms.progress_of("m_synth")
	_check_eq(int(p[0][0]), 2, "kill 目标已 2/3")
	_check_eq(int(p[1][0]), 0, "extract 目标仍 0/1（类型不同不受影响）")
	_check(ms.is_active("m_synth"), "未完成仍是进行中")


func _test_multi_objective_done() -> void:
	var ms := MissionSystem.new(_mk_defs())
	ms.start("m_synth")

	# ⚠️ 用 Dictionary 而非局部变量接信号：GDScript 的 lambda 里给**外层局部变量**
	#    赋值不会传回外层（实测拿到空字符串），但改 Dictionary 的内容可以（引用语义）。
	var got := {"id": ""}
	ms.mission_completed.connect(func(id: String): got["id"] = id)

	ms.notify("kill", 3)      # kill 3/3
	_check(not ms.is_done("m_synth"), "kill 满了但 extract 没满 -> 未完成")
	ms.notify("extract")      # extract 1/1
	_check(ms.is_done("m_synth"), "两个目标都满 -> 完成")
	_check_eq(str(got["id"]), "m_synth", "完成信号带出任务 id")

	# 完成后再上报不应再触发
	got["id"] = ""
	ms.notify("kill", 10)
	_check_eq(str(got["id"]), "", "已完成的任务不再重复发完成信号")


func _test_guard_rules() -> void:
	var ms := MissionSystem.new(_mk_defs())
	# 未接取 -> 上报不推进
	ms.notify("kill", 5)
	_check_eq(int(ms.progress_of("m_synth")[0][0]), 0, "未接取的任务不被推进")

	_check(ms.start("m_synth"), "首次接取成功")
	_check(not ms.start("m_synth"), "重复接取被拒")

	# 不存在的任务
	_check(not ms.start("m_no_such"), "接取不存在的任务失败")
	_check(ms.progress_of("m_no_such").is_empty(), "不存在任务的进度为空（不炸）")


func _test_empty_defs() -> void:
	# 真实 data/missions.json 目前就是空的 —— 框架必须能扛住
	var ms := MissionSystem.new({})
	_check_eq(ms.mission_count(), 0, "空定义不炸")
	ms.notify("kill", 3)      # 空集合上报不应报错
	_check(ms.ids().is_empty(), "空定义的 ids 为空")
	_check(ms.def_of("x").is_empty(), "取不存在的定义返回空字典")
