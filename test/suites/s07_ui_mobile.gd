extends TestSuite

## UI 与移动端
##
## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。


func register() -> void:
	_suite("真机修复：结算界面与触屏接口", _test_result_overlay_exists)
	_suite("真机修复2：触屏输入隔离", _test_touch_input_isolation)
	_suite("真机修复2：白模渲染", _test_whitebox_render)
	_suite("PC实测：键位与设置菜单", _test_keybindings)
	_suite("PC实测：Control 尺寸不得塌成 0", _test_control_size_not_zero)
	_suite("PC实测：藏身处布局", _test_hideout_layout)
	_suite("手机实测：HUD 性能读数", _test_hud_perf_metric)
	_suite("PC实测：粒子坐标换算", _test_fx_cell_coords)
	_suite("真机修复3：测试模式敌人上限", _test_enemy_count_test_mode)
	# ⚠️ 原先【定义了但从未注册】—— 补上（见 test_kit.gd 的说明）
	_suite("补注册：settings menu layout", _test_settings_menu_layout)


func _test_result_overlay_exists() -> void:
	# 结算界面必须存在且可实例化 —— 它是手机上唯一的"再来一局"出口
	var s: GDScript = load("res://ui/result_overlay.gd")
	_check(s != null, "result_overlay.gd 可载入")
	var ov: Node = s.new()
	root.add_child(ov)
	# _ready 只在进树时跑；这里手动触发一次，保证后续断言有意义
	if not ov.has_method("show_result"):
		_check(false, "result_overlay 缺少 show_result")
	else:
		_check(true, "result_overlay 有 show_result")
	_check(ov.has_signal("restart_requested"), "有 restart_requested 信号")
	ov.queue_free()

	# 触屏控件也要有"整体收起"接口（结算时藏起来，不然会透过遮罩露出来）
	var ts: GDScript = load("res://ui/touch_controls.gd")
	_check(ts != null, "touch_controls.gd 可载入")
	var tc: Node = ts.new()
	root.add_child(tc)
	_check(tc.has_method("set_controls_visible"), "有 set_controls_visible")
	_check(tc.has_method("release_all"), "有 release_all")
	_check(tc.has_method("move_vector") and tc.has_method("aim_vector"), "有移动/瞄准读取接口")
	_check(tc.has_method("aim_push"), "有 aim_push（aim assist 靠它判断推力）")
	tc.queue_free()


# ─────────────────── 触屏输入隔离 / 卡顿 / 白模（第二轮真机反馈）───────────────────


func _test_touch_input_isolation() -> void:
	# ⚠️ 安卓真机反馈的三个问题（按右侧任意处开火 / 点瞄准摇杆开火 / 按治疗也开火）
	#    根因是同一个：raid_scene 的 _input 里还留着【没有触屏控件时代】的
	#    全局触摸开火代码，它和 VirtualJoystick / TouchButton 抢输入。
	#
	#    这类"遗留代码抢输入"很容易在后续迭代里被无意加回来，
	#    所以这里做**源码级守卫**。
	var src := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(not src.is_empty(), "能读到 raid_scene.gd")
	_check(not src.contains("is InputEventScreenTouch"),
		"raid_scene 不再自己处理触摸事件（交给 VirtualJoystick / TouchButton）")
	_check(not src.contains("_touch_move_id"), "遗留的自绘摇杆状态已清除")
	# ⚠️ 这几条是「行为存在」类断言 —— 用视图层合并源码查。
	#    它们原来查 raid_scene.gd，但读取触屏状态的代码随 _tick_player
	#    搬到了 raid_sim_runner.gd。用 _view_src() 之后，
	#    代码在视图层内再怎么搬都不会误报（见 suite_base.gd 的说明）。
	var vsrc := _view_src()
	_check(vsrc.contains("touch.is_firing()"),
		"开火状态确实读取了触屏开火按钮（否则按钮点了没反应）")
	_check(vsrc.contains("touch.move_vector()"), "移动读取触屏摇杆")
	_check(vsrc.contains("touch.aim_vector()"), "瞄准读取触屏摇杆")

	# 触屏按钮必须按 finger index 分别记录（T-12）
	var btn := FileAccess.get_file_as_string("res://ui/touch_button.gd")
	_check(btn.contains("_finger"), "TouchButton 按 finger index 记录触点（T-12）")
	_check(btn.contains("t.index == _finger"),
		"抬起时只清【该 index】—— 无脑清空会导致别的按钮同时归零")


func _test_whitebox_render() -> void:
	# 技术验证阶段默认白模（用户建议 + 真机"看不出哪能走"）
	# ⚠️ 这里原本断言白模的**实现细节**在 raid_scene.gd 里。
	#    但那块代码已经搬到 `view/raid_map_baker.gd`（拆分上帝对象）——
	#    于是三条断言失败。**这是这类"源码文本断言"的通病**：
	#    它把「代码在哪」和「代码对不对」绑在了一起，一重构就失效。
	#    修法分两层，各查各的：
	#      · 「默认是白模」是**场景的策略** -> 查 raid_scene.gd
	#      · 「烘焙怎么做」是**烘焙器的实现** -> 查 raid_map_baker.gd
	var src := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	var baker := FileAccess.get_file_as_string("res://view/raid_map_baker.gd")
	_check(src.contains("RENDER_WHITEBOX"), "有白模渲染模式")
	_check(src.contains("RENDER_ART"), "保留美术 tile 模式（可切换）")
	_check(src.contains("var render_mode := RENDER_WHITEBOX"),
		"默认是白模（技术验证优先『能读懂』而非『好看』）")
	_check(baker.contains("_build_whitebox"), "有白模烘焙函数")
	# 白模的语义必须极端简单：亮 = 可走，暗 + 描边 = 阻挡
	_check(baker.contains("WB_FLOOR") and baker.contains("WB_WALL"),
		"白模区分地板与墙的配色")
	_check(baker.contains("WB_WALL_EDGE"), "墙有高亮描边（一眼可辨）")
	# 场景必须把烘焙委托出去，而不是又长回来
	_check(src.contains("RaidMapBaker") and src.contains("map_baker.build("),
		"场景把地图烘焙委托给 RaidMapBaker（防代码回流）")

	# 白模烘焙必须真的能跑出图（不崩、尺寸对）
	var reg := DataRegistry.new()
	reg.load_all("B")
	var gen := MapGenerator.new()
	_check(gen.generate(4242, reg.room_types), "地图生成成功")
	var g := gen.grid
	var te := g.tile_extents()
	_check(te.x > 0 and te.y > 0, "tile 尺寸 %s" % str(te))
	# 直接调静态语义：可走格与阻挡格在数据层确实是分开的
	_check(g.is_walkable(gen.spawn_room().center), "出生点房间中心可走")
	var solid_found := false
	for y in g.height:
		for x in g.width:
			if not g.is_walkable(Vector2i(x, y)):
				solid_found = true
				break
		if solid_found:
			break
	_check(solid_found, "地图里确实存在阻挡格（白模要把它画出来）")


# ─────────────────── 性能回归：听觉代价场缓存 ───────────────────


func _test_keybindings() -> void:
	# 用户 PC 实测："修改 pc 按键 r 为装弹 k 为重启 t 为治疗"
	#           "f1 到 f4 没有说明 应该加入 esc 设置菜单"
	# ⚠️ 键位分派已搬到 view/raid_input.gd（拆分上帝对象，第 5 处）。
	#    这已是本次重构中第 5 次遇到"源码文本断言因代码搬家而失效"——
	#    它把「代码在哪」和「代码对不对」绑在了一起。
	#    修法不是简单换文件名，而是**查该查的地方**：
	#      · 键位分派 -> raid_input.gd
	#      · 「场景把输入委托出去」-> raid_scene.gd
	#      · ESC 归属     -> 两个文件都不能处理
	var ri := FileAccess.get_file_as_string("res://view/raid_input.gd")
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	var i := ri.find("func handle_key(event: InputEvent)")
	_check(i > 0, "找到 handle_key")
	var seg := ri.substr(i, 1600)
	_check(seg.contains("KEY_R:") and seg.contains("start_reload()"),
		"R = 装弹")
	_check(seg.contains("KEY_T:") and seg.contains("_try_heal()"),
		"T = 治疗")
	_check(seg.contains("KEY_B:") and seg.contains("_open_bag()"),
		"B = 背包/搜索（PC 上必须有键，否则尸体搜不了）")
	_check(seg.contains("KEY_K:"), "K 已绑定（重开）")
	_check(not seg.contains("KEY_L:"), "旧的 L 键已移除")
	# ESC 不能在 raid_input / raid_scene 里处理，
	# 否则和 SettingsMenu 撞车（toggle 两次 = 没反应）
	_check(not seg.contains("KEY_ESCAPE"),
		"ESC 不由 raid_input 处理（交给 SettingsMenu 独占）")
	_check(not rs.contains("KEY_ESCAPE"),
		"ESC 也不由 raid_scene 处理")
	# 防回流：场景必须把输入委托出去
	_check(rs.contains("raid_input.handle_key(event)"),
		"场景把 _input 委托给 RaidInput（防代码回流）")
	var sm := FileAccess.get_file_as_string("res://ui/settings_menu.gd")
	_check(sm.contains('is_action_pressed("ui_cancel")'), "ESC 走 ui_cancel")
	_check(sm.contains("NOTIFICATION_WM_GO_BACK_REQUEST"), "安卓返回键也接上了")
	_check(sm.contains("F1") and sm.contains("F4"),
		"设置菜单里写了 F1~F4 的说明（用户：『f1 到 f4 没有说明』）")
	# ⚠️ 这里**故意断言不使用 get_tree().paused**。
	#    PC 实测：用了它之后按 ESC 卡死（树被暂停 28 秒且 ESC 关不掉）。
	#    它会连输入一起门控，导致菜单看得见、点不动。
	#    现在改成纯逻辑冻结（Game.paused），输入路径完全不变。
	_check(not sm.contains("get_tree().paused = true"),
		"不使用 get_tree().paused（它会门控输入 -> 菜单点不动 -> 卡死）")
	_check(sm.contains("Game.paused = true"), "打开菜单会冻结游戏逻辑")
	_check(sm.contains("Game.paused = false"), "关闭菜单会恢复")
	_check(rs.contains("Game.paused") or rs.contains("game_paused"),
		"场景 _process 会看暂停标志")
	_check(sm.contains("PROCESS_MODE_ALWAYS"), "菜单自身不受暂停影响")
	# 场景里要有场景内开关的钩子
	_check(rs.contains("func toggle_whitebox()"), "有 toggle_whitebox 钩子")
	_check(rs.contains("func toggle_debug()"), "有 toggle_debug 钩子")
	_check(rs.contains("var game_paused := false"), "有 game_paused 标志")


func _test_control_size_not_zero() -> void:
	# ⚠️ 这个坑在本会话里踩了三次：
	#   ① 虚拟摇杆   —— 布局全挤在角落
	#   ② 结算面板   —— 面板整个看不见
	#   ③ 设置菜单   —— 按 ESC 后**只看得到顶部两个小圆按钮，
	#                   暗色背景和所有开关都不渲染**（用户："esc 了看不到继续"）
	#
	# 根因完全相同：**`Control` 直接挂在 `CanvasLayer` / `Node2D` 下时，
	#   `set_anchors_preset(FULL_RECT)` 解析不到父矩形 -> 自身 size 停在 (0,0)
	#   -> 子节点全部塌掉。**
	#
	# 正确做法：自己跟 viewport 尺寸同步（并在 viewport 变化时重新同步）。
	var sm := FileAccess.get_file_as_string("res://ui/settings_menu.gd")
	_check(sm.contains("func _fit_viewport"), "设置菜单有 _fit_viewport")
	_check(sm.contains("size = vp"), "把自身 size 钉到视口尺寸")
	_check(sm.contains("get_viewport().size_changed.connect"),
		"监听 viewport 尺寸变化（窗口/旋转后要重新同步）")
	# 顺序：必须先手动同步一次，再连信号（否则第一帧仍然是塌的）
	var i_fit := sm.find("_fit_viewport()")
	var i_conn := sm.find("size_changed.connect")
	_check(i_fit > 0 and i_conn > 0 and i_fit < i_conn,
		"先同步再连接信号（fit@%d < connect@%d）" % [i_fit, i_conn])

	# 结算面板也要有这个兜底（它是第二个踩坑的地方）
	var ro := FileAccess.get_file_as_string("res://ui/result_overlay.gd")
	_check(ro.contains("get_viewport_rect()") or ro.contains("size = vp"),
		"结算面板也用了 viewport 兜底")

	# TouchButton 不能无条件覆盖调用方设的最小尺寸 ——
	# 否则设置菜单里设的 150x76 会被悄悄改成 60x60，文字溢出到圆外
	var tb := FileAccess.get_file_as_string("res://ui/touch_button.gd")
	_check(tb.contains("if custom_minimum_size == Vector2.ZERO"),
		"TouchButton 只在调用方没指定时才推最小尺寸")
	_check(tb.contains("func _draw_wide"),
		"宽控件画圆角矩形（否则文字溢出圆形按钮）")


func _test_hideout_layout() -> void:
	# 真机反馈："在返回藏身处后加入 开始下一局的 ui"
	# 查证：藏身处早先把所有内容塞进一个 VBox，
	# 640x360 下内容总高约 586px -> **「出发」按钮被挤出屏幕**，
	# 玩家回到藏身处后找不到怎么开下一局。
	# （与设置菜单"看不到继续"完全同类：内容超出视口 + 关键按钮放在末尾。）
	var hs := FileAccess.get_file_as_string("res://view/hideout_scene.gd")
	_check(hs.contains("开始下一局"), "按钮文案是「开始下一局」")
	_check(hs.contains("func _fit_viewport"), "藏身处也有 _fit_viewport 兜底")
	_check(hs.contains("ScrollContainer"), "内容放进滚动容器")
	# 关键：按钮必须在滚动区【之前】创建 = 位于顶部固定栏
	var i_go := hs.find("开始下一局")
	var i_scroll := hs.find("ScrollContainer.new()")
	_check(i_go > 0 and i_scroll > 0, "两者都存在")
	_check(i_go < i_scroll,
		"「开始下一局」在滚动区之前创建 = 顶部固定栏，任何分辨率都可见（go@%d < scroll@%d）"
		% [i_go, i_scroll])
	_check(hs.contains("Game.start_raid()"), "点了会开新一局")


func _test_hud_perf_metric() -> void:
	# 手机实测截图：`FPS 60  帧 25.2 ms` —— 两个数不可能同时成立。
	# 查证：HUD 那一路还在用 `Performance.TIME_PROCESS`，
	# 而它在 Android 上正是【已经被遥测判定为不可靠】并被换掉的那个。
	# （同一个坑踩了两次：先修遥测、漏了 HUD。）
	# ⚠️ HUD 的绘制代码已经搬到 `view/raid_hud.gd`（拆分 raid_scene.gd 上帝对象）。
	#    所以断言要分别看两处：**场景里不许有**（防回退），**HUD 模块里必须有**。
	#    （拆分让这条断言失效了一次 —— 这是好事：说明守卫确实盯着源码文本。）
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	var rh := FileAccess.get_file_as_string("res://view/raid_hud.gd")
	# ⚠️ 只检查**实际调用** —— 注释里会提到它（说明为什么不能用），不算违规
	_check(not rs.contains("get_monitor(Performance.TIME_PROCESS)"),
		"不得再使用 Performance.TIME_PROCESS（Android 上会与 FPS 自相矛盾）")
	_check(not rh.contains("get_monitor(Performance.TIME_PROCESS)"),
		"HUD 模块也不得使用它")
	_check(rh.contains("Tel.last_avg_ms()"), "HUD 用遥测的墙钟均值")
	_check(rh.contains("Tel.last_worst_ms()"), "HUD 用遥测的墙钟最慢值")
	# 世界绘制已抽到 view/raid_drawer.gd（拆分上帝对象）
	var dr := FileAccess.get_file_as_string("res://view/raid_drawer.gd")
	_check(not rs.contains("func _draw()"),
		"场景自己不再 _draw（世界图形全在 RaidDrawer）")
	_check(dr.contains("func _draw()") and dr.contains("scene."),
		"RaidDrawer 持有 _draw 并读场景状态")
	_check(rs.contains("drawer.queue_redraw()"),
		"场景把重绘委托给 drawer（防代码回流）")
	_check(rs.contains("drawer = RaidDrawer.new()"), "场景创建了 drawer")
	_check(rs.contains("raid_hud.refresh()"),
		"场景把 HUD 刷新委托给 RaidHud（而不是把逻辑留回场景里）")
	var tel := FileAccess.get_file_as_string("res://telemetry/telemetry.gd")
	_check(tel.contains("func last_avg_ms"), "Tel 暴露 last_avg_ms")
	_check(tel.contains("func last_worst_ms"), "Tel 暴露 last_worst_ms")
	_check(tel.contains("_last_avg_ms = wall"), "窗口关闭时记录真实墙钟均值")


# ─────────────────── 白模白模：视觉可走 == 实际可走 ───────────────────


func _test_fx_cell_coords() -> void:
	# 用户 PC 实测："我刚才这个弹夹打出的子弹，会在地图左上角有火花动画"
	# 根因：burst() 收到的是【逻辑格坐标】（如 5.5），
	#       而粒子节点在世界空间里 1 格 = 48 像素 ——
	#       于是全部堆在 (5.5, 5.5) 像素 = 地图左上角。
	# 现在 burst() 内部统一乘 CELL_PX，调用方一律传逻辑格坐标。
	var src := FileAccess.get_file_as_string("res://view/fx_pool.gd")
	_check(src.contains("p.global_position = pos * CELL_PX"),
		"burst() 把逻辑格坐标换算成像素（漏了就会全堆在左上角）")
	_check(src.contains("const CELL_PX := 48.0"), "CELL_PX 常量存在")
	# 必须与 raid_scene 的 CELL_PX 一致，否则火花位置会整体偏移
	var rs := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(rs.contains("CELL_PX") or rs.contains("LogicalGrid.CELL_PX"),
		"raid_scene 也使用同一套格->像素换算")
	_check(src.contains("burst(kind: String, pos: Vector2"),
		"burst 签名仍收 Vector2（逻辑格坐标）")


func _test_enemy_count_test_mode() -> void:
	# 真机反馈 #2：技术验证阶段敌人太多（35 个），曾要求每类型各 1 个、总数 <= 4。
	# ⚠️ 2026-10-13 需求变更：用户要求"敌人数量参考地图大小" ——
	#    默认改为 **不钳制（0）**，总数由地图主题的 enemy_density 决定
	#    （MapThemeDef.target_enemy_count / MapGenerator._apply_enemy_density）。
	#    钳制开关保留，仅供调试时临时把敌人压到极少。
	# ⚠️ 用 load() 取常量而不是引用类型名 —— 后者会在编译期把整个场景脚本拉进来，
	#    而场景脚本引用了 autoload（Sfx/Feel/Tel），会污染无关脚本的编译。
	var src: GDScript = load("res://view/raid_scene.gd")
	_check(src != null, "能载入 raid_scene.gd")
	var cap: int = int(src.get("MAX_TEST_ENEMIES"))
	_check_eq(cap, 0, "默认不钳制敌人（改由地图主题密度决定）")
	var text := FileAccess.get_file_as_string("res://view/raid_scene.gd")
	_check(text.contains("agents.size() >= MAX_TEST_ENEMIES"), "刷怪循环里仍保留钳制开关（调试用）")
	_check(text.contains("MAX_TEST_ENEMIES > 0"), "开关打开时仍走钳制分支")
	# 新契约：敌人总数按地图大小/主题密度缩放
	var mg := FileAccess.get_file_as_string("res://sim/mapgen/map_generator.gd")
	_check(mg.contains("_apply_enemy_density"), "敌人总数按地图密度缩放（MapGenerator）")
	_check(mg.contains("target_enemy_count"), "密度目标由地图主题给出（MapThemeDef）")



# ─────────────────── 真机反馈第三轮：#1 hitbox / #4#5 auto-aim / #6 尸体 / #7 藏身处 ───────────────────


func _test_settings_menu_layout() -> void:
	# 直接读源码断言"操作按钮在顶部固定栏"，而不是在滚动区底部。
	# 早先放在滚动内容末尾 —— 16 行按键说明 + 一堆开关比屏幕高，
	# 按钮被挤到折叠线以下，玩家根本看不到（真机原话："看不到继续"）。
	var sm := FileAccess.get_file_as_string("res://ui/settings_menu.gd")
	var i_bar := sm.find("顶部固定栏")
	var i_scroll := sm.find("下方滚动区")
	var i_resume := sm.find("resume_top")
	_check(i_bar > 0, "有顶部固定栏")
	_check(i_scroll > 0, "有下方滚动区")
	_check(i_resume > 0, "「继续」按钮存在")
	_check(i_resume < i_scroll,
		"「继续」在滚动区【之前】创建 = 位于固定栏，不会被内容挤出屏幕")
	_check(sm.contains("went_hideout.emit()"), "「返回藏身处」仍可用")
