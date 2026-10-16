extends TestSuite

## 可玩性 Step1：时间压力真正生效（2026-10-16 · WorkBuddy）
##
## 背景（specs/game-design-doc.md 门 1 的硬证据）：
##   · 一局固定 300s，且**三张图不分大小**（森林 56² vs 军事基地 72²）；
##   · 端到端实测跑刀 **17.6 秒**撤离、0 击杀、满血、带出 472 元
##     —— 于是「多摸一个箱子还是见好就收」这个品类灵魂抉择**根本没发生过**。
##
## 本轮改两件事，本套件钉死不许退化：
##   ① 地图级时限（maps.json 的 raid_seconds），start(0) 必须安全回退；
##   ② 撤离点分批关闭：**最近的先关，最远的保底常开** —— 贪的代价是待会儿走更远。


func register() -> void:
	_suite("地图级时限：三张图梯度正确 + clone 保留", _test_map_raid_seconds)
	_suite("start(0) 安全回退默认（绝不「开局即死」）", _test_start_zero_fallback)
	_suite("撤离点按离出生点由近到远排序", _test_extract_sorted_by_distance)
	_suite("撤离窗口：最近的先关，最后一个保底常开", _test_extract_windows)
	_suite("时间流逝后撤离点真的关闭，且不能在那儿撤离", _test_extract_closes_over_time)
	_suite("搜刮有代价：翻够时间才拿得到东西", _test_search_costs_time)
	_suite("搜刮中走开 → 中断但进度保留", _test_search_interrupted_keeps_progress)


var _reg: DataRegistry = null


func _fresh_reg() -> DataRegistry:
	if _reg != null:
		return _reg
	_reg = DataRegistry.new()
	var ok: bool = _reg.load_all("C")
	_check(ok, "DataRegistry.load_all(C) 应零错误")
	return _reg


func _fresh_gen(seed_value: int) -> MapGenerator:
	var reg := _fresh_reg()
	var gen := MapGenerator.new()
	gen.generate(seed_value, reg.room_types)
	return gen


func _fresh_raid(seed_value: int = 31337) -> RaidSession:
	var reg := _fresh_reg()
	var rng := SimRng.new(5)
	var stash := Inventory.new(40, reg.items, 999.0)
	var raid := RaidSession.new(reg.items, rng, stash)
	raid.load_map(_fresh_gen(seed_value))
	return raid


## 取地图出生点（撤离点排序的基准）
func _spawn_of(gen: MapGenerator) -> Vector2:
	for r in gen.graph.rooms:
		if r.room_type == "spawn":
			return Ballistics.cell_center(r.center)
	return Vector2.ZERO


func _test_map_raid_seconds() -> void:
	var reg := _fresh_reg()
	var forest: MapThemeDef = reg.get_map("map_forest")
	var urban: MapThemeDef = reg.get_map("map_urban")
	var mil: MapThemeDef = reg.get_map("map_military")
	_check(forest != null and urban != null and mil != null, "三张图都能取到")
	_check_eq(int(forest.raid_seconds), 180, "森林 56x56 → 180 秒")
	_check_eq(int(urban.raid_seconds), 240, "城区 64x64 → 240 秒（旧的硬编码基线）")
	_check_eq(int(mil.raid_seconds), 300, "军事基地 72x72 → 300 秒")
	_check(forest.raid_seconds < urban.raid_seconds
			and urban.raid_seconds < mil.raid_seconds,
			"面积越大时限越长 —— 小图不再白给时间")

	# clone() 必须带上：局内变体（RunModifiers）走 clone()，漏了就静默退回默认，
	# 而且是「看起来改了其实没生效」那类最难查的坑。
	var c: MapThemeDef = forest.clone()
	_check_eq(int(c.raid_seconds), int(forest.raid_seconds), "clone() 保留 raid_seconds")


func _test_start_zero_fallback() -> void:
	var raid := _fresh_raid()
	raid.start(0.0)
	_check(raid.time_left > 0.0, "start(0) 应回退默认，而不是把 time_left 灌成 0")
	_check_eq(int(raid.time_left), int(RaidSession.DEFAULT_RAID_SECONDS),
			"回退值 = DEFAULT_RAID_SECONDS")
	_check_eq(raid.phase_name(), "ACTIVE", "start 后 ACTIVE，没有「开局即判超时死亡」")


func _test_extract_sorted_by_distance() -> void:
	var gen := _fresh_gen(31337)
	var spawn := _spawn_of(gen)
	var raid := _fresh_raid(31337)
	_check(raid.extract_points.size() >= 2,
			"至少 2 个撤离点（实际 %d 个）" % raid.extract_points.size())
	var prev := -1.0
	var i := 0
	for p in raid.extract_points:
		var d: float = p.distance_to(spawn)
		_check(d >= prev - 0.001,
				"第 %d 个撤离点比上一个远（%.1f >= %.1f）—— 由近到远排序" % [i, d, prev])
		prev = d
		i += 1


func _test_extract_windows() -> void:
	var raid := _fresh_raid()
	var n := raid.extract_points.size()
	_check(n >= 2, "至少 2 个撤离点（实际 %d 个）" % n)
	if n < 2:
		return
	_check_eq(raid.extract_close_ratios.size(), n, "每个撤离点都有一个关闭比例")
	_check(float(raid.extract_close_ratios[n - 1]) <= 0.0,
			"最远的撤离点永不关闭（保底，否则玩家必死 —— 那是挫败不是张力）")
	for i in range(n - 1):
		var r := float(raid.extract_close_ratios[i])
		_check(r > 0.0, "第 %d 个撤离点会在 %.0f%% 时关闭" % [i, r * 100.0])
		if i > 0:
			_check(r > float(raid.extract_close_ratios[i - 1]),
					"关闭时间依次推后（近的先关）")
	_check_eq(raid.active_extract_count(), n, "开局时全部撤离点都开着")


func _test_extract_closes_over_time() -> void:
	var raid := _fresh_raid()
	var n := raid.extract_points.size()
	if n < 2:
		return
	raid.start(100.0)
	var ratio: float = float(raid.extract_close_ratios[0])
	var close_at := 100.0 * ratio

	# 关闭之前：还开着，且 HUD 预警为正
	raid.tick(close_at - 2.0, Vector2(1000.0, 1000.0))
	_check(raid.is_extract_active(0), "%.0f%% 之前，最近的撤离点还开着" % (ratio * 100.0))
	_check(raid.next_extract_close_in() > 0.0,
			"HUD 预警：还有 %.1f 秒关闭" % raid.next_extract_close_in())

	# 关闭之后：不再可用
	raid.tick(4.0, Vector2(1000.0, 1000.0))
	_check(not raid.is_extract_active(0), "过了 %.0f%% 后，最近的撤离点已关闭" % (ratio * 100.0))
	_check(raid.active_extract_count() < n, "可用撤离点变少了")
	_check(raid.is_extract_active(n - 1), "保底的那个仍然开着")

	# 站在已关闭的撤离点上：进度不涨（不能偷偷撤出去）
	var closed_pt: Vector2 = raid.extract_points[0]
	raid.tick(3.0, closed_pt)
	_check_eq(raid.extract_progress, 0.0, "站在已关闭的撤离点 → 进度 0")

	# 走到保底撤离点：仍然能撤
	var last_pt: Vector2 = raid.extract_points[n - 1]
	raid.tick(RaidSession.EXTRACT_COUNTDOWN + 0.5, last_pt)
	_check_eq(raid.phase_name(), "EXTRACTED", "保底撤离点照样能撤出去")


func _new_raid_with(cd: ContainerDef) -> RaidSession:
	var reg := _fresh_reg()
	var rng := SimRng.new(7)
	var stash := Inventory.new(40, reg.items, 999.0)
	var raid := RaidSession.new(reg.items, rng, stash)
	raid.add_container(cd, Vector2(5.0, 5.0), [{"item_id": "ammo_rifle", "count": 10}])
	raid.start(120.0)
	return raid


func _test_search_costs_time() -> void:
	var reg := _fresh_reg()
	var cd: ContainerDef = reg.get_container("container_ammo_box")
	_check(cd != null and cd.search_time > 0.0,
			"容器定义了 search_time（%.1f 秒）" % (0.0 if cd == null else cd.search_time))
	var raid := _new_raid_with(cd)

	_check(not raid.containers[0].is_unlocked(), "刚登记 = 锁着")
	_check_eq(raid.take_from_container(0, "ammo_rifle", 5), 0, "没翻完 → 一件都拿不到")

	raid.begin_search(0)
	raid.tick(cd.search_time * 0.5, Vector2(5.0, 5.0))
	_check(not raid.containers[0].is_unlocked(), "只翻了一半 → 还锁着")
	_check(raid.search_ratio() > 0.4 and raid.search_ratio() < 0.6,
			"进度约 50%%（实际 %.2f）" % raid.search_ratio())

	raid.tick(cd.search_time * 0.6, Vector2(5.0, 5.0))
	_check(raid.containers[0].is_unlocked(), "翻够了 → 解锁")
	_check_eq(raid.search_finished_idx, 0, "解锁那一帧记下 search_finished_idx（view 据此刷面板）")
	_check_eq(raid.take_from_container(0, "ammo_rifle", 5), 5, "解锁后才拿得到")


func _test_search_interrupted_keeps_progress() -> void:
	var reg := _fresh_reg()
	var cd: ContainerDef = reg.get_container("container_lab_case")
	_check(cd != null, "取到实验柜定义（search_time 最长的那类）")
	var raid := _new_raid_with(cd)

	raid.begin_search(0)
	raid.tick(1.0, Vector2(5.0, 5.0))
	var p1: float = raid.containers[0].search_progress
	_check(p1 > 0.0, "翻了 %.1f 秒" % p1)

	# 走开 → 中断
	raid.tick(0.1, Vector2(40.0, 40.0))
	_check_eq(raid.search_idx, -1, "走开了 → 搜刮中断")
	# ⭐ 进度保留：回来不用从头翻（否则一被打断就前功尽弃，那是惩罚不是张力）
	_check(float(raid.containers[0].search_progress) >= p1 - 0.001,
			"进度保留（%.1f 秒）—— 回来接着搜" % raid.containers[0].search_progress)

	raid.begin_search(0)
	raid.tick(cd.search_time, Vector2(5.0, 5.0))
	_check(raid.containers[0].is_unlocked(), "回来翻够 → 解锁")
