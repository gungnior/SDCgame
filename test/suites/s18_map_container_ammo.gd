extends TestSuite

## 本轮 6 项需求的专项回归套件（2026-10-13）
##
## 覆盖：
##   ① 敌人数量由【地图主题密度 × 房间数】决定（取消 MAX_TEST_ENEMIES=4 硬上限）
##   ② 地图扩大 + 更多房间类型 + 房间里有可搜索容器
##   ③ 容器与房间／容器类型挂靠（room_type.containers[] → container → loot_table）
##   ④ 弹型区分（穿甲弹 / 肉伤弹 / 标准弹）+ 对有甲/无甲目标的相对强弱
##   ⑤ 装备损耗（耐久 / 磨损折损 / 损坏 / 修理 / 存档往返）
##   ⑥ 地图主题区分（森林 / 城区 / 军事基地）+ 对应敌人生成
##
## 只用显式类型（避开 untyped Array 上的 := 推断陷阱）。

func register() -> void:
	_suite("地图主题：敌人密度与尺寸", _test_theme_density_and_size)
	_suite("地图主题：房间类型与容器挂靠", _test_theme_rooms_and_containers)
	_suite("容器：三级对应与交互", _test_container_pipeline)
	_suite("弹药：弹型对有甲/无甲的目标强弱", _test_ammo_types)
	_suite("装备：损耗与修理", _test_durability)
	_suite("地图：主题区分与敌人生成", _test_theme_enemy_spawn)


func _load() -> DataRegistry:
	var reg := DataRegistry.new()
	reg.load_all("C")
	return reg


# ═══════════════ ① 敌人密度与地图尺寸 ═══════════════

func _test_theme_density_and_size() -> void:
	var reg := _load()
	_check(reg.maps.size() >= 3, "至少 3 个地图主题（实际 %d）" % reg.maps.size())

	var forest: MapThemeDef = reg.get_map("map_forest")
	var urban: MapThemeDef = reg.get_map("map_urban")
	var military: MapThemeDef = reg.get_map("map_military")
	_check(forest != null and urban != null and military != null, "森林/城区/军事基地都存在")

	# 尺寸必须【各不相同】且军事基地最大（城区 > 森林，军事 > 城区）
	_check(military.map_w > urban.map_w and urban.map_w > forest.map_w,
		"地图尺寸递增：森林 %d < 城区 %d < 军事 %d" % [
			forest.map_w, urban.map_w, military.map_w])
	_check(military.map_w >= 40, "最大的地图 >= 40 格（实际 %d）" % military.map_w)

	# ① 敌人总数 = round(房间数 × 密度)。这是"人数参考地图大小"的落点。
	_check_eq(forest.target_enemy_count(20), int(round(20.0 * forest.enemy_density)),
		"target_enemy_count = round(房间数 × 密度)")
	_check(military.target_enemy_count(24) > forest.target_enemy_count(24),
		"同一房间数下，军事基地敌人多于森林（密度 %.1f > %.1f）"
			% [military.enemy_density, forest.enemy_density])

	# 集成：真的按主题生成一次，敌人预算应贴近主题目标（不再卡死 4）
	var gen := MapGenerator.new()
	var ok := gen.generate(20261013, reg.room_types, military.map_w, military.map_h, military)
	_check(ok, "军事基地地图生成成功（%s）" % gen.summary())
	_check_eq(gen.grid_w, military.map_w, "生成的地图宽度 == 主题宽度")
	_check_eq(gen.grid_h, military.map_h, "生成的地图高度 == 主题高度")

	var budget := gen.total_enemy_budget()
	_check(budget > 4, "敌人预算不再卡死为 4（实际 %d）" % budget)
	var target := military.target_enemy_count(gen.graph.rooms.size())
	# 允许 ±15% 的取整误差（每个房间单独 round 会累积）
	_check(absf(float(budget) - float(target)) <= float(target) * 0.15 + 2.0,
		"敌人预算贴近主题目标 round(房间%d×密度)=%d（实际 %d）"
			% [gen.graph.rooms.size(), target, budget])

	# 对照：theme == null 时不缩放（旧行为逐字节保留）
	var gen2 := MapGenerator.new()
	var ok2 := gen2.generate(20261013, reg.room_types, 26, 26)
	_check(ok2, "无主题地图仍能生成（向后兼容）")
	_check_eq(gen2.total_container_count(), 0, "无主题时不生成容器（旧行为）")
	_check(gen2.theme == null, "无主题时 theme 为 null")


# ═══════════════ ② 更多房间类型 + 容器 ═══════════════

func _test_theme_rooms_and_containers() -> void:
	var reg := _load()
	var commons: Array[RoomTypeDef] = reg.common_room_defs()
	_check(commons.size() >= 5,
		"普通房间类型 >= 5 种（实际 %d：%s）" % [
			commons.size(), ", ".join(commons.map(func(r): return r.id))])

	# 每种普通房间都应挂靠至少一个容器（否则"房间里有东西可搜"不成立）
	var missing: Array[String] = []
	for rd in commons:
		if rd.containers.is_empty():
			missing.append(rd.id)
	_check(missing.is_empty(), "每个普通房间都挂了容器（缺：%s）" % str(missing))

	# 房间加权：权重 > 0 的普通房间才参与主题分配
	var weighted := 0
	for rd in commons:
		if rd.weight > 0:
			weighted += 1
	_check(weighted >= 4, ">= 4 种普通房间带正权重参与分配（实际 %d）" % weighted)

	# 真生成一张主题图，应当刷出容器
	var urban: MapThemeDef = reg.get_map("map_urban")
	var gen := MapGenerator.new()
	gen.generate(4242, reg.room_types, urban.map_w, urban.map_h, urban)
	_check(gen.total_container_count() > 0,
		"主题地图刷出可搜索容器（实际 %d 个）" % gen.total_container_count())

	# 各房间 container_spawns 之和 == container_total
	var summed := 0
	for r in gen.graph.rooms:
		summed += r.container_spawns.size()
	_check_eq(summed, gen.container_total, "容器总数 == 各房间容器布点之和")


# ═══════════════ ③ 三级对应：房间 → 容器 → 掉落表 ═══════════════

func _test_container_pipeline() -> void:
	var reg := _load()
	_check(reg.containers.size() >= 6, "容器类型 >= 6（实际 %d）" % reg.containers.size())

	# room_type.containers[].container_id 必须能解析到 ContainerDef
	var bad_refs: Array[String] = []
	for k in reg.room_types:
		var rd: RoomTypeDef = reg.room_types[k]
		for cr in rd.containers:
			if reg.get_container(cr.container_id) == null:
				bad_refs.append("%s -> %s" % [rd.id, cr.container_id])
	_check(bad_refs.is_empty(), "房间挂靠的容器都存在（坏引用：%s）" % str(bad_refs))

	# ContainerDef.loot_table_id 必须能解析到掉落表
	var bad_loot: Array[String] = []
	for id in reg.containers:
		var cd: ContainerDef = reg.containers[id]
		if not reg.loot_tables.has(cd.loot_table_id):
			bad_loot.append("%s -> %s" % [cd.id, cd.loot_table_id])
	_check(bad_loot.is_empty(), "容器对应的掉落表都存在（坏引用：%s）" % str(bad_loot))

	# 真生成后：每个房间布点的 container_id 必须【是它自己房间类型声明的】容器
	var military: MapThemeDef = reg.get_map("map_military")
	var gen := MapGenerator.new()
	gen.generate(777, reg.room_types, military.map_w, military.map_h, military)
	var leaks: Array[String] = []
	for r in gen.graph.rooms:
		var rd: RoomTypeDef = reg.room_types.get(r.room_type_id)
		if rd == null:
			continue
		var allowed: Array = []
		for cr in rd.containers:
			allowed.append(cr.container_id)
		for s in r.container_spawns:
			if not allowed.has(str(s.get("container_id", ""))):
				leaks.append("%s 里出现了未声明的 %s" % [r.room_type_id, s.get("container_id")])
	_check(leaks.is_empty(), "容器只出现在声明它的房间类型里（越界：%s）" % str(leaks))

	# 容器交互：登记 → 就近查找 → 拿取
	var raid := RaidSession.new(reg.items, SimRng.new(1))
	var cd: ContainerDef = reg.get_container("container_ammo_box")
	_check(cd != null, "取到弹药箱容器定义")
	var drops: Array = [{"item_id": "ammo_rifle", "count": 30}]
	var idx := raid.add_container(cd, Vector2(5.0, 5.0), drops)
	_check_eq(idx, 0, "第一个容器 id 为 0")
	_check_eq(raid.container_near(Vector2(5.2, 5.0)), 0, "邻近位置能查到该容器")
	_check_eq(raid.container_near(Vector2(50.0, 50.0)), -1, "远处查不到容器")
	var taken := raid.take_from_container(0, "ammo_rifle", 10)
	_check_eq(taken, 10, "从容器拿走 10 发")
	_check(raid.containers[0].searched, "拿取后容器标记为已搜过")
	_check_eq(raid.containers_looted, 1, "本次战局已搜容器 +1")
	# 搜空后不再提示交互
	raid.take_all_from_container(0)
	_check(raid.containers[0].is_done(), "拿空后容器为 done（不再提示）")
	_check_eq(raid.container_near(Vector2(5.2, 5.0)), -1, "搜空的容器不再就近提示")


# ═══════════════ ④ 弹型：穿甲 / 肉伤 / 标准 ═══════════════

func _test_ammo_types() -> void:
	var reg := _load()
	var std: ItemDef = reg.get_item("ammo_rifle")
	var ap: ItemDef = reg.get_item("ammo_rifle_ap")
	var hp: ItemDef = reg.get_item("ammo_rifle_hp")
	_check(std != null and ap != null and hp != null, "三种弹型（标准/穿甲/肉伤）都存在")
	_check_eq(std.ammo_type, "standard", "ammo_rifle 是标准弹")
	_check_eq(ap.ammo_type, "ap", "ammo_rifle_ap 是穿甲弹")
	_check_eq(hp.ammo_type, "hp", "ammo_rifle_hp 是肉伤弹")

	# 弹型定位：AP pen 高 flesh 低；HP pen 低 flesh 高；标准居中
	_check(ap.pen > std.pen and ap.flesh < std.flesh, "穿甲弹：pen 更高、flesh 更低")
	_check(hp.pen < std.pen and hp.flesh > std.flesh, "肉伤弹：pen 更低、flesh 更高")

	# armor_multiplier 的基本性质
	_check(absf(DamageModel.armor_multiplier(0.0, 0.0) - 1.0) < 0.001, "无甲目标穿甲系数恒为 1.0")
	_check(absf(DamageModel.armor_multiplier(0.0, 6.0) - 0.25) < 0.001, "pen=0 打有甲 -> 0.25 下界")
	_check(absf(DamageModel.armor_multiplier(9.0, 6.0) - 1.0) < 0.001, "pen>=护甲 -> 1.0（打穿）")
	_check(DamageModel.armor_multiplier(3.0, 6.0) < DamageModel.armor_multiplier(7.0, 6.0),
		"护甲相同的前提下，pen 越高系数越大")

	# ⭐ 核心需求：AP 优势对抗有甲，HP 优势对抗无甲，标准居中
	var base := 100
	var armored := 6.0      # enemy_raider 的护甲
	var unarmored := 0.0
	var d_std_a := DamageModel.resolve_vs_armor(base, std, armored)
	var d_ap_a := DamageModel.resolve_vs_armor(base, ap, armored)
	var d_hp_a := DamageModel.resolve_vs_armor(base, hp, armored)
	_check(d_ap_a > d_std_a and d_std_a > d_hp_a,
		"对有甲目标：穿甲(%d) > 标准(%d) > 肉伤(%d)" % [d_ap_a, d_std_a, d_hp_a])

	var d_std_u := DamageModel.resolve_vs_armor(base, std, unarmored)
	var d_ap_u := DamageModel.resolve_vs_armor(base, ap, unarmored)
	var d_hp_u := DamageModel.resolve_vs_armor(base, hp, unarmored)
	_check(d_hp_u > d_std_u and d_std_u > d_ap_u,
		"对无甲目标：肉伤(%d) > 标准(%d) > 穿甲(%d)" % [d_hp_u, d_std_u, d_ap_u])

	# ammo=null（无弹型）时：对【无甲】目标退化为原始伤害（向后兼容）；
	# 对有甲目标则按 pen=0 吃到 0.25 下界（没弹药就啃不动甲）。
	_check_eq(DamageModel.resolve_vs_armor(base, null, unarmored), base,
		"ammo=null 打无甲目标 -> 原始伤害（向后兼容）")
	_check_eq(DamageModel.resolve_vs_armor(base, null, armored),
		DamageModel.resolve_vs_armor(base, null, 99.0),
		"ammo=null 打有甲目标 -> 吃到 0.25 下界（与 pen=0 一致）")

	# 期望击杀数：AP 打有甲比 HP 少
	var raider: EnemyDef = reg.get_enemy("enemy_raider")
	var rifle: WeaponDef = reg.get_weapon("weapon_rifle")
	var stk_ap := DamageModel.shots_to_kill_vs_armor(rifle, ap, raider, 20.0)
	var stk_hp := DamageModel.shots_to_kill_vs_armor(rifle, hp, raider, 20.0)
	_check(stk_ap < stk_hp, "打有甲敌人：穿甲弹需 %.1f 发 < 肉伤弹 %.1f 发" % [stk_ap, stk_hp])


# ═══════════════ ⑤ 装备损耗 ═══════════════

func _test_durability() -> void:
	var reg := _load()
	var eq := Equipment.new(reg.items, reg.weapons)
	var inv := Inventory.new(20, reg.items, 999.0)
	inv.add("weapon_rifle", 1)
	inv.add("armor_heavy", 1)
	eq.equip(inv, "weapon_rifle")     # -> weapon 槽
	eq.equip(inv, "armor_heavy")      # -> armor 槽

	# ⚠️ 损耗按【槽位上的物品】结算（weapon_damage_factor 走 id_in("weapon")），
	#    所以必须先真的把枪装上，不能只对 item_id 调 apply_wear。
	_check(eq.max_dur_of("weapon_rifle") > 0,
		"步枪有耐久上限（%d）" % eq.max_dur_of("weapon_rifle"))
	_check_eq(eq.slot_dur("weapon"), eq.slot_max_dur("weapon"), "未记录 = 全新")
	_check(absf(eq.wear_ratio("weapon_rifle") - 1.0) < 0.001, "全新时磨损比为 1.0")

	# 磨损：扣 1 点耐久
	var mx := eq.slot_max_dur("weapon")
	eq.wear_slot("weapon", 1)
	_check_eq(eq.slot_dur("weapon"), mx - 1, "磨损后耐久 -1")
	_check(not eq.is_broken("weapon_rifle"), "只磨损 1 点不算损坏")

	# 武器伤害折损：磨损一半 -> 系数应在 (0.6, 1.0) 之间
	eq.wear_slot("weapon", mx / 2)
	var half := eq.wear_ratio("weapon_rifle")
	_check(half < 1.0 and half > 0.0, "磨损过半后比例 %.2f 在 (0,1)" % half)
	_check(eq.weapon_damage_factor() < 1.0, "武器磨损 -> 伤害折损系数 < 1.0")

	# 修满
	var gained := eq.repair_full("weapon_rifle")
	_check(gained > 0, "修满返回修回的耐久（%d）" % gained)
	_check(absf(eq.wear_ratio("weapon_rifle") - 1.0) < 0.001, "修满后磨损比回到 1.0")

	# 打坏：耐久归零 -> is_broken，折损到 0.6 下限
	eq.wear_slot("weapon", mx)
	_check(eq.is_broken("weapon_rifle"), "耐久归零 -> 判定损坏")
	_check(absf(eq.weapon_damage_factor() - 0.6) < 0.001,
		"损坏武器伤害折损到下限 0.6（不会归零）")

	# 护甲损耗影响减伤：装备护甲 -> 有护甲值；打坏 -> 不再计入
	_check_eq(eq.worn_armor(), 9, "穿上重甲 -> 护甲值 9")
	eq.apply_wear("armor_heavy", eq.max_dur_of("armor_heavy"))
	_check_eq(eq.worn_armor(), 0, "护甲打坏后不再提供减伤")

	# 不参与损耗的物品恒为 1.0（弹药之类没有耐久）
	_check(absf(eq.wear_ratio("ammo_pistol") - 1.0) < 0.001,
		"无耐久物品的磨损比恒为 1.0")

	# 存档往返：dur 表必须一起存
	var eq2 := Equipment.new(reg.items, reg.weapons)
	eq2.from_dict(eq.to_dict())
	_check(eq.to_dict().has("dur"), "存档里带 dur 键")
	_check_eq(eq2.dur_of("armor_heavy"), eq.dur_of("armor_heavy"),
		"往返后护甲耐久一致")
	_check_eq(eq2.worn_armor(), eq.worn_armor(), "往返后护甲值一致")


# ═══════════════ ⑥ 地图主题区分与敌人生成 ═══════════════

func _test_theme_enemy_spawn() -> void:
	var reg := _load()

	# 主题三件套差异：色调 / 敌池
	var forest: MapThemeDef = reg.get_map("map_forest")
	var urban: MapThemeDef = reg.get_map("map_urban")
	var military: MapThemeDef = reg.get_map("map_military")
	_check(forest.tile_theme != urban.tile_theme and urban.tile_theme != military.tile_theme,
		"三张图色调不同：%s / %s / %s" % [
			forest.tile_theme, urban.tile_theme, military.tile_theme])
	_check(forest.enemy_weights != military.enemy_weights, "森林与军事基地的敌池不同")

	# 军事基地敌池含重甲单位，森林不含
	_check(military.enemy_weights.has("enemy_brute"), "军事基地会刷重装（enemy_brute）")
	_check(not forest.enemy_weights.has("enemy_brute"), "森林不刷重装")

	# 敌池里的 id 必须都能解析到 EnemyDef
	var bad: Array[String] = []
	for theme in [forest, urban, military]:
		for k in theme.enemy_weights:
			if reg.get_enemy(str(k)) == null:
				bad.append("%s -> %s" % [theme.id, k])
	_check(bad.is_empty(), "主题敌池 id 都能解析（坏引用：%s）" % str(bad))

	# roll_enemy 只会抽出主题敌池里的敌人（注入 rng，可复现）
	var rng := SimRng.new(123)
	var allowed := {}
	for k in military.enemy_weights:
		allowed[str(k)] = true
	var leaked: Array[String] = []
	for _i in 200:
		var eid := military.roll_enemy(rng)
		if not allowed.has(eid):
			leaked.append(eid)
	_check(leaked.is_empty(), "roll_enemy 只抽本主题的敌人（越界：%s）" % str(leaked))

	# 相同种子 roll_enemy 可复现（T-32 种子纪律）
	var r1 := SimRng.new(999)
	var r2 := SimRng.new(999)
	var same := true
	for _i in 50:
		if forest.roll_enemy(r1) != forest.roll_enemy(r2):
			same = false
	_check(same, "相同种子下 roll_enemy 结果可复现")

	# 房间主题也来自权重，且只抽到本主题声明过的房间
	var allowed_rooms := {}
	for k in military.room_weights:
		allowed_rooms[str(k)] = true
	var leaked_rooms: Array[String] = []
	var r3 := SimRng.new(55)
	for _i in 200:
		var rid := military.roll_room_def(r3)
		if not allowed_rooms.has(rid):
			leaked_rooms.append(rid)
	_check(leaked_rooms.is_empty(),
		"roll_room_def 只抽本主题声明的房间（越界：%s）" % str(leaked_rooms))
