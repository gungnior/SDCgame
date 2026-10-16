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
##   · 每个条目是一个自绘按钮：点一下执行动作（拿走 / 使用 / 装备 / 丢弃）
##   · **顶部装备栏**（装备系统）：4 个槽位，点已装备的 = 脱下回背包
##
## ⚠️ 面板**不认识战斗**：它只发信号（equip_requested / unequip_requested），
##    "换了枪要重建 WeaponState" 是场景的事。这样面板能在藏身处和战局里复用
##    （两边只差一个"容器是谁"）。
##
## ── 2026-10-13 真机反馈 #4 / #5 ──
##   #4「物品在交互的时候加入拖动系统」：
##      **保留**点一下执行动作，**外加**拖拽 —— 把左栏条目拖到右栏 = 整堆拿走。
##      为此 rows 用 `TouchButton.drag_enabled`（拖过阈值才算拖，否则仍是点按）。
##   #5「搜刮时对堆叠物品快速拾取 + 自定义数量」：
##      堆叠行（>1）额外给「全拿」和「取N…」两颗按钮；点行本体仍是拿 1 个。
##
## ⚠️ **本面板不再声称"手机上没有拖拽"** —— 那句话是 spec T-62 时代的取舍，
##    现在被真机反馈推翻。点选点放仍在，拖拽只是**多**一条路。

signal closed()
signal action(item_id: String, count: int)
## 请求把背包里的某件穿上（场景负责调 equipment.equip 并刷新）
signal equip_requested(item_id: String)
## 请求脱下某个槽位（场景负责调 equipment.unequip 并刷新）
signal unequip_requested(slot: String)

const ROW_H := 34

var _title: Label
var _equip_title: Label
var _equip_row: HBoxContainer
var _left_title: Label
var _right_title: Label
var _left_box: VBoxContainer
var _right_box: VBoxContainer
var _left_scroll: ScrollContainer
var _right_scroll: ScrollContainer
var _hint: Label
var _sort_btn: TouchButton
var _close_btn: TouchButton

var _items: Dictionary = {}          ## ItemDef 表
var _left_inv: Inventory = null      ## 搜索目标（可为 null）
var _right_inv: Inventory = null     ## 玩家背包
var _equipment: Equipment = null     ## 身上装备（null = 本局没有装备系统）
## 全境2化 P2：品质/词条表（面板显示"稀有 · 伤害+8% · 评分 132"用）。
## 空表 = 退回 2026-10-16 之前的样式（不显示品质），老调用方行为不变。
var _rarities: Array = []
var _affixes: Array = []
var _left_mode := "take"             ## take=从容器拿
var _open := false
var _built := false

## 拖拽（真机反馈 #4）
var _ghost: DragGhost = null
var _drag: Dictionary = {}           ## {item_id, count, from_left}
## 数量弹窗（真机反馈 #5）
var _qty: QtyPrompt = null
var _pending_take := ""


func _ready() -> void:
	_ensure_built()


## 保证界面**只建一次**（理由见 ui/mod_panel.gd 的同名函数）。
## ⚠️ 顺带修掉一个原有隐患：本面板原来**没有 `_fit_viewport`** ——
##    而它和设置菜单/结算面板一样是挂在 `CanvasLayer` 下的 Control，
##    锚点解析不到父矩形时整块会塌成 (0,0)（本项目已因此栽过三次）。
##    真机上之所以"看起来正常"，是因为视口恰好是屏幕尺寸；一旦换了
##    分辨率/旋转就没人兜底了。
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


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UITokens.fade(UITokens.BG_DEEP, 0.93)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP     # 挡住下层，防止误触摇杆
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_title = _mk_label("背包", 22, UITokens.TEXT_HI)
	root.add_child(_title)

	# ── 装备栏（装备系统）──
	# ⚠️ 放在【两栏之上】而不是做成第三栏：640x360 的竖屏手机上三栏每栏不到
	#    210px，文字会被截断。横排放 4 个槽位宽度足够，高度只吃 ~56px。
	#    默认隐藏 —— 没有装备系统时（老调用方）面板外观与以前完全一致。
	_equip_title = _mk_label("", 14, UITokens.SUCCESS)
	_equip_title.visible = false
	root.add_child(_equip_title)

	_equip_row = HBoxContainer.new()
	_equip_row.add_theme_constant_override("separation", 6)
	_equip_row.visible = false
	root.add_child(_equip_row)

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

	_hint = _mk_label("", 13, UITokens.TEXT_MID)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ⚠️ `clip_text` 让 Label 的**最小宽度不再包含文本** ——
	#    否则一句长提示会把整个面板的最小宽度顶大（探针实测：一行 405px 的提示
	#    + 120 整理 + 120 关闭 + 间距 = 665 > 640，整块面板被撑到 665 宽，
	#    右栏与「关闭」被挤出屏幕）。
	_hint.clip_text = true
	bottom.add_child(_hint)

	# ⭐「整理」—— spec T-62 说触屏上"一键整理"是必需品。
	#   Inventory.compact() 在 sim 层早已实现并单测，但此前**从未被 UI 调用**，
	#   等于能力存在、玩家用不到。这里把它接上：合并同类堆叠 + 挤紧空槽。
	_sort_btn = TouchButton.new()
	_sort_btn.label_text = "整理"
	_sort_btn.use_hold = false
	_sort_btn.base_radius = 26.0
	_sort_btn.custom_minimum_size = Vector2(120, 72)
	_sort_btn.accent = UITokens.INFO
	_sort_btn.pressed_down.connect(_on_sort)
	bottom.add_child(_sort_btn)

	_close_btn = TouchButton.new()
	_close_btn.label_text = "关闭"
	_close_btn.use_hold = false
	_close_btn.base_radius = 26.0
	_close_btn.custom_minimum_size = Vector2(120, 72)
	_close_btn.accent = UITokens.DANGER
	_close_btn.pressed_down.connect(close)
	bottom.add_child(_close_btn)

	# ── 拖拽浮标 + 数量弹窗（真机反馈 #4 / #5）──
	# ⚠️ 必须**最后** add_child：CanvasItem 按加入顺序绘制，
	#    它们要盖在所有行之上（浮标盖行、弹窗盖浮标）。
	_ghost = DragGhost.new()
	add_child(_ghost)
	_ghost.set_anchors_preset(Control.PRESET_FULL_RECT)

	_qty = QtyPrompt.new()
	_qty.confirmed.connect(_on_qty_confirmed)
	_qty.cancelled.connect(func(): _pending_take = "")
	add_child(_qty)


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
	return [t, sc, inner]


## 清空容器（VBox / HBox 都要用 —— 参数类型写 VBoxContainer 会让装备栏编译不过）
func _clear(box: Container) -> void:
	for c in box.get_children():
		c.queue_free()


## 打开面板。
##   container_inv / container_title：要搜索的容器（null = 纯背包）
##   equipment：身上装备（null = 不显示装备栏 —— 保持旧调用方的行为）
##   gear_defs：{"rarities": Array[RarityDef], "affixes": Array[AffixDef]}（可省略）
func open(items: Dictionary, carry: Inventory, container_inv: Inventory = null,
		container_title: String = "搜索目标", equipment: Equipment = null,
		gear_defs: Dictionary = {}) -> void:
	_ensure_built()
	_items = items
	_right_inv = carry
	_left_inv = container_inv
	_equipment = equipment
	_rarities = (gear_defs.get("rarities", []) as Array).duplicate()
	_affixes = (gear_defs.get("affixes", []) as Array).duplicate()
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title.text = "背包" if container_inv == null else "搜索：%s" % container_title
	_left_title.visible = container_inv != null
	_left_scroll.visible = container_inv != null
	_equip_title.visible = _equipment != null
	_equip_row.visible = _equipment != null
	_hint.text = "点条目执行动作 · 也可拖到右栏 · 堆叠行有「全拿 / 取N…」"
	refresh()


## 外部让面板重新取数（场景处理完 equip/unequip 后调用）
func refresh() -> void:
	_refresh()


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _close_btn != null:
		_close_btn.force_release()
	# 拖拽/数量弹窗不能带着状态留下（下次打开会看到上一次的浮标）
	if _ghost != null:
		_ghost.hide_ghost()
	_drag = {}
	if _qty != null and _qty.is_open():
		_qty.close()
	closed.emit()


## 「整理」：合并同类堆叠 + 挤紧空槽（spec T-62：触屏上"一键整理"是必需品）。
## 只整理玩家自己的背包 —— 左栏是尸体/容器的**临时视图**，整理它没有意义。
func _on_sort() -> void:
	if _sort_btn != null:
		_sort_btn.force_release()
	if _right_inv == null:
		return
	_right_inv.compact()
	_refresh()


func _refresh() -> void:
	# 重建行会把"正在被拖的那颗按钮"queue_free 掉 —— 先收掉拖拽态，
	# 否则浮标会永远挂在屏幕上（按钮没了，drag_dropped 永远不发）。
	_drag = {}
	if _ghost != null:
		_ghost.hide_ghost()
	_clear(_right_box)
	_clear(_left_box)
	if _right_inv != null:
		_right_title.text = "我的背包  %s" % _right_inv.summary()
		_add_rows(_right_box, _right_inv, false)
	if _left_inv != null:
		_left_title.text = "%s  %s" % [_title.text.replace("搜索：", ""), _left_inv.summary()]
		_add_rows(_left_box, _left_inv, true)
		if _left_inv.is_empty():
			var l := _mk_label("（空）", 13, UITokens.TEXT_LOW)
			_left_box.add_child(l)
	_refresh_equip()


## 顶部装备栏：4 个槽位按钮。点【已装备的】= 脱下回背包。
func _refresh_equip() -> void:
	_clear(_equip_row)
	if _equipment == null:
		return
	_equip_title.text = "装备 · 身上 %.1f kg（点已装备的脱下）" % _equipment.worn_weight()
	for slot in Equipment.SLOTS:
		var id: String = _equipment.id_in(slot)
		var b := TouchButton.new()
		b.use_hold = false
		b.base_radius = 22.0
		b.custom_minimum_size = Vector2(0, 52)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# ⭐ 全境2化 P2：身上这件显示品质名 + 用品质色描边（数据自带 color）
		var g: Dictionary = (_equipment.gear.get(slot, {}) as Dictionary) \
			if _equipment.gear != null else {}
		var shown := _display_name(id)
		var r := _rarity_def(g)
		if r != null:
			shown = "%s · %s" % [shown, r.name]
		b.label_text = "%s\n%s" % [str(Equipment.SLOT_LABEL.get(slot, slot)), shown]
		b.accent = _rarity_color(g) if not g.is_empty() \
			else (UITokens.SUCCESS if id != "" else UITokens.TEXT_LOW)
		# ⚠️ 用 bind 而不是 lambda 读循环变量：bind 的参数在**绑定时**求值，
		#    4 个按钮一定各拿到自己的槽位（lambda 捕获循环变量的语义容易出错）。
		b.pressed_down.connect(_on_slot_pressed.bind(slot, id))
		_equip_row.add_child(b)


func _on_slot_pressed(slot: String, id: String) -> void:
	if id == "":
		_hint.text = "这个槽是空的 —— 从下面背包里点「装备」"
		return
	_hint.text = "脱下 %s" % _display_name(id)
	unequip_requested.emit(slot)


func _display_name(id: String) -> String:
	if id == "":
		return "（空）"
	var d: ItemDef = _items.get(id)
	return str(d.name) if d != null else id


# ─────────────── 全境2化 P2：品质 / 词条 / 评分的显示 ───────────────

## 品质定义（无 gear 或查不到 = null）
func _rarity_def(gear: Dictionary) -> RarityDef:
	if gear.is_empty():
		return null
	return GearGen.find_rarity(_rarities, str(gear.get("rarity", "")))


## 品质染色：数据自带 #rrggbb；没表 / 解析失败一律退回中性色（不许因显示报错）
func _rarity_color(gear: Dictionary) -> Color:
	var r := _rarity_def(gear)
	if r == null or r.color == "":
		return UITokens.NEUTRAL
	return Color(r.color)


## 一行的装备摘要："稀有 · 武器伤害+8% · 评分 132"（无 gear 返回空串）
func _gear_text(gear: Dictionary, category: String) -> String:
	if gear.is_empty():
		return ""
	var r := _rarity_def(gear)
	var head := GearGen.summary(gear, r, _affixes)
	return "%s · 评分 %d" % [head, GearGen.score_of(gear, category, r)]


func _category_of(id: String) -> String:
	var d: ItemDef = _items.get(id)
	return str(d.category) if d != null else "?"


## 把背包里的堆叠汇总成一行一项（手机屏幕上重复条目很碍眼）
func _add_rows(box: VBoxContainer, inv: Inventory, is_container: bool) -> void:
	var counts: Dictionary = {}
	var order: Array[String] = []
	# ⭐ 全境2化 P2：带 gear 的装备**每槽一行** —— 两把同 id 的枪品质不同，
	#    合并成一行的话玩家根本没法挑（这正是"看到词条才能决策"的意义）。
	var gears: Array[Dictionary] = []
	for s in inv.slots:
		if s == null:
			continue
		var sd: Dictionary = s as Dictionary
		if sd.has("gear"):
			gears.append({"id": str(sd.get("item_id", "")), "gear": sd["gear"]})
			continue
		var id := str(sd.get("item_id", ""))
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + int(sd.get("count", 0))
	for id in order:
		box.add_child(_make_row(id, int(counts[id]), is_container))
	for e in gears:
		box.add_child(_make_gear_row(str(e["id"]), (e["gear"] as Dictionary), is_container))
	if order.is_empty() and gears.is_empty():
		var l := _mk_label("（空）", 13, UITokens.TEXT_LOW)
		box.add_child(l)


## 带品质词条的装备单独成行："名字 / 稀有 · 词条 / 动作"。
##
## ⚠️ 已知限制：装备动作仍按 item_id 发信号（`Equipment.equip` 走
##    `first_slot_of`），背包里有两把同 id 不同品质的枪时，穿上的可能不是你点的那把。
##    修法（下一步）：equip 改按槽位下标 —— 见 workboard「装备闭环补齐四步」。
func _make_gear_row(item_id: String, gear: Dictionary, is_container: bool) -> Control:
	var name_ := _display_name(item_id)
	var tail := _gear_text(gear, _category_of(item_id))
	if is_container:
		return _mk_item_button("%s\n%s\n拿走" % [name_, tail], _rarity_color(gear), func():
			action.emit(item_id, 1)
			_refresh())
	var can_equip := _equipment != null and _equipment.is_equippable(item_id)
	if can_equip:
		return _mk_item_button("%s\n%s\n装备" % [name_, tail], _rarity_color(gear), func():
			_hint.text = "装备 %s（%s）" % [name_, tail]
			equip_requested.emit(item_id))
	return _mk_item_button("%s\n%s\n丢弃" % [name_, tail], _rarity_color(gear), func():
		action.emit(item_id, -2)
		_refresh())


func _make_row(item_id: String, count: int, is_container: bool) -> Control:
	# 左栏（搜到的容器/尸体）走"堆叠行"，见 _make_container_row
	if is_container:
		return _make_container_row(item_id, count)
	var d: ItemDef = _items.get(item_id)
	var name_ := str(d.name) if d != null else item_id
	var cat := str(d.category) if d != null else "?"
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 22.0
	b.custom_minimum_size = Vector2(0, ROW_H + 20)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# ── 自己的背包：可装备的优先给「装备」，其次医疗类「使用」，其余「丢弃」──
	# ⚠️ 顺序不能反：护甲同时也是"非医疗品"，先判使用的话护甲只能被丢掉。
	var can_equip := _equipment != null and _equipment.is_equippable(item_id)
	if can_equip:
		b.label_text = "%s x%d\n装备" % [name_, count]
		b.accent = UITokens.SUCCESS
		b.pressed_down.connect(func():
			_hint.text = "装备 %s" % name_
			equip_requested.emit(item_id))
		return b
	var act := "使用" if cat == "medical" or cat == "consumable" else "丢弃"
	b.label_text = "%s x%d\n%s" % [name_, count, act]
	b.accent = UITokens.INFO if act == "使用" else UITokens.NEUTRAL
	b.pressed_down.connect(func():
		action.emit(item_id, -1 if act == "使用" else -2)
		_refresh())
	return b


# ─────────────────── 左栏：容器堆叠行（真机反馈 #4 / #5）───────────────────

## 造一个普通条目按钮。
func _mk_item_button(label: String, accent: Color, cb: Callable) -> TouchButton:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 22.0
	b.custom_minimum_size = Vector2(0, ROW_H + 20)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.label_text = label
	b.accent = accent
	b.pressed_down.connect(cb)
	return b


## 左栏（容器/尸体）的一行。
##
## 布局：
##   count <= 1  -> 只有一个按钮（拿走），行为与以前一致
##   count >  1  -> [ 名字 xN / 拿走 1 ] [ 全拿 ] [ 取N… ]
##
## 三个动作对应三档需求（真机反馈 #5 的"快速拾取 + 自定义数量"）：
##   · 点行本体 = 拿 1（精挑细选）
##   · 全拿      = 整堆一次拿走（快速）
##   · 取N…     = 弹数量窗自己定（自定义）
## 再加上"把行拖到右栏"= 整堆拿走（真机反馈 #4）。
func _make_container_row(item_id: String, count: int) -> Control:
	var d: ItemDef = _items.get(item_id)
	var name_ := str(d.name) if d != null else item_id

	if count <= 1:
		var single := _mk_item_button("%s x1\n拿走" % name_, UITokens.SUCCESS,
			func():
				action.emit(item_id, 1)
				_refresh())
		_attach_drag(single, "%s x1" % name_, item_id, 1)
		return single

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var main := _mk_item_button("%s x%d\n拿走 1" % [name_, count], UITokens.SUCCESS,
		func():
			action.emit(item_id, 1)
			_refresh())
	# 拖它 = 整堆搬走（拖拽语义：拖的是"这一堆"）
	_attach_drag(main, "%s x%d" % [name_, count], item_id, count)
	row.add_child(main)

	var all_btn := _mk_item_button("全拿\n%d" % count, UITokens.SUCCESS,
		func():
			action.emit(item_id, count)
			_refresh())
	all_btn.custom_minimum_size = Vector2(92, ROW_H + 20)
	all_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(all_btn)

	var qty_btn := _mk_item_button("取N…", UITokens.INFO,
		func(): _open_qty(item_id, name_, count))
	qty_btn.custom_minimum_size = Vector2(92, ROW_H + 20)
	qty_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	row.add_child(qty_btn)
	return row


## 给条目挂上拖拽（真机反馈 #4）。from_left=true 表示"从容器拖向背包"。
func _attach_drag(btn: TouchButton, label: String, item_id: String, count: int,
		from_left: bool = true) -> void:
	btn.drag_enabled = true
	btn.drag_started.connect(func(gp: Vector2):
		_begin_drag(gp, label, item_id, count, from_left))
	btn.drag_moved.connect(_on_drag_moved)
	btn.drag_dropped.connect(_on_drag_dropped)


func _begin_drag(gpos: Vector2, label: String, item_id: String, count: int,
		from_left: bool) -> void:
	_drag = {"item_id": item_id, "count": count, "from_left": from_left}
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
	# 落点判定：拖到【自己的背包】那一栏 = 拿走
	if bool(d["from_left"]) and _right_scroll != null \
			and _right_scroll.get_global_rect().has_point(gpos):
		if Sfx != null:
			Sfx.play("pickup")
		action.emit(str(d["item_id"]), int(d["count"]))
		_refresh()


## 面板局部坐标 <- 全局（canvas）坐标。
## ⚠️ TouchButton 发的是**全局**坐标（它在 ScrollContainer 里，局部的没意义）。
func _g2l(g: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * g


# ─────────────────── 自定义数量（真机反馈 #5）───────────────────

func _open_qty(item_id: String, item_name: String, count: int) -> void:
	if _qty == null:
		return
	# 上限提示：背包实际还能塞下多少个（让玩家别白输一个放不下的数）
	var fit := count
	if _right_inv != null:
		fit = _right_inv.fit_count(item_id, count)
	_pending_take = item_id
	_qty.open(item_name, count, fit)


func _on_qty_confirmed(n: int) -> void:
	var id := _pending_take
	_pending_take = ""
	if id.is_empty() or n <= 0:
		return
	action.emit(id, n)
	_refresh()


## 供测试/调用方查询：当前拖拽态
func drag_state() -> Dictionary:
	return _drag.duplicate()

