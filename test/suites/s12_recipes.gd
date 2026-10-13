extends TestSuite

## C 阶段制造配方数据（W-02）
##
## 验证 data/recipes.json 能被 DataRegistry 正确加载、所有引用都合法、
## 阶段过滤真的生效。契约见 data/SCHEMA.md §8。


func register() -> void:
	_suite("配方加载", _test_recipe_load)
	_suite("配方交叉引用", _test_recipe_crossref)
	_suite("配方结构约束", _test_recipe_structure)


func _test_recipe_load() -> void:
	var reg := DataRegistry.new()
	var ok := reg.load_all("C")

	if not reg.errors.is_empty():
		for e in reg.errors:
			print("        err: %s" % e)

	_check(ok, "load_all(\"C\") 无错误")
	_check(reg.recipes.size() > 0, "recipes 已加载且非空")
	if reg.recipes.is_empty():
		return

	var r: RecipeDef = reg.get_recipe("recipe_medkit_from_parts")
	_check(r != null, "能找到 recipe_medkit_from_parts")
	if r:
		_check(r.inputs.size() >= 1, "该配方至少有一个输入")
		_check(reg.items.has(r.output_item_id), "输出 %s 存在于 items" % r.output_item_id)
		_check(r.time > 0.0, "craft 时间 > 0")


func _test_recipe_crossref() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")

	# 每条配方的输入/输出都必须在已加载物品里（对照 validate_data.py 的契约）
	var bad := 0
	for rid in reg.recipes:
		var r: RecipeDef = reg.recipes[rid]
		if not reg.items.has(r.output_item_id):
			bad += 1
			print("        bad output: %s -> %s" % [rid, r.output_item_id])
		for g in r.inputs:
			if not reg.items.has(g.item_id):
				bad += 1
				print("        bad input: %s -> %s" % [rid, g.item_id])
	_check_eq(bad, 0, "所有配方的输入/输出都指向已加载物品")

	# 阶段过滤：B 档不应含任何 C 阶段配方（纯数据开关，不改代码）
	var reg_b := DataRegistry.new()
	reg_b.load_all("B")
	_check(reg_b.recipes.is_empty(), "B 档不含任何 C 阶段配方")


func _test_recipe_structure() -> void:
	var reg := DataRegistry.new()
	reg.load_all("C")

	for rid in reg.recipes:
		var r: RecipeDef = reg.recipes[rid]
		_check(RecipeDef.STATIONS.has(r.station),
			"%s.station='%s' 合法" % [rid, r.station])
		_check(r.output_count >= 1, "%s 产出数量 >= 1" % rid)
		_check(r.time >= 0.0, "%s 时间 >= 0" % rid)
		var bad_in := 0
		for g in r.inputs:
			if not reg.items.has(g.item_id) or g.count < 1:
				bad_in += 1
		_check_eq(bad_in, 0, "%s 的每个输入都合法" % rid)
