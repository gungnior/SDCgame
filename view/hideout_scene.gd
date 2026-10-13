extends Control

## 藏身处场景（真机反馈 #7）
##
## 用户原话："完善藏身处系统。比如死亡后点击的藏身处，玩家可以真正的返回，
##            而不是重启战局。"
##
## 所以它是一个**独立场景**，不是突袭场景里的一个弹窗：
##   突袭（死亡/撤离）-> 结算界面点「回藏身处」-> 切到这个场景
##   这个场景点「出发」-> 切回突袭场景（新地图、新种子）
##
## 持久状态放在 Game（autoload）里，场景切换不会丢。
##
## 布局刻意用最简单的纵向列表 —— 技术验证阶段先要"能用"。

const CELL := 4.0

## ── 顶部固定栏的尺寸常量 ──
#
# ⚠️ 为什么写成常量还带个自检函数：
#   这一栏是"横向"排的（标题/资金 占 EXPAND，按钮占固定宽）。
#   挤不下时**不会报错**，只会把左侧标题资金压成一条缝 ——
#   和早先「出发」被滚动挤出屏幕是同一类问题，只是方向相反。
#   加第四个按钮的人不会知道自己搞坏了，除非有个东西会喊。
#
# ⚠️ 2026-10-13 实测教训：加「主菜单」后 4 个按钮的**最小宽度之和**
#   超过了视口 —— 表现不只是"开始下一局"被挤出右边，
#   连【下方滚动区】都被撑宽到 714px，右边缘被裁掉（第 4 个选图按钮看不见）。
#   根因：bar 的 min 宽度 > 视口时，外层 VBox 会被强制撑到 min 宽。
#   所以 bar_fits() **必须把标题/资金的最小宽度也算进去**（BAR_HEAD_MIN_W）。
#
# ⚠️ 按钮高度取 64：`TouchButton` 只在 `size.x > size.y * 1.4` 时才画圆角矩形，
#   否则退回圆形绘制（文字会溢出到圆外 —— 设置菜单踩过这个坑）。
#   92 / 160 对 64 都满足 1.4 倍（89.6），所以都能正常画。
const BAR_BTN_W_SIDE := 92.0     ## 配装 / 商人 / 主菜单
const BAR_BTN_W_GO := 160.0      ## 开始下一局
const BAR_BTN_H := 64.0
const BAR_SEP := 10.0            ## bar_row 的 separation
const BAR_MARGIN := 16.0         ## bar 的左右 margin
## 标题/资金那一列的最小宽度预算（实测「藏身处」+「资金 N 元」约 98px）
const BAR_HEAD_MIN_W := 120.0

## 顶部栏放不放得下（静态，便于测试直接调用；将来加按钮先跑这个）
static func bar_fits(viewport_w: float) -> bool:
	var need := BAR_BTN_W_SIDE * 3.0 + BAR_BTN_W_GO + BAR_SEP * 3.0 \
		+ BAR_MARGIN * 2.0 + BAR_HEAD_MIN_W
	return need <= viewport_w


## ── 分区标签栏（真机反馈 #7）──
#
# 用户原话："菜单交互下拉不方便"。
# 查证：藏身处早先是一条**纵向长列表** —— 仓库 / 配装 / 地图 / 升级 / 制造 /
# 修理 / 辅助瞄准 共 7 段挤在同一个 ScrollContainer 里，手机上必须一路往下拉
# 才能找到"修理台"或"选图"。功能都在，但**找不到 = 不存在**。
#
# 现在改成**分区标签**：一次只显示一个分区，点标签直接切 —— 不用再下拉。
# ⚠️ 同一类坑：标签放不下时不会报错，只会被裁到屏幕外 ——
#    所以照顶部栏的做法给一个静态自检 `tabs_fit()`，加标签先撞在这里。
const SECTION_KEYS: Array[String] = [
	"overview", "carry", "upgrade", "craft", "repair", "settings"]
const SECTION_LABEL := {
	"overview": "概览",
	"carry": "携带",
	"upgrade": "升级",
	"craft": "制造",
	"repair": "修理",
	"settings": "设置",
}
const TAB_BTN_MIN_W := 70.0     ## 每格最小宽（配合 EXPAND_FILL 均分剩余宽度）
const TAB_BTN_H := 52.0         ## > 52*1.4=72.8 才画圆角矩形，宽度通常远大于此
const TAB_SEP := 6.0

## 分区标签栏放不放得下（理由同 bar_fits）
static func tabs_fit(viewport_w: float) -> bool:
	var need := TAB_BTN_MIN_W * float(SECTION_KEYS.size()) \
		+ TAB_SEP * float(SECTION_KEYS.size() - 1) + BAR_MARGIN * 2.0
	return need <= viewport_w

var _root: VBoxContainer
var _wallet_label: Label
var _stash_label: Label
var _loadout_label: Label
var _carry_label: Label = null
var _status: Label
## 分区标签（真机反馈 #7：不再靠下拉找功能）
var _sections: Dictionary = {}          ## key -> VBoxContainer（一次只显示一个）
var _tab_buttons: Array[TouchButton] = []
var _current_section: String = "overview"
var _page_host: VBoxContainer = null
## 需要整批刷新的按钮（升级 / 开关），避免每次都扫全树
var _upgrade_buttons: Array[TouchButton] = []
var _toggle_buttons: Array[TouchButton] = []
## 选图按钮（森林 / 城区 / 军事基地 + 随机）。写入 Game.map_id。
var _map_buttons: Array[TouchButton] = []
var _map_hint: Label = null
## 修理台按钮（装备损耗系统）
var _repair_btn: TouchButton = null
## 商人面板（④ 商人系统）—— 商人逻辑早就有，缺的是入口
var merchant_panel: MerchantPanel = null
## 制造面板（C 阶段制造系统）—— CraftSystem 逻辑已实现，同样缺的是入口
var craft_panel: CraftPanel = null
## 配装面板（装备系统）—— Equipment 逻辑已实现并有单测，缺的同样是入口
var loadout_panel: LoadoutPanel = null
## 携带背包面板（真机反馈 #2：自己决定带什么进局）
var carry_panel: CarryPanel = null
## 仓库浏览面板（2026-10-14「优化藏身处仓库」：分类标签 + 排序 + 全量滚动）
var stash_panel: StashPanel = null


func _ready() -> void:
	# ⚠️ 场景切换必须重置阶段计时 —— 否则新场景第一次 mark() 会把
	#    在【上一个场景】待了多久 算成某一阶段的耗时
	#    （实测出现过 draw_end=4917ms 的幽灵卡顿，其实只是在藏身处待了 4.7 秒）
	if Tel != null:
		Tel.reset_phases()
	RenderingServer.set_default_clear_color(UITokens.BG_DEEP)
	# _build 里会调 _fit_viewport 把自身尺寸钉到视口
	if Game != null:
		Game.ensure_loaded()
		Game.apply_accessibility()
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITokens.BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ⚠️ 布局必须分两段：**顶部固定栏 + 下方滚动区**。
	#
	# 早先把"资金/仓库/升级/辅助瞄准/出发按钮"全塞进一个 VBox，
	# 而 640x360 的视口装不下（内容总高约 586px）——
	# **「出发」按钮被直接挤出屏幕**，玩家回到藏身处后找不到怎么开下一局。
	# （与设置菜单"看不到继续"是完全相同的一类问题。
	#  Control 直接挂在 CanvasLayer/Viewport 下时锚点解析不到父矩形，
	#  所以这里也补了 _fit_viewport 兜底。）
	_fit_viewport()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_fit_viewport)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	# ① 顶部固定栏：标题 + 资金 + 【开始下一局】
	var bar := MarginContainer.new()
	bar.add_theme_constant_override("margin_left", int(BAR_MARGIN))
	bar.add_theme_constant_override("margin_top", 12)
	bar.add_theme_constant_override("margin_right", int(BAR_MARGIN))
	bar.add_theme_constant_override("margin_bottom", 6)
	col.add_child(bar)

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", int(BAR_SEP))
	bar.add_child(bar_row)

	# 顶部栏挤不下时**要喊**（否则只是标题被压成一条缝，没人会发现）
	if not bar_fits(get_viewport_rect().size.x if get_viewport_rect().size.x > 0.0 else 640.0):
		push_warning("[藏身处] 顶部栏按钮放不下 640 宽视口 —— 会被挤出屏幕 + 撑宽下方滚动区，去调 BAR_BTN_W_* 常量")

	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 把预算写进布局：min 宽度与 bar_fits() 的 BAR_HEAD_MIN_W 保持一致，
	# 否则自检算出的宽度和实际排版会脱节（这次就是这么漏掉 4 按钮溢出的）。
	head.custom_minimum_size = Vector2(BAR_HEAD_MIN_W, 0)
	head.add_theme_constant_override("separation", 0)
	bar_row.add_child(head)
	head.add_child(_title("藏身处", 26, UITokens.TEXT_HI))
	_wallet_label = _title("", 16, UITokens.ACCENT)
	head.add_child(_wallet_label)

	# ── 配装（装备系统）──
	# ⚠️ 放在**顶部固定栏**：它是"出门前必做的一步"，
	#    绝不能像早先的「出发」那样被滚动挤出屏幕（真机反馈 #7 的教训）。
	#    （左侧标题/资金被挤紧的风险由 bar_fits() 自检兜住 —— 见文件头的常量说明。）
	var load_btn := TouchButton.new()
	load_btn.label_text = "配装"
	load_btn.use_hold = false
	load_btn.accent = UITokens.SUCCESS
	load_btn.base_radius = 26.0
	load_btn.custom_minimum_size = Vector2(BAR_BTN_W_SIDE, BAR_BTN_H)
	load_btn.pressed_down.connect(_open_loadout)
	bar_row.add_child(load_btn)

	# 商人 —— 逻辑早就有，这里只是入口
	var mer := TouchButton.new()
	mer.label_text = "商人"
	mer.use_hold = false
	mer.accent = UITokens.ACCENT
	mer.base_radius = 26.0
	mer.custom_minimum_size = Vector2(BAR_BTN_W_SIDE, BAR_BTN_H)
	mer.pressed_down.connect(_open_merchant)
	bar_row.add_child(mer)

	# 主菜单 —— 提供"回主页 / 退出游戏"的出口（安卓上尤其需要，否则退不出去）
	var home := TouchButton.new()
	home.label_text = "主菜单"
	home.use_hold = false
	home.accent = UITokens.TEXT_MID
	home.base_radius = 26.0
	home.custom_minimum_size = Vector2(BAR_BTN_W_SIDE, BAR_BTN_H)
	home.pressed_down.connect(_on_home)
	bar_row.add_child(home)

	# 开始下一局 —— 真机反馈："在返回藏身处后加入 开始下一局的 ui"
	var go := TouchButton.new()
	go.label_text = "开始下一局"
	go.use_hold = false
	go.accent = UITokens.SUCCESS
	go.base_radius = 30.0
	go.custom_minimum_size = Vector2(BAR_BTN_W_GO, BAR_BTN_H)
	go.pressed_down.connect(_on_go)
	bar_row.add_child(go)

	# ② 分区标签栏（真机反馈 #7：不再靠"下拉"找功能）
	col.add_child(_build_tab_bar())

	# ③ 下方内容区：**一次只显示一个分区**（见 SECTION_KEYS 的说明）
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 8)
	sc.add_child(margin)

	_page_host = VBoxContainer.new()
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.add_theme_constant_override("separation", 8)
	margin.add_child(_page_host)
	# ⚠️ `_root` 保留指向 _page_host —— 旧代码（_on_upgrade / _on_toggle 的按钮扫描）
	#    与"内容放进滚动容器"的说法都以它为准。
	_root = _page_host

	_sections.clear()
	for key in SECTION_KEYS:
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8)
		box.visible = false
		_page_host.add_child(box)
		_sections[key] = box

	_build_overview_section()
	_build_carry_section()
	_build_upgrade_section()
	_build_craft_section()
	_build_repair_section()
	_build_settings_section()

	# ④ 底部固定状态行 —— 升级/修理的提示**永远可见**
	#    （早先它在滚动区末尾，翻到别的分区就看不到了）
	var sb := MarginContainer.new()
	sb.add_theme_constant_override("margin_left", 20)
	sb.add_theme_constant_override("margin_right", 20)
	sb.add_theme_constant_override("margin_top", 2)
	sb.add_theme_constant_override("margin_bottom", 10)
	col.add_child(sb)
	_status = _title("", 14, UITokens.SUCCESS)
	sb.add_child(_status)

	_show_section("overview", false)

	# 商人面板：挂在场景根上（不是 _root），这样它能盖住整个屏幕
	merchant_panel = MerchantPanel.new()
	merchant_panel.changed.connect(_refresh)
	merchant_panel.closed.connect(func(): if Game != null: Game.save_game())
	add_child(merchant_panel)

	# 制造面板：同样挂在场景根，能盖住整个屏幕
	craft_panel = CraftPanel.new()
	craft_panel.changed.connect(_refresh)
	craft_panel.closed.connect(func(): if Game != null: Game.save_game())
	add_child(craft_panel)

	# 配装面板：同上（它自己内嵌改枪面板）
	loadout_panel = LoadoutPanel.new()
	loadout_panel.changed.connect(_refresh)
	# ⚠️ 配装改动【必须立刻存档】：死亡掉装备的前提是"你身上这套真的被记下来了"，
	#    如果只在出发时才存，藏身处被杀进程就等于配装白做。
	loadout_panel.closed.connect(func():
		if Game != null:
			Game.save_game()
		_refresh())
	add_child(loadout_panel)

	# 携带背包面板（真机反馈 #2）
	carry_panel = CarryPanel.new()
	carry_panel.changed.connect(_refresh)
	carry_panel.closed.connect(func():
		if Game != null:
			Game.save_game()
		_refresh())
	add_child(carry_panel)

	# 仓库浏览面板（2026-10-14「优化藏身处仓库」）
	stash_panel = StashPanel.new()
	stash_panel.closed.connect(func():
		if Game != null:
			Game.save_game()
		_refresh())
	add_child(stash_panel)


# ─────────────────── 分区标签（真机反馈 #7）───────────────────

func _build_tab_bar() -> Control:
	var bar := MarginContainer.new()
	bar.add_theme_constant_override("margin_left", int(BAR_MARGIN))
	bar.add_theme_constant_override("margin_right", int(BAR_MARGIN))
	bar.add_theme_constant_override("margin_bottom", 2)
	if not tabs_fit(_viewport_w()):
		push_warning("[藏身处] 分区标签放不下本视口 —— 会被裁到屏幕外，去调 TAB_BTN_MIN_W")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(TAB_SEP))
	bar.add_child(row)
	_tab_buttons.clear()
	for key in SECTION_KEYS:
		var b := TouchButton.new()
		b.use_hold = false
		b.base_radius = 22.0
		b.custom_minimum_size = Vector2(TAB_BTN_MIN_W, TAB_BTN_H)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("section", key)
		b.pressed_down.connect(_on_tab.bind(key))
		_tab_buttons.append(b)
		row.add_child(b)
	return bar


func _viewport_w() -> float:
	var w := 0.0
	if is_inside_tree():
		w = get_viewport_rect().size.x
	return w if w > 0.0 else 640.0


func _on_tab(key: String) -> void:
	_show_section(key, true)


## 切到某个分区。play_sfx=false 用于初始化（避免进场景就响一声）。
func _show_section(key: String, play_sfx: bool = true) -> void:
	if not _sections.has(key):
		key = "overview"
	if key == _current_section and play_sfx:
		return                              # 点同一个标签不做无谓的重排
	_current_section = key
	for k in _sections:
		(_sections[k] as CanvasItem).visible = (k == key)
	_refresh_tab_buttons()
	if play_sfx:
		_status.text = ""
		if Sfx != null:
			Sfx.play("ui_click")


func _refresh_tab_buttons() -> void:
	for b in _tab_buttons:
		var k := str(b.get_meta("section"))
		var sel := k == _current_section
		b.label_text = str(SECTION_LABEL.get(k, k))
		# ⚠️ 未选中项必须【明显压暗】—— 早先未选也用 TEXT_LOW，截图里六个标签
		#    亮度几乎一样，玩家看不出自己在哪个分区（视觉寻路失效）。
		#    现在：选中 = 填充染色 + INFO 蓝边；未选只留一道暗边，靠对比说话。
		b.accent = UITokens.INFO if sel else UITokens.fade(UITokens.BORDER, 0.45)
		b.active = sel


# ─────────────────── 各分区内容 ───────────────────

## 概览：仓库清单 + 当前配装 + 选图
func _build_overview_section() -> void:
	var box: VBoxContainer = _sections["overview"]
	box.add_child(_title("仓库", 16, UITokens.TEXT))
	_stash_label = _title("", 14, UITokens.TEXT)
	_stash_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stash_label.custom_minimum_size = Vector2(0, 70)
	box.add_child(_stash_label)
	var stash_row := HBoxContainer.new()
	stash_row.add_theme_constant_override("separation", 10)
	box.add_child(stash_row)
	var open_stash_btn := TouchButton.new()
	open_stash_btn.label_text = "打开仓库"
	open_stash_btn.icon_text = "📦"
	open_stash_btn.use_hold = false
	open_stash_btn.accent = UITokens.SUCCESS
	open_stash_btn.base_radius = 30.0
	open_stash_btn.custom_minimum_size = Vector2(200, 80)
	open_stash_btn.pressed_down.connect(_open_stash)
	stash_row.add_child(open_stash_btn)

	box.add_child(_title("配装", 16, UITokens.TEXT))
	_loadout_label = _title("", 14, UITokens.SUCCESS)
	_loadout_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_loadout_label)

	# ── 地图：选择去哪张图（森林 / 城区 / 军事基地）──
	# 走 Game.map_id（跨场景持久），突袭场景的 _pick_map_theme() 会优先用它。
	# 按钮**从 Game.reg.maps 生成**（数据驱动）—— 将来加地图只改 data/maps.json。
	box.add_child(_title("地图", 16, UITokens.TEXT))
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 10)
	box.add_child(map_row)
	_map_buttons.clear()
	map_row.add_child(_make_map_button("", "随机"))
	var map_ids: Array = Game.reg.maps.keys() if (Game != null and Game.reg != null) else []
	map_ids.sort()
	for mid in map_ids:
		map_row.add_child(_make_map_button(str(mid), _map_label_of(str(mid))))
	_map_hint = _title("", 13, UITokens.TEXT_MID)
	box.add_child(_map_hint)


## 携带：这一局带什么进去（真机反馈 #2）
func _build_carry_section() -> void:
	var box: VBoxContainer = _sections["carry"]
	box.add_child(_title("携带背包", 16, UITokens.TEXT))
	_carry_label = _title("", 14, UITokens.TEXT_HI)
	_carry_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_carry_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var open_btn := TouchButton.new()
	open_btn.label_text = "打开携带背包"
	open_btn.icon_text = "🎒"
	open_btn.use_hold = false
	open_btn.accent = UITokens.SUCCESS
	open_btn.base_radius = 30.0
	open_btn.custom_minimum_size = Vector2(200, 80)
	open_btn.pressed_down.connect(_open_carry)
	row.add_child(open_btn)
	box.add_child(_title(
		"在这里决定这一局带什么进去：左栏点一下 = 带进背包，右栏点一下 = 放回仓库。\n"
		+ "撤离后剩下的会回到仓库；阵亡则连同身上的装备一起丢掉。",
		13, UITokens.TEXT_MID))


## 升级
func _build_upgrade_section() -> void:
	var box: VBoxContainer = _sections["upgrade"]
	box.add_child(_title("升级", 16, UITokens.TEXT))
	var ups := HBoxContainer.new()
	ups.add_theme_constant_override("separation", 10)
	box.add_child(ups)
	_upgrade_buttons.clear()
	for id in Hideout.UPGRADES.keys():
		var b := _make_upgrade_button(str(id))
		_upgrade_buttons.append(b)
		ups.add_child(b)


## 制造（C 阶段）
func _build_craft_section() -> void:
	var box: VBoxContainer = _sections["craft"]
	box.add_child(_title("制造", 16, UITokens.TEXT))
	var craft_row := HBoxContainer.new()
	craft_row.add_theme_constant_override("separation", 10)
	box.add_child(craft_row)
	var craft_btn := TouchButton.new()
	craft_btn.label_text = "制造台"
	craft_btn.icon_text = "⚒"
	craft_btn.use_hold = false
	craft_btn.accent = UITokens.SUCCESS
	craft_btn.base_radius = 30.0
	craft_btn.custom_minimum_size = Vector2(180, 80)
	craft_btn.pressed_down.connect(_open_craft)
	craft_row.add_child(craft_btn)


## 修理（装备损耗系统的回本入口）
func _build_repair_section() -> void:
	var box: VBoxContainer = _sections["repair"]
	box.add_child(_title("修理", 16, UITokens.TEXT))
	var repair_row := HBoxContainer.new()
	repair_row.add_theme_constant_override("separation", 10)
	box.add_child(repair_row)
	_repair_btn = TouchButton.new()
	_repair_btn.use_hold = false
	_repair_btn.base_radius = 30.0
	_repair_btn.custom_minimum_size = Vector2(200, 80)
	_repair_btn.pressed_down.connect(_on_repair)
	repair_row.add_child(_repair_btn)
	box.add_child(_title(
		"武器开火、护甲受击都会掉耐久；打坏的护甲不再提供减伤。\n"
		+ "这里一次性修满身上的装备（每缺 1 点 = %d 元）。" % Hideout.REPAIR_PRICE_PER_POINT,
		13, UITokens.TEXT_MID))


## 辅助瞄准（跨场景持久设置）
func _build_settings_section() -> void:
	var box: VBoxContainer = _sections["settings"]
	box.add_child(_title("辅助瞄准", 16, UITokens.TEXT))
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 10)
	box.add_child(toggles)
	_toggle_buttons.clear()
	for pair in [["自动射击", "auto_fire"], ["自动瞄准", "auto_aim"],
			["视野跟随", "vision_follows_lock"]]:
		var b := _make_toggle(str(pair[0]), str(pair[1]))
		_toggle_buttons.append(b)
		toggles.add_child(b)
	box.add_child(_title("辅助范围会随枪械属性变化（狙击更窄、霰弹更宽）。",
		13, UITokens.TEXT_MID))


## 把自身尺寸钉到视口（Control 挂在非 Control 父节点下时必须手动做）
func _fit_viewport() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if stash_panel != null:
		stash_panel._fit_viewport()


func _title(txt: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


func _make_upgrade_button(id: String) -> TouchButton:
	var u: Dictionary = Hideout.UPGRADES[id]
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 30.0
	b.custom_minimum_size = Vector2(112, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("upgrade_id", id)
	b.pressed_down.connect(_on_upgrade.bind(id))
	_refresh_upgrade_button(b, id)
	return b


func _refresh_upgrade_button(b: TouchButton, id: String) -> void:
	var h := _hideout()
	if h == null:
		return
	var u: Dictionary = Hideout.UPGRADES[id]
	var lv := h.level_of(id)
	var mx := h.max_level_of(id)
	var cost := h.upgrade_cost(id)
	b.label_text = "%s\nLv%d/%d\n%s" % [
		str(u["name"]), lv, mx,
		"满级" if cost < 0 else "%d 元" % cost]
	b.accent = UITokens.INFO if cost >= 0 and h.wallet >= cost else UITokens.TEXT_LOW


func _make_toggle(label: String, key: String) -> TouchButton:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 30.0
	b.custom_minimum_size = Vector2(112, 76)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("setting_key", key)
	b.pressed_down.connect(_on_toggle.bind(key))
	_refresh_toggle_button(b, key, label)
	return b


func _refresh_toggle_button(b: TouchButton, key: String, label: String) -> void:
	var on := bool(Game.get(key)) if Game != null else false
	b.label_text = "%s\n%s" % [label, "开" if on else "关"]
	b.accent = UITokens.SUCCESS if on else UITokens.TEXT_LOW


# ─────────────── 选图（森林 / 城区 / 军事基地）───────────────

## 生成一个选图按钮。id == "" 表示"随机"（按种子挑一张）。
func _make_map_button(id: String, label: String) -> TouchButton:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 26.0
	b.custom_minimum_size = Vector2(80, 64)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("map_id", id)
	b.pressed_down.connect(_on_pick_map.bind(id))
	_refresh_map_button(b, id, label)
	_map_buttons.append(b)
	return b


func _refresh_map_button(b: TouchButton, id: String, label: String) -> void:
	var cur := str(Game.map_id) if Game != null else ""
	var sel := cur == id
	b.label_text = "%s\n%s" % [label, "已选" if sel else "选择"]
	b.accent = UITokens.SUCCESS if sel else UITokens.TEXT_LOW


func _refresh_map_buttons() -> void:
	for b in _map_buttons:
		var mid := str(b.get_meta("map_id"))
		_refresh_map_button(b, mid, _map_label_of(mid))


## 地图显示名（"" -> "随机"）。查不到时回退 id（数据缺失也不崩）。
func _map_label_of(id: String) -> String:
	if id == "":
		return "随机"
	if Game != null and Game.reg != null:
		var d: MapThemeDef = Game.reg.get_map(id)
		if d != null:
			return d.name
	return id


func _on_pick_map(id: String) -> void:
	if Game == null:
		return
	Game.map_id = id
	Game.save_game()          # 改选图即存档：切场景/被杀进程都不丢
	if Sfx != null:
		Sfx.play("ui_click")
	_refresh_map_buttons()
	_refresh()


func _hideout() -> Hideout:
	return Game.hideout if Game != null else null


func _refresh() -> void:
	var h := _hideout()
	if h == null:
		_status.text = "数据未加载"
		return
	_wallet_label.text = "资金  %d 元" % h.wallet
	# 仓库清单（按价值从高到低，只列前若干项避免刷屏）
	# ⚠️ Inventory 没有公开的 items 字典，必须从 slots 汇总
	#    （实测踩过：直接访问 h.stash.items 会 Invalid access）
	var counts: Dictionary = {}
	for s in h.stash.slots:
		if s == null:
			continue
		counts[str(s["item_id"])] = int(counts.get(str(s["item_id"]), 0)) + int(s["count"])
	var entries: Array = []
	for item_id in counts:
		var n: int = int(counts[item_id])
		if n <= 0:
			continue
		var d: ItemDef = Game.reg.items.get(item_id)
		entries.append([item_id, n, 0 if d == null else d.value * n,
			0 if d == null else str(d.name)])
	entries.sort_custom(func(a, b): return a[2] > b[2])
	var lines: Array[String] = []
	lines.append("槽位 %d/%d · 共 %d 种" % [h.stash.used_slots(), h.stash.slot_count(), entries.size()])
	for e in entries.slice(0, 8):
		lines.append("  %s x%d" % [e[3], e[1]])
	if entries.size() > 8:
		lines.append("  …还有 %d 种" % (entries.size() - 8))
	_stash_label.text = "\n".join(lines)
	# ── 配装（装备系统）──
	# ⚠️ 这行是"我身上到底穿了什么"的唯一可见处 ——
	#    没有它，玩家在藏身处看不出配装是否生效（只会觉得死亡掉装备很莫名其妙）。
	#    左对齐，用中文槽位名（weapon/armor 这种 id 不该给玩家看）。
	var lp: Array[String] = []
	for slot in Equipment.SLOTS:
		var id: String = h.loadout.id_in(slot)
		var nm := h.display_name_of(id)
		# 有耐久上限的才显示 "cur/max" —— 没耐久的（如医疗品）不显示 0/0
		var mx: int = h.loadout.max_dur_of(id)
		if mx > 0:
			lp.append("%s %s %d/%d" % [str(Equipment.SLOT_LABEL.get(slot, slot)), nm,
				h.loadout.dur_of(id), mx])
		else:
			lp.append("%s %s" % [str(Equipment.SLOT_LABEL.get(slot, slot)), nm])
	_loadout_label.text = "%s\n身上 %.1f kg · 进「配装」可换装 / 改枪" % [
		" | ".join(lp), h.loadout.worn_weight()]
	# 携带背包（真机反馈 #2）
	if _carry_label != null:
		_carry_label.text = "%s\n带进这一局的东西：撤离后剩余的回到仓库，阵亡则全丢。" % \
			h.pack.summary()
	# 修理台：显示当前费用 / 是否已完好
	if _repair_btn != null:
		var rcost := h.repair_cost()
		_repair_btn.label_text = "修理台\n%s" % (
			"装备完好" if rcost <= 0 else "修满 %d 元" % rcost)
		_repair_btn.accent = UITokens.ACCENT if rcost > 0 and h.wallet >= rcost \
			else UITokens.TEXT_LOW
	# 选图提示：当前选中哪张图、多大、敌人多密
	if _map_hint != null:
		if Game != null and Game.reg != null and str(Game.map_id) != "":
			var md: MapThemeDef = Game.reg.get_map(str(Game.map_id))
			_map_hint.text = "" if md == null else "本局地图：%s（%d×%d，敌密度 %.1f）" % [
				md.name, md.map_w, md.map_h, md.enemy_density]
		else:
			_map_hint.text = "本局地图：随机（每局按种子挑一张）"
	# 按钮状态（升级 / 开关 / 选图 / 标签）—— 直接遍历持有的引用，
	# 不再扫 _root 的孩子（分区化之后 _root 的直接孩子是分区容器，不是按钮行）
	_refresh_upgrade_buttons()
	_refresh_toggle_buttons()
	_refresh_map_buttons()
	_refresh_tab_buttons()


## 刷新全部升级按钮（价格/等级会随购买变化）
func _refresh_upgrade_buttons() -> void:
	for b in _upgrade_buttons:
		if b.has_meta("upgrade_id"):
			_refresh_upgrade_button(b, str(b.get_meta("upgrade_id")))


func _refresh_toggle_buttons() -> void:
	for b in _toggle_buttons:
		if b.has_meta("setting_key"):
			var k := str(b.get_meta("setting_key"))
			_refresh_toggle_button(b, k, _label_for_key(k))


## 打开制造台（C 阶段）
func _open_craft() -> void:
	if craft_panel == null or Game == null or Game.hideout == null:
		return
	# ⚠️ 工作台解锁状态：技术验证期先**全部开放**。
	#    将来接「工作台升级」时，**只改这个 Dictionary** 即可，不用动 CraftPanel
	#    （和 CraftSystem 一样走依赖注入，面板不自己判定解锁来源）。
	var stations := {"bench": true, "forge": true, "lab": true, "kitchen": true}
	craft_panel.open(Game.reg.items, Game.reg.recipes, Game.hideout.stash, stations)
	if Sfx != null:
		Sfx.play("ui_open")


## 打开商人（买卖）
func _open_merchant() -> void:
	if merchant_panel == null or Game == null or Game.hideout == null:
		return
	merchant_panel.open(Game.hideout, Game.reg.items)
	if Sfx != null:
		Sfx.play("ui_open")


## 打开配装（装备系统）
func _open_loadout() -> void:
	if loadout_panel == null or Game == null or Game.hideout == null or Game.reg == null:
		return
	loadout_panel.open(Game.hideout, Game.reg.items, Game.reg.weapons, Game.reg.attachments)
	if Sfx != null:
		Sfx.play("ui_open")


## 打开携带背包（真机反馈 #2：自己决定带什么进局）
func _open_carry() -> void:
	if carry_panel == null or Game == null or Game.hideout == null:
		return
	carry_panel.open(Game.hideout)
	if Sfx != null:
		Sfx.play("ui_open")


## 打开仓库浏览面板（2026-10-14「优化藏身处仓库」）
func _open_stash() -> void:
	if stash_panel == null or Game == null or Game.hideout == null:
		return
	stash_panel.open(Game.hideout)
	if Sfx != null:
		Sfx.play("ui_open")


func _on_upgrade(id: String) -> void:
	var h := _hideout()
	if h == null:
		return
	var err := h.buy_upgrade(id)
	if Sfx != null:
		Sfx.play("ui_confirm" if err == "" else "ui_deny")
	_refresh()      # 里面有 _refresh_upgrade_buttons()（价格会变）
	if Game != null:
		Game.save_game()      # 改动即存档：在藏身处被杀进程也不丢进度
	_status.text = "升级成功" if err == "" else err


## 修理台：把身上装备全部修满（缺 1 点耐久 = REPAIR_PRICE_PER_POINT 元）
func _on_repair() -> void:
	var h := _hideout()
	if h == null:
		return
	var r: Dictionary = h.repair_all()
	var ok := bool(r["ok"])
	var paid := int(r["cost"])
	var msg := ""
	if ok:
		msg = "装备全部完好，无需修理" if paid <= 0 else \
			"修理完成：修回 %d 点，花费 %d 元" % [int(r["points"]), paid]
	else:
		msg = str(r["err"])
	if Sfx != null:
		Sfx.play("ui_confirm" if ok else "ui_deny")
	if Game != null:
		Game.save_game()
	_refresh()
	_status.text = msg
	# ⚠️ 提示必须在 _refresh() 之后写。
	#    早先 _refresh() 末尾会 `_status.text = ""`，把刚设好的提示清掉 ——
	#    "升级成功 / 资金不足" 于是从来没显示过（本轮一并修掉）。
	#    现在 _refresh() 不再动 _status，且状态行是**底部固定栏**，
	#    切到别的分区也还看得见。


func _on_toggle(key: String) -> void:
	if Game == null:
		return
	Game.set(key, not bool(Game.get(key)))
	Game.save_game()
	if Sfx != null:
		Sfx.play("ui_click")
	_refresh_toggle_buttons()
	_refresh()


func _label_for_key(k: String) -> String:
	match k:
		"auto_fire": return "自动射击"
		"auto_aim": return "自动瞄准"
		"vision_follows_lock": return "视野跟随"
	return k


func _on_go() -> void:
	if Sfx != null:
		Sfx.play("ui_confirm")
	if Game != null:
		Game.save_game()
		Game.start_raid()


## 回主菜单（先存档 —— 藏身处进度不能因为切场景丢）
func _on_home() -> void:
	if Sfx != null:
		Sfx.play("ui_click")
	if Game != null:
		Game.save_game()
		Game.go_to_main_menu()


func _input(event: InputEvent) -> void:
	# 桌面调试：回车/空格出发
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_SPACE):
			_on_go()
