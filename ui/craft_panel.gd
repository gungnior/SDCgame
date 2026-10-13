class_name CraftPanel
extends Control

## 制造面板（C 阶段制造系统的 UI 入口）
##
## ⚠️ 为什么写它：`sim/craft_system.gd`（CraftSystem）+ `data/recipes.json` 都已实现，
##    但**没有任何 UI 入口** —— 玩家在藏身处根本造不了东西。
##    这和 MerchantPanel 当年的处境一模一样（"逻辑早就有，缺的是入口"）。
##
## 设计（沿用 spec T-62：手机没有鼠标 -> 点选点放，不做拖拽）：
##   每行为一个配方：显示「产出 xN」+「所需材料 现有/需要」+ 工作台；
##   **材料够且工作台已解锁**才可点（绿色），否则灰色并说明缺什么。
##   制造走 CraftSystem.craft()（原子：扣料→出货，不满足整体不动）。
##
## ⚠️ 工作台解锁状态由**外部注入**（stations: Dictionary station -> bool），
##    本面板不自己判定来源 —— 与 CraftSystem 的依赖注入思路一致：
##    将来接"工作台升级"时，只改传进来的 Dictionary，不动本文件。

signal closed()
signal changed()          ## 制造成功后（让藏身处刷新仓库显示）

const ROW_H := 34

var _title: Label
var _hint: Label
var _box: VBoxContainer
var _close_btn: TouchButton
var _open := false

var _items: Dictionary = {}
var _recipes: Dictionary = {}
var _stash: Inventory = null
var _stations: Dictionary = {}
var _craft: CraftSystem = null


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
	_fit_viewport()
	var bg := ColorRect.new()
	bg.color = UITokens.fade(UITokens.BG_DEEP, 0.93)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	_title = _mk_label("制造", 22, UITokens.TEXT_HI)
	root.add_child(_title)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(sc)

	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 3)
	sc.add_child(_box)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	root.add_child(bottom)

	_hint = _mk_label("", 13, UITokens.TEXT_MID)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_hint)

	_close_btn = TouchButton.new()
	_close_btn.label_text = "关闭"
	_close_btn.use_hold = false
	_close_btn.base_radius = 26.0
	_close_btn.custom_minimum_size = Vector2(120, 72)
	_close_btn.accent = UITokens.DANGER
	_close_btn.pressed_down.connect(close)
	bottom.add_child(_close_btn)


func _mk_label(t: String, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	return l


## 打开面板。stations: station_id -> bool（哪些工作台已解锁）
func open(items: Dictionary, recipes: Dictionary, stash: Inventory,
		stations: Dictionary) -> void:
	_items = items
	_recipes = recipes
	_stash = stash
	_stations = stations
	_craft = CraftSystem.new(recipes, items)
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh()


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _close_btn != null:
		_close_btn.force_release()
	closed.emit()


func _refresh() -> void:
	if _box == null:
		return
	for c in _box.get_children():
		c.queue_free()
	if _stash == null or _craft == null:
		return
	_hint.text = "点配方制造 · 灰色 = 材料不足或工作台未解锁"
	for rid in _recipes:
		var r: RecipeDef = _recipes[rid]
		_box.add_child(_make_row(r))


func _make_row(r: RecipeDef) -> Control:
	var unlocked: bool = bool(_stations.get(r.station, false))
	var miss: RecipeDef.Ingredient = _craft.missing_input(r.id, _stash)
	var can: bool = _craft.can_craft(r.id, _stash, _stations)

	# 材料行："材料名 现有/需要"
	var parts := ""
	for g in r.inputs:
		var have: int = _stash.count_of(g.item_id)
		if parts != "":
			parts += " · "
		parts += "%s %d/%d" % [_name_of(g.item_id), have, g.count]

	var txt: String = "%s x%d\n%s" % [_name_of(r.output_item_id), r.output_count, parts]
	if not unlocked:
		txt += "\n需要工作台：%s" % r.station
	elif miss != null:
		txt += "\n缺 %s" % _name_of(miss.item_id)

	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 22.0
	b.custom_minimum_size = Vector2(0, ROW_H + 28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.label_text = txt
	b.accent = UITokens.SUCCESS if can else UITokens.BORDER
	b.pressed_down.connect(func():
		if _craft == null or _stash == null:
			return
		if _craft.can_craft(r.id, _stash, _stations) and _craft.craft(r.id, _stash, _stations):
			changed.emit()
		_refresh())
	return b


func _name_of(item_id: String) -> String:
	var d: ItemDef = _items.get(item_id)
	return str(d.name) if d != null else item_id
