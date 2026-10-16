extends TestSuite

## 装备闭环 Phase A（2026-10-16 · WorkBuddy）
##
## 背景：拥有者四问体检发现 —— 装备系统**"穿上之后"是通的，"掉落到捡起"是断的**：
##   · `_spawn_containers` 从不 roll 词条（生产路径漏调 `roll_gear_for_drops`）；
##   · `add_container` 只复制 item_id/count，gear 直接丢；
##   · `ContainerInstance.take/take_all` 与 `take_from_corpse/take_all_from_corpse`
##     全用 `inv.add()` —— **带词条的枪捡进背包就变回普通品质**。
## 本套件把这两条断点**钉死不许再断**：
##   ① add_container / add_corpse 保留 gear 键；
##   ② 四条取物路径走 `add_with_gear`，gear 随物品进背包；
##   ③ 背包塞不下时 gear **留在原处**（容器/尸体里还能再捡），绝不静默丢失；
##   ④ 无 gear 的普通掉落（堆叠货）行为与 2026-10-16 之前逐字一致。


func register() -> void:
	_suite("容器：add_container 保留 gear + take 搬进背包", _test_container_take)
	_suite("容器：take_all 保留 gear，塞不下的留在容器里", _test_container_take_all)
	_suite("尸体：add_corpse 保留 gear + take 搬进背包", _test_corpse_take)
	_suite("尸体：take_all 保留 gear，塞不下的留在尸体里", _test_corpse_take_all)
	_suite("向后兼容：无 gear 掉落行为不变", _test_no_gear_unchanged)
	_suite("UI：背包面板真的显示品质与评分", _test_panel_shows_gear)


var _reg: DataRegistry = null


func _fresh_reg() -> DataRegistry:
	if _reg != null:
		return _reg
	_reg = DataRegistry.new()
	var ok: bool = _reg.load_all("C")
	_check(ok, "DataRegistry.load_all(C) 应零错误")
	return _reg


func _fresh_raid() -> RaidSession:
	var reg := _fresh_reg()
	var rng := SimRng.new(7)
	return RaidSession.new(reg.items, rng, null, {}, {},
		{"rarities": reg.gear_rarities, "affixes": reg.gear_affixes})


## 造一件带词条的装备掉落
func _gear_drop(item_id: String, rarity: String) -> Dictionary:
	return {"item_id": item_id, "count": 1,
		"gear": {"rarity": rarity, "affixes": [{"id": "aff_weapon_dmg", "value": 0.1}]}}


func _rarity_of(slot: Variant) -> String:
	if not (slot is Dictionary):
		return ""
	var d: Dictionary = slot as Dictionary
	if not d.has("gear"):
		return ""
	return str((d["gear"] as Dictionary).get("rarity", ""))


func _test_container_take() -> void:
	var raid := _fresh_raid()
	var idx := raid.add_container(null, Vector2.ZERO, [_gear_drop("weapon_rifle", "rare")])
	_check(idx >= 0, "容器登记成功")
	var c: ContainerInstance = raid.containers[idx]
	var d0: Dictionary = c.drops[0] as Dictionary
	_check(d0.has("gear"), "add_container 必须保留 gear 键（这里丢了就再也捡不到）")
	var taken := c.take("weapon_rifle", 1, raid.carry)
	_check_eq(taken, 1, "拿走一件带词条步枪")
	_check_eq(_rarity_of(raid.carry.slots[0]), "rare",
		"★ 进背包后槽位仍带 gear（旧代码走 add() 会把词条洗掉）")


func _test_container_take_all() -> void:
	var reg := _fresh_reg()
	var raid := _fresh_raid()
	var small := Inventory.new(1, reg.items, 999.0)
	var idx := raid.add_container(null, Vector2.ZERO, [
		_gear_drop("weapon_rifle", "epic"),
		_gear_drop("armor_light", "rare"),
	])
	var c: ContainerInstance = raid.containers[idx]
	var rest := c.take_all(small)
	var filled := 0
	for s in small.slots:
		if s != null:
			filled += 1
	_check_eq(filled, 1, "容量 1 的背包只塞下一件")
	_check_eq(rest.size(), 1, "剩一件留在容器里")
	var r0: Dictionary = rest[0] as Dictionary
	_check(r0.has("gear"), "★ 塞不下的那件 gear 必须留在容器里（不能丢）")
	_check(_rarity_of(small.slots[0]) != "", "塞进去的那件带 gear")


func _test_corpse_take() -> void:
	var raid := _fresh_raid()
	var cid := raid.add_corpse(Vector2.ZERO, "enemy_scav", [_gear_drop("weapon_smg", "legendary")])
	_check(cid >= 0, "尸体登记成功")
	var taken := raid.take_from_corpse(cid, "weapon_smg", 1)
	_check_eq(taken, 1, "从尸体拿走一件")
	_check_eq(_rarity_of(raid.carry.slots[0]), "legendary",
		"★ 搜尸捡起的装备保留品质词条（旧代码在这里洗掉）")


func _test_corpse_take_all() -> void:
	var reg := _fresh_reg()
	var raid := _fresh_raid()
	var small := Inventory.new(1, reg.items, 999.0)
	raid.carry = small
	var cid := raid.add_corpse(Vector2.ZERO, "enemy_scav", [
		_gear_drop("weapon_smg", "epic"),
		_gear_drop("armor_medium", "rare"),
	])
	var rest := raid.take_all_from_corpse(cid)
	_check_eq(rest.size(), 1, "容量 1 -> 剩一件在尸体里")
	var r0: Dictionary = rest[0] as Dictionary
	_check(r0.has("gear"), "★ 塞不下的那件 gear 必须留在尸体里")
	_check(_rarity_of(small.slots[0]) != "", "搜进背包的那件带 gear")


func _test_no_gear_unchanged() -> void:
	var raid := _fresh_raid()
	# 堆叠货（弹药）没有 gear —— 走老的 add 路径，count 语义必须一字不变
	var idx := raid.add_container(null, Vector2.ZERO, [{"item_id": "ammo_rifle", "count": 30}])
	var c: ContainerInstance = raid.containers[idx]
	var taken := c.take("ammo_rifle", 12, raid.carry)
	_check_eq(taken, 12, "无 gear 掉落按请求数量拿（与旧行为一致）")
	var d0: Dictionary = c.drops[0] as Dictionary
	_check_eq(int(d0.get("count", 0)), 18, "容器里余 18")
	_check(not d0.has("gear"), "无 gear 掉落不该被凭空加上 gear")


## 面板冒烟：真的建出来、真的 open、真的扫子节点文本。
##
## ⚠️ 与 s17 同手法：**刻意不 add_child(root)**（运行器在 SceneTree._initialize 跑测试，
##    那一刻 root 还没进树，`_ready` 会被推迟到测试体之后）→ 手动 `_ensure_built()`。
func _test_panel_shows_gear() -> void:
	var reg := _fresh_reg()
	var carry := Inventory.new(20, reg.items, 999.0)
	carry.add_with_gear("weapon_rifle",
		{"rarity": "rare", "affixes": [{"id": "aff_weapon_dmg", "value": 0.1}]})
	var ip := InventoryPanel.new()
	ip.call("_ensure_built")
	ip.open(reg.items, carry, null, "背包", null,
		{"rarities": reg.gear_rarities, "affixes": reg.gear_affixes})
	var texts := _collect_text(ip)
	var hit_rarity := false
	var hit_score := false
	for t in texts:
		if t.find("稀有") >= 0:
			hit_rarity = true
		if t.find("评分") >= 0:
			hit_score = true
	_check(hit_rarity, "★ 背包面板要显示品质名（否则玩家看不出装备差异）")
	_check(hit_score, "★ 背包面板要显示评分（全境2 的取舍依据）")
	ip.close()


## 递归收集子树里所有控件的文本（TouchButton.label_text / Label.text）
func _collect_text(node: Node) -> Array[String]:
	var out: Array[String] = []
	if node == null:
		return out
	if "label_text" in node:
		out.append(str(node.get("label_text")))
	elif "text" in node:
		out.append(str(node.get("text")))
	for c in node.get_children():
		out.append_array(_collect_text(c))
	return out
