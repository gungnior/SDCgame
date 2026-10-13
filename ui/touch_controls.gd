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
##   §7.7：**touch down 即开火**（不留抬手延迟）
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
## 静步开关（原「蹲伏」改为静步）：慢走 + 脚步不发声
signal silent_pressed()

## 输入动作名（同时在 project.godot 的 InputMap 里声明）
const A_MOVE := ["move_left", "move_right", "move_up", "move_down"]
const A_AIM := ["aim_left", "aim_right", "aim_up", "aim_down"]

# 布局（按视口比例，适配任意分辨率）
const STICK_RADIUS_RATIO := 0.115      ## 相对视口短边
const BTN_RADIUS_RATIO := 0.082
const EDGE_RATIO := 0.06

var move_stick: VirtualJoystick
var aim_stick: VirtualJoystick
var fire_btn: TouchButton
var reload_btn: TouchButton
var heal_btn: TouchButton
var bag_btn: TouchButton
var menu_btn: TouchButton
var silent_btn: TouchButton
## 地图（真机反馈 #2：需要能看撤离点位置）
var map_btn: TouchButton

var _safe := Rect2()                   ## 安全区内的可用矩形（视口坐标）

## 自动开火（spec：默认手动开火 + 强 aim assist；辅助开火做成可选无障碍项）
var auto_fire := false
var auto_fire_target_dist := 14.0


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

	# ── 瞄准摇杆：右半屏，FIXED 固定锚点（少一次"找零位"）──
	aim_stick = VirtualJoystick.new()
	aim_stick.name = "AimStick"
	aim_stick.joystick_mode = VirtualJoystick.JOYSTICK_FIXED
	aim_stick.visibility_mode = VirtualJoystick.VISIBILITY_ALWAYS
	aim_stick.joystick_size = short * STICK_RADIUS_RATIO * 2.0
	aim_stick.tip_size = short * STICK_RADIUS_RATIO * 0.72
	aim_stick.deadzone_ratio = 0.10
	aim_stick.action_left = A_AIM[0]
	aim_stick.action_right = A_AIM[1]
	aim_stick.action_up = A_AIM[2]
	aim_stick.action_down = A_AIM[3]
	aim_stick.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(aim_stick)

	# ── 动作按钮（配色全部走 UITokens 语义色，不再各处硬编码）──
	var br := short * BTN_RADIUS_RATIO
	fire_btn = _make_button("Fire", "◉", "开火", br, UITokens.DANGER, true)
	reload_btn = _make_button("Reload", "⟳", "换弹", br * 0.82, UITokens.INFO, false)
	heal_btn = _make_button("Heal", "✚", "治疗", br * 0.82, UITokens.SUCCESS, false)
	bag_btn = _make_button("Bag", "▤", "背包", br * 0.82, UITokens.ACCENT, false)
	bag_btn.pressed_down.connect(func(): bag_pressed.emit())
	# 静步（原「蹲伏」改为静步）：慢走 + 脚步不发声。放在治疗与背包之间（该处有空档）
	silent_btn = _make_button("Silent", "◌", "静步", br * 0.82, UITokens.STEALTH, false)
	silent_btn.pressed_down.connect(func(): silent_pressed.emit())
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

	# ── 三栏布局，互不重叠（实测踩过：摇杆底座压在"治疗"按钮上）──
	#   |  移动摇杆(DYNAMIC)  |   瞄准摇杆(FIXED)   | 动作按钮(沿右边缘竖排) |
	var split_move := vp.x * 0.44
	var split_aim := vp.x * 0.85
	var split_y := vp.y * 0.44

	move_stick.position = Vector2(_safe.position.x, split_y + _safe.position.y * 0.5)
	move_stick.size = Vector2(maxf(8.0, split_move - _safe.position.x),
		maxf(8.0, vp.y - split_y - _safe.position.y * 0.5))

	aim_stick.position = Vector2(split_move, split_y)
	aim_stick.size = Vector2(maxf(8.0, split_aim - split_move),
		maxf(8.0, vp.y - split_y - _safe.position.y * 0.5))

	# 动作按钮：沿右边缘竖排，中间是开火（拇指自然落点）
	var cx := b.x - br - short * 0.012
	_place(fire_btn, Vector2(cx, b.y - br - short * 0.02), br)
	_place(reload_btn, Vector2(cx, b.y - br * 2.0 - short * 0.075), br * 0.78)
	_place(heal_btn, Vector2(cx, b.y - br * 2.0 - short * 0.23), br * 0.78)
	# 静步插在"治疗"与"背包"之间：这两者中心相距约 br*1.2 + 短边*0.17，
	# 减去按钮直径后仍有约 50px 空档（640x360 下实测），不会互相压住。
	_place(silent_btn, Vector2(cx, b.y - br * 2.6 - short * 0.315), br * 0.78)
	_place(bag_btn, Vector2(cx, b.y - br * 3.2 - short * 0.40), br * 0.78)

	# 地图按钮：右上角（`menu_btn` 在 (0,0) 即左上角，两者对角线，不会互压）
	var mr := br * 0.72
	_place(map_btn, Vector2(b.x - mr - short * 0.012, _safe.position.y + mr + short * 0.012), mr)


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


func aim_vector() -> Vector2:
	return Input.get_vector(A_AIM[0], A_AIM[1], A_AIM[2], A_AIM[3])


## 瞄准摇杆的推力 0~1（aim assist 靠它判断"玩家是否在推摇杆"）
func aim_push() -> float:
	return clampf(aim_vector().length(), 0.0, 1.0)


func is_firing() -> bool:
	return fire_btn != null and fire_btn.is_down


func release_all() -> void:
	for b in [fire_btn, reload_btn, heal_btn, silent_btn, bag_btn, menu_btn, map_btn]:
		if b != null:
			b.force_release()


## 结算/暂停时整体收起（否则摇杆与按钮会透过结算遮罩露出来，很乱）
func set_controls_visible(on: bool) -> void:
	visible = on
	if not on:
		release_all()
