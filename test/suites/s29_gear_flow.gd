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
	_suite("敌人侧：gear 词条乘区（与玩家侧同一函数）", _test_apply_affixes_shared)
	_suite("按下标穿 + 自动作战挑更好的装备", _test_equip_at_and_best_upgrade)


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


## 同一 id 有多件、品质不同时：按 id 穿会拿到靠前那格（可能不是你点的那件），
## 所以要有 equip_at（按下标）+ best_upgrade_slot（挑更好的）。
func _test_equip_at_and_best_upgrade() -> void:
	var reg := _fresh_reg()
	var eq := Equipment.new(reg.items, reg.weapons, reg.attachments, reg.affix_map())
	var inv := Inventory.new(6, reg.items, 999.0)
	inv.add_with_gear("weapon_rifle", {"rarity": "rare", "affixes": []})
	inv.add_with_gear("weapon_rifle", {"rarity": "epic", "affixes": []})

	# ① 按 id 穿 -> 靠前那格（这正是"点史诗却穿上稀有"的成因）
	_check_eq(eq.equip(inv, "weapon_rifle"), "", "按 id 穿上步枪")
	_check_eq(_equipped_rarity(eq, "weapon"), "rare", "按 id 穿取靠前那格（已知行为）")

	# ② 脱下后按下标穿第 2 格 -> 必须是史诗
	eq.unequip(inv, "weapon")
	_check_eq(eq.equip_at(inv, 1), "", "按下标穿第 2 格")
	_check_eq(_equipped_rarity(eq, "weapon"), "epic",
		"★ 按下标穿 = 穿上的正是那一件（面板点哪件就上哪件）")

	# ③ 自动作战：空槽 + 带品质候选 -> 该换
	var eq2 := Equipment.new(reg.items, reg.weapons, reg.attachments, reg.affix_map())
	var inv2 := Inventory.new(6, reg.items, 999.0)
	inv2.add_with_gear("armor_light", {"rarity": "rare", "affixes": []})
	_check(eq2.best_upgrade_slot(inv2, reg.gear_rarities) >= 0,
		"★ 空槽遇到带品质装备 -> 自动作战会换上")

	# ④ 无 gear 的普通货不参与（老档 / 无品质系统时不替玩家换装）
	var inv3 := Inventory.new(6, reg.items, 999.0)
	inv3.add("armor_light", 1)
	_check_eq(eq2.best_upgrade_slot(inv3, reg.gear_rarities), -1,
		"★ 无 gear 普通货不参与（行为与 2026-10-16 之前一致）")

	# ⑤ 身上已是最好的 -> 不降级替换
	var eq4 := Equipment.new(reg.items, reg.weapons, reg.attachments, reg.affix_map())
	var inv4 := Inventory.new(6, reg.items, 999.0)
	inv4.add_with_gear("armor_light", {"rarity": "legendary", "affixes": []})
	eq4.equip(inv4, "armor_light")
	inv4.add_with_gear("armor_light", {"rarity": "common", "affixes": []})
	_check_eq(eq4.best_upgrade_slot(inv4, reg.gear_rarities), -1,
		"★ 背包里更差 -> 不降级")


func _equipped_rarity(eq: Equipment, slot: String) -> String:
	var g: Variant = eq.gear.get(slot, {})
	if not (g is Dictionary):
		return ""
	return str((g as Dictionary).get("rarity", ""))


## 敌人穿戴的装备也要吃品质词条 —— 关键是**与玩家侧同一个函数**，
## 否则两边公式会各走各的（玩家涨 10%、敌人涨 12% 这种偏差最难查）。
func _test_apply_affixes_shared() -> void:
	var reg := _fresh_reg()
	var w: WeaponDef = reg.get_weapon("weapon_rifle")
	_check(w != null, "weapon_rifle 应在武器表里")
	if w == null:
		return
	var dmg_affix: AffixDef = reg.get_affix("aff_weapon_dmg")
	var armor_affix: AffixDef = reg.get_affix("aff_armor")
	_check(dmg_affix != null and armor_affix != null, "伤害/护甲词条都应在表里")

	# ① 无 gear：数值与裸枪逐字段一致（浅区敌人不变强 = 向后兼容）
	var lo0 := WeaponModding.create_loadout(w, WeaponModding.SLOTS_A)
	GearGen.apply_affixes(lo0, {}, reg.gear_affixes)
	_check_eq(int(round(float(lo0.effective.get("damage", 0.0)))), int(w.damage),
		"★ 无 gear 时与裸枪一致（浅区敌人不加成，行为与旧版相同）")

	# ② 有 gear：伤害 +10%
	var gear: Dictionary = {"rarity": "rare",
		"affixes": [{"id": "aff_weapon_dmg", "value": 0.1}]}
	var lo1 := WeaponModding.create_loadout(w, WeaponModding.SLOTS_A)
	GearGen.apply_affixes(lo1, gear, reg.gear_affixes)
	var d1: float = float(lo1.effective.get("damage", 0.0))
	_check(absf(d1 - float(w.damage) * 1.1) < 0.001, "伤害词条 +10pct 生效")

	# ③ 敌人 equip 的是 to_weapon_def() 的产物 —— 词条必须烘进 WeaponDef
	var wd: WeaponDef = lo1.to_weapon_def()
	_check_eq(int(wd.damage), int(round(d1)),
		"to_weapon_def 把词条烘进 WeaponDef（敌人手里拿的就是它）")

	# ④ 防呆：护甲词条是玩家属性，不该污染武器数值
	var lo2 := WeaponModding.create_loadout(w, WeaponModding.SLOTS_A)
	GearGen.apply_affixes(lo2, {"rarity": "rare",
		"affixes": [{"id": "aff_armor", "value": 2.0}]}, reg.gear_affixes)
	_check_eq(int(round(float(lo2.effective.get("damage", 0.0)))), int(w.damage),
		"防呆：护甲词条不污染武器数值")


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
