class_name TouchControls
extends Control

## 触屏控件组装 —— 双摇杆 + 动作按钮
##
## 依据 specs/tech-stack.md §2 与 §7.7：
##
##   T-10  **优先用 4.7 内置的原生 `VirtualJoystick`**（已验证 4.7.2 存在）。
##         能用原生就不引第三方 —— 少一个依赖与版本绑定。
##   T-11  按钮/摇杆底一律 `Control` 自绘，禁用 `TouchScreenButton`
##   T-12  多点触控状态按 **finger index** 分别存（原生摇杆内部已按触点处理）
##
##   摇杆模式选择（§7.7）：
##     · 瞄准摇杆用 **FIXED（固定锚点）** —— DYNAMIC 每次要"找零位"，是额外延迟
##     · 移动摇杆用 **DYNAMIC（浮动）** —— 移动对几毫秒延迟不敏感，浮动更舒服；
##       且 spec §2.2 要求"浮动摇杆按下瞬间才显示，避免幽灵摇杆糊屏"
##
##   §7.7：**touch down 即开火**（不留抬手延迟）——
##         ⚠️ 2026-10-13 起**此条已不适用**：开火键被删除，攻击由 AutoAim 自动完成；
##         右半屏改为「十字键位」（见 _layout()）。
##
##   §2.2：「刘海/圆角区点不到」-> `DisplayServer.get_display_safe_area()` 留安全边距

signal reload_pressed()
signal heal_pressed()
signal interact_pressed()
## 打开背包 / 搜索（真机反馈 #3 / #6）
signal bag_pressed()
## 左上角齿轮：打开设置/暂停（第三轮 #3，安卓必须能暂停）
signal menu_pressed()
## 打开战术地图（看撤离点位置）
signal map_pressed()
## 闪避（2026-10-13 用户需求：位移 1.5 倍人物身位）
signal dodge_pressed()

## 输入动作名（同时在 project.godot 的 InputMap 里声明）
const A_MOVE := ["move_left", "move_right", "move_up", "move_down"]

# 布局（按视口比例，适配任意分辨率）
const STICK_RADIUS_RATIO := 0.115      ## 相对视口短边
const BTN_RADIUS_RATIO := 0.082
const EDGE_RATIO := 0.06
## 十字键位中心相对视口短边的内缩（越大越靠屏幕中心）
const CROSS_MARGIN_RATIO := 2.9
## 十字中心到四臂的距离（相对按钮半径）
const CROSS_ARM_RATIO := 1.95

var move_stick: VirtualJoystick
var reload_btn: TouchButton
var heal_btn: TouchButton
var bag_btn: TouchButton
var menu_btn: TouchButton
## 闪避 —— **十字键位的中心**：拇指自然落点，最需要盲按的那个
var dodge_btn: TouchButton
## 地图（真机反馈 #2：需要能看撤离点位置）—— 十字的下臂
var map_btn: TouchButton

var _safe := Rect2()                   ## 安全区内的可用矩形（视口坐标）


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE    # 全屏层不吃触点（spec §2.2）
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_ensure_actions()
	_build()
	# ⚠️ `_ready()` 时本 Control 的 size 可能还是 (0,0)（CanvasLayer 布局尚未发生），
	#    直接拿 size 算位置会把摇杆摆到原点（实测踩过：瞄准摇杆跑到屏幕顶端）。
	#    所以：① 用视口尺寸兜底 ② 监听 resized 重排。
	resized.connect(_apply_safe_area)
	_apply_safe_area()


## 权威尺寸：优先用视口（CanvasLayer 下的 Control 在 _ready 时 size 常为 0）
func _vp() -> Vector2:
	if size.x > 4.0 and size.y > 4.0:
		return size
	return get_viewport_rect().size


## 用代码建 InputMap action，而不是手写 project.godot 的序列化格式 ——
## 那个格式又长又容易写错，且 action 名改了要同步两处。
static func _ensure_actions() -> void:
	# 桌面兜底：WASD / 方向键
	_add_key("move_left", KEY_A)
	_add_key("move_left", KEY_LEFT)
	_add_key("move_right", KEY_D)
	_add_key("move_right", KEY_RIGHT)
	_add_key("move_up", KEY_W)
	_add_key("move_up", KEY_UP)
	_add_key("move_down", KEY_S)
	_add_key("move_down", KEY_DOWN)
	# 瞄准：桌面用鼠标方向，这里只保证 action 存在（摇杆会写它）
	for a in ["aim_left", "aim_right", "aim_up", "aim_down"]:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.12)


static func _add_key(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.12)
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _build() -> void:
	var short := _short_side()

	# ── 移动摇杆：左半屏，DYNAMIC 浮动 ──
	move_stick = VirtualJoystick.new()
	move_stick.name = "MoveStick"
	move_stick.joystick_mode = VirtualJoystick.JOYSTICK_DYNAMIC
	move_stick.visibility_mode = VirtualJoystick.VISIBILITY_WHEN_TOUCHED
	move_stick.joystick_size = short * STICK_RADIUS_RATIO * 2.0
	move_stick.tip_size = short * STICK_RADIUS_RATIO * 0.72
	move_stick.deadzone_ratio = 0.14
	move_stick.action_left = A_MOVE[0]
	move_stick.action_right = A_MOVE[1]
	move_stick.action_up = A_MOVE[2]
	move_stick.action_down = A_MOVE[3]
	move_stick.mouse_filter = Control.MOUSE_FILTER_STOP   # 摇杆容器必须 STOP
	add_child(move_stick)

	# ── 右半屏：不再有瞄准摇杆与开火键（2026-10-13 用户需求）──
	# 攻击已改为【自动锁定 + 自动开火】（见 AutoAim / raid_sim_runner.update_auto_aim），
	# 于是右拇指只需要负责"走位之外的决策"：闪避、换弹、治疗、背包、地图 —— 排成十字。

	# ── 动作按钮（配色全部走 UITokens 语义色，不再各处硬编码）──
	var br := short * BTN_RADIUS_RATIO
	reload_btn = _make_button("Reload", "⟳", "换弹", br * 0.86, UITokens.INFO, false)
	heal_btn = _make_button("Heal", "✚", "治疗", br * 0.82, UITokens.SUCCESS, false)
	bag_btn = _make_button("Bag", "▤", "背包", br * 0.82, UITokens.ACCENT, false)
	bag_btn.pressed_down.connect(func(): bag_pressed.emit())
	# 闪避：位移 1.5 倍人物身位（BodyMetrics.DODGE_DISTANCE）。
	# 放**十字中心** —— 它是最需要盲按的一个，而且方向由左摇杆给（任意方向）。
	dodge_btn = _make_button("Dodge", "⟫", "闪避", br, UITokens.STEALTH, false)
	dodge_btn.pressed_down.connect(func(): dodge_pressed.emit())
	# 齿轮放【左上角】—— 用户明确要求。
	# 注意：它压在移动摇杆的 DYNAMIC 区域内，但它是后加入的 GUI 子节点，
	# 触摸优先给它，所以不会互相打架（摇杆只在齿轮之外的区域响应）。
	menu_btn = _make_button("Menu", "⚙", "", br * 0.72, UITokens.NEUTRAL, false)
	menu_btn.pressed_down.connect(func(): menu_pressed.emit())
	# 地图按钮（真机反馈 #2）：放在【右上角】—— 那是全屏唯一空着的地方
	# （左上角是齿轮、顶部中间是 toast、右侧竖排是动作按钮、底部是摇杆）。
	map_btn = _make_button("Map", "▦", "地图", br * 0.72, UITokens.SUCCESS, false)
	map_btn.pressed_down.connect(func(): map_pressed.emit())
	reload_btn.pressed_down.connect(func(): reload_pressed.emit())
	heal_btn.pressed_down.connect(func(): heal_pressed.emit())


func _make_button(n: String, icon: String, label: String, r: float,
		accent: Color, hold: bool) -> TouchButton:
	var b := TouchButton.new()
	b.name = n
	b.icon_text = icon
	b.label_text = label
	b.base_radius = r
	b.accent = accent
	b.use_hold = hold
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(b)
	return b


func _short_side() -> float:
	var s := _vp()
	return minf(s.x, s.y)


# ─────────────────── 安全区（刘海 / 圆角 / 手势条）───────────────────

func _apply_safe_area() -> void:
	var vp := _vp()
	_safe = Rect2(Vector2.ZERO, vp)

	var screen := DisplayServer.screen_get_size()
	var sa := DisplayServer.get_display_safe_area()
	# headless / 桌面可能返回空，那就退化成"全屏 + 固定边距"
	if screen.x <= 0 or screen.y <= 0 or sa.size.x <= 0 or sa.size.y <= 0:
		_safe = Rect2(Vector2(vp.x * EDGE_RATIO * 0.5, vp.y * EDGE_RATIO * 0.5),
			vp - Vector2(vp.x * EDGE_RATIO, vp.y * EDGE_RATIO))
	else:
		# 屏幕像素 -> 比例 -> 视口像素
		var kx := vp.x / float(screen.x)
		var ky := vp.y / float(screen.y)
		_safe = Rect2(
			Vector2(float(sa.position.x) * kx, float(sa.position.y) * ky),
			Vector2(float(sa.size.x) * kx, float(sa.size.y) * ky))

	_layout()


func _layout() -> void:
	var vp := _vp()
	var short := _short_side()
	var br := short * BTN_RADIUS_RATIO
	var b := _safe.end

	# ── 左半屏：移动摇杆（DYNAMIC 浮动）──
	# ⚠️ 它同时是**闪避方向**的来源：摇杆推哪个方向，闪避就往哪边走（任意角度）。
	#    右半屏不再有摇杆 —— 视角摇杆已按用户要求移除（瞄准全自动）。
	var split_move := vp.x * 0.5
	var split_y := vp.y * 0.44
	move_stick.position = Vector2(_safe.position.x, split_y + _safe.position.y * 0.5)
	move_stick.size = Vector2(maxf(8.0, split_move - _safe.position.x),
		maxf(8.0, vp.y - split_y - _safe.position.y * 0.5))

	# ── 右半屏：动作键摆成「十字」（2026-10-13 用户需求）──
	#   中心 = 闪避（最常按、要盲按），四臂 = 换弹 / 治疗 / 背包 / 地图。
	#   摆位规则纯比例：中心离右下角 CROSS_MARGIN_RATIO 个按钮半径，
	#                 四臂离中心 CROSS_ARM_RATIO 个按钮半径 —— 适配任意分辨率。
	var mr := br * 0.72
	var arm := br * CROSS_ARM_RATIO
	var center := Vector2(b.x - br * CROSS_MARGIN_RATIO, b.y - br * CROSS_MARGIN_RATIO)
	_place(dodge_btn, center, br)
	_place(reload_btn, center + Vector2(0, -arm), br * 0.86)
	_place(heal_btn, center + Vector2(-arm, 0), br * 0.86)
	_place(bag_btn, center + Vector2(arm, 0), br * 0.86)
	_place(map_btn, center + Vector2(0, arm), mr)

func _place(btn: TouchButton, center: Vector2, r: float) -> void:
	btn.position = center - Vector2(r, r)
	btn.size = Vector2(r * 2, r * 2)


func _draw() -> void:
	# 摇杆底座由引擎的 VirtualJoystick 自己画（T-10 用原生），
	# 这里【不重复画】—— 之前画过一次，结果叠出两个圆。
	pass


func short_radius() -> float:
	return _short_side() * STICK_RADIUS_RATIO


# ─────────────────── 对外读取 ───────────────────

func move_vector() -> Vector2:
	# 摇杆把结果写进 InputMap action；这里读回模拟量
	var v := Input.get_vector(A_MOVE[0], A_MOVE[1], A_MOVE[2], A_MOVE[3])
	# 键盘（桌面）兜底
	if v == Vector2.ZERO:
		v = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	return v


## ⚠️ 2026-10-13：`aim_vector()` / `aim_push()` / `is_firing()` **已删除** ——
## 视角摇杆与开火键按用户要求移除，攻击改为自动锁定 + 自动开火。
## 场景侧不再读这三个接口（s07 有一条防回流断言盯着它们不许回来）。


func release_all() -> void:
	for b in [dodge_btn, reload_btn, heal_btn, bag_btn, menu_btn, map_btn]:
		if b != null:
			b.force_release()


## 结算/暂停时整体收起（否则摇杆与按钮会透过结算遮罩露出来，很乱）
func set_controls_visible(on: bool) -> void:
	visible = on
	if not on:
		release_all()
