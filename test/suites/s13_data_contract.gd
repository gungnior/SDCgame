extends TestSuite

## 数据 ↔ 代码契约测试（W-05）
##
## 目标：抓住"引用了不存在的 id"这类错误 —— 正是 T-64 时代踩过的坑
##（掉落表引用了未加载物品，表现为"掉落悄悄变少"，肉眼极难发现）。
##
## 两个方向，缺一不可：
##   · 正向：干净加载后，四类交叉引用（weapon.ammo_id / loot.item_id /
##     room.loot_table_id / recipe.input|output）全部解析，errors 为空；
##   · 负向：注入悬空 id 后，DataRegistry._validate_cross_refs() 必须报错，
##     且报错信息里能定位到那个坏 id（证明守卫真的在查，不是空转）。
##
## ⚠️ 只用显式类型（var x: T）。之前 s11 在 untyped Array 上用 := 推断失败，
##    导致整文件 parse error 且 Godot --script 空转不退出（假死）。此处规避。


func register() -> void:
	_suite("契约：干净加载无悬空引用", _test_clean_load_no_dangling)
	_suite("契约：注入悬空引用必被抓住", _test_dangling_refs_caught)


func _test_clean_load_no_dangling() -> void:
	# 三个 stage 逐级装载，每次都必须无错误（B ⊂ A ⊂ C）
	for stage in ["B", "A", "C"]:
		var reg := DataRegistry.new()
		var ok := reg.load_all(stage)
		if not reg.errors.is_empty():
			for e in reg.errors:
				print("        [%s] err: %s" % [stage, e])
		_check(ok, "load_all(\"%s\") 无错误" % stage)

	# C 档四类表要真的装进来，否则下面的"全解析"是空话
	var reg := DataRegistry.new()
	reg.load_all("C")
	_check(reg.weapons.size() > 0 and reg.loot_tables.size() > 0
		and reg.room_types.size() > 0 and reg.recipes.size() > 0,
		"C 档四类表都非空（w=%d l=%d r=%d rec=%d）"
		% [reg.weapons.size(), reg.loot_tables.size(), reg.room_types.size(), reg.recipes.size()])

	# 独立再扫一遍交叉引用（不依赖 _validate_cross_refs，双保险）
	var bad := 0
	for wid in reg.weapons:
		var w: WeaponDef = reg.weapons[wid]
		if not reg.items.has(w.ammo_id):
			bad += 1
	for tid in reg.loot_tables:
		var t: LootTableDef = reg.loot_tables[tid]
		for e in t.entries:
			if not reg.items.has(e.item_id):
				bad += 1
	for rid in reg.room_types:
		var rt: RoomTypeDef = reg.room_types[rid]
		if not rt.loot_table_id.is_empty() and not reg.loot_tables.has(rt.loot_table_id):
			bad += 1
	for rcid in reg.recipes:
		var r: RecipeDef = reg.recipes[rcid]
		if not reg.items.has(r.output_item_id):
			bad += 1
		for g in r.inputs:
			if not reg.items.has(g.item_id):
				bad += 1
	_check_eq(bad, 0, "四类交叉引用全部解析，无悬空 id")


func _test_dangling_refs_caught() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")
	if reg.weapons.is_empty() or reg.loot_tables.is_empty() or reg.room_types.is_empty() or reg.recipes.is_empty():
		_check(false, "前置：C 档四类表非空")
		return

	# 注入 5 个不同的悬空 id（每种引用类型一个）
	var bad_w: String = "ammo___dangling_w___"
	var bad_l: String = "item___dangling_l___"
	var bad_r: String = "loot___dangling_r___"
	var bad_out: String = "item___dangling_out___"
	var bad_in: String = "item___dangling_in___"

	var w: WeaponDef = reg.weapons.values()[0]
	var orig_ammo: String = w.ammo_id
	w.ammo_id = bad_w

	var t: LootTableDef = reg.loot_tables.values()[0]
	var e0: LootTableDef.Entry = t.entries[0]
	var orig_loot: String = e0.item_id
	e0.item_id = bad_l

	var rt: RoomTypeDef = reg.room_types.values()[0]
	var orig_room: String = rt.loot_table_id
	rt.loot_table_id = bad_r

	var rc: RecipeDef = reg.recipes.values()[0]
	var orig_out: String = rc.output_item_id
	rc.output_item_id = bad_out
	var orig_in: String = str(rc.inputs[0].item_id)
	rc.inputs[0].item_id = bad_in

	# 重新校验（只清 errors 再跑 cross-ref；map 约束不受影响）
	reg.errors.clear()
	reg._validate_cross_refs()

	var joined := "\n".join(reg.errors)
	_check(reg.errors.size() >= 5, "注入 5 个悬空引用后报错数 >= 5（实际 %d）" % reg.errors.size())
	_check(joined.contains(bad_w), "weapon.ammo_id 悬空被抓住")
	_check(joined.contains(bad_l), "loot entry item_id 悬空被抓住")
	_check(joined.contains(bad_r), "room.loot_table_id 悬空被抓住")
	_check(joined.contains(bad_out), "recipe output_item_id 悬空被抓住")
	_check(joined.contains(bad_in), "recipe input item_id 悬空被抓住")

	# 恢复（reg 是局部的，恢复只是好习惯）
	w.ammo_id = orig_ammo
	e0.item_id = orig_loot
	rt.loot_table_id = orig_room
	rc.output_item_id = orig_out
	rc.inputs[0].item_id = orig_in
