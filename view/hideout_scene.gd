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

var _root: VBoxContainer
var _wallet_label: Label
var _stash_label: Label
var _status: Label
## 商人面板（④ 商人系统）—— 商人逻辑早就有，缺的是入口
var merchant_panel: MerchantPanel = null


func _ready() -> void:
	# ⚠️ 场景切换必须重置阶段计时 —— 否则新场景第一次 mark() 会把
	#    在【上一个场景】待了多久 算成某一阶段的耗时
	#    （实测出现过 draw_end=4917ms 的幽灵卡顿，其实只是在藏身处待了 4.7 秒）
	if Tel != null:
		Tel.reset_phases()
	RenderingServer.set_default_clear_color(Color(0.07, 0.08, 0.10))
	# _build 里会调 _fit_viewport 把自身尺寸钉到视口
	if Game != null:
		Game.ensure_loaded()
		Game.apply_accessibility()
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.10)
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
	bar.add_theme_constant_override("margin_left", 20)
	bar.add_theme_constant_override("margin_top", 12)
	bar.add_theme_constant_override("margin_right", 20)
	bar.add_theme_constant_override("margin_bottom", 6)
	col.add_child(bar)

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 12)
	bar.add_child(bar_row)

	var head := VBoxContainer.new()
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override("separation", 0)
	bar_row.add_child(head)
	head.add_child(_title("藏身处", 26, Color(0.94, 0.96, 1.0)))
	_wallet_label = _title("", 16, Color(0.95, 0.82, 0.40))
	head.add_child(_wallet_label)

	# 开始下一局 —— 真机反馈："在返回藏身处后加入 开始下一局的 ui"
	var mer := TouchButton.new()
	mer.label_text = "商人"
	mer.icon_text = "¥"
	mer.use_hold = false
	mer.accent = Color(0.85, 0.72, 0.38)
	mer.base_radius = 34.0
	mer.custom_minimum_size = Vector2(156, 96)   # 必须 > 96*1.4=134.4 才会走圆角矩形绘制
	mer.pressed_down.connect(_open_merchant)
	bar_row.add_child(mer)

	var go := TouchButton.new()
	go.label_text = "开始下一局"
	go.icon_text = "▶"
	go.use_hold = false
	go.accent = Color(0.42, 0.82, 0.52)
	go.base_radius = 44.0
	go.custom_minimum_size = Vector2(250, 96)
	go.pressed_down.connect(_on_go)
	bar_row.add_child(go)

	# ② 下方滚动区：仓库 / 升级 / 开关
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	sc.add_child(margin)

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 8)
	margin.add_child(_root)

	_root.add_child(_title("仓库", 16, Color(0.70, 0.78, 0.90)))
	_stash_label = _title("", 14, Color(0.80, 0.84, 0.90))
	_stash_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stash_label.custom_minimum_size = Vector2(0, 90)
	_root.add_child(_stash_label)

	_root.add_child(_title("升级", 16, Color(0.70, 0.78, 0.90)))
	var ups := HBoxContainer.new()
	ups.add_theme_constant_override("separation", 10)
	_root.add_child(ups)
	for id in Hideout.UPGRADES.keys():
		ups.add_child(_make_upgrade_button(id))

	_root.add_child(_title("辅助瞄准", 16, Color(0.70, 0.78, 0.90)))
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 10)
	_root.add_child(toggles)
	toggles.add_child(_make_toggle("自动射击", "auto_fire"))
	toggles.add_child(_make_toggle("自动瞄准", "auto_aim"))
	toggles.add_child(_make_toggle("视野跟随", "vision_follows_lock"))

	_status = _title("", 14, Color(0.55, 0.90, 0.62))
	_root.add_child(_status)

	# 商人面板：挂在场景根上（不是 _root），这样它能盖住整个屏幕
	merchant_panel = MerchantPanel.new()
	merchant_panel.changed.connect(_refresh)
	merchant_panel.closed.connect(func(): if Game != null: Game.save_game())
	add_child(merchant_panel)


## 把自身尺寸钉到视口（Control 挂在非 Control 父节点下时必须手动做）
func _fit_viewport() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)


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
	b.accent = Color(0.42, 0.72, 0.95) if cost >= 0 and h.wallet >= cost else Color(0.45, 0.48, 0.55)


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
	b.accent = Color(0.42, 0.82, 0.52) if on else Color(0.45, 0.48, 0.55)


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
	for e in entries.slice(0, 10):
		lines.append("  %s x%d" % [e[3], e[1]])
	if entries.size() > 10:
		lines.append("  …还有 %d 种" % (entries.size() - 10))
	_stash_label.text = "\n".join(lines)
	_status.text = ""


## 打开商人（买卖）
func _open_merchant() -> void:
	if merchant_panel == null or Game == null or Game.hideout == null:
		return
	merchant_panel.open(Game.hideout, Game.reg.items)
	if Sfx != null:
		Sfx.play("ui_open")


func _on_upgrade(id: String) -> void:
	var h := _hideout()
	if h == null:
		return
	var err := h.buy_upgrade(id)
	_status.text = "升级成功" if err == "" else err
	if Sfx != null:
		Sfx.play("ui_confirm" if err == "" else "ui_deny")
	# 刷新所有升级按钮（价格会变）
	for c in _root.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				if b is TouchButton and b.has_meta("upgrade_id"):
					_refresh_upgrade_button(b, str(b.get_meta("upgrade_id")))
	if Game != null:
		Game.save_game()      # 改动即存档：在藏身处被杀进程也不丢进度
	_refresh()


func _on_toggle(key: String) -> void:
	if Game == null:
		return
	Game.set(key, not bool(Game.get(key)))
	Game.save_game()
	if Sfx != null:
		Sfx.play("ui_click")
	for c in _root.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				if b is TouchButton and b.has_meta("setting_key"):
					var k := str(b.get_meta("setting_key"))
					_refresh_toggle_button(b, k, _label_for_key(k))
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


func _input(event: InputEvent) -> void:
	# 桌面调试：回车/空格出发
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_SPACE):
			_on_go()
