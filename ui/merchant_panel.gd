class_name MerchantPanel
extends Control

## 商人面板（④ 商人系统）
##
## ⚠️ 为什么要写它：`Hideout.buy() / sell() / stock_price()` **早就实现了**，
##    但**没有任何 UI 入口** —— 玩家在藏身处根本点不到。
##    所以"商人系统"实际上是不可见的。
##
## 设计（沿用 spec T-62：手机没有鼠标 -> 点选点放，不做拖拽）：
##   左栏 = 商人在售（点一下买 1 个）
##   右栏 = 我的仓库（点一下卖 1 个）
##   底部显示资金 + 回收比例（受「商人关系」升级影响）

signal closed()
signal changed()          ## 买卖发生后（让藏身处刷新仓库/资金显示）

const ROW_H := 34

var _title: Label
var _wallet: Label
var _hint: Label
var _buy_box: VBoxContainer
var _sell_box: VBoxContainer
var _open := false

var _hideout: Hideout = null
var _items: Dictionary = {}

## 商人在售清单（id -> 每次购买的默认数量）
## 只卖"基础补给" —— 高级装备要玩家自己去局内搜，否则搜打撤的循环就断了。
const STOCK := {
	"ammo_pistol": 30, "ammo_rifle": 30, "ammo_shell": 12,
	"medical_tourniquet": 2, "medical_bandage": 2, "medical_painkiller": 2,
	"medical_kit": 1, "medical_antibiotic": 1,
	"consumable_energybar": 2, "consumable_water": 2, "consumable_can": 2,
	"armor_light": 1, "armor_helmet_light": 1, "backpack_tactical": 1,
}


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func is_open() -> bool:
	return _open


func _fit_viewport() -> void:
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _build() -> void:
	# ⚠️ Control 挂在 CanvasLayer/Control 下时锚点解析不到父矩形，
	#    必须自己钉尺寸（本项目已因此栽过三次）。
	_fit_viewport()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_fit_viewport)

	var bg := ColorRect.new()
	bg.color = UITokens.fade(UITokens.BG_DEEP, 0.95)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 4)
	add_child(col)

	# ── 顶部固定栏：标题 + 资金 + 关闭 ──
	var bar := MarginContainer.new()
	bar.add_theme_constant_override("margin_left", 20)
	bar.add_theme_constant_override("margin_top", 12)
	bar.add_theme_constant_override("margin_right", 20)
	bar.add_theme_constant_override("margin_bottom", 4)
	col.add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)

	_title = _mk("商人", 24, UITokens.TEXT_HI)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)
	_wallet = _mk("", 16, UITokens.ACCENT)
	_wallet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_wallet)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var close_btn := TouchButton.new()
	close_btn.label_text = "离开"
	close_btn.use_hold = false
	close_btn.base_radius = 28.0
	close_btn.custom_minimum_size = Vector2(140, 72)
	close_btn.accent = UITokens.DANGER
	close_btn.pressed_down.connect(close)
	row.add_child(close_btn)

	# ── 两栏 ──
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cols)
	_buy_box = _column(cols, "商人在售（点一下买）")
	_sell_box = _column(cols, "我的仓库（点一下卖）")

	_hint = _mk("", 13, UITokens.TEXT)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 20)
	hm.add_theme_constant_override("margin_bottom", 10)
	hm.add_child(_hint)
	col.add_child(hm)


func _mk(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


func _column(parent: Node, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	box.add_child(_mk(title, 15, UITokens.TEXT))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 3)
	sc.add_child(inner)
	return inner


func open(hideout: Hideout, items: Dictionary) -> void:
	_hideout = hideout
	_items = items
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()


func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()


func _refresh() -> void:
	if _hideout == null:
		return
	_wallet.text = "资金 %d 元" % _hideout.wallet
	_hint.text = "回收比例 %.0f%%（受「商人关系」升级影响）· 买卖都是 1 个/次，方便手指点" % (
		_hideout.sell_ratio() * 100.0)
	# ── 在售 ──
	_clear(_buy_box)
	for id in STOCK:
		var d: ItemDef = _items.get(id)
		if d == null:
			continue
		var unit := _hideout.stock_price(id)
		var n := int(STOCK[id])
		var total := unit * n
		var can := _hideout.wallet >= total
		_buy_box.add_child(_row("%s x%d" % [d.name, n], "%d 元" % total,
			UITokens.INFO if can else UITokens.BORDER,
			func(): _do_buy(id, n)))
	# ── 仓库可卖 ──
	_clear(_sell_box)
	var counts: Dictionary = {}
	var order: Array[String] = []
	for s in _hideout.stash.slots:
		if s == null:
			continue
		var id := str(s["item_id"])
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + int(s["count"])
	for id in order:
		var d2: ItemDef = _items.get(id)
		var name_ := str(d2.name) if d2 != null else id
		var unit2 := int(round(float(d2.value) * _hideout.sell_ratio())) if d2 != null else 0
		_sell_box.add_child(_row("%s x%d" % [name_, int(counts[id])],
			"卖 %d 元/个" % unit2, UITokens.ACCENT,
			func(): _do_sell(id, 1)))
	if order.is_empty():
		_sell_box.add_child(_mk("（仓库是空的）", 13, UITokens.TEXT_LOW))


func _row(label: String, price: String, accent: Color, cb: Callable) -> Control:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 22.0
	b.custom_minimum_size = Vector2(0, ROW_H + 20)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.label_text = "%s\n%s" % [label, price]
	b.accent = accent
	b.pressed_down.connect(cb)
	return b


func _do_buy(id: String, n: int) -> void:
	if _hideout == null:
		return
	var err := _hideout.buy(id, n)
	if err == "":
		if Sfx != null:
			Sfx.play("pickup")
		_hint.text = "买入成功"
	else:
		if Sfx != null:
			Sfx.play("ui_deny")
		_hint.text = err
	changed.emit()
	_refresh()


func _do_sell(id: String, n: int) -> void:
	if _hideout == null:
		return
	var got := _hideout.sell(id, n)
	if got > 0:
		if Sfx != null:
			Sfx.play("pickup")
		_hint.text = "卖出 +%d 元" % got
	else:
		if Sfx != null:
			Sfx.play("ui_deny")
		_hint.text = "卖不出去（仓库里没有这个）"
	changed.emit()
	_refresh()
