class_name StashPanel
extends Control

## 仓库浏览面板（2026-10-14「优化藏身处仓库」）
##
## 现状痛点：藏身处「概览」里仓库只显示一段「按价值降序的前 N 项」文字摘要，
## 仓库一扩容（64→80+ 槽）就完全看不清单里有什么、也按不了类找。
##
## 本面板把仓库变成**可浏览、可分类、可排序**的清单：
##   · 顶部一排在 `Hideout.group_of` 的分组里切换（全部/武器/护甲/弹药/医疗/贵重/杂物）
##   · 一行排序切换（价值/名称/数量）
##   · 可滚动列出**全部**物品（不再截断前 N 项）
##
## 只读浏览：装备/卖出/搬运的「动作」在配装 / 商人 / 携带 面板里完成，
## 这里只负责「看见并归类」（优化仓库的第一步是能看见）。
##
## 接线模式与库存/携带/配装面板一致：幂等 `_ensure_built()`，
## `open(hideout)` 后浮在场景最上层（不透明背景盖住下层），`closed` 信号由场景接刷新+存档。

signal closed

const GROUPS := ["全部", "武器", "护甲", "弹药", "医疗", "贵重", "杂物"]
const SORTS := ["价值", "名称", "数量"]

## 配色统一走 UITokens（早先这里自带一套 C_* 常量，和别处对不上）
## ⚠️ 用 `var` 不用 `const`：跨类 const 引用 / 静态函数调用都不是"常量表达式"，
##    GDScript 的 const 不接受，会直接编译失败（drag_ghost.gd 上过当）。
var C_BG := UITokens.BG_DEEP
var C_PANEL := UITokens.BG_PANEL
var C_HEAD := UITokens.TEXT
var C_ROW := UITokens.TEXT
var C_SUB := UITokens.TEXT_MID
var C_TAB_ON := UITokens.INFO
var C_TAB_OFF := UITokens.fade(UITokens.BORDER, 0.45)

var _hideout: Hideout = null
var _group: String = "全部"
var _sort: int = 0          ## 0=价值降序 1=名称升序 2=数量降序
var _built := false
var _bg: ColorRect = null
var _tab_row: HBoxContainer = null
var _sort_row: HBoxContainer = null
var _list: VBoxContainer = null
var _hint: Label = null
var _tab_buttons: Array[TouchButton] = []
var _sort_buttons: Array[TouchButton] = []


func _ensure_built() -> void:
	if _built:
		return
	_built = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bg = ColorRect.new()
	_bg.color = C_BG
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# ── 顶部：标题 + 关闭（关闭放顶行右端，避免压到下方列表）──
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	root.add_child(head)
	var title := Label.new()
	title.text = "仓库"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", C_HEAD)
	head.add_child(title)
	head.add_spacer(true)
	var close_btn := TouchButton.new()
	close_btn.label_text = "✕ 关闭"
	close_btn.use_hold = false
	close_btn.base_radius = 18.0
	close_btn.custom_minimum_size = Vector2(120, 48)
	close_btn.accent = UITokens.DANGER
	close_btn.pressed_down.connect(_on_close)
	head.add_child(close_btn)

	# ── 分类标签行 ──
	_tab_row = HBoxContainer.new()
	_tab_row.add_theme_constant_override("separation", 6)
	root.add_child(_tab_row)
	_tab_buttons.clear()
	for g in GROUPS:
		var b := TouchButton.new()
		b.label_text = g
		b.use_hold = false
		b.base_radius = 16.0
		b.custom_minimum_size = Vector2(78, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("group", g)
		b.pressed_down.connect(_on_tab.bind(g))
		_tab_row.add_child(b)
		_tab_buttons.append(b)

	# ── 排序行 ──
	_sort_row = HBoxContainer.new()
	_sort_row.add_theme_constant_override("separation", 6)
	root.add_child(_sort_row)
	var sort_cap := Label.new()
	sort_cap.text = "排序："
	sort_cap.add_theme_font_size_override("font_size", 13)
	sort_cap.add_theme_color_override("font_color", C_SUB)
	_sort_row.add_child(sort_cap)
	_sort_buttons.clear()
	for i in SORTS.size():
		var b := TouchButton.new()
		b.label_text = SORTS[i]
		b.use_hold = false
		b.base_radius = 16.0
		b.custom_minimum_size = Vector2(96, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("sort", i)
		b.pressed_down.connect(_on_sort.bind(i))
		_sort_row.add_child(b)
		_sort_buttons.append(b)

	# ── 列表（可滚动）──
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)

	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", C_SUB)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_hint)

	_refresh_tab_styles()
	_refresh_sort_styles()

	_fit_viewport()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_fit_viewport)


func open(h: Hideout) -> void:
	_ensure_built()
	_hideout = h
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true
	_refresh()
	if Sfx != null:
		Sfx.play("ui_open")


func close() -> void:
	visible = false
	_hideout = null


func is_open() -> bool:
	return visible


func toggle(h: Hideout) -> void:
	if is_open():
		close()
	else:
		open(h)


func _on_close() -> void:
	close()
	closed.emit()
	if Sfx != null:
		Sfx.play("ui_cancel")


func _on_tab(g: String) -> void:
	_group = g
	_refresh_tab_styles()
	_refresh()


func _on_sort(i: int) -> void:
	_sort = i
	_refresh_sort_styles()
	_refresh()


func _refresh_tab_styles() -> void:
	for b in _tab_buttons:
		var on: bool = str(b.get_meta("group", "")) == _group
		b.accent = C_TAB_ON if on else C_TAB_OFF
		b.active = on


func _refresh_sort_styles() -> void:
	for b in _sort_buttons:
		var on: bool = int(b.get_meta("sort", 0)) == _sort
		b.accent = C_TAB_ON if on else C_TAB_OFF
		b.active = on


func _refresh() -> void:
	if _list == null or _hideout == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)      # 立即摘除，保证 get_child_count() 即时反映（queue_free 是延迟的）
		c.queue_free()
	var entries: Array = _hideout.stash_entries_filtered(_group, _sort)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "（这个分类里没有东西）"
		empty.add_theme_font_size_override("font_size", 14)
		empty.add_theme_color_override("font_color", C_SUB)
		_list.add_child(empty)
	else:
		for e in entries:
			_list.add_child(_make_row(str(e["name"]), int(e["count"]), int(e["value"])))
	var used := _hideout.stash.used_slots()
	var cap := _hideout.stash.slot_count()
	if _hint != null:
		_hint.text = "仓库 %d/%d 槽 · 当前分类「%s」共 %d 种" % [used, cap, _group, entries.size()]


func _make_row(name: String, count: int, value: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var main := Label.new()
	main.text = "%s ×%d" % [name, count]
	main.add_theme_font_size_override("font_size", 14)
	main.add_theme_color_override("font_color", C_ROW)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.clip_text = true
	row.add_child(main)
	var val := Label.new()
	val.text = "%d 元" % value
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", C_SUB)
	row.add_child(val)
	return row


func _fit_viewport() -> void:
	# 不在树里时 get_viewport_rect() 会报引擎错误 —— 先判在不在树（同 InventoryPanel）
	var vp := Vector2.ZERO
	if is_inside_tree():
		vp = get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)
