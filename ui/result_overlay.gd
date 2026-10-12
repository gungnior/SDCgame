class_name ResultOverlay
extends Control

## 结算界面 —— 撤离成功 / 阵亡，以及【触屏可用的重开按钮】
##
## ⚠️ 为什么必须有这个（安卓真机实测反馈）：
##   早先结束时只在 HUD 上打一行「阵亡：xxx（装备已丢失）按 R 重开」。
##   **手机上没有键盘**，玩家死亡后无路可走，看起来就像「游戏卡死了」。
##   所以：任何"游戏结束"状态都必须有一个**触摸可达**的出口。

signal restart_requested()
signal hideout_requested()

var _panel: ColorRect
var _title: Label
var _body: Label
var _btn_restart: TouchButton
var _btn_hideout: TouchButton
var _shown := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# ⚠️ 不要用 set_anchors_preset(FULL_RECT) 再手动赋 size ——
	#    那会让 Godot 打印 "Nodes with non-equal opposite anchors will have
	#    their size overridden after _ready()"，而且赋的 size 会被锚点覆盖。
	#    正确做法：**零锚点（PRESET_TOP_LEFT）+ 自己钉 position/size**。
	#    （设置菜单 / MerchantPanel 都改成了这套写法。）
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	_build()
	visible = false
	_fit_viewport()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_fit_viewport)


## 把自身与遮罩都钉到视口尺寸
func _fit_viewport() -> void:
	var vp := get_viewport_rect().size
	if vp.x < 4.0 or vp.y < 4.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	_layout()


func _build() -> void:
	_panel = ColorRect.new()
	_panel.color = Color(0.03, 0.04, 0.06, 0.82)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP   # 挡住下层，防止误触摇杆
	# 零锚点：尺寸由 _layout() 手动给（避免锚点覆盖 size 的警告）
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	add_child(_panel)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 34)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_title)

	_body = Label.new()
	_body.add_theme_font_size_override("font_size", 15)
	_body.add_theme_color_override("font_color", Color(0.80, 0.84, 0.90))
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_body)

	_btn_restart = TouchButton.new()
	_btn_restart.label_text = "再来一局"
	_btn_restart.use_hold = false
	_btn_restart.accent = Color(0.42, 0.82, 0.52)
	_panel.add_child(_btn_restart)
	_btn_restart.pressed_down.connect(func(): restart_requested.emit())

	_btn_hideout = TouchButton.new()
	_btn_hideout.label_text = "回藏身处"
	_btn_hideout.use_hold = false
	_btn_hideout.accent = Color(0.85, 0.72, 0.36)
	_panel.add_child(_btn_hideout)
	_btn_hideout.pressed_down.connect(func(): hideout_requested.emit())


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_READY:
		_layout()


func _layout() -> void:
	if _panel == null:
		return
	# ⚠️ 同 touch_controls 的坑：Control 在 _ready 时 size 常为 (0,0)，
	#    直接用它算尺寸会让遮罩变成 0 大小 -> 结算界面没有深色背景、字压在游戏画面上（实测踩过）。
	var vp := size
	if vp.x < 4.0 or vp.y < 4.0:
		vp = get_viewport_rect().size
		# 这里**不能**再 `size = vp` —— 有了锚点之后赋值会被覆盖并触发警告。
		# 尺寸由 _fit_viewport() 统一负责。
	_panel.position = Vector2.ZERO
	_panel.size = vp

	var cx := vp.x * 0.5
	_title.position = Vector2(0, vp.y * 0.20)
	_title.size = Vector2(vp.x, 48)
	_body.position = Vector2(0, vp.y * 0.33)
	_body.size = Vector2(vp.x, vp.y * 0.30)
	var r := minf(vp.x, vp.y) * 0.108
	var by := vp.y * 0.78
	_place(_btn_restart, Vector2(cx - r * 1.22, by), r)
	_place(_btn_hideout, Vector2(cx + r * 1.22, by), r * 0.84)


func _place(b: TouchButton, c: Vector2, r: float) -> void:
	b.position = c - Vector2(r, r)
	b.size = Vector2(r * 2, r * 2)
	b.base_radius = r


## 显示结算。win=true 撤离成功，false 阵亡。
func show_result(win: bool, stat_lines: Array) -> void:
	_shown = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title.text = "撤离成功" if win else "阵 亡"
	_title.add_theme_color_override("font_color",
		Color(0.45, 0.92, 0.55) if win else Color(0.95, 0.38, 0.36))
	_body.text = "\n".join(stat_lines)
	_layout()
	# 把摇杆/按钮也藏起来（结算时它们没有意义，还会挡住按钮）
	if _btn_restart != null:
		_btn_restart.force_release()


func hide_result() -> void:
	_shown = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _btn_restart != null:
		_btn_restart.force_release()
	if _btn_hideout != null:
		_btn_hideout.force_release()


func is_shown() -> bool:
	return _shown
