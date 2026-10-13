extends TestSuite
## 任务系统：内容（data/missions.json）+ 接线（raid_session.notify）→ 奖励（仓库/钱）
## 验证 GameDesigner 填的任务真的能在战局里推进并完成发奖。

func register() -> void:
	_suite("任务载入与奖励物品合法", _test_mission_load)
	_suite("击杀任务完成并发奖励", _test_mission_kill_reward)
	_suite("撤离任务完成", _test_mission_extract)
	_suite("搜刮任务累计", _test_mission_loot)
	_suite("多目标（猎手：8杀+撤离）", _test_mission_multi)


func _test_mission_load() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	_check(reg.missions.has("m_first_blood"), "m_first_blood 已载入")
	_check(reg.missions.has("m_extract_basic"), "m_extract_basic 已载入")
	_check(reg.missions.has("m_salvager"), "m_salvager 已载入")
	_check(reg.missions.has("m_hunter"), "m_hunter 已载入")
	# 奖励物品必须存在，否则 DataRegistry 交叉校验会报错
	_check(reg.items.has("ammo_pistol"), "奖励物品 ammo_pistol 存在")
	_check(reg.items.has("valuables_goldwatch"), "奖励物品 valuables_goldwatch 存在")


func _new_session() -> RaidSession:
	var reg := DataRegistry.new()
	reg.load_all("C")
	var stash := Inventory.new(40, reg.items, 999.0)
	var rs := RaidSession.new(reg.items, SimRng.new(1), stash, {}, reg.missions)
	rs.start(240.0)
	return rs


func _test_mission_kill_reward() -> void:
	var rs := _new_session()
	_check(rs.mission != null, "RaidSession 持有 MissionSystem")
	var st := rs.mission_status()
	_check_eq(st.size(), 4, "4 个任务已激活")
	for s in st:
		_check(s["state"] == "active", "任务 %s 处于 active" % s["id"])
	# 击杀 3 个 -> m_first_blood 完成（奖励 200 元 + ammo_pistol x20）
	rs.register_kill()
	rs.register_kill()
	rs.register_kill()
	_check(rs.mission.is_done("m_first_blood"), "击杀 3 次后 m_first_blood 完成")
	_check_eq(rs.mission_wallet_earned, 200, "钱包奖励累计 200 元")
	_check(rs.stash.count_of("ammo_pistol") >= 20, "奖励 ammo_pistol 进入仓库（>=20）")


func _test_mission_extract() -> void:
	var rs := _new_session()
	rs.extract()
	_check(rs.mission.is_done("m_extract_basic"), "撤离后 m_extract_basic 完成")
	_check_eq(rs.mission_wallet_earned, 300, "撤离奖励 300 元")


func _test_mission_loot() -> void:
	var rs := _new_session()
	# m_salvager 需要搜刮 10 次（每次 notify 的 amount 累加）
	for i in 10:
		if rs.mission != null:
			rs.mission.notify("loot", 1)
	_check(rs.mission.is_done("m_salvager"), "搜刮 10 次后 m_salvager 完成")


func _test_mission_multi() -> void:
	var rs := _new_session()
	for i in 8:
		rs.register_kill()
	_check(not rs.mission.is_done("m_hunter"), "8 杀但还没撤离 -> 未完成")
	rs.extract()
	_check(rs.mission.is_done("m_hunter"), "8 杀 + 撤离后 m_hunter 完成")
	_check(rs.stash.count_of("valuables_goldwatch") >= 1, "猎手奖励金表进仓库")
