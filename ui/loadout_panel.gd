class_name LoadoutPanel
extends Control

## 配装面板（藏身处）—— 装备系统的「配装」入口
##
## ⚠️ 为什么要写它：`Equipment`（穿脱/换装/错误原因）在 sim 层早就实现并有单测，
##    但**没有任何 UI 入口**，玩家在藏身处点不到 —— 等于"装备系统不存在"。
##    这和商人/制造是同一类问题（能力存在、玩家用不到）。
##
## 设计（沿用 spec T-62：手机没有鼠标 -> 点选点放，不做拖拽）：
##   左栏 = 仓库里**可装备**的东西（点一下穿上）
##   右栏 = 4 个装备槽（点一下脱回仓库）
##   底部 = 「改枪」（对武器槽）+「关闭」
##
## ⚠️ 本面板**不判定任何规则**：能不能穿、有没有插槽、背包放不放得下，
##    全在 Equipment 里（那里有单测，返回的也是可直接给玩家看的中文原因）。
##    面板只做「把点击翻译成调用 + 把结果贴到 hint 上」。
##
## ── 2026-10-13 真机反馈 #4：加拖拽 ──
##   左栏条目可**拖到右栏**（装备），右栏条目可**拖到左栏**（脱下）；
##   点一下照样能穿脱（原路保留）。

signal closed()
signal changed()          ## 配装变化（让藏身处刷新仓库/资金显示）

const ROW_H := 34

var _title: Label
var _wallet: Label
var _left_title: Label
var _right_title: Label
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _hint: Label
var _mod_btn: TouchButton
var _close_btn: TouchButton
## 改枪面板（作为本面板的子节点，天然画在上面）
var mod_panel: ModPanel = null

## 拖拽（真机反馈 #4）
var _ghost: DragGhost = null
var _drag: Dictionary = {}

var _hideout: Hideout = null
var _items: Dictionary = {}
var _weapons: Dictionary = {}
var _attachments: Dictionary = {}
var _open := false
var _built := false


func _ready() -> void:
	_ensure_built()


## 保证界面**只建一次**（理由见 ui/mod_panel.gd 的同名函数：
## `_ready` 只在进树时执行，面板可能在没进树时就被 open）。
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func is_open() -> bool:
	return _open


func _fit_viewport() -> void:
	# 不在树里时 get_viewport_rect() 会报引擎错误 —— 先判在不在树
	var vp := Vector2.ZERO
	if is_inside_tree():
		vp = get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _mk(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


func _build() -> void:
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

	var bar := MarginContainer.new()
	bar.add_theme_constant_override("margin_left", 20)
	bar.add_theme_constant_override("margin_top", 10)
	bar.add_theme_constant_override("margin_right", 20)
	bar.add_theme_constant_override("margin_bottom", 2)
	col.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	_title = _mk("配装", 22, UITokens.TEXT_HI)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)
	_wallet = _mk("", 15, UITokens.ACCENT)
	_wallet.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_wallet)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(cols)
	var l := _column(cols, "仓库（点一下穿上）")
	_left_title = l[0]
	_left_box = l[1]
	var r := _column(cols, "装备（点一下脱回仓库）")
	_right_title = r[0]
	_right_box = r[1]

	# 底部：提示 + 改枪 + 关闭
	var bottom := MarginContainer.new()
	bottom.add_theme_constant_override("margin_left", 20)
	bottom.add_theme_constant_override("margin_right", 20)
	bottom.add_theme_constant_override("margin_bottom", 8)
	bottom.add_theme_constant_override("margin_top", 2)
	col.add_child(bottom)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 10)
	bottom.add_child(brow)
	_hint = _mk("", 13, UITokens.TEXT)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ⚠️ 长提示会顶大面板最小宽度 -> 右栏被挤出屏幕（见 InventoryPanel 同名说明）
	_hint.clip_text = true
	brow.add_child(_hint)
	_mod_btn = TouchButton.new()
	_mod_btn.label_text = "改枪"
	_mod_btn.icon_text = "⚙"
	_mod_btn.use_hold = false
	_mod_btn.base_radius = 26.0
	_mod_btn.custom_minimum_size = Vector2(140, 68)
	_mod_btn.accent = UITokens.INFO
	_mod_btn.pressed_down.connect(_open_mod)
	brow.add_child(_mod_btn)
	_close_btn = TouchButton.new()
	_close_btn.label_text = "关闭"
	_close_btn.use_hold = false
	_close_btn.base_radius = 26.0
	_close_btn.custom_minimum_size = Vector2(130, 68)
	_close_btn.accent = UITokens.DANGER
	_close_btn.pressed_down.connect(close)
	brow.add_child(_close_btn)

	# 拖拽浮标：加在【行之后、改枪面板之前】——
	#   · 行是运行时动态生成进 _left_box/_right_box 的，那两个 VBox 在 _build
	#     里已经 add 完，所以浮标加在这里就等于"在所有行之上"；
	#   · 改枪面板是模态的，必须盖住浮标，所以浮标要在它**之前**加。
	_ghost = DragGhost.new()
	add_child(_ghost)
	_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)

	# 改枪面板：挂在【本面板】上而不是藏身处根节点 ——
	# 这样它的层级天然在配装面板之上，不需要藏身处再管一个 CanvasLayer。
	mod_panel = ModPanel.new()
	mod_panel.changed.connect(_refresh)
	add_child(mod_panel)


## 返回 [标题Label, 内容VBox]
func _column(parent: Node, title: String) -> Array:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 2)
	parent.add_child(box)
	var t := _mk(title, 15, UITokens.TEXT)
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


func open(hideout: Hideout, items: Dictionary, weapons: Dictionary,
		attachments: Dictionary) -> void:
	_ensure_built()
	_hideout = hideout
	_items = items
	_weapons = weapons
	_attachments = attachments
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hint.text = "点左栏穿 / 右栏脱 · 可拖到对面 · 「改枪」调配件"
	_refresh()


func close() -> void:
	# 改枪开着时先关它（否则它留在上面挡住——它是本面板的子节点）
	if mod_panel != null and mod_panel.is_open():
		mod_panel.close()
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _close_btn != null:
		_close_btn.force_release()
	if _ghost != null:
		_ghost.hide_ghost()
	_drag = {}
	closed.emit()


func _clear(box: Container) -> void:
	for c in box.get_children():
		c.queue_free()


func _display_name(id: String) -> String:
	if id == "":
		return "（空）"
	if _hideout != null:
		return _hideout.display_name_of(id)
	var d: ItemDef = _items.get(id)
	return str(d.name) if d != null else id


func _refresh() -> void:
	if _hideout == null:
		return
	# 重建行会把"正在被拖的那颗按钮"queue_free 掉 —— 先收掉拖拽态（见 InventoryPanel）
	_drag = {}
	if _ghost != null:
		_ghost.hide_ghost()
	_wallet.text = "资金 %d 元" % _hideout.wallet
	var ids := _hideout.equippable_in_stash()
	_left_title.text = "仓库（点一下穿上）  %d 件可装备" % ids.size()
	_right_title.text = "装备  身上 %.1f kg" % _hideout.loadout.worn_weight()

	# 左栏：仓库里可装备的（可拖到右栏穿上）
	_clear(_left_box)
	for id in ids:
		var n := _hideout.stash.count_of(id)
		_left_box.add_child(_row("%s x%d\n穿上" % [_display_name(id), n],
			UITokens.SUCCESS, _on_equip_pressed.bind(id),
			_on_equip_pressed.bind(id), true))
	if ids.is_empty():
		_left_box.add_child(_mk("（仓库里没有可装备的东西）", 13, UITokens.TEXT_LOW))

	# 右栏：4 个槽（可拖到左栏脱下）
	_clear(_right_box)
	for slot in Equipment.SLOTS:
		var id2: String = _hideout.loadout.id_in(slot)
		var extra := ""
		if slot == "weapon" and id2 != "":
			var cur: Dictionary = _hideout.loadout.mods_of(id2)
			extra = "  配件 %d" % cur.size()
		var label := "%s：%s%s" % [str(Equipment.SLOT_LABEL.get(slot, slot)), _display_name(id2), extra]
		if id2 == "":
			_right_box.add_child(_row(label, UITokens.BORDER,
				Callable()))
		else:
			_right_box.add_child(_row("%s\n脱下" % label, UITokens.ACCENT,
				_on_unequip_pressed.bind(slot),
				_on_unequip_pressed.bind(slot), false))


## 一行按钮。cb 为空（Callable()）时按钮不可用（空槽）—— 我们不做"看起来能点其实没反应"。
##
## drag_action：拖拽落下时执行的动作（真机反馈 #4）。
## drag_to_worn=true 表示"拖到右栏（装备）才生效"，false = "拖到左栏（脱下）"。
func _row(label: String, accent: Color, cb: Callable,
		drag_action: Callable = Callable(), drag_to_worn: bool = true) -> Control:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 22.0
	b.custom_minimum_size = Vector2(0, ROW_H + 16)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.label_text = label
	b.accent = accent
	if cb.is_valid():
		b.pressed_down.connect(cb)
	else:
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if drag_action.is_valid():
		b.drag_enabled = true
		b.drag_started.connect(func(gp: Vector2):
			_begin_drag(gp, label.split("\n")[0], drag_action, drag_to_worn))
		b.drag_moved.connect(_on_drag_moved)
		b.drag_dropped.connect(_on_drag_dropped)
	return b


# ─────────────────── 拖拽（真机反馈 #4）───────────────────

func _begin_drag(gpos: Vector2, label: String, action: Callable, to_worn: bool) -> void:
	_drag = {"action": action, "to_worn": to_worn}
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
	var on_right := _g2l(gpos).x > size.x * 0.5
	# 只有拖到【对面】才是有效操作（拖回自己那边 = 取消）
	if bool(d["to_worn"]) != on_right:
		return
	var act: Callable = d["action"]
	if act.is_valid():
		act.call()


func _g2l(g: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * g


## 供测试/调用方查询：当前拖拽态
func drag_state() -> Dictionary:
	return _drag.duplicate()


func _on_equip_pressed(id: String) -> void:
	if _hideout == null:
		return
	var err := _hideout.equip_from_stash(id)
	_after(err, "穿上")


func _on_unequip_pressed(slot: String) -> void:
	if _hideout == null:
		return
	var err := _hideout.unequip_to_stash(slot)
	_after(err, "脱下")


func _after(err: String, verb: String) -> void:
	if err == "":
		if Sfx != null:
			Sfx.play("ui_confirm")
		_hint.text = "%s成功" % verb
	else:
		if Sfx != null:
			Sfx.play("ui_deny")
		_hint.text = err
	changed.emit()
	_refresh()


func _open_mod() -> void:
	if mod_panel == null or _hideout == null:
		return
	if _hideout.loadout.id_in("weapon") == "":
		_hint.text = "武器槽是空的 —— 先穿一把枪才能改"
		if Sfx != null:
			Sfx.play("ui_deny")
		return
	mod_panel.open(_hideout, _weapons, _attachments, WeaponModding.SLOTS_C)
	if Sfx != null:
		Sfx.play("ui_open")
