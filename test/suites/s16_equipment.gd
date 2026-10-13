extends TestSuite

## 装备系统测试（C 阶段）
##
## 覆盖 `sim/equipment.gd`：槽位判定 / 装备 / 脱下 / 换装退回 / 错误原因 /
## 身上重量 / 存档往返；以及**敌人装备系统**的数据契约：
##   敌人携带的 weapon_id / armor_id / helmet_id 必须都是**能进背包的 item**
##   （武器已作为 item 存在，id 与 weapons.json 一致 —— 否则掉了捡不起来）。
##
## 只用显式类型（避开 untyped Array 上的 := 推断陷阱）。

func register() -> void:
	_suite("装备：槽位判定", _test_slot_for)
	_suite("装备：穿脱与换装", _test_equip_unequip)
	_suite("装备：错误原因与重量", _test_errors_and_weight)
	_suite("装备：存档往返", _test_serialize)
	_suite("装备：敌人装备是可捡的 item", _test_enemy_gear_is_item)


func _load() -> DataRegistry:
	var reg := DataRegistry.new()
	reg.load_all("C")
	return reg


func _test_slot_for() -> void:
	var reg := _load()
	var eq := Equipment.new(reg.items, reg.weapons)
	_check_eq(eq.slot_for("weapon_rifle"), "weapon", "步枪 -> weapon 槽")
	_check_eq(eq.slot_for("armor_light"), "armor", "护甲 -> armor 槽")
	_check_eq(eq.slot_for("armor_helmet_light"), "helmet", "头盔 -> helmet 槽")
	_check_eq(eq.slot_for("backpack_tactical"), "backpack", "背包 -> backpack 槽")
	_check_eq(eq.slot_for("medical_bandage"), "", "医疗品不能装备")
	_check(eq.is_equippable("weapon_rifle"), "枪可装备")
	_check(not eq.is_equippable("medical_bandage"), "绷带不可装备")


func _test_equip_unequip() -> void:
	var reg := _load()
	var eq := Equipment.new(reg.items, reg.weapons)
	var inv := Inventory.new(20, reg.items, 999.0)
	inv.add("weapon_rifle", 1)
	inv.add("armor_light", 1)

	_check_eq(eq.equip(inv, "weapon_rifle"), "", "装备步枪成功")
	_check_eq(eq.id_in("weapon"), "weapon_rifle", "weapon 槽是步枪")
	_check_eq(inv.count_of("weapon_rifle"), 0, "枪已离开背包（不占槽位）")

	_check_eq(eq.equip(inv, "armor_light"), "", "装备护甲成功")
	_check_eq(eq.id_in("armor"), "armor_light", "armor 槽是护甲")

	# 脱下
	_check_eq(eq.unequip(inv, "armor"), "", "脱下护甲成功")
	_check_eq(eq.id_in("armor"), "", "armor 槽已空")
	_check_eq(inv.count_of("armor_light"), 1, "护甲回到背包")

	# 换装：新枪顶掉旧枪，旧枪退回背包
	inv.add("weapon_shotgun", 1)
	_check_eq(eq.equip(inv, "weapon_shotgun"), "", "换装霰弹枪成功")
	_check_eq(eq.id_in("weapon"), "weapon_shotgun", "weapon 槽换成霰弹枪")
	_check_eq(inv.count_of("weapon_rifle"), 1, "换下的步枪退回背包")


func _test_errors_and_weight() -> void:
	var reg := _load()
	var eq := Equipment.new(reg.items, reg.weapons)
	var inv := Inventory.new(20, reg.items, 999.0)

	_check(eq.equip(inv, "weapon_rifle") != "", "背包里没有 -> 装备失败并有原因")
	# 空槽脱下应当**返回原因**（不是成功），UI 直接拿去 toast
	_check(eq.unequip(inv, "weapon") != "", "空槽脱下 -> 返回原因（该槽位是空的）")
	_check(eq.unequip(inv, "nosuchslot") != "", "不存在槽位 -> 有错误原因")

	inv.add("weapon_rifle", 1)
	eq.equip(inv, "weapon_rifle")
	var w: float = eq.worn_weight()
	_check(w > 0.0, "身上重量 > 0（实际 %.2f）" % w)
	# 身上重量应等于该枪 ItemDef.weight
	var d: ItemDef = reg.items["weapon_rifle"]
	_check(abs(w - d.weight) < 0.001, "身上重量 = 枪的重量 %.2f" % d.weight)


func _test_serialize() -> void:
	var reg := _load()
	var eq := Equipment.new(reg.items, reg.weapons)
	var inv := Inventory.new(20, reg.items, 999.0)
	inv.add("weapon_rifle", 1)
	eq.equip(inv, "weapon_rifle")

	var snap := eq.to_dict()
	var eq2 := Equipment.new(reg.items, reg.weapons)
	eq2.from_dict(snap)
	_check_eq(eq2.id_in("weapon"), "weapon_rifle", "往返后 weapon 槽一致")
	_check_eq(eq2.id_in("armor"), "", "往返后空槽仍是空")


func _test_enemy_gear_is_item() -> void:
	var reg := _load()
	var checked := 0
	var bad := 0
	for eid in reg.enemies:
		var e: EnemyDef = reg.enemies[eid]
		# 每个非空的装备 id 都必须能在 items 里找到 —— 否则掉了捡不起来
		for gid in [e.weapon_id, e.armor_id, e.helmet_id]:
			if gid == "":
				continue
			checked += 1
			if not reg.items.has(gid):
				bad += 1
				print("        装备 %s 不是 item：%s（%s）" % [gid, eid, "掉了捡不起来"])
	_check(checked > 0, "至少检查了 %d 个敌人装备引用" % checked)
	_check_eq(bad, 0, "敌人携带的装备全部是能进背包的 item")

	# 具体抽查：拾荒者带手枪，且手枪是可装备的
	var scav: EnemyDef = reg.enemies["enemy_scav"]
	_check_eq(scav.weapon_id, "weapon_pistol", "拾荒者带手枪")
	var eq := Equipment.new(reg.items, reg.weapons)
	_check_eq(eq.slot_for(scav.weapon_id), "weapon", "拾荒者的手枪能装进 weapon 槽")
