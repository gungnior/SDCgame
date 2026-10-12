class_name TouchButton
extends Control

## 触屏按钮 —— 自绘 Control
##
## 依据 specs/tech-stack.md T-11：
##   **按钮/摇杆底一律用 `Control` 自绘，禁用 `TouchScreenButton`**
##   理由：`TouchScreenButton` 继承 `Node2D`，不支持 anchors，无法自适应；
##        且只能触发 action，无模拟量。
##
## 依据 T-12：多点触控状态按 **finger index** 分别存 ——
##   用单一"当前触点"是双摇杆/多按钮互相干扰的根因。

signal pressed_down()
signal pressed_up()
signal tapped()

@export var label_text := ""
@export var icon_text := ""            ## 用文字当图标（避免依赖美术资源）
@export var base_radius := 34.0
@export var accent := Color(0.36, 0.72, 1.0)
@export var use_hold := true           ## true = 按住持续触发（开火）；false = 点按

var is_down := false
var _finger := -1                      ## 正在按这个按钮的手指 id（-1 = 无）
var _visual := 0.0                     ## 按下动画 0~1


func _ready() -> void:
	# 摇杆容器 / 按钮必须是 STOP，否则触不到（spec §2.2 常见 bug）
	mouse_filter = Control.MOUSE_FILTER_STOP
	# ⚠️ 只在调用方【没显式指定】时才用 base_radius 推最小尺寸。
	#    早先无条件覆盖，导致设置菜单里设的 150x76 被悄悄改成 60x60，
	#    按钮上的文字直接溢出到圆外面（截图里看得很清楚）。
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(base_radius * 2, base_radius * 2)
	set_process(true)


func _process(delta: float) -> void:
	var target := 1.0 if is_down else 0.0
	if not is_equal_approx(_visual, target):
		_visual = move_toward(_visual, target, delta * 8.0)
		queue_redraw()


func _center() -> Vector2:
	return size * 0.5


func _hit(pos: Vector2) -> bool:
	# 圆形热区（方形热区在角落会误触）
	return pos.distance_to(_center()) <= base_radius + 8.0


func _gui_input(event: InputEvent) -> void:
	# ── 触屏 ──
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if _finger < 0 and _hit(t.position):
				_finger = t.index              # T-12：按 index 记录
				_press()
				accept_event()
		else:
			# ⚠️ 只清【该 index】—— 抬起事件无脑清空会导致别的按钮同时归零
			if t.index == _finger:
				_finger = -1
				_release()
				accept_event()
		return

	# ── 桌面调试（鼠标）──
	if event is InputEventMouseButton:
		var m := event as InputEventMouseButton
		if m.button_index == MOUSE_BUTTON_LEFT:
			if m.pressed and _hit(m.position):
				_press()
				accept_event()
			elif not m.pressed and is_down:
				_release()
				accept_event()


func _press() -> void:
	if is_down:
		return
	is_down = true
	queue_redraw()
	pressed_down.emit()
	tapped.emit() if not use_hold else null


func _release() -> void:
	if not is_down:
		return
	is_down = false
	queue_redraw()
	pressed_up.emit()


## 外部强制释放（如切场景 / 失去焦点）
func force_release() -> void:
	_finger = -1
	_release()


func _draw() -> void:
	var c := _center()
	# ⚠️ 控件尺寸和"圆"未必一致：
	#    游戏内摇杆按钮是正方形（圆正好），但设置菜单里的开关是 186x68 的长方形。
	#    早先无论控件多宽都按 base_radius 画圆 + 文字放圆下方，
	#    结果文字直接溢出到圆外面（截图里看得很清楚）。
	#    现在：明显偏宽时画【圆角矩形】，并按可用宽度自动选字号、居中排版。
	var wide := size.x > size.y * 1.4
	if wide:
		_draw_wide()
		return

	var r := base_radius
	# 底：被按下时缩一点（廉价但有效的按压反馈）
	var rr := r * (1.0 - _visual * 0.08)
	draw_circle(c, rr + 3.0, Color(0.06, 0.07, 0.09, 0.72))
	draw_circle(c, rr, Color(0.16, 0.18, 0.22, 0.86).lerp(accent.darkened(0.35), _visual))
	draw_arc(c, rr, 0, TAU, 28, accent.lerp(Color.WHITE, _visual * 0.5), 2.0 + _visual)

	if icon_text != "":
		var f := ThemeDB.fallback_font
		if f != null:
			var fs := int(r * 0.95)
			var sz := f.get_string_size(icon_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(f, c - Vector2(sz.x * 0.5, -sz.y * 0.30), icon_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.97, 1.0, 0.9))
	if label_text != "":
		var f2 := ThemeDB.fallback_font
		if f2 != null:
			var fs2 := int(maxf(9.0, r * 0.34))
			var sz2 := f2.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
			draw_string(f2, c + Vector2(-sz2.x * 0.5, r * 0.72), label_text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0.72, 0.78, 0.86, 0.85))


## 宽控件（设置菜单里的开关/操作按钮）：圆角矩形 + 自动换行居中
func _draw_wide() -> void:
	var c := _center()
	var pad := 5.0
	var rc := Rect2(Vector2(pad, pad), size - Vector2(pad, pad) * 2.0)
	var rad := minf(rc.size.y * 0.34, 16.0)
	draw_rect(Rect2(rc.position + Vector2(0, 2), rc.size), Color(0.06, 0.07, 0.09, 0.72), true)
	var fill := Color(0.16, 0.18, 0.22, 0.86).lerp(accent.darkened(0.35), _visual)
	draw_rect(rc, fill, true)
	# 边框（圆角用四条线近似，够看）
	var bc := accent.lerp(Color.WHITE, _visual * 0.5)
	var w := 2.0 + _visual
	draw_line(rc.position + Vector2(rad, 0), rc.position + Vector2(rc.size.x - rad, 0), bc, w)
	draw_line(rc.position + Vector2(rad, rc.size.y), rc.position + Vector2(rc.size.x - rad, rc.size.y), bc, w)
	draw_line(rc.position + Vector2(0, rad), rc.position + Vector2(0, rc.size.y - rad), bc, w)
	draw_line(rc.position + Vector2(rc.size.x, rad), rc.position + Vector2(rc.size.x, rc.size.y - rad), bc, w)

	var f := ThemeDB.fallback_font
	if f == null:
		return
	var lines := label_text.split("\n")
	# 按可用高度选字号，保证不溢出
	var fs := int(clampf(rc.size.y / maxf(float(lines.size()), 1.0) * 0.62, 9.0, 22.0))
	var lh := f.get_height(fs) * 1.05
	var total := lh * float(lines.size())
	var y := c.y - total * 0.5 + f.get_ascent(fs) * 0.92
	for i in lines.size():
		var line := str(lines[i])
		var sz := f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var col := Color(0.95, 0.97, 1.0, 0.95) if i == 0 else Color(0.72, 0.80, 0.90, 0.92)
		draw_string(f, Vector2(c.x - sz.x * 0.5, y + lh * float(i)), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
