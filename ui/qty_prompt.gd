class_name QtyPrompt
extends Control

## 自定义拾取数量弹窗（2026-10-13 真机反馈 #5）
##
## 用户原话："搜刮的时候加入对堆叠物品的快速拾取，要求能自定义拾取数量"。
##
## 早先容器里的每一行**只有一个动作**：点一下拿 1 个。
## 面对"60 发子弹 / 12 个绷带"这种堆叠，玩家得点 60 次 ——
## 这在触屏上等于不可用。
##
## 本弹窗提供三档快捷 + 精调：
##   · 「1」「一半」「全部」—— 覆盖绝大多数场景（快速拾取）
##   · 「−」「+」—— 精调任意数量（自定义）
##
## ── 设计纪律 ──
##   · `_ensure_built()` 幂等（测试里 add_child 不触发 _ready）
##   · 数量夹取走 `Inventory.clamp_amount()`（sim 层，有单测）——
##     界面算出来的数必须和真正搬走的数是同一套规则
##   · 面板不认识战斗：只发 `confirmed(count)`，谁去搬由调用方决定

signal confirmed(count: int)
signal cancelled()

const CARD_W := 400.0
const CARD_H := 268.0

var _title: Label = null
var _sub: Label = null
var _value: Label = null
var _minus: TouchButton = null
var _plus: TouchButton = null
var _ok: TouchButton = null
var _cancel: TouchButton = null

var _max := 1
var _cur := 1
var _open := false
var _built := false


# ─────────────────── 纯helper（可单测） ───────────────────

## 「一半」的取法：至少 1，且不超过上限。
static func half_of(max_n: int) -> int:
	return clampi(max_n / 2, 1, maxi(1, max_n))


# ─────────────────── 生命周期 ───────────────────

func _ready() -> void:
	_ensure_built()


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	visible = false
	_fit_viewport()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_fit_viewport)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func is_open() -> bool:
	return _open


func current() -> int:
	return _cur


func _fit_viewport() -> void:
	# ⚠️⚠️ 同 ui/map_panel.gd：`size = vp` 不能省 —— 只设锚点会得到 0×0，
	#     卡片就会以"父尺寸 0"去居中，整块跑到屏幕左上角外面去
	#     （探针 `_tmp_r8_probe` 实测：卡片中点落在 (-200,-134)）。
	var vp := Vector2.ZERO
	if is_inside_tree():
		vp = get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _mk(text: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


func _mk_btn(text: String, accent: Color, cb: Callable) -> TouchButton:
	var b := TouchButton.new()
	b.label_text = text
	b.use_hold = false
	b.base_radius = 24.0
	b.custom_minimum_size = Vector2(0, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.accent = accent
	b.pressed_down.connect(cb)
	return b


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	# ⚠️ 卡片用【显式 offset】钉成固定尺寸居中，而不是靠 custom_minimum_size ——
	#    后者要等一次布局才生效，测试里（没进树）会得到一张零尺寸的卡。
	var card := PanelContainer.new()
	card.anchor_left = 0.5
	card.anchor_top = 0.5
	card.anchor_right = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -CARD_W * 0.5
	card.offset_top = -CARD_H * 0.5
	card.offset_right = CARD_W * 0.5
	card.offset_bottom = CARD_H * 0.5
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	# ⚠️ 必须显式给一个背景 StyleBox —— 默认 PanelContainer 的主题面板几乎是透明的，
	#    卡片会"糊"在背包面板上（探针截图里能看到后面的「武器/护甲」透出来，
	#    玩家分不清哪一层是可以点的）。
	var sb := StyleBoxFlat.new()
	sb.bg_color = UITokens.fade(UITokens.BG_PANEL, 0.99)
	sb.border_color = UITokens.fade(UITokens.INFO, 0.92)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14.0)
	card.add_theme_stylebox_override("panel", sb)
	add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	card.add_child(col)

	_title = _mk("拿取物品", 19, UITokens.TEXT_HI)
	col.add_child(_title)

	_sub = _mk("", 13, UITokens.TEXT)
	col.add_child(_sub)

	# ── 精调行：− [N] + ──
	var step := HBoxContainer.new()
	step.add_theme_constant_override("separation", 8)
	col.add_child(step)
	_minus = _mk_btn("−", UITokens.TEXT, _on_minus)
	# ⚠️ 宽度必须 > 高度*1.4，否则 TouchButton 会走**圆形**绘制分支 ——
	#    圆形分支把文字画在圆下方，± 这种单字符会变成圆心一小点（探针截图里很难看）。
	_minus.custom_minimum_size = Vector2(96, 58)
	_minus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	step.add_child(_minus)
	_value = _mk("1", 26, Color(1.0, 0.92, 0.55))
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step.add_child(_value)
	_plus = _mk_btn("+", UITokens.TEXT, _on_plus)
	_plus.custom_minimum_size = Vector2(96, 58)
	_plus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	step.add_child(_plus)

	# ── 快捷行：1 / 一半 / 全部 ──
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 8)
	col.add_child(quick)
	quick.add_child(_mk_btn("1", UITokens.INFO, func(): _set_cur(1)))
	quick.add_child(_mk_btn("一半", UITokens.STEALTH, func(): _set_cur(half_of(_max))))
	quick.add_child(_mk_btn("全部", UITokens.SUCCESS, func(): _set_cur(_max)))

	# ── 底部：取消 / 确定 ──
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	col.add_child(bottom)
	_cancel = _mk_btn("取消", UITokens.DANGER, close)
	bottom.add_child(_cancel)
	_ok = _mk_btn("确定", UITokens.SUCCESS, _on_ok)
	bottom.add_child(_ok)


# ─────────────────── 对外 ───────────────────

## item_name：给玩家看的名字；max_count：源里实际有多少（上限）。
## fit_hint：可选的"背包还能放 N 个"提示（<=0 不显示）。
func open(item_name: String, max_count: int, fit_hint: int = -1) -> void:
	_ensure_built()
	_max = maxi(1, max_count)
	_cur = 1
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title.text = "拿取 %s" % item_name
	var sub := "这一堆最多 %d 个" % max_count
	if fit_hint >= 0:
		sub += " · 背包还能放 %d 个" % fit_hint
	_sub.text = sub
	_sync_value()
	queue_redraw()


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _ok != null:
		_ok.force_release()
	if _cancel != null:
		_cancel.force_release()
	cancelled.emit()


func _on_minus() -> void:
	_set_cur(_cur - 1)


func _on_plus() -> void:
	_set_cur(_cur + 1)


func _set_cur(v: int) -> void:
	# 数量夹取用 sim 层那一份规则（want<=0 = 全部）
	_cur = maxi(1, Inventory.clamp_amount(v, _max))
	_sync_value()


func _sync_value() -> void:
	if _value != null:
		_value.text = "%d / %d" % [_cur, _max]
	if _minus != null:
		_minus.accent = UITokens.TEXT if _cur > 1 else UITokens.BORDER
	if _plus != null:
		_plus.accent = UITokens.TEXT if _cur < _max else UITokens.BORDER


func _on_ok() -> void:
	var n := _cur
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	confirmed.emit(n)
