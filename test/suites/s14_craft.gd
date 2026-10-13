extends TestSuite

## C 阶段制造系统测试（W-02 配套）
##
## 验证 sim/craft_system.gd 的四件事：
##   ① 正常制造：材料齐 + 工作台解锁 -> 输入被扣、产物到手；
##   ② 工作台未解锁 -> 拒绝，且背包一动不动（原子性）；
##   ③ 材料不足 -> 拒绝，且背包一动不动；
##   ④ can_craft 只读、不改状态。
##
## 用真实 DataRegistry("C") 数据，取第一条配方动态填充，不写死配方内容。
## 只用显式类型（避开 untyped Array 上的 := 推断陷阱）。


func register() -> void:
	_suite("制造：正常流程", _test_craft_roundtrip)
	_suite("制造：未解锁工作台拒绝", _test_craft_locked_station)
	_suite("制造：材料不足拒绝", _test_craft_missing_input)
	_suite("制造：can_craft 只读", _test_can_craft_is_readonly)


## 取一条"输入都能塞进背包"的配方（动态，避免写死）
func _pick_recipe(reg: DataRegistry) -> RecipeDef:
	for rid in reg.recipes:
		var r: RecipeDef = reg.recipes[rid]
		var probe := Inventory.new(60, reg.items, 99999.0)
		var ok := true
		for g in r.inputs:
			if probe.add(g.item_id, g.count) != 0:
				ok = false
		if ok and r.output_count >= 1:
			return r
	return null


func _filled_inv(reg: DataRegistry, r: RecipeDef) -> Inventory:
	var inv := Inventory.new(60, reg.items, 99999.0)
	for g in r.inputs:
		inv.add(g.item_id, g.count)
	return inv


func _test_craft_roundtrip() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	var r := _pick_recipe(reg)
	_check(r != null, "找到一条可制造的配方")
	if r == null:
		return

	var inv := _filled_inv(reg, r)
	var stations := {r.station: true}
	var cs := CraftSystem.new(reg.recipes, reg.items)

	_check(cs.can_craft(r.id, inv, stations), "材料齐 + 工作台解锁 -> can_craft 为真")

	# 记录制造前各类数量（before/after 法，防输出恰等于某输入）
	var before_in: Dictionary = {}
	for g in r.inputs:
		before_in[g.item_id] = inv.count_of(g.item_id)
	var before_out: int = inv.count_of(r.output_item_id)

	var ok := cs.craft(r.id, inv, stations)
	_check(ok, "craft 返回成功")

	for g in r.inputs:
		var expect: int = int(before_in[g.item_id]) - g.count
		_check_eq(inv.count_of(g.item_id), expect,
			"输入 %s 被扣掉 %d（剩 %d）" % [g.item_id, g.count, expect])
	_check_eq(inv.count_of(r.output_item_id), before_out + r.output_count,
		"产物 %s 增加 %d" % [r.output_item_id, r.output_count])


func _test_craft_locked_station() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	var r := _pick_recipe(reg)
	if r == null:
		_check(false, "找到一条可制造的配方")
		return

	var inv := _filled_inv(reg, r)
	# 全部工作台都锁着
	var stations := {}
	var cs := CraftSystem.new(reg.recipes, reg.items)

	_check(not cs.can_craft(r.id, inv, stations), "未解锁工作台 -> can_craft 为假")
	var ok := cs.craft(r.id, inv, stations)
	_check(not ok, "未解锁工作台 -> craft 拒绝")

	# 原子性：背包一点都没动
	for g in r.inputs:
		_check_eq(inv.count_of(g.item_id), g.count, "材料 %s 未被扣" % g.item_id)
	_check_eq(inv.count_of(r.output_item_id), 0, "没有产出 %s" % r.output_item_id)


func _test_craft_missing_input() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	var r := _pick_recipe(reg)
	if r == null:
		_check(false, "找到一条可制造的配方")
		return

	# 只放"除第一种外"的输入，制造一种材料短缺
	var inv := Inventory.new(60, reg.items, 99999.0)
	var short: RecipeDef.Ingredient = r.inputs[0]
	for i in r.inputs.size():
		if i == 0:
			inv.add(r.inputs[i].item_id, maxi(0, r.inputs[i].count - 1))
		else:
			inv.add(r.inputs[i].item_id, r.inputs[i].count)

	var stations := {r.station: true}
	var cs := CraftSystem.new(reg.recipes, reg.items)
	_check(not cs.can_craft(r.id, inv, stations), "缺 %d 个 %s -> can_craft 为假" % [1, short.item_id])
	var miss: RecipeDef.Ingredient = cs.missing_input(r.id, inv)
	_check(miss != null and miss.item_id == short.item_id, "missing_input 指出缺的材料")

	var before_total := inv.used_slots()
	var ok := cs.craft(r.id, inv, stations)
	_check(not ok, "材料不足 -> craft 拒绝")
	_check_eq(inv.count_of(r.output_item_id), 0, "没有产出")
	# 原子性：没被扣任何东西（used_slots 不变）
	_check_eq(inv.used_slots(), before_total, "背包槽位占用不变（未半扣）")


func _test_can_craft_is_readonly() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	var r := _pick_recipe(reg)
	if r == null:
		_check(false, "找到一条可制造的配方")
		return

	var inv := _filled_inv(reg, r)
	var stations := {r.station: true}
	var cs := CraftSystem.new(reg.recipes, reg.items)

	# 反复问 can_craft，背包不应有任何变化
	var snap := inv.to_dict()
	for _i in 5:
		cs.can_craft(r.id, inv, stations)
	var snap2 := inv.to_dict()
	_check(str(snap) == str(snap2), "多次 can_craft 后背包状态逐字节不变")
