extends TestSuite

## 装备系统「打通」测试（C 阶段）
##
## ⚠️ 为什么还要一套：`s16_equipment` 覆盖的是 `Equipment` **自身的纯逻辑**
##    （槽位判定 / 穿脱 / 重量 / 存档）。但"打通"是另一回事 ——
##    用户的原话是「装备系统需要和 ui 交互以及背包界面打通：藏身处配装、
##    战局里穿脱装备、修改枪械配件、从敌人身上拿到装备和枪械」。
##
##    换句话说要证明的是**接线**：
##      · 藏身处仓库 <-> 装备槽 真的搬家（不是只有个界面）
##      · 局内穿脱走的是**随身背包**（死了要一起丢）
##      · 死亡真的把**身上**那套也清掉（只清背包 = 半个搜打撤）
##      · 改枪改出来的数值真的进 combat（不是只改了个名字）
##      · 面板/入口都在（能力存在但玩家点不到 = 等于不存在）
##
## 只用显式类型（避开 untyped Array 上的 := 推断陷阱）。

func register() -> void:
	_suite("配装：仓库 <-> 装备槽", _test_hideout_loadout)
	_suite("配装：存档往返（含配件 / 旧档兼容）", _test_save_roundtrip)
	_suite("战局：局内穿脱", _test_raid_equip)
	_suite("战局：死亡连身上装备一起丢", _test_death_drops_worn)
	_suite("改枪：配件真的改到数值", _test_modding)
	_suite("闭环：尸体捡枪 -> 装到身上", _test_corpse_to_worn)
	_suite("UI 接线：入口与装备栏都在", _test_ui_wiring)
	_suite("UI 冒烟：面板真能建起来、点得动", _test_panel_smoke)


func _reg() -> DataRegistry:
	var reg := DataRegistry.new()
	reg.load_all("C")
	return reg


## 藏身处 + 4 件可装备的东西 + 3 个绷带（绷带用来证明"不是所有东西都能穿"）
func _hideout_with_gear(reg: DataRegistry) -> Hideout:
	var h := Hideout.new(reg.items, 1000, reg.weapons, reg.attachments)
	h.stash.add("weapon_rifle", 1)
	h.stash.add("armor_light", 1)
	h.stash.add("armor_helmet_light", 1)
	h.stash.add("backpack_tactical", 1)
	h.stash.add("medical_bandage", 3)
	return h


func _src(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# ─────────────────────── 配装 ───────────────────────

func _test_hideout_loadout() -> void:
	var reg := _reg()
	var h := _hideout_with_gear(reg)

	var ids := h.equippable_in_stash()
	_check_eq(ids.size(), 4, "仓库里 4 件可装备（药不算）")
	_check(not ids.has("medical_bandage"), "医疗品不在可装备列表里")

	_check_eq(h.equip_from_stash("weapon_rifle"), "", "穿上步枪")
	_check_eq(h.loadout.id_in("weapon"), "weapon_rifle", "武器槽 = 步枪")
	# ⚠️ 这条是"穿身上不占仓库槽"的核心：枪真的从仓库搬走了
	_check_eq(h.stash.count_of("weapon_rifle"), 0, "枪已离开仓库（穿身上不占仓库槽）")

	_check_eq(h.equip_from_stash("armor_light"), "", "穿上护甲")
	_check_eq(h.loadout.id_in("armor"), "armor_light", "护甲槽")
	_check_eq(h.equip_from_stash("armor_helmet_light"), "", "穿上头盔")
	_check_eq(h.loadout.id_in("helmet"), "armor_helmet_light",
		"头盔走 helmet 槽（同为 armor 类，按 id 含 helmet 区分）")
	_check_eq(h.equip_from_stash("backpack_tactical"), "", "穿上背包")
	_check_eq(h.loadout.id_in("backpack"), "backpack_tactical", "背包槽")

	_check_eq(h.loadout.worn_count(), 4, "身上 4 件")
	_check(h.loadout.worn_weight() > 0.0, "身上重量 > 0（%.1f kg）" % h.loadout.worn_weight())

	# 不能凭空穿
	_check(h.equip_from_stash("armor_heavy") != "", "仓库里没有 -> 有错误原因")
	_check(h.equip_from_stash("medical_bandage") != "", "医疗品不能装备 -> 有错误原因")

	# 脱下回仓库
	_check_eq(h.unequip_to_stash("armor"), "", "脱下护甲")
	_check_eq(h.stash.count_of("armor_light"), 1, "护甲回到仓库")
	_check_eq(h.loadout.id_in("armor"), "", "护甲槽已空")
	_check(h.unequip_to_stash("armor") != "", "空槽脱下 -> 有错误原因（不是静默成功）")

	# 装备槽独立持有：穿一身甲之后仓库还剩 1 个槽位的东西能用
	_check(h.stash.slot_count() >= 4, "装备不占用仓库槽位（仓库槽 %d）" % h.stash.slot_count())


# ─────────────────────── 存档 ───────────────────────

func _test_save_roundtrip() -> void:
	var reg := _reg()
	var h := _hideout_with_gear(reg)
	h.equip_from_stash("weapon_rifle")
	h.equip_from_stash("armor_light")
	_check_eq(h.loadout.set_mod("weapon_rifle", "sight", "att_sight_red_dot"), "", "装红点")
	_check_eq(h.loadout.set_mod("weapon_rifle", "mag", "att_mag_ext"), "", "装扩容弹匣")

	var h2 := Hideout.new(reg.items, 0, reg.weapons, reg.attachments)
	h2.from_dict(h.to_dict())
	_check_eq(h2.loadout.id_in("weapon"), "weapon_rifle", "配装武器往返一致")
	_check_eq(h2.loadout.id_in("armor"), "armor_light", "配装护甲往返一致")
	_check_eq(str(h2.loadout.mods_of("weapon_rifle").get("sight", "")),
		"att_sight_red_dot", "配件（瞄准镜）往返一致")
	_check_eq(str(h2.loadout.mods_of("weapon_rifle").get("mag", "")),
		"att_mag_ext", "配件（弹匣）往返一致")
	_check_eq(h2.stash.count_of("medical_bandage"), 3, "仓库同一次往返也正常")

	# ── 旧档兼容 ──
	# v3 及以前的档**没有 loadout 键**。读进来必须"身上是空的"，
	# 而不是保留上一局的装备（那会让死亡掉装备失效）。
	var h3 := _hideout_with_gear(reg)
	h3.equip_from_stash("weapon_rifle")
	_check_eq(h3.loadout.id_in("weapon"), "weapon_rifle", "h3 前置：已穿上")
	h3.from_dict({"wallet": 10, "upgrades": {}, "stash": {"slots": [], "max_weight": 999.0}})
	_check_eq(h3.loadout.id_in("weapon"), "", "无 loadout 键的旧档 -> 身上是空的")

	# Equipment 自己也要能读**扁平**的旧形状（v3 以前 to_dict 直接返回 slots）
	var eq := Equipment.new(reg.items, reg.weapons, reg.attachments)
	eq.from_dict({"weapon": "weapon_rifle", "armor": ""})
	_check_eq(eq.id_in("weapon"), "weapon_rifle", "兼容旧扁平存档形状")
	_check_eq(eq.id_in("armor"), "", "旧档空槽仍是空")


# ─────────────────────── 战局穿脱 ───────────────────────

func _test_raid_equip() -> void:
	var reg := _reg()
	var h := _hideout_with_gear(reg)
	var raid := RaidSession.new(reg.items, SimRng.new(7), h.stash, h.raid_modifiers())
	raid.equipment = h.loadout
	raid.start(240.0)

	raid.carry.add("weapon_shotgun", 1)
	raid.carry.add("medical_bandage", 1)
	_check_eq(raid.equip_from_carry("weapon_shotgun"), "", "局内穿上霰弹枪")
	# ⚠️ 穿的必须是**藏身处那个 loadout 对象**（引用），撤离后就是你的新配装
	_check_eq(h.loadout.id_in("weapon"), "weapon_shotgun", "穿上后写进藏身处配装（同一对象，无需再搬）")
	_check_eq(raid.carry.count_of("weapon_shotgun"), 0, "枪离开随身背包")

	_check(raid.equip_from_carry("medical_bandage") != "", "医疗品装不上 -> 有原因")

	_check_eq(raid.unequip_from_carry("weapon"), "", "局内脱下")
	_check_eq(raid.carry.count_of("weapon_shotgun"), 1, "脱下的枪回到随身背包")

	# 本局结束后不允许再穿脱（否则结算完还能"白捡"）
	raid.extract()
	_check(raid.equip_from_carry("weapon_shotgun") != "", "撤离后不允许再装备")
	_check(raid.unequip_from_carry("weapon") != "", "撤离后不允许再脱下")

	# 没有装备系统的局（equipment = null）也不能崩
	var raid2 := RaidSession.new(reg.items, SimRng.new(8), null, {})
	raid2.start(60.0)
	_check(raid2.equip_from_carry("weapon_rifle") != "", "无装备系统 -> 有原因且不崩")


# ─────────────────────── 死亡掉落 ───────────────────────

func _test_death_drops_worn() -> void:
	var reg := _reg()
	var h := _hideout_with_gear(reg)
	h.equip_from_stash("weapon_rifle")
	h.equip_from_stash("armor_light")
	var raid := RaidSession.new(reg.items, SimRng.new(9), h.stash, h.raid_modifiers())
	raid.equipment = h.loadout
	raid.start(240.0)
	raid.carry.add("valuables_gpu", 1)
	_check_eq(h.loadout.worn_count(), 2, "前置：身上 2 件")

	raid.take_damage(999)
	_check(raid.phase_name() == "DEAD", "已阵亡")
	# ⭐ 这是"搜打撤"的核心判定：**身上穿的也要丢**
	_check_eq(h.loadout.worn_count(), 0, "死亡后身上装备全部丢失")
	_check_eq(raid.carry.used_slots(), 0, "随身背包同样清空")
	_check_eq(h.stash.count_of("weapon_rifle"), 0, "仓库里没有多出一把枪（没丢成假账）")

	var rep := raid.settle()
	_check(int(rep["lost_value"]) > 0, "结算报告把身上装备算进了损失（%d 元）" % int(rep["lost_value"]))
	_check(int(rep["lost_slots"]) >= 2, "结算报告的丢失格数含身上装备（%d 格）" % int(rep["lost_slots"]))

	# ── 撤离成功：身上装备**保留**（它就是你的新配装）──
	var h2 := _hideout_with_gear(reg)
	h2.equip_from_stash("weapon_rifle")
	var raid2 := RaidSession.new(reg.items, SimRng.new(10), h2.stash, h2.raid_modifiers())
	raid2.equipment = h2.loadout
	raid2.start(240.0)
	raid2.carry.add("valuables_gpu", 1)
	raid2.extract()
	raid2.settle()
	_check_eq(h2.loadout.id_in("weapon"), "weapon_rifle", "撤离后身上的枪还在（不丢）")
	_check_eq(h2.stash.count_of("valuables_gpu"), 1, "撤离战利品进了仓库")


# ─────────────────────── 改枪 ───────────────────────

func _test_modding() -> void:
	var reg := _reg()
	var h := _hideout_with_gear(reg)
	h.equip_from_stash("weapon_rifle")
	var base: WeaponDef = reg.get_weapon("weapon_rifle")

	var lo0 = h.loadout.build_loadout(WeaponModding.SLOTS_C)
	_check(lo0 != null, "能造出有效数值快照")
	_check_eq(int(round(float(lo0.effective["damage"]))), int(base.damage), "裸枪伤害 = 数据里的伤害")

	# 装一个**真能改数值**的配件（枪口延长：射程 +14、伤害 +4）
	_check_eq(h.loadout.set_mod("weapon_rifle", "muzzle", "att_muzzle_ext"), "", "装枪口延长件")
	var lo1 = h.loadout.build_loadout(WeaponModding.SLOTS_C)
	_check(lo1 != null and lo1.attachments.size() == 1, "有效配置里有 1 个配件")
	_check(int(round(float(lo1.effective["range_m"]))) > int(base.range_m),
		"射程真的变长了（%d -> %d）" % [int(base.range_m), int(round(float(lo1.effective["range_m"])))])
	_check(int(round(float(lo1.effective["damage"]))) > int(base.damage),
		"伤害真的变高了（%d -> %d）" % [int(base.damage), int(round(float(lo1.effective["damage"])))])

	# ── 校验：错的插槽 / 不存在的配件不能静默成功 ──
	_check(h.loadout.set_mod("weapon_rifle", "sight", "att_mag_ext") != "",
		"弹匣配件装不进瞄准镜槽 -> 有原因")
	_check(h.loadout.set_mod("weapon_rifle", "nose", "att_sight_red_dot") != "",
		"不存在的插槽 -> 有原因")
	_check(h.loadout.set_mod("weapon_rifle", "sight", "att_nope") != "",
		"不存在的配件 -> 有原因")
	_check(h.loadout.set_mod("", "sight", "att_sight_red_dot") != "",
		"没选中武器 -> 有原因")

	# 卸下
	_check_eq(h.loadout.set_mod("weapon_rifle", "muzzle", ""), "", "卸下枪口件")
	_check(h.loadout.mods_of("weapon_rifle").is_empty(), "配件表清空")
	var lo2 = h.loadout.build_loadout(WeaponModding.SLOTS_C)
	_check(int(round(float(lo2.effective["range_m"]))) == int(base.range_m), "卸下后射程回到裸枪值")

	# 武器槽空 -> 返回 null，调用方据此回退默认枪（raid_scene 走这条路）
	h.unequip_to_stash("weapon")
	_check(h.loadout.build_loadout(WeaponModding.SLOTS_C) == null, "武器槽空 -> null（调用方回退）")

	# 配件跟枪走：换枪再换回来，配置还在
	h.stash.add("weapon_smg", 1)
	h.equip_from_stash("weapon_smg")
	_check_eq(h.loadout.set_mod("weapon_smg", "grip", "att_grip_vertical"), "", "给 SMG 装握把")
	h.equip_from_stash("weapon_rifle")
	_check_eq(str(h.loadout.mods_of("weapon_smg").get("grip", "")), "att_grip_vertical",
		"换回 SMG 时它自己的配件配置还在（配件按枪索引）")


# ─────────────────────── 端到端闭环 ───────────────────────

func _test_corpse_to_worn() -> void:
	var reg := _reg()
	var h := _hideout_with_gear(reg)
	var raid := RaidSession.new(reg.items, SimRng.new(11), h.stash, h.raid_modifiers())
	raid.equipment = h.loadout
	raid.start(240.0)

	# 模拟"打死一个带 DMR 的敌人"：尸体里有那把枪
	var drops: Array = [{"item_id": "weapon_dmr", "count": 1}]
	var cid := raid.add_corpse(Vector2(3, 3), "enemy_marksman", drops)
	_check_eq(raid.take_from_corpse(cid, "weapon_dmr", 1), 1, "从尸体拿到 DMR")
	_check_eq(raid.carry.count_of("weapon_dmr"), 1, "DMR 进了随身背包")
	_check_eq(raid.equip_from_carry("weapon_dmr"), "", "再从背包装到身上")
	_check_eq(h.loadout.id_in("weapon"), "weapon_dmr", "身上换成 DMR（撤离后就是你的配装）")
	_check_eq(raid.carry.count_of("weapon_dmr"), 0, "背包里那把已消失（没有重复计数）")

	# 装上之后能造出 DMR 的有效数值（= 进局后打的真的是它）
	var lo = h.loadout.build_loadout(WeaponModding.SLOTS_C)
	_check(lo != null and lo.weapon.id == "weapon_dmr", "有效数值来自 DMR（不是旧枪）")

	# 敌人掉落表里的装备都是"能进背包的 item"这条契约在 s16，
	# 这里补一条端到端：**尸体掉的护甲也能穿上**
	var drops2: Array = [{"item_id": "armor_medium", "count": 1}]
	var cid2 := raid.add_corpse(Vector2(4, 4), "enemy_raider", drops2)
	raid.take_from_corpse(cid2, "armor_medium", 1)
	_check_eq(raid.equip_from_carry("armor_medium"), "", "尸体掉的护甲也能穿")
	_check_eq(h.loadout.id_in("armor"), "armor_medium", "护甲槽 = 中型护甲")


# ─────────────────────── UI 接线 ───────────────────────

func _test_ui_wiring() -> void:
	# 配装面板
	var lp := _src("res://ui/loadout_panel.gd")
	_check(lp.contains("func _fit_viewport"), "配装面板有 _fit_viewport 兜底（Control 挂 CanvasLayer 下会塌）")
	_check(lp.contains("equip_from_stash") and lp.contains("unequip_to_stash"),
		"按钮接的是 Hideout 的配装 API")
	_check(lp.contains("ModPanel"), "配装面板内嵌改枪面板")
	_check(lp.contains("Equipment.SLOTS"), "槽位遍历走 Equipment.SLOTS（不是各写一份）")

	# 改枪面板
	var mp := _src("res://ui/mod_panel.gd")
	_check(mp.contains("func _fit_viewport"), "改枪面板有 _fit_viewport 兜底")
	_check(mp.contains("set_mod"), "改枪走 Equipment.set_mod（数值只在 sim 层算）")
	_check(mp.contains("build_loadout"), "数值摘要来自 build_loadout（有效值，不是裸枪）")

	# 背包面板：装备栏 + 两个信号
	var ip := _src("res://ui/inventory_panel.gd")
	_check(ip.contains("signal equip_requested") and ip.contains("signal unequip_requested"),
		"背包面板发出穿/脱请求（面板自己不认识战斗）")
	_check(ip.contains("Equipment.SLOTS"), "背包面板有装备栏")
	_check(ip.contains("is_equippable"), "背包条目按『能不能装备』决定动作（不是只看 category）")

	# 藏身处：入口必须在**顶部固定栏**（早先「出发」被滚动挤出屏幕的教训）
	var hs := _src("res://view/hideout_scene.gd")
	_check(hs.contains("LoadoutPanel"), "藏身处有配装面板")
	_check(hs.contains("_open_loadout"), "藏身处有配装入口")
	var i_btn := hs.find("load_btn.pressed_down.connect(_open_loadout)")
	var i_scroll := hs.find("ScrollContainer.new()")
	_check(i_btn > 0 and i_scroll > 0 and i_btn < i_scroll,
		"配装入口在滚动区之前 = 顶部固定栏，任何分辨率都点得到（btn@%d < scroll@%d）"
		% [i_btn, i_scroll])
	# ⚠️ 反向风险：加了第三个按钮后**横向**挤不下，左侧标题/资金会被压成一条缝。
	#    栏位尺寸写成了常量 + 静态自检函数，这里直接调它（将来加按钮会先撞在这里）。
	var scene_script: GDScript = load("res://view/hideout_scene.gd")
	_check(scene_script.bar_fits(640.0),
		"顶部栏四个按钮在 640 宽视口放得下（配装+商人+主菜单+开始下一局）")
	_check(scene_script.bar_fits(1280.0), "1280 宽当然也放得下")

	# 战局：配装真的接进来，且会换枪
	var rs := _src("res://view/raid_scene.gd")
	_check(rs.contains("raid.equipment = hideout.loadout"), "战局把藏身处配装接进来")
	_check(rs.contains("build_loadout"), "玩家武器来自配装的枪（不是写死的步枪）")
	_check(rs.contains("_rebuild_player_weapon"), "换枪后重建手里的枪")
	_check(rs.contains("equip_requested.connect") and rs.contains("unequip_requested.connect"),
		"背包面板的穿/脱信号有接收方（否则点了没反应）")

	# HUD：装备变化要有可见证据
	var rh := _src("res://view/raid_hud.gd")
	_check(rh.contains("_equip_text"), "HUD 显示身上装备（穿脱才看得见）")


# ─────────────────────── UI 冒烟（真建节点） ───────────────────────
#
# ⚠️ 源码断言只能证明"代码写了"，证明不了"点了不崩"。
#    本项目已经栽过三次同类问题（摇杆挤角落 / 结算面板不可见 / 设置菜单
#    size 塌成 0）—— 那些都是**运行时**才暴露的。
#    所以这里真的把面板建出来、真的 open、真的调用点击处理函数。
#
# ⚠️⚠️ **刻意不 add_child(root)**：运行器是在 `SceneTree._initialize()` 里跑测试的，
#    那一刻 root 还没真正进树，子节点的 `_ready` 会被推迟到测试体**之后**才执行。
#    踩到的表现非常误导人：面板"能打开"，但里面每个控件都是 null，
#    于是一路刷 `Invalid assignment ... on a base object of type 'Nil'`。
#    （s07 里也有同一条注记："_ready 只在进树时跑"。）
#    所以这里手动 `_ensure_built()`：要验证的是"面板建得起来、点得动"，
#    而不是"引擎什么时候调 _ready"。
func _test_panel_smoke() -> void:
	var reg := _reg()
	var h := _hideout_with_gear(reg)

	# ── 配装面板 ──
	var lp := LoadoutPanel.new()
	lp.call("_ensure_built")
	_check(lp.get_child_count() > 0,
		"配装面板 _build 真的建出了节点（%d 个子节点）" % lp.get_child_count())
	_check(not lp.is_open(), "配装面板初始是关的")
	lp.open(h, reg.items, reg.weapons, reg.attachments)
	_check(lp.is_open() and lp.visible, "配装面板能打开且可见")
	_check(lp.size.x > 100.0 and lp.size.y > 100.0,
		"面板尺寸被 _fit_viewport 钉住（%s）—— 否则整块塌成 0" % str(lp.size))

	# 点左栏 -> 真的穿上
	lp.call("_on_equip_pressed", "weapon_rifle")
	_check_eq(h.loadout.id_in("weapon"), "weapon_rifle", "点左栏 -> 真的穿到身上")
	lp.call("_on_equip_pressed", "armor_light")
	_check_eq(h.loadout.id_in("armor"), "armor_light", "点第二件 -> 也穿上")

	# 改枪：面板内嵌打开
	lp.call("_open_mod")
	_check(lp.mod_panel != null and lp.mod_panel.is_open(), "配装面板里能打开改枪")
	# 空槽脱下（不该崩，只该给个原因）
	lp.call("_on_unequip_pressed", "helmet")
	lp.call("_on_unequip_pressed", "armor")
	_check_eq(h.loadout.id_in("armor"), "", "点右栏 -> 真的脱回仓库")
	lp.close()
	_check(not lp.is_open(), "配装面板能关闭")
	_check(lp.mod_panel == null or not lp.mod_panel.is_open(),
		"关闭配装时改枪也一起关（否则它会留在上面挡住）")

	# ── 改枪面板（独立开一次）──
	var mp := ModPanel.new()
	mp.call("_ensure_built")
	mp.open(h, reg.weapons, reg.attachments)
	_check(mp.is_open() and mp.visible, "改枪面板能独立打开")
	_check(mp.size.x > 100.0 and mp.size.y > 100.0, "改枪面板尺寸不是 0")
	mp.call("_do_attach", "sight", "att_sight_red_dot")
	_check_eq(str(h.loadout.mods_of("weapon_rifle").get("sight", "")), "att_sight_red_dot",
		"点配件 -> 真的写进配置")
	mp.call("_do_detach", "sight", true)
	_check(h.loadout.mods_of("weapon_rifle").is_empty(), "点已装的 -> 真的卸下")
	mp.call("_do_attach", "sight", "att_nope")
	_check(mp.is_open(), "装不存在的配件只提示、不崩")
	mp.close()
	_check(not mp.is_open(), "改枪面板能关闭")

	# ── 背包面板（带装备栏）──
	var ip := InventoryPanel.new()
	ip.call("_ensure_built")
	ip.open(reg.items, h.stash, null, "", h.loadout)
	_check(ip.is_open(), "背包面板带装备栏能打开")
	_check(ip.size.x > 100.0 and ip.size.y > 100.0, "背包面板尺寸不是 0")
	# 背包里的装备请求要走信号出去（面板自己不做判定）
	var got := [""]
	ip.equip_requested.connect(func(id: String): got[0] = id)
	ip.call("_on_slot_pressed", "weapon", h.loadout.id_in("weapon"))
	ip.close()
	_check(not ip.is_open(), "背包面板能关闭")

	# ⚠️ 这三个节点**从未进过树**，所以 `free()` 是安全的
	#    （不会在 _process/_physics 回调里被杀；项目"一律 queue_free"的规则针对的是树内节点）
	lp.free()
	mp.free()
	ip.free()
