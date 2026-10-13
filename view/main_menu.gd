extends Control

## 主菜单（主页）—— 游戏入口
##
## ─── 为什么要有它 ───
## 早先 `run/main_scene` 直接是 `raid_scene.tscn`：一启动就掉进战局，
## 而且**没有任何退出游戏的出口** —— 安卓上只能从系统里强杀进程。
## 现在流程是「主菜单 -> 藏身处 -> 突袭 -> 结算 -> 藏身处 ...」，
## 主菜单提供：开始游戏 / 设置 / 退出。
##
## ─── 复用 ───
## 设置菜单直接复用 `ui/settings_menu.gd`（它自带 ESC 与安卓返回键处理）。
## 这里把它的「返回藏身处」按钮隐藏 —— 主菜单没有"藏身处"可退。

var _root: VBoxContainer = null
var _settings: SettingsMenu = null
var _status: Label = null


func _ready() -> void:
	# 场景切换重置阶段计时（理由同 hideout_scene：否则第一次 mark() 会把
	# 上一个场景的停留时长算进来，产生幽灵卡顿读数）
	if Tel != null:
		Tel.reset_phases()
	RenderingServer.set_default_clear_color(UITokens.BG_DEEP)
	if Game != null:
		Game.ensure_loaded()
		Game.apply_accessibility()
	_build()


func _build() -> void:
	# Control 挂在 Viewport 根下时锚点解析不到父矩形 -> 自己钉到视口
	_fit_viewport()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_fit_viewport)

	var bg := ColorRect.new()
	bg.color = UITokens.BG_DEEP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 顶部一道极淡的强调色渐变带 —— 不用贴图就能把"这是个有设计的游戏"
	# 和"纯色背景"区分开（搜打撤题材，琥珀金=撤离/贵重）
	var band := ColorRect.new()
	band.color = UITokens.fade(UITokens.ACCENT, 0.10)
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.offset_bottom = 3.0
	add_child(band)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", int(UITokens.SP_2))
	center.add_child(_root)

	var title := _label("搜打撤", UITokens.FS_DISPLAY, UITokens.TEXT_HI)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)

	var sub := _label("2D 像素俯视 · 单机 PvE · 完全离线", UITokens.FS_CAPTION, UITokens.TEXT_MID)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(sub)

	_root.add_child(_divider())

	_root.add_child(_menu_button("开始游戏", UITokens.SUCCESS, _on_start))
	_root.add_child(_menu_button("设置", UITokens.INFO, _open_settings))
	_root.add_child(_menu_button("退出", UITokens.DANGER, _on_quit))

	_root.add_child(_spacer(int(UITokens.SP_2)))
	_status = _label("", UITokens.FS_CAPTION, UITokens.TEXT_LOW)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_status)

	# 设置菜单挂在场景根（不是 _root），这样能盖住整个屏幕
	_settings = SettingsMenu.new()
	add_child(_settings)
	# ⚠️ 必须在 add_child **之后** 调 bind_scene ——
	#    SettingsMenu 的「返回藏身处」按钮是它 _ready() 里 _build() 才创建的，
	#    在 add_child 之前调，_bottom_hb 还是 null，隐藏会落空。
	_settings.bind_scene(null, false)

	_refresh()


## 把自身尺寸钉到视口（Control 挂在非 Control 父节点下时必须手动做）
func _fit_viewport() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)


## 存档 / 战绩一览（让玩家一眼看到"我这档打到哪了"）
func _refresh() -> void:
	if _status == null:
		return
	var parts: Array[String] = []
	if Game != null:
		if Game.hideout != null:
			parts.append("资金 %d 元" % Game.hideout.wallet)
		var st: Dictionary = Game.stats
		parts.append("出击 %d · 撤离 %d · 阵亡 %d" % [
			int(st.get("raids", 0)), int(st.get("extracts", 0)), int(st.get("deaths", 0))])
		if str(Game.save_status) != "":
			parts.append(str(Game.save_status))
	_status.text = "  ·  ".join(parts)


func _label(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## 标题与按钮之间的细分隔线：中间一条短强调线，比纯空档更有"设计过"的感觉
func _divider() -> Control:
	var wrap := CenterContainer.new()
	var line := ColorRect.new()
	line.color = UITokens.fade(UITokens.ACCENT, 0.45)
	line.custom_minimum_size = Vector2(120, 1)
	wrap.add_child(line)
	return wrap


func _menu_button(text: String, accent: Color, cb: Callable) -> TouchButton:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 26.0
	b.accent = accent
	b.custom_minimum_size = Vector2(240, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.label_text = text
	b.pressed_down.connect(cb)
	return b


func _on_start() -> void:
	if Sfx != null:
		Sfx.play("ui_confirm")
	if Game != null:
		Game.save_game()
		Game.go_to_hideout()
	else:
		# Game 未就绪（极端情况）也别把玩家卡死在主菜单
		get_tree().change_scene_to_file("res://view/hideout_scene.tscn")


func _open_settings() -> void:
	if _settings != null:
		_settings.open()


func _on_quit() -> void:
	if Game != null:
		Game.save_game()
	get_tree().quit()


func _input(event: InputEvent) -> void:
	# 桌面调试：回车 / 空格开始游戏（设置菜单打开时不抢）
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_SPACE):
			if _settings != null and _settings.is_open():
				return
			_on_start()
