class_name CarryPanel
extends Control

## 携带背包面板 —— 「这一局带什么进去」（真机反馈 #2）
##
## 用户原话："人物在藏身处配装时候应该可以选择带物品去背包"。
##
## 之前 `raid.carry` 是**写死的三样起始物资**，玩家在藏身处毫无发言权。
## 这个面板把「仓库 <-> 携带背包」的搬运做成两个可点的列：
##   左栏 = 仓库（点一下 -> 带进背包）
##   右栏 = 携带背包（点一下 -> 放回仓库）
##
## ⚠️ 设计纪律（与 InventoryPanel 一致）：
##   · 面板不认识游戏逻辑：只调 `Hideout` 的 API 并刷新
##   · `_ensure_built()` 幂等 —— 测试里 `add_child` 不会触发 `_ready`
##     （见 MEMORY「root.add_child 不触发 _ready」那条坑）
##
## ── 2026-10-13 真机反馈 #4：加拖拽 ──
##   点一下仍能搬运（原来的路没删），**外加**把条目拖到对面那一栏也能搬。
##   见 `TouchButton.drag_enabled`（拖过阈值才算拖，否则仍是点按）。

signal changed()
signal closed()

const ROW_H := 46

var _title: Label
var _left_title: Label
var _right_title: Label
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _hint: Label
var _close_btn: TouchButton

## 拖拽（真机反馈 #4）
var _ghost: DragGhost = null
var _drag: Dictionary = {}

var _hideout: Hideout = null
var _open := false
var _built := false

## 仓库分类标签 + 排序（2026-10-14「优化仓库」）
var _cat_filter: String = "全部"
var _sort_mode: int = 0                                  ## 0=价值↓ 1=名称↑ 2=数量↓
var _groups: Array[String] = ["全部", "武器", "护甲", "弹药", "医疗", "贵重", "杂物"]
var _tab_bar: HBoxContainer = null
var _tab_btns: Dictionary = {}                           # group -> TouchButton
var _sort_btn: TouchButton = null


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


func _fit_viewport() -> void:
	# 不在树里时 get_viewport_rect() 会报引擎 ERROR —— 先判在不在树
	var vp := Vector2.ZERO
	if is_inside_tree():
		vp = get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITokens.fade(UITokens.BG_DEEP, 0.93)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP     # 挡住下层，防误触
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_title = _mk_label("携带背包", 22, UITokens.TEXT_HI)
	root.add_child(_title)

	# ── 仓库分类标签 + 排序（2026-10-14「优化仓库」）──
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 6)
	root.add_child(_tab_bar)
	_mk_tabs()

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	var l := _mk_column("仓库（点一下带走）", cols)
	_left_title = l[0]
	_left_box = l[1]
	var r := _mk_column("携带背包（点一下放回）", cols)
	_right_title = r[0]
	_right_box = r[1]

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)

	_hint = _mk_label("", 13, UITokens.TEXT_MID)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ⚠️ 长提示会顶大面板最小宽度 -> 右栏被挤出屏幕（见 InventoryPanel 同名说明）
	_hint.clip_text = true
	bottom.add_child(_hint)

	var back := TouchButton.new()
	back.label_text = "全部放回"
	back.use_hold = false
	back.base_radius = 26.0
	back.custom_minimum_size = Vector2(130, 72)
	back.accent = UITokens.ACCENT
	back.pressed_down.connect(_on_clear)
	bottom.add_child(back)

	_close_btn = TouchButton.new()
	_close_btn.label_text = "关闭"
	_close_btn.use_hold = false
	_close_btn.base_radius = 26.0
	_close_btn.custom_minimum_size = Vector2(120, 72)
	_close_btn.accent = UITokens.DANGER
	_close_btn.pressed_down.connect(close)
	bottom.add_child(_close_btn)

	# 拖拽浮标必须**最后**加（CanvasItem 按加入顺序绘制，它要盖在所有行上）
	_ghost = DragGhost.new()
	add_child(_ghost)
	_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)


func _mk_label(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


## 返回 [标题Label, VBox]
func _mk_column(title: String, parent: Node) -> Array:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)

	var t := _mk_label(title, 15, UITokens.TEXT)
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
	return [t, inner]


func _clear(box: Container) -> void:
	for c in box.get_children():
		c.queue_free()


# ─────────────────── 仓库分类标签 + 排序（2026-10-14「优化仓库」）───────────────────

func _mk_tabs() -> void:
	for g in _groups:
		var b := TouchButton.new()
		b.label_text = g
		b.use_hold = false
		b.base_radius = 15.0
		b.custom_minimum_size = Vector2(70, 30)
		b.accent = UITokens.BORDER
		b.pressed_down.connect(_on_tab.bind(g))
		_tab_bar.add_child(b)
		_tab_btns[g] = b
	_sort_btn = TouchButton.new()
	_sort_btn.label_text = "价值↓"
	_sort_btn.use_hold = false
	_sort_btn.base_radius = 15.0
	_sort_btn.custom_minimum_size = Vector2(92, 30)
	_sort_btn.accent = UITokens.TEXT_MID
	_sort_btn.pressed_down.connect(_on_cycle_sort)
	_tab_bar.add_child(_sort_btn)
	_refresh_tabs()


func _on_tab(group: String) -> void:
	if _cat_filter == group:
		return
	_cat_filter = group
	_refresh_tabs()
	refresh()


func _refresh_tabs() -> void:
	for g in _tab_btns:
		var b: TouchButton = _tab_btns[g]
		b.accent = UITokens.TEXT_HI if g == _cat_filter else UITokens.BORDER


func _on_cycle_sort() -> void:
	_sort_mode = (_sort_mode + 1) % 3
	_sort_btn.label_text = "价值↓" if _sort_mode == 0 else ("名称↑" if _sort_mode == 1 else "数量↓")
	refresh()


# ─────────────────── 对外 ───────────────────

func open(hideout: Hideout) -> void:
	_ensure_built()
	_hideout = hideout
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hint.text = "点一下即搬运 · 也可以把条目拖到对面那一栏"
	refresh()


func refresh() -> void:
	if not _built:
		return
	# 重建行会把"正在被拖的那颗按钮"queue_free 掉 —— 先收掉拖拽态（见 InventoryPanel）
	_drag = {}
	if _ghost != null:
		_ghost.hide_ghost()
	_clear(_left_box)
	_clear(_right_box)
	if _hideout == null or _hideout.pack == null:
		_hint.text = "携带背包不可用"
		return
	var pk := _hideout.pack
	_right_title.text = "携带背包  %d/%d 槽 · %.1f/%.1f kg" % [
		pk.used_slots(), pk.slot_count(), pk.total_weight(), pk.max_weight]
	_left_title.text = "仓库（%s）  %d/%d 槽" % [
		_cat_filter, _hideout.stash.used_slots(), _hideout.stash.slot_count()]
	for e in _hideout.stash_entries_filtered(_cat_filter, _sort_mode):
		_left_box.add_child(_make_row(str(e["name"]), int(e["count"]), true, str(e["id"])))
	for e in _hideout.pack_entries():
		_right_box.add_child(_make_row(str(e["name"]), int(e["count"]), false, str(e["id"])))
	if _hideout.pack_entries().is_empty():
		_right_box.add_child(_mk_label("（空）—— 从左栏点物品带进来", 13, UITokens.TEXT_LOW))


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _close_btn != null:
		_close_btn.force_release()
	if _ghost != null:
		_ghost.hide_ghost()
	_drag = {}
	closed.emit()


# ─────────────────── 行 ───────────────────

## to_pack=true 表示这一行是"从仓库带进背包"，否则是"放回仓库"。
func _make_row(name_: String, count: int, to_pack: bool, item_id: String) -> Control:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 22.0
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.label_text = "%s x%d\n%s" % [name_, count, "带进 →" if to_pack else "← 放回"]
	b.accent = UITokens.SUCCESS if to_pack else UITokens.INFO
	# ⚠️ 用 bind 而非 lambda 捕获循环变量：bind 参数在**绑定时**求值
	b.pressed_down.connect(_on_row.bind(item_id, to_pack))
	# ── 拖拽（真机反馈 #4）──
	b.drag_enabled = true
	b.drag_started.connect(func(gp: Vector2):
		_begin_drag(gp, "%s x%d" % [name_, count], item_id, to_pack))
	b.drag_moved.connect(_on_drag_moved)
	b.drag_dropped.connect(_on_drag_dropped)
	return b


# ─────────────────── 拖拽（真机反馈 #4）───────────────────

func _begin_drag(gpos: Vector2, label: String, item_id: String, to_pack: bool) -> void:
	_drag = {"item_id": item_id, "to_pack": to_pack}
	if _ghost != null:
		_ghost.show_at(label, _g2l(gpos))


func _on_drag_moved(gpos: Vector2) -> void:
	if _ghost != null:
		_ghost.move_to(_g2l(gpos))


func _on_drag_dropped(gpos: Vector2) -> void:
	var d := _drag
	_drag = {}
	if _ghost != null:
		_ghost.hide_ghost()
	if d.is_empty():
		return
	# 落点判定：两栏各占半边，用中点分界（比取 VBox 的全局矩形稳 ——
	# 空栏的 VBox 尺寸会塌缩，拿它判定会把"拖到空栏"误判成失败）
	var half := _g2l(gpos).x > size.x * 0.5
	var to_pack := bool(d["to_pack"])
	# 拖到【对面】那一栏才生效（拖回自己那边 = 取消）
	if to_pack and not half:
		return
	if not to_pack and half:
		return
	_on_row(str(d["item_id"]), to_pack)


func _g2l(g: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * g


## 供测试/调用方查询：当前拖拽态
func drag_state() -> Dictionary:
	return _drag.duplicate()


func _on_row(item_id: String, to_pack: bool) -> void:
	if _hideout == null:
		return
	var err := ""
	if to_pack:
		err = _hideout.stash_to_pack(item_id)          # count<=0 = 能带多少带多少
	else:
		err = _hideout.pack_to_stash(item_id)
	_hint.text = err if err != "" else ("已带进 %s" % _hideout.display_name_of(item_id)
		if to_pack else "已放回 %s" % _hideout.display_name_of(item_id))
	refresh()
	changed.emit()


func _on_clear() -> void:
	if _hideout == null:
		return
	_hideout.pack_clear_to_stash()
	_hint.text = "携带背包已清空"
	refresh()
	changed.emit()
