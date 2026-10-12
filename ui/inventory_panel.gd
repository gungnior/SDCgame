class_name InventoryPanel
extends Control

## 背包 / 搜索面板（真机反馈 #3 与 #6 共用一个框架）
##
## #3「背包框架，需要玩家可以在 ui 打开的可以互动的」
## #6「敌人死亡后会有战利品在尸体里，配合背包框架给玩家搜索」
##
## 设计（spec T-62：手机没有鼠标怎么办 —— 不依赖拖拽）：
##   · 点选 → 点放，不做拖拽
##   · 面板打开时**冻结游戏输入**（否则会和摇杆抢触点）
##   · 左栏 = 搜索目标（尸体 / 容器），右栏 = 自己的背包
##   · 每个条目是一个自绘按钮：点一下执行动作（拿走 / 使用 / 丢弃）

signal closed()
signal action(item_id: String, count: int)

const ROW_H := 34

var _title: Label
var _left_title: Label
var _right_title: Label
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _left_scroll: ScrollContainer
var _right_scroll: ScrollContainer
var _hint: Label
var _close_btn: TouchButton

var _items: Dictionary = {}          ## ItemDef 表
var _left_inv: Inventory = null      ## 搜索目标（可为 null）
var _right_inv: Inventory = null     ## 玩家背包
var _left_mode := "take"             ## take=从容器拿
var _open := false


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func is_open() -> bool:
	return _open


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.07, 0.93)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP     # 挡住下层，防止误触摇杆
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_title = _mk_label("背包", 22, Color(0.94, 0.96, 1.0))
	root.add_child(_title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var l := _mk_column("搜索目标", cols)
	_left_title = l[0]
	_left_scroll = l[1]
	_left_box = l[2]

	var r := _mk_column("我的背包", cols)
	_right_title = r[0]
	_right_scroll = r[1]
	_right_box = r[2]

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)

	_hint = _mk_label("", 13, Color(0.65, 0.72, 0.82))
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_hint)

	_close_btn = TouchButton.new()
	_close_btn.label_text = "关闭"
	_close_btn.use_hold = false
	_close_btn.base_radius = 26.0
	_close_btn.custom_minimum_size = Vector2(120, 72)
	_close_btn.accent = Color(0.85, 0.55, 0.45)
	_close_btn.pressed_down.connect(close)
	bottom.add_child(_close_btn)


func _mk_label(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


## 返回 [标题Label, ScrollContainer, VBox]
func _mk_column(title: String, parent: Node) -> Array:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)

	var t := _mk_label(title, 15, Color(0.72, 0.80, 0.92))
	box.add_child(t)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", 3)
	sc.add_child(inner)
	return [t, sc, inner]


func _clear(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()


## 打开面板。
##   container_inv / container_title：要搜索的容器（null = 纯背包）
func open(items: Dictionary, carry: Inventory, container_inv: Inventory = null,
		container_title: String = "搜索目标") -> void:
	_items = items
	_right_inv = carry
	_left_inv = container_inv
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title.text = "背包" if container_inv == null else "搜索：%s" % container_title
	_left_title.visible = container_inv != null
	_left_scroll.visible = container_inv != null
	_hint.text = "点条目执行动作 · 手机上没有拖拽（spec T-62）"
	_refresh()


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _close_btn != null:
		_close_btn.force_release()
	closed.emit()


func _refresh() -> void:
	_clear(_right_box)
	_clear(_left_box)
	if _right_inv != null:
		_right_title.text = "我的背包  %s" % _right_inv.summary()
		_add_rows(_right_box, _right_inv, false)
	if _left_inv != null:
		_left_title.text = "%s  %s" % [_title.text.replace("搜索：", ""), _left_inv.summary()]
		_add_rows(_left_box, _left_inv, true)
		if _left_inv.is_empty():
			var l := _mk_label("（空）", 13, Color(0.6, 0.64, 0.70))
			_left_box.add_child(l)


## 把背包里的堆叠汇总成一行一项（手机屏幕上重复条目很碍眼）
func _add_rows(box: VBoxContainer, inv: Inventory, is_container: bool) -> void:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for s in inv.slots:
		if s == null:
			continue
		var id := str(s["item_id"])
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + int(s["count"])
	for id in order:
		box.add_child(_make_row(id, int(counts[id]), is_container))
	if order.is_empty():
		var l := _mk_label("（空）", 13, Color(0.6, 0.64, 0.70))
		box.add_child(l)


func _make_row(item_id: String, count: int, is_container: bool) -> Control:
	var d: ItemDef = _items.get(item_id)
	var name_ := str(d.name) if d != null else item_id
	var cat := str(d.category) if d != null else "?"
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 22.0
	b.custom_minimum_size = Vector2(0, ROW_H + 20)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if is_container:
		b.label_text = "%s x%d\n拿走" % [name_, count]
		b.accent = Color(0.45, 0.80, 0.55)
		b.pressed_down.connect(func():
			action.emit(item_id, 1)
			_refresh())
	else:
		var act := "使用" if cat == "medical" or cat == "consumable" else "丢弃"
		b.label_text = "%s x%d\n%s" % [name_, count, act]
		b.accent = Color(0.45, 0.72, 0.95) if act == "使用" else Color(0.70, 0.55, 0.50)
		b.pressed_down.connect(func():
			action.emit(item_id, -1 if act == "使用" else -2)
			_refresh())
	return b
