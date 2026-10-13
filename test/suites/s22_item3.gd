extends TestSuite

## 第 3 项（用户拍板"允许偏离"后补全的三处功能缺口）回归套件
##
## 用户原话（总结里的「接下来干什么 · 3」）：
##   给护甲/头盔/背包槽加数值意义（护甲值、负重上限）；
##   换枪后备弹按弹药类型取；定"死亡损失规则"让掉装备真的心疼。
##
## ⚠️ 数值平衡 / 任务 / 经济系统已交给别的专家 —— 本套件只测**机制与管道**，
##   不测具体数值。可调常量（BASE_RESERVE/MAX_RESERVE、背包 carry_slots 等）
##   都标了"平衡专家调"，默认值与旧行为一致（不回归）。
##
## 护甲/头盔进战斗、死亡掉光装备 是第七轮已做的，本套件只补：
##   3a 背包槽 -> 本局容量/负重
##   3b 换枪备弹按弹种
##   3c 死亡损失可配置策略（默认仍全掉）


func register() -> void:
	_suite("3a：背包容量字段与接线", _test_backpack_capacity)
	_suite("3a：RaidSession 携带容量来自 modifiers", _test_carry_capacity)
	_suite("3b：换枪备弹按弹种（源码守卫）", _test_ammo_type_reserve)
	_suite("3c：DeathPolicy.plan_keep 纯函数", _test_death_plan)
	_suite("3c：默认策略仍全掉（不回归）", _test_death_default_all)
	_suite("3c：keep=1.0 保留装备/背包", _test_death_keep_all)


# ─────────────────── 3a：背包容量 ───────────────────

func _test_backpack_capacity() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	var n := 0
	var bad: Array[String] = []
	for id in reg.items.keys():
		var d: ItemDef = reg.get_item(id)
		if d.category == "backpack":
			n += 1
			if d.carry_slots <= 0 or d.carry_weight <= 0.0:
				bad.append(id)
	_check(n >= 1 and bad.is_empty(),
		"所有背包都配置了 carry_slots/carry_weight（%d 个，问题：%s）" % [n, str(bad)])

	# ItemDef 能解析这两个字段
	var bp: ItemDef = reg.get_item("backpack_assault")
	_check(bp != null and bp.carry_slots > 12, "backpack_assault 容量大于默认 12（%d）" % (0 if bp == null else bp.carry_slots))
	_check(bp != null and bp.carry_weight > 0.0, "backpack_assault 有负重上限（%.1f）" % (0.0 if bp == null else bp.carry_weight))

	# 源码守卫：raid_scene 把背包 ItemDef 的容量注入 mods
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("bp.carry_slots") and rs.contains('mods["carry_slots"]'),
		"raid_scene 把背包 carry_slots 注入 RaidSession mods")
	_check(rs.contains("bp.carry_weight") and rs.contains("carry_weight_limit"),
		"raid_scene 把背包 carry_weight 注入 mods（与升级上限取 max）")


func _test_carry_capacity() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	var stash := Inventory.new(40, reg.items, 999.0)

	# modifiers 能改携带格数 / 负重上限
	var big := RaidSession.new(reg.items, SimRng.new(2), stash,
		{"carry_slots": 18, "carry_weight_limit": 40.0})
	_check_eq(big.carry.slot_count(), 18, "modifiers.carry_slots=18 -> 携带背包 18 格")
	_check_eq(big.carry.max_weight, 40.0, "modifiers.carry_weight_limit=40 -> 负重上限 40")

	# 默认回退 12 格（与旧行为一致）
	var def := RaidSession.new(reg.items, SimRng.new(3), stash)
	_check_eq(def.carry.slot_count(), 12, "默认 carry_slots=12（不回归）")


# ─────────────────── 3b：换枪备弹按弹种 ───────────────────

func _test_ammo_type_reserve() -> void:
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("wdef.ammo_id") and rs.contains("raid.carry.count_of"),
		"_make_player_weapon 按武器 ammo_id 取背包里该弹种的携带量")
	_check(rs.contains("BASE_RESERVE") and rs.contains("MAX_RESERVE"),
		"备弹有上下限常量（数值交给平衡专家调）")
	_check(rs.contains("clampi(carried, BASE_RESERVE, MAX_RESERVE)"),
		"备弹 = 背包该弹种携带量夹在 [BASE, MAX] 内")


# ─────────────────── 3c：死亡损失策略 ───────────────────

func _test_death_plan() -> void:
	_check(DeathPolicy.plan_keep([10, 100, 50], 0.0, 0).is_empty(), "ratio=0 -> 全掉")
	var all := DeathPolicy.plan_keep([10, 100, 50], 1.0, 0)
	_check_eq(all.size(), 3, "ratio=1 -> 全留")
	# 按价值降序：100(idx1) > 50(idx2) > 10(idx0)
	_check_eq(all[0], 1, "保留顺序按价值：先最值钱 100(idx1)")
	_check_eq(all[1], 2, "其次 50(idx2)")
	_check_eq(all[2], 0, "再次 10(idx0)")
	# ratio 0.5 -> floor(0.5*3)=1 -> 只留最值钱 1 个
	_check_eq(DeathPolicy.plan_keep([10, 100, 50], 0.5, 0).size(), 1, "ratio=0.5 -> 留 1 个")
	# 保险槽位：即便 ratio=0 也至少留最值钱 N 个
	_check_eq(DeathPolicy.plan_keep([10, 100, 50], 0.0, 1).size(), 1, "insured=1 -> 即便 ratio=0 也留 1 个")
	_check_eq(DeathPolicy.plan_keep([10, 100, 50], 0.0, 1)[0], 1, "保险留的是最值钱那个(idx1)")
	# 空输入安全
	_check(DeathPolicy.plan_keep([], 1.0, 0).is_empty(), "空输入不崩")


func _test_death_default_all() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	var eq := Equipment.new(reg.items, reg.weapons)
	eq.slots["weapon"] = "weapon_rifle"
	eq.slots["armor"] = "armor_light"
	var raid := RaidSession.new(reg.items, SimRng.new(7), Inventory.new(40, reg.items, 999.0))
	raid.equipment = eq
	raid.carry.add("ammo_rifle", 30)
	raid.carry.add("medical_kit", 2)
	raid.start(240.0)
	raid.take_damage(9999)
	_check(raid.is_over(), "死亡后 is_over()")
	_check_eq(eq.id_in("weapon"), "", "默认策略：身上武器掉光")
	_check_eq(eq.id_in("armor"), "", "默认策略：护甲掉光")
	_check_eq(raid.carry.used_slots(), 0, "默认策略：携带背包掉光")
	_check(raid.lost_slots >= 4, "结算记录丢失槽位数（%d）" % raid.lost_slots)


func _test_death_keep_all() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	var eq := Equipment.new(reg.items, reg.weapons)
	eq.slots["weapon"] = "weapon_rifle"
	eq.slots["armor"] = "armor_light"
	# keep_equipment=1.0 + keep_carry=1.0 -> 全部保留（验证策略两端都生效）
	var raid := RaidSession.new(reg.items, SimRng.new(8), Inventory.new(40, reg.items, 999.0),
		{"death_keep_equipment": 1.0, "death_keep_carry": 1.0})
	raid.equipment = eq
	raid.carry.add("ammo_rifle", 30)
	raid.carry.add("ammo_pistol", 12)
	raid.start(240.0)
	raid.take_damage(9999)
	_check(eq.id_in("weapon") != "", "keep=1.0：武器保留")
	_check(eq.id_in("armor") != "", "keep=1.0：护甲保留")
	_check_eq(raid.carry.used_slots(), 2, "keep=1.0：携带背包保留 2 格")
	_check_eq(raid.lost_slots, 0, "keep=1.0：丢失槽位 = 0")
