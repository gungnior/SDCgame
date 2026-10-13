class_name SettingsMenu
extends Control

## 设置 / 暂停菜单（真机反馈第三轮 #3）
##
## 用户原话："f1 到 f4 没有说明 应该加入 esc 设置菜单
##            （安卓需要为加入左上角为齿轮 ui 和安卓返回指令暂停游戏，出现设置选项）
##            在里面可以设置。"
##
## 所以这里同时承担两件事：
##   · PC：ESC 打开/关闭
##   · 安卓：左上角齿轮按钮打开；系统返回键（ui_cancel）打开
##   · 内嵌**完整按键说明**（F1~F4 到底干什么，之前完全没写）
##
## 打开时冻结游戏逻辑（Game.paused = true），关闭时恢复。
## ⚠️【不使用 get_tree().paused】—— 它会连输入一起门控，导致菜单点不动。

signal resumed()
signal went_hideout()

## 暂停时仍然响应输入（否则菜单自己也会被暂停冻住）
## 见 _ready 里的 process_mode 设置。

var _root: VBoxContainer
var _open := false
var _allow_hideout := true


func is_open() -> bool:
	return _open


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	# ⚠️⚠️【本会话第三次栽在这里】⚠️⚠️
	#   `Control` 直接挂在 `CanvasLayer` 下时，`set_anchors_preset(FULL_RECT)`
	#   **解析不到父矩形** -> 自身 size 停在 (0,0) ->
	#   子节点（背景 ColorRect / ScrollContainer）全部塌成 0 尺寸 ->
	#   ScrollContainer 把内容整段裁掉。
	#   实测表现：按 ESC 后【只看得到顶部两个小圆按钮，背景和所有开关都不渲染】。
	#   （前两次是虚拟摇杆和结算面板，症状不同、根因相同。）
	#   修法：自己跟 viewport 尺寸同步。
	_fit_viewport()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_fit_viewport)
	_build()
	_force_always(self)


## 把自身尺寸钉到视口上（Control 挂在非 Control 父节点下时必须手动做）
func _fit_viewport() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		# 极端情况：viewport 还没准备好 -> 退回项目设定的视口尺寸
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITokens.fade(UITokens.BG_DEEP, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# ── 纵向两段：顶部固定操作栏 + 下方滚动设置区 ──
	#
	# ⚠️ 真机反馈："esc 了看不到继续"。
	#    早先把「继续 / 返回藏身处」放在滚动内容的**最底部**，
	#    而按键说明有 16 行、加上一堆开关，内容比 720px 高得多 ——
	#    按钮被挤到折叠线以下，玩家根本看不见。
	#    现在把操作按钮放进**顶部固定栏**，无论内容多长都一定可见。
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	# ① 顶部固定栏（不滚动）
	var bar := MarginContainer.new()
	bar.add_theme_constant_override("margin_left", 28)
	bar.add_theme_constant_override("margin_top", 14)
	bar.add_theme_constant_override("margin_right", 28)
	bar.add_theme_constant_override("margin_bottom", 6)
	col.add_child(bar)

	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 12)
	bar.add_child(bar_row)

	var title := _label("设置", 26, UITokens.TEXT_HI)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_row.add_child(title)

	var resume_top := TouchButton.new()
	resume_top.label_text = "继续"
	resume_top.use_hold = false
	resume_top.base_radius = 30.0
	resume_top.custom_minimum_size = Vector2(150, 76)
	resume_top.accent = UITokens.SUCCESS
	resume_top.pressed_down.connect(close)
	bar_row.add_child(resume_top)

	var hb_top := TouchButton.new()
	hb_top.label_text = "返回藏身处"
	hb_top.use_hold = false
	hb_top.base_radius = 30.0
	hb_top.custom_minimum_size = Vector2(170, 76)
	hb_top.accent = UITokens.ACCENT
	hb_top.pressed_down.connect(func():
		close()
		went_hideout.emit())
	bar_row.add_child(hb_top)
	_bottom_hb = hb_top

	# ② 下方滚动区
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 18)
	sc.add_child(margin)

	_root = VBoxContainer.new()
	_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_theme_constant_override("separation", 6)
	margin.add_child(_root)

	# ── 玩法辅助 ──
	_root.add_child(_label("辅助瞄准", 15, UITokens.TEXT))
	var assist := HBoxContainer.new()
	assist.add_theme_constant_override("separation", 8)
	_root.add_child(assist)
	assist.add_child(_toggle("自动射击", "auto_fire"))
	assist.add_child(_toggle("自动瞄准", "auto_aim"))
	assist.add_child(_toggle("视野跟随", "vision_follows_lock"))

	# ── 无障碍（spec §7.3 第 4 条）──
	_root.add_child(_label("画面与手感", 15, UITokens.TEXT))
	var acc := HBoxContainer.new()
	acc.add_theme_constant_override("separation", 8)
	_root.add_child(acc)
	acc.add_child(_toggle("屏幕震动", "shake_enabled"))
	acc.add_child(_toggle("命中顿帧", "hitstop_enabled"))
	acc.add_child(_toggle("受击闪白", "flash_enabled"))
	var acc2 := HBoxContainer.new()
	acc2.add_theme_constant_override("separation", 8)
	_root.add_child(acc2)
	acc2.add_child(_toggle("音效", "sfx_enabled"))
	acc2.add_child(_toggle("调试视图", "debug_view"))
	acc2.add_child(_toggle("白模地图", "whitebox"))

	# ── 按键说明（用户明确要求："f1 到 f4 没有说明"）──
	_root.add_child(_label("按键", 15, UITokens.TEXT))
	var keys := _label(
		"  WASD / 方向键    移动\n"
		+ "  鼠标移动          瞄准\n"
		+ "  J 或 空格         开火（按住连发）\n"
		+ "  R                 装弹\n"
		+ "  T                 治疗\n"
		+ "  B                 背包 / 搜索尸体\n"
		+ "  K                 重开一局\n"
		+ "  ESC               打开 / 关闭本菜单\n"
		+ "  Tab               调试视图切换\n"
		+ "  F5                白模 <-> 美术地图\n"
		+ "  F1                关/开 屏幕震动\n"
		+ "  F2                关/开 命中顿帧\n"
		+ "  F3                关/开 受击闪白\n"
		+ "  F4                特效强度 减半/全开\n"
		+ "  M                 静音\n"
		+ "  安卓返回键         暂停（打开本菜单）",
		13, UITokens.TEXT)
	_root.add_child(keys)

	# 结尾的「继续 / 返回藏身处」已经移到【顶部固定栏】了（见 _build 开头）。
	# 这里不再重复放 —— 早先放这里就是因为它们被挤到折叠线以下，
	# 玩家按 ESC 后完全看不到（真机反馈："esc 了看不到继续"）。
	_root.add_child(_label(
		"（按 ESC 或点右上角「继续」关闭本菜单）",
		12, UITokens.TEXT_LOW))


var _bottom_hb: TouchButton = null


func _label(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


func _toggle(label: String, key: String) -> TouchButton:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 26.0
	b.custom_minimum_size = Vector2(108, 68)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("setting_key", key)
	b.set_meta("setting_label", label)
	b.pressed_down.connect(_on_toggle.bind(b, key, label))
	_paint(b, key, label)
	return b


func _paint(b: TouchButton, key: String, label: String) -> void:
	var on := _read_setting(key)
	b.label_text = "%s\n%s" % [label, "开" if on else "关"]
	b.accent = UITokens.SUCCESS if on else UITokens.TEXT_LOW


## 读设置。
## ⚠️ 不能叫 `_get` —— 那是 Object 的内置虚函数，签名是 `_get(StringName) -> Variant`，
##    重名会直接编译失败（实测踩过）。
## 四个"开关"类设置里，前三个走 Game（跨场景），后三个直接作用在 Feel/Sfx/场景上。
func _read_setting(key: String) -> bool:
	match key:
		"shake_enabled": return Feel.shake_enabled if Feel != null else true
		"hitstop_enabled": return Feel.hitstop_enabled if Feel != null else true
		"flash_enabled": return Feel.flash_enabled if Feel != null else true
		"sfx_enabled": return Sfx.enabled if Sfx != null else true
		"debug_view": return _ext.get("debug_mode") != 0 if _ext else false
		"whitebox": return _ext.get("render_mode") == 0 if _ext else true
	if Game != null:
		return bool(Game.get(key))
	return false


func _on_toggle(b: TouchButton, key: String, label: String) -> void:
	match key:
		"shake_enabled":
			if Feel != null: Feel.shake_enabled = not Feel.shake_enabled
		"hitstop_enabled":
			if Feel != null:
				Feel.hitstop_enabled = not Feel.hitstop_enabled
				if not Feel.hitstop_enabled:
					Engine.time_scale = 1.0
		"flash_enabled":
			if Feel != null: Feel.flash_enabled = not Feel.flash_enabled
		"sfx_enabled":
			if Sfx != null: Sfx.enabled = not Sfx.enabled
		"debug_view":
			if _ext and _ext.has_method("toggle_debug"):
				_ext.toggle_debug()
		"whitebox":
			if _ext and _ext.has_method("toggle_whitebox"):
				_ext.toggle_whitebox()
		_:
			if Game != null:
				Game.set(key, not bool(Game.get(key)))
	if Sfx != null:
		Sfx.play("ui_click")
	_paint(b, key, label)


## 外部场景（raid_scene）—— 用于转发"调试视图/白模"这类场景内开关
var _ext: Node = null


func bind_scene(node: Node, allow_hideout: bool = true) -> void:
	_ext = node
	_allow_hideout = allow_hideout
	if _bottom_hb != null:
		_bottom_hb.visible = allow_hideout


func open() -> void:
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _ext != null:
		_ext.set("game_paused", true)
	# ⚠️【不再使用 get_tree().paused】。
	#
	# 用户 PC 实测按 ESC 后卡死：日志显示 hp=None 持续 28 秒，
	# 但 Tel(PROCESS_MODE_ALWAYS) 仍在记录 —— 树被暂停了，而且 ESC 也关不掉。
	# 原因是 get_tree().paused 同时门控【逻辑推进】和【节点能否收输入】，
	# 想只冻结前者就必须精确控制整棵子树的 process_mode，
	# 漏一处就变成"菜单看得见、点不动"。
	#
	# 现在改成纯逻辑冻结：把场景的 game_paused 置位，
	# 由场景自己在 _process 里跳过游戏逻辑。
	# HUD / 绘制 / 输入 / 按钮一律照常 -> 不可能再"点不动"。
	# 也不再碰 Engine.time_scale，避免和 hitstop 打架。
	if Game != null:
		Game.paused = true
	# 刷新所有开关的显示（可能被 F1~F4 改过）
	for c in _root.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				if b is TouchButton and b.has_meta("setting_key"):
					_paint(b, str(b.get_meta("setting_key")), str(b.get_meta("setting_label")))
	if Sfx != null:
		Sfx.play("ui_open")


## 递归把整棵子树的 process_mode 设成 ALWAYS —— 暂停时仍能收输入/动画
func _force_always(n: Node) -> void:
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	for ch in n.get_children():
		_force_always(ch)


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Game != null:
		Game.paused = false
	if _ext != null:
		_ext.set("game_paused", false)
	if Sfx != null:
		Sfx.play("ui_click")
	resumed.emit()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func _input(event: InputEvent) -> void:
	# ESC / 安卓返回键都走 ui_cancel
	if event.is_action_pressed("ui_cancel"):
		toggle()
		get_viewport().set_input_as_handled()


## 安卓系统返回键。
## ⚠️ 只靠 ui_cancel 不够稳 —— 某些 ROM/Godot 版本下返回键走的是
##    NOTIFICATION_WM_GO_BACK_REQUEST 而不是 ui_cancel。
##    用户明确要求"安卓返回指令暂停游戏，出现设置选项"，所以两条路都接上。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		toggle()
