extends TestSuite

## 主菜单 / 选图 / 修理 / 白模主题着色（2026-10-13 第二轮）
##
## 覆盖：
##   ① 白模按 tile_theme 着色（森林/城区/军事基地），且**默认路径逐像素不变**
##   ② 修理：藏身处修理台的费用与修满逻辑（纯 sim 层）
##   ③ 主菜单场景与选图入口（源码/常量契约）
##
## ⚠️ 主菜单**不能**在这里实例化 —— `--script` 模式下 autoload（Game/Sfx/Tel）
##    不注册，`raid_scene.gd` 会 "Identifier not found: Game"。
##    运行时验证在 `test/pc_verify.gd` 的 ⑥ 段（那是场景模式跑）。

func register() -> void:
	_suite("白模：主题着色与不变量", _test_theme_palette)
	_suite("白模：主题真的改变像素", _test_theme_changes_pixels)
	_suite("修理：费用与修满", _test_repair)
	_suite("主菜单：场景与入口契约", _test_main_menu_contract)
	_suite("选图：数据驱动与持久字段", _test_map_pick_contract)


func _load() -> DataRegistry:
	var reg := DataRegistry.new()
	reg.load_all("C")
	return reg


# ═══════════════ ① 主题配色 ═══════════════

func _test_theme_palette() -> void:
	# 默认（"" 和未知 id）必须回退 concrete
	var def_pal := WhiteboxPainter.theme_colors("")
	_check(def_pal == WhiteboxPainter.theme_colors("concrete"), "空主题 == concrete")
	_check(def_pal == WhiteboxPainter.theme_colors("不存在的主题"), "未知主题回退 concrete")

	# ⚠️ concrete 必须与 WB_* 常量逐字节相同 —— s09 的逐像素确定性断言依赖它
	_check(def_pal["floor"] == WhiteboxPainter.WB_FLOOR, "concrete.floor == WB_FLOOR")
	_check(def_pal["corridor"] == WhiteboxPainter.WB_CORRIDOR, "concrete.corridor == WB_CORRIDOR")
	_check(def_pal["wall"] == WhiteboxPainter.WB_WALL, "concrete.wall == WB_WALL")
	_check(def_pal["edge"] == WhiteboxPainter.WB_WALL_EDGE, "concrete.edge == WB_WALL_EDGE")

	# 三个主题的地面色必须互不相同
	var thr := WhiteboxPainter.theme_colors("dirt")
	var urb := WhiteboxPainter.theme_colors("concrete")
	var mil := WhiteboxPainter.theme_colors("metal")
	_check(thr["floor"] != urb["floor"] and urb["floor"] != mil["floor"]
		and thr["floor"] != mil["floor"], "森林/城区/军事基地的地面色各不相同")

	# ⭐ 不变量：looks_like_wall 用 0.16 当分界，每个主题都必须满足
	#    墙 < 0.16 <= 地面/走廊，否则"画成墙 vs 碰撞是墙"会反向。
	for tid in ["dirt", "concrete", "metal"]:
		var p := WhiteboxPainter.theme_colors(tid)
		_check(WhiteboxPainter.looks_like_wall(p["wall"]),
			"%s：墙被判为墙（亮度 %.3f）" % [tid, (p["wall"] as Color).get_luminance()])
		_check(not WhiteboxPainter.looks_like_wall(p["floor"]),
			"%s：地面被判为可走（亮度 %.3f）" % [tid, (p["floor"] as Color).get_luminance()])
		_check(not WhiteboxPainter.looks_like_wall(p["corridor"]),
			"%s：走廊被判为可走" % tid)

	# 地图数据里的 tile_theme 必须都是已知主题（否则白模会静默回退到灰色）
	var reg := _load()
	for mid in reg.maps:
		var md: MapThemeDef = reg.maps[mid]
		_check(WhiteboxPainter.THEME_COLORS.has(md.tile_theme),
			"地图 %s 的 tile_theme '%s' 是已知主题" % [md.id, md.tile_theme])


func _test_theme_changes_pixels() -> void:
	var g := _open_grid(12, 8)
	var rooms: Array = []
	var base := WhiteboxPainter.paint(g, rooms)
	# 默认参数 == 显式 ""：保证既有调用行为不变
	_check(_img_equal(base, WhiteboxPainter.paint(g, rooms, "")),
		"paint(g, rooms) 与 paint(g, rooms, '') 逐像素一致")
	# 换主题必须真的改像素
	_check(not _img_equal(base, WhiteboxPainter.paint(g, rooms, "metal")),
		"军事基地配色与默认配色像素不同")
	_check(not _img_equal(WhiteboxPainter.paint(g, rooms, "dirt"),
		WhiteboxPainter.paint(g, rooms, "metal")),
		"森林与军事基地配色像素不同")

	# 烘焙器也要透传主题
	var baker := RaidMapBaker.new()
	var tex_def := baker.build(g, rooms, true)
	var tex_mil := baker.build(g, rooms, true, "metal")
	_check(tex_def != null and tex_mil != null, "主题烘焙都成功")
	if tex_def != null and tex_mil != null:
		_check(not _img_equal(tex_def.get_image(), tex_mil.get_image()),
			"RaidMapBaker.build 的主题参数真的生效")
		_check(_img_equal(tex_def.get_image(), base),
			"不带主题的烘焙仍等于 WhiteboxPainter 默认输出（确定性未破）")


func _img_equal(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return false
	return true


# ═══════════════ ② 修理 ═══════════════

func _test_repair() -> void:
	var reg := _load()
	var h := Hideout.new(reg.items, 10000, reg.weapons, reg.attachments)
	h.stash.add("weapon_rifle", 1)
	h.stash.add("armor_heavy", 1)
	_check_eq(h.equip_from_stash("weapon_rifle"), "", "穿上步枪")
	_check_eq(h.equip_from_stash("armor_heavy"), "", "穿上重甲")

	# 全新装备：清单有 2 项、无缺失、无需修理
	var worn: Array = h.equipped_wear()
	_check_eq(worn.size(), 2, "装备清单列出 2 件带耐久的装备")
	_check_eq(h.repair_cost(), 0, "全新时修理费为 0")
	var r0: Dictionary = h.repair_all()
	_check(bool(r0["ok"]) and int(r0["cost"]) == 0, "无需修理时 repair_all 成功且不花钱")

	# 造 30 点损耗 -> 修理费 = 30 * 单价
	h.loadout.apply_wear("weapon_rifle", 20)
	h.loadout.apply_wear("armor_heavy", 10)
	_check_eq(h.repair_cost(), 30 * Hideout.REPAIR_PRICE_PER_POINT,
		"修理费 = 缺失点数 x 单价")

	var w_before := h.wallet
	var r1: Dictionary = h.repair_all()
	_check(bool(r1["ok"]), "资金充足时修满成功")
	_check_eq(int(r1["points"]), 30, "修回 30 点")
	_check_eq(h.wallet, w_before - 30 * Hideout.REPAIR_PRICE_PER_POINT, "扣款正确")
	_check_eq(h.repair_cost(), 0, "修满后修理费归零")
	_check_eq(h.loadout.slot_dur("weapon"), h.loadout.slot_max_dur("weapon"), "步枪耐久回满")
	_check_eq(h.loadout.slot_dur("armor"), h.loadout.slot_max_dur("armor"), "护甲耐久回满")

	# 资金不足：不修、不扣钱
	var poor := Hideout.new(reg.items, 0, reg.weapons, reg.attachments)
	poor.stash.add("weapon_rifle", 1)
	poor.equip_from_stash("weapon_rifle")
	poor.loadout.apply_wear("weapon_rifle", 5)
	var need := poor.repair_cost()
	_check(need > 0, "穷档也产生了修理需求（%d 元）" % need)
	var r2: Dictionary = poor.repair_all()
	_check(not bool(r2["ok"]), "资金不足时 repair_all 失败")
	_check(str(r2["err"]) != "", "失败时给出原因（%s）" % str(r2["err"]))
	_check_eq(poor.wallet, 0, "失败时不动钱包")
	_check_eq(int(r2["points"]), 0, "失败时一点没修")

	# 不参与损耗的物品不进清单
	var plain := Hideout.new(reg.items, 100, reg.weapons, reg.attachments)
	plain.stash.add("ammo_rifle", 30)
	_check_eq(plain.equipped_wear().size(), 0, "弹药（无耐久）不进修理清单")


# ═══════════════ ③ 主菜单契约 ═══════════════

func _test_main_menu_contract() -> void:
	_check(ResourceLoader.exists("res://view/main_menu.tscn"), "主菜单场景文件存在")
	_check(ResourceLoader.exists("res://view/main_menu.gd"), "主菜单脚本存在")

	var mm := FileAccess.get_file_as_string("res://view/main_menu.gd")
	_check(mm.contains("开始游戏"), "主菜单有『开始游戏』")
	_check(mm.contains("设置"), "主菜单有『设置』")
	_check(mm.contains("退出"), "主菜单有『退出』")
	_check(mm.contains("SettingsMenu"), "主菜单复用设置菜单")
	_check(mm.contains("go_to_hideout"), "『开始游戏』进藏身处")
	_check(mm.contains("get_tree().quit()"), "『退出』真的退出进程")

	# 项目主场景必须指向主菜单
	var pj := FileAccess.get_file_as_string("res://project.godot")
	_check(pj.contains('run/main_scene="res://view/main_menu.tscn"'),
		"项目主场景 = 主菜单")

	# Game 必须提供主菜单场景常量与切换方法
	var gs := FileAccess.get_file_as_string("res://game/game_state.gd")
	_check(gs.contains("MAIN_MENU_SCENE"), "Game 有 MAIN_MENU_SCENE 常量")
	_check(gs.contains("func go_to_main_menu"), "Game 有 go_to_main_menu()")

	# 藏身处必须有回主菜单的出口（否则安卓上退不出去）
	var hs := FileAccess.get_file_as_string("res://view/hideout_scene.gd")
	_check(hs.contains("主菜单"), "藏身处有『主菜单』按钮")
	_check(hs.contains("_on_home"), "藏身处有回主菜单的处理")
	# 顶部栏自检必须把新按钮算进去（4 个按钮仍要放得下 640）
	var script: GDScript = load("res://view/hideout_scene.gd")
	_check(script.bar_fits(640.0), "顶部栏四个按钮在 640 宽视口放得下")


# ═══════════════ ④ 选图契约 ═══════════════

func _test_map_pick_contract() -> void:
	var reg := _load()
	_check(reg.maps.size() >= 3, "至少 3 张可选地图")

	var hs := FileAccess.get_file_as_string("res://view/hideout_scene.gd")
	_check(hs.contains("_on_pick_map"), "藏身处有选图处理")
	_check(hs.contains("Game.map_id"), "选图写进 Game.map_id（跨场景持久）")
	_check(hs.contains("Game.reg.maps"), "选图按钮从数据生成（不写死三张图）")
	_check(hs.contains("_on_repair"), "藏身处有修理入口")

	# 突袭场景必须优先用 Game.map_id
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("Game.map_id"), "突袭场景读 Game.map_id")
	_check(rs.contains("theme.tile_theme"), "突袭场景把主题色调传给地图烘焙")
