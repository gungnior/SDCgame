extends TestSuite

## 第八轮真人反馈修复（问题 1~5）回归套件
##
## 用户原话（r7 实机）：
##   1 辅助瞄准太强，玩家需要加上视野锥，辅助瞄准现在甚至可以玩家在看上面
##     辅助会自动锁定到下方敌人
##   2 需要有地图界面可以看到撤离点位置
##   3 不同的敌人需要有不同的特征（颜色），现有的系统是敌人会警戒然后变色
##   4 物品在交互的时候加入拖动系统
##   5 搜刮的时候加入对堆叠物品的快速拾取，要求能自定义拾取数量
##
## ⚠️ 只放**单元层能证明**的东西（sim/ 与纯函数 + 源码结构守卫）。
##    需要真树的（地图真的画出来、拖拽真的落下、弹窗真的弹）在
##    test/pc_verify.gd 的 `_verify_raid_scene` 里 —— 那边有真实 SceneTree 与真实布局。


func register() -> void:
	_suite("问题1：辅助瞄准的视野锥是硬门限", _test_vision_cone_gate)
	_suite("问题1：锁定扫描不会锁到背后/脚下的近距离目标", _test_scan_no_behind)
	_suite("问题1：有效视野锥与绘制同源", _test_effective_cone)
	_suite("问题2：地图等比 letterbox 与坐标换算", _test_map_geometry)
	_suite("问题2：地图接线（面板/按钮/键位）", _test_map_wiring)
	_suite("问题3：敌人身份色解析与去重", _test_enemy_colors)
	_suite("问题3：绘制层把身份色与警示环分开", _test_drawer_two_channels)
	_suite("问题4：TouchButton 拖拽（默认关、开关开）", _test_drag_button)
	_suite("问题4：三个面板都接了拖拽", _test_panels_drag)
	_suite("问题5：数量夹取与一半", _test_qty_math)
	_suite("问题5：堆叠快速拾取接线", _test_qty_ui_wiring)


# ─────────────────── 问题 1：辅助瞄准的视野锥 ───────────────────
#
# 根因：判定是「角度锥 OR 实体半径」，近距离垂距趋近 0 -> 半径通路无条件放行，
#       连正后方（~180°）都算命中；而 `AutoAim.scan_nearest` 连角度兜底都没有。


func _test_vision_cone_gate() -> void:
	# 门限本身必须是"收得住"的：太宽等于没加，太窄会把贴脸正常场景也毙掉
	_check(AimAssist.PLAYER_VISION_HALF_DEG >= 25.0
		and AimAssist.PLAYER_VISION_HALF_DEG <= 60.0,
		"视野锥半角在 25~60 度之间（%.0f°）" % AimAssist.PLAYER_VISION_HALF_DEG)
	_check(AimAssist.within_vision_cone(0.0), "正前方在锥内")
	_check(AimAssist.within_vision_cone(AimAssist.PLAYER_VISION_HALF_DEG - 0.5), "锥内边界内")
	_check(not AimAssist.within_vision_cone(AimAssist.PLAYER_VISION_HALF_DEG + 0.5), "锥外边界外")
	_check(not AimAssist.within_vision_cone(90.0), "侧面 90° 出局")
	_check(not AimAssist.within_vision_cone(180.0), "正后方 180° 出局")

	var g := _open_grid(24, 16)
	var origin := Vector2(6.5, 8.5)
	# 背后 + 超大半径：修复前会被 hitbox 通路放行
	var behind := [{"id": "z", "pos": Vector2(5.5, 8.9), "faction": "enemy",
		"alive": true, "radius": 9.0}]
	_check(AimAssist.pick(origin, Vector2.RIGHT, 0.6, behind, g, 4.2, 30.0).is_empty(),
		"pick：背后的超大目标（半径 9）不被磁性命中")
	# 正当场景仍在：贴脸偏心 0.4 格（21.8°）必须命中
	var near_ok := [{"id": "c", "pos": Vector2(7.5, 8.9), "faction": "enemy", "alive": true}]
	_check(not AimAssist.pick(origin, Vector2.RIGHT, 0.6, near_ok, g, 4.2, 30.0).is_empty(),
		"pick：视野锥内的贴脸目标照常命中")


func _test_scan_no_behind() -> void:
	# 这是用户的原话场景：玩家朝上瞄，脚边偏下的敌人被锁定/自动射击
	var g := _open_grid(24, 16)
	var origin := Vector2(6.5, 8.5)
	var below := [{"id": 1, "pos": Vector2(6.5, 9.4), "faction": "enemy",
		"alive": true, "radius": 9.0}]
	_check(AutoAim.scan_nearest(origin, Vector2.UP, 55.0, 60.0, below, g).is_empty(),
		"朝上瞄时**不会**锁到下方（贴得再近、半径再大也一样）")

	var behind := [{"id": 2, "pos": Vector2(5.5, 8.9), "faction": "enemy",
		"alive": true, "radius": 9.0}]
	_check(AutoAim.scan_nearest(origin, Vector2.RIGHT, 55.0, 60.0, behind, g).is_empty(),
		"朝右瞄时不会锁到背后")

	# 锥角参数被门限夹住：即使调用方传 179°（几乎全向），侧面目标仍出局
	var side := [{"id": 3, "pos": Vector2(7.5, 10.0), "faction": "enemy",
		"alive": true, "radius": 9.0}]
	_check(AutoAim.scan_nearest(origin, Vector2.RIGHT, 179.0, 60.0, side, g).is_empty(),
		"调用方传 179° 锥角也被夹到视野锥门限（56° 的侧面目标出局）")

	# 正常目标照旧
	var front := [{"id": 4, "pos": Vector2(9.5, 8.9), "faction": "enemy", "alive": true}]
	var f := AutoAim.scan_nearest(origin, Vector2.RIGHT, 55.0, 60.0, front, g)
	_check(not f.is_empty() and int(f["target"]["id"]) == 4, "锥内正前方照常锁定")


func _test_effective_cone() -> void:
	# 有效锥 = 枪械锥 ∩ 门限。步枪 55 -> 门限；狙击 30 -> 30（更窄的枪仍然更窄）
	_check_eq(AimAssist.effective_cone_deg(55.0), AimAssist.PLAYER_VISION_HALF_DEG,
		"步枪 55° 被夹到门限 %.0f°" % AimAssist.PLAYER_VISION_HALF_DEG)
	_check(absf(AimAssist.effective_cone_deg(30.0) - 30.0) < 0.001,
		"狙击 30° 保持 30°（门限不会把它放大）")
	_check_eq(AimAssist.effective_cone_deg(0.0), AimAssist.PLAYER_VISION_HALF_DEG,
		"缺数据回退到门限")
	_check(AimAssist.effective_cone_deg(34.0) < AimAssist.effective_cone_deg(45.0),
		"仍随枪械单调（34° < 45°）")

	# ⭐ 逻辑与绘制必须同源：场景的 aim_cone_deg() 必须走 effective_cone_deg
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("AimAssist.effective_cone_deg"),
		"aim_cone_deg() 用 effective_cone_deg（绘制与锁定同一个上限）")
	# 模拟层不许再直接用 w.aim_cone_deg 当扫描锥
	var sr := FileAccess.get_file_as_string("res://view/raid_sim_runner.gd")
	_check(sr.contains("scene.aim_cone_deg()"), "扫描用场景的有效视野锥")
	_check(not sr.contains("var cone = w.aim_cone_deg"), "不再直接用枪械原始视野锥")


# ─────────────────── 问题 2：地图 ───────────────────


func _test_map_geometry() -> void:
	# ① 方形地图 -> 方形区域，且在面板里水平/垂直居中
	var r := MapPanel.fit_rect(44, 44, Vector2(640.0, 360.0), 23.0)
	_check(r.size.x > 0.0 and absf(r.size.x - r.size.y) < 0.01,
		"44x44 地图 -> 方形区域（%.1f x %.1f）" % [r.size.x, r.size.y])
	_check(absf((r.position.x + r.size.x * 0.5) - 320.0) < 0.5, "水平居中")
	_check(absf((r.position.y + r.size.y * 0.5) - 180.0) < 0.5, "垂直居中")
	_check(r.size.y <= 360.0 - 46.0 + 0.5, "不超过可用高度（留了边距）")

	# ② 非方形地图必须**保持宽高比**（拉伸会让撤离点位置全错）
	var r2 := MapPanel.fit_rect(40, 20, Vector2(640.0, 360.0), 20.0)
	_check(absf((r2.size.x / r2.size.y) - 2.0) < 0.02,
		"40x20 地图保持 2:1（实际 %.3f）" % (r2.size.x / r2.size.y))

	# ③ 退化输入不崩
	_check(MapPanel.fit_rect(0, 0, Vector2(640.0, 360.0), 20.0) == Rect2(), "零尺寸地图返回空矩形")
	_check(MapPanel.fit_rect(40, 40, Vector2(20.0, 20.0), 20.0) == Rect2(),
		"面板小于边距时返回空矩形（不做负数缩放）")

	# ④ 格 -> 像素换算：四角与中心
	var mp := Rect2(10.0, 20.0, 100.0, 100.0)
	_check_eq(MapPanel.cell_to_panel(Vector2(0, 0), mp, 40, 40), Vector2(10.0, 20.0), "(0,0) -> 左上角")
	_check_eq(MapPanel.cell_to_panel(Vector2(40, 40), mp, 40, 40), Vector2(110.0, 120.0), "(40,40) -> 右下角")
	_check_eq(MapPanel.cell_to_panel(Vector2(20, 20), mp, 40, 40), Vector2(60.0, 70.0), "中心")


func _test_map_wiring() -> void:
	var mp := FileAccess.get_file_as_string("res://ui/map_panel.gd")
	_check(mp.contains('"撤离"'), "地图上写「撤离」字样（玩家要一眼找到）")
	_check(mp.contains("extract_points"), "地图遍历 raid.extract_points")
	_check(mp.contains("C_EXTRACT"), "撤离点有专属配色")
	_check(mp.contains("room_type == \"extract\""), "撤离房间描成金色")

	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("MapPanel.new()"), "突袭场景实例化地图面板")
	_check(rs.contains("func _toggle_map"), "有开关地图的入口")
	_check(rs.contains("touch.map_pressed.connect(_toggle_map)"), "触屏地图按钮接到开关")
	_check(rs.contains("map_panel.is_open()"), "地图打开时参与逻辑冻结判定")

	var tc := FileAccess.get_file_as_string("res://ui/touch_controls.gd")
	_check(tc.contains("signal map_pressed"), "触屏层有 map_pressed 信号")
	_check(tc.contains("map_btn"), "触屏层有地图按钮")

	var ri := FileAccess.get_file_as_string("res://view/raid_input.gd")
	_check(ri.contains("KEY_N") and ri.contains("_toggle_map"), "PC 上 N 键开地图")

	var hud := FileAccess.get_file_as_string("res://view/raid_hud.gd")
	_check(hud.contains("地图"), "HUD 提示里写了地图入口")


# ─────────────────── 问题 3：敌人身份色 ───────────────────


func _test_enemy_colors() -> void:
	# ① 解析 #rrggbb
	var a := EnemyDef.from_dict({"id": "e1", "color": "#6fbf73"})
	_check(absf(a.color.g - Color.html("#6fbf73").g) < 0.01 and a.color != EnemyDef.DEFAULT_COLOR,
		"解析 '#rrggbb' 成功（%s）" % str(a.color))

	# ② 非法/缺失 -> 按 id 稳定派生（同一 id 永远同一色，不同 id 不同色）
	var b := EnemyDef.from_dict({"id": "e2", "color": "not-a-color"})
	var b2 := EnemyDef.from_dict({"id": "e2"})
	_check_eq(b.color, b2.color, "非法 color 与缺失 color 都按 id 派生，且结果一致")
	var c := EnemyDef.from_dict({"id": "e3"})
	_check(b.color != c.color, "不同 id 派生出的颜色不同（%s / %s）" % [str(b.color), str(c.color)])

	# ③ 真空数据：7 种敌人必须两两不同色
	var reg := DataRegistry.new()
	reg.load_all("C")
	var seen := {}
	var bad: Array[String] = []
	for id in reg.enemies.keys():
		var d: EnemyDef = reg.get_enemy(id)
		if d == null:
			continue
		var key := str(d.color)
		if seen.has(key):
			bad.append("%s 与 %s 同色 %s" % [id, str(seen[key]), key])
		seen[key] = id
	_check(bad.is_empty(), "所有敌人两两不同色（%d 种）%s" % [reg.enemies.size(),
		"" if bad.is_empty() else str(bad)])


func _test_drawer_two_channels() -> void:
	# 现状：只有"警戒变色"一条通道，感染体与暴徒长得一样。
	# 修法：填充 = 类型身份色；外圈环 = 警戒状态。两条通道必须在绘制里都能找到。
	var dr := FileAccess.get_file_as_string("res://view/raid_drawer.gd")
	_check(dr.contains("a.def.color"), "敌人填充用类型身份色")
	_check(dr.contains("ring_col"), "警戒状态改用外圈环")
	_check(dr.contains("draw_arc(ctr, r + 2.5"), "状态环真的画出来了")
	_check(dr.contains("C_ENEMY_ALERT") and dr.contains("C_ENEMY_COMBAT"),
		"状态环仍保留警觉/交战两级配色")
	# 类型色必须来自数据（而不是又写死一张表）
	_check(dr.contains("var body: Color = a.def.color"), "body 取自 def.color")


# ─────────────────── 问题 4：拖拽 ───────────────────


func _test_drag_button() -> void:
	# ① 默认必须关（否则开火/摇杆会变成"松手才触发"）
	var off := TouchButton.new()
	_check(not off.drag_enabled, "TouchButton 默认 drag_enabled=false（老行为逐字不变）")
	_check(off.drag_threshold > 0.0, "有拖拽阈值（防手抖）")

	# ② 关着时：按下即触发（老语义）
	var hits := [0]
	off.pressed_down.connect(func(): hits[0] += 1)
	root.add_child(off)
	off.call("_begin_press", Vector2(10, 10))
	_check_eq(hits[0], 1, "drag 关闭时，按下就发 pressed_down")
	off.call("_end_press", Vector2(10, 10))
	off.queue_free()

	# ③ 开着时：没拖动 -> 松手才算点按
	var on := TouchButton.new()
	on.drag_enabled = true
	var taps := [0]
	var starts := [0]
	var drops := [0]
	on.pressed_down.connect(func(): taps[0] += 1)
	on.drag_started.connect(func(_p): starts[0] += 1)
	on.drag_dropped.connect(func(_p): drops[0] += 1)
	root.add_child(on)
	on.call("_begin_press", Vector2(10, 10))
	_check_eq(taps[0], 0, "拖拽模式下按下**不**立刻执行动作（要等松手才知道是点还是拖）")
	on.call("_end_press", Vector2(12, 12))
	_check_eq(taps[0], 1, "没拖过阈值 -> 松手当点按")
	_check_eq(starts[0], 0, "没拖过阈值不发 drag_started")

	# ④ 拖过阈值 -> drag_started / drag_dropped，且**不**发 pressed_down
	on.call("_begin_press", Vector2(10, 10))
	on.call("_update_drag", Vector2(10.0 + on.drag_threshold + 6.0, 10.0))
	_check_eq(starts[0], 1, "超过阈值发 drag_started")
	on.call("_end_press", Vector2(200, 200))
	_check_eq(drops[0], 1, "拖拽松手发 drag_dropped")
	_check_eq(taps[0], 1, "拖拽结束**不**再补发 pressed_down（否则会误触发动作）")

	# ⑤ 强制释放要把拖拽态也清掉（切场景/失去焦点）
	on.drag_enabled = true
	on.call("_begin_press", Vector2(10, 10))
	on.call("_update_drag", Vector2(500, 500))
	on.call("force_release")
	_check(not on.is_down, "force_release 关掉按下态")

	# ⑥ 命中区必须和画出来的形状一致（宽行早先只有中间圆圈能点）
	var bb := FileAccess.get_file_as_string("res://ui/touch_button.gd")
	_check(bb.contains("size.x > size.y * 1.4"), "命中区按宽/方分别判定（与 _draw 的宽控件分支一致）")

	on.queue_free()


func _test_panels_drag() -> void:
	for f in ["res://ui/inventory_panel.gd", "res://ui/carry_panel.gd",
			"res://ui/loadout_panel.gd"]:
		var src := FileAccess.get_file_as_string(f)
		_check(src.contains("DragGhost"), "%s 有拖拽浮标" % f)
		_check(src.contains("drag_enabled = true"), "%s 给条目开了拖拽" % f)
		_check(src.contains("drag_dropped.connect"), "%s 接了落下回调" % f)
		_check(src.contains("func drag_state"), "%s 暴露拖拽态（可测）" % f)
	# 落点判定必须用"对面那一栏"，不是随便松手就生效
	var cp := FileAccess.get_file_as_string("res://ui/carry_panel.gd")
	_check(cp.contains("size.x * 0.5"), "携带面板按中线判定落点（拖回自己那边 = 取消）")
	var lp := FileAccess.get_file_as_string("res://ui/loadout_panel.gd")
	_check(lp.contains("bool(d[\"to_worn\"]) != on_right"), "配装面板按方向判定（装 / 脱）")
	# 浮标不能吃触摸（吃了就"怎么拖都放不下"）
	var dg := FileAccess.get_file_as_string("res://ui/drag_ghost.gd")
	_check(dg.contains("MOUSE_FILTER_IGNORE"), "拖拽浮标不吃触摸")


# ─────────────────── 问题 5：快速拾取 + 自定义数量 ───────────────────


func _test_qty_math() -> void:
	# clamp_amount：want<=0 = 全部（与 Hideout 的搬运 API 语义一致）
	_check_eq(Inventory.clamp_amount(0, 12), 12, "0 = 全部")
	_check_eq(Inventory.clamp_amount(-5, 7), 7, "负数 = 全部")
	_check_eq(Inventory.clamp_amount(5, 12), 5, "正常数量原样")
	_check_eq(Inventory.clamp_amount(99, 12), 12, "超过源里有的 -> 夹到 12")
	_check_eq(Inventory.clamp_amount(3, 0), 0, "源里没有 -> 0")

	# 一半：至少 1，不超过上限（0 个物品时也不能给 0，否则按钮变成死键）
	_check_eq(QtyPrompt.half_of(12), 6, "12 的一半 = 6")
	_check_eq(QtyPrompt.half_of(13), 6, "13 的一半 = 6（整除）")
	_check_eq(QtyPrompt.half_of(1), 1, "1 的一半 = 1（不能是 0）")
	_check_eq(QtyPrompt.half_of(0), 1, "0 的一半也给 1（不死键）")

	# fit_count：按背包剩余容量夹
	var reg := DataRegistry.new()
	reg.load_all("A")
	var inv := Inventory.new(2, reg.items, 999.0)
	var ammo: ItemDef = reg.get_item("ammo_rifle")
	_check(ammo != null and ammo.stack_max > 1, "步枪弹可堆叠（stack_max=%d）"
		% (0 if ammo == null else ammo.stack_max))
	var cap := ammo.stack_max * 2
	_check_eq(inv.fit_count("ammo_rifle", cap), cap, "2 个空槽 -> 能放 2 个满堆")
	inv.add("ammo_rifle", ammo.stack_max)
	_check_eq(inv.fit_count("ammo_rifle", cap), ammo.stack_max, "占满 1 槽后只剩 1 槽的容量")
	_check_eq(inv.fit_count("ammo_rifle", 3), 3, "要的比容量少 -> 原样")


func _test_qty_ui_wiring() -> void:
	var ip := FileAccess.get_file_as_string("res://ui/inventory_panel.gd")
	_check(ip.contains("全拿"), "堆叠行有「全拿」按钮")
	_check(ip.contains("取N…"), "堆叠行有「取N…」按钮")
	_check(ip.contains("func _make_container_row"), "容器行有独立构建函数")
	_check(ip.contains("QtyPrompt.new()"), "面板内嵌数量弹窗")
	_check(ip.contains("action.emit(item_id, count)"), "「全拿」= 一次搬走整堆")
	_check(ip.contains("_right_inv.fit_count"), "弹窗上限用 fit_count 提示")
	_check(ip.contains("func _on_qty_confirmed"), "确定后发出自定义数量")

	var qp := FileAccess.get_file_as_string("res://ui/qty_prompt.gd")
	_check(qp.contains("signal confirmed(count: int)"), "弹窗发 confirmed(count)")
	_check(qp.contains("Inventory.clamp_amount"), "夹取走 sim 层的 clamp_amount（界面与搬运同一套规则）")
	_check(qp.contains("全部") and qp.contains("一半"), "有「一半 / 全部」快捷")
	_check(qp.contains("func _ensure_built"), "幂等构建（测试里 add_child 不触发 _ready）")
