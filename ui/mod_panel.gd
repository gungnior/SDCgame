class_name ModPanel
extends Control

## 改枪面板（装备系统的「修改枪械配件」）
##
## 依据 specs/feasibility.md D-08：第一版只改数值，不做视觉变形。
##
## ⚠️ 两个刻意的设计决定：
##
## ① **配件库全开放（依赖注入）**
##    attachments.json 不在 items.json 里 —— 配件不是 item、不占背包。
##    所以"这个配件你有没有"这件事，本面板**不判定**：候选池由调用方注入
##    （和 CraftPanel 的 stations 完全同一套做法）。
##    将来要改成"配件得买 / 得从敌人身上捡"，**只需换掉注入的 pool**，
##    本文件一行不用改。
##
## ② **配置记在 Equipment 上，不是记在这里**
##    `set_mod` 写进 Equipment.mods（按 weapon_id 索引，跟枪走），然后由
##    `build_loadout()` 产出有效战斗数值。面板只负责"显示 + 转发点击"，
##    不改任何数值 —— 数值只在 WeaponModding 里算（单一真源）。

signal closed()
signal changed()          ## 装/卸发生后（让配装面板刷新摘要）

## 数值字段的中文名（给玩家看的不能是 spread_deg 这种）
const FIELD_LABEL := {
	"damage": "伤害", "rpm": "射速", "mag_size": "弹匣", "reload_time": "装填",
	"spread_deg": "散布", "range_m": "射程", "recoil_v": "垂直后坐",
	"recoil_h": "水平后坐", "weight": "重量", "noise_m": "噪音",
}

var _title: Label
var _stats: Label
var _hint: Label
var _list: VBoxContainer
var _close_btn: TouchButton

var _hideout: Hideout = null
var _weapons: Dictionary = {}
var _attachments: Dictionary = {}
var _slot_limit := WeaponModding.SLOTS_C
var _open := false
var _built := false


func _ready() -> void:
	_ensure_built()


## 保证界面**只建一次**。
##
## ⚠️ 为什么不是直接写在 `_ready` 里：`_ready` 只在【进树】时执行，
##    而面板可能在还没进树时就被 `open()`（测试、将来"面板池预建"也会这样）。
##    那一刻 `_build` 没跑过 -> 里面每个控件都还是 null ->
##    `open()` 第一行就 `Invalid assignment ... on a base object of type 'Nil'`。
##    （这不是猜的：s17 的 UI 冒烟测试真跑出来了，而且报错位置极具误导性。）
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


## Control 直接挂 CanvasLayer 下时锚点解析不到父矩形 -> size 停在 (0,0)，
## 面板整个看不见（本项目已因此栽过三次）。必须自己钉尺寸。
func _fit_viewport() -> void:
	# ⚠️ 不在树里时 `get_viewport_rect()` 会报 "!is_inside_tree()" 引擎错误，
	#    所以先判在不在树（面板能脱离树建出来，测试才干净）。
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
	bg.color = UITokens.fade(UITokens.BG_DEEP, 0.96)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.add_theme_constant_override("separation", 3)
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
	_title = _mk("改枪", 22, UITokens.TEXT_HI)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_close_btn = TouchButton.new()
	_close_btn.label_text = "返回"
	_close_btn.use_hold = false
	_close_btn.base_radius = 26.0
	_close_btn.custom_minimum_size = Vector2(130, 64)
	_close_btn.accent = UITokens.DANGER
	_close_btn.pressed_down.connect(close)
	row.add_child(_close_btn)

	# 有效数值摘要（"改装真的生效了吗" —— 必须一眼看得见）
	var sm := MarginContainer.new()
	sm.add_theme_constant_override("margin_left", 20)
	sm.add_theme_constant_override("margin_right", 20)
	col.add_child(sm)
	_stats = _mk("", 14, UITokens.ACCENT)
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sm.add_child(_stats)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(sc)
	var inner_margin := MarginContainer.new()
	inner_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner_margin.add_theme_constant_override("margin_left", 20)
	inner_margin.add_theme_constant_override("margin_right", 20)
	sc.add_child(inner_margin)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	inner_margin.add_child(_list)

	_hint = _mk("", 13, UITokens.TEXT)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 20)
	hm.add_theme_constant_override("margin_bottom", 8)
	hm.add_child(_hint)
	col.add_child(hm)


## 打开。attachments 是候选池（技术验证期传全量 = 全开放）。
func open(hideout: Hideout, weapons: Dictionary, attachments: Dictionary,
		slot_limit: int = WeaponModding.SLOTS_C) -> void:
	_ensure_built()
	_hideout = hideout
	_weapons = weapons
	_attachments = attachments
	_slot_limit = slot_limit
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_hint.text = "点配件装上 / 点已装的卸下 · 配件不占背包"
	_refresh()


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _close_btn != null:
		_close_btn.force_release()
	closed.emit()


func _clear() -> void:
	for c in _list.get_children():
		c.queue_free()


func _weapon_id() -> String:
	if _hideout == null or _hideout.loadout == null:
		return ""
	return _hideout.loadout.id_in("weapon")


func _refresh() -> void:
	_clear()
	var wid := _weapon_id()
	if wid == "":
		_title.text = "改枪"
		_stats.text = "武器槽是空的 —— 先在配装里装一把枪"
		return
	var w: WeaponDef = _weapons.get(wid)
	_title.text = "改枪 · %s" % (w.name if w != null else wid)
	var lo: WeaponModding.Loadout = _hideout.loadout.build_loadout(_slot_limit)
	if lo == null:
		_stats.text = "拿不到这把枪的数值（数据缺失）"
		return
	_stats.text = lo.summary()
	if not lo.diff().is_empty():
		_stats.text += "\n改装增量：%s" % _diff_text(lo.diff())

	# ── ① 插槽现状：点已装的 = 卸下 ──
	var cur: Dictionary = _hideout.loadout.mods_of(wid)
	for slot in lo.free_slots:
		var has_it: bool = cur.has(slot)
		var label := "%s：" % _slot_label(slot)
		if has_it:
			var a: AttachmentDef = _attachments.get(str(cur[slot]))
			label += "%s（点一下卸下）" % (a.name if a != null else str(cur[slot]))
		else:
			label += "（空）"
		_list.add_child(_row(label, "", UITokens.ACCENT if has_it
			else UITokens.BORDER, _on_detach_pressed.bind(slot, has_it)))

	# ── ② 候选配件：点一下装到它自己的插槽上 ──
	var ids: Array = _attachments.keys()
	ids.sort()
	var shown := 0
	for id in ids:
		var a2: AttachmentDef = _attachments[id]
		if not lo.free_slots.has(a2.slot):
			continue                  # 这把枪没有这个插槽
		shown += 1
		var tag := "已装" if str(cur.get(a2.slot, "")) == str(id) else "装上"
		_list.add_child(_row("%s\n%s · %s" % [a2.name, _slot_label(a2.slot), _mods_text(a2)],
			tag, UITokens.INFO, _on_attach_pressed.bind(str(a2.slot), str(id))))
	if shown == 0:
		_list.add_child(_mk("（没有可用的配件）", 13, UITokens.TEXT_LOW))


## ⚠️ 槽位/配件 id 一律用 `bind` 传进回调，**不在 lambda 里读循环变量** ——
##    lambda 捕获循环变量的语义容易踩坑（拿到最后一个值），
##    而 `bind` 的参数在**绑定时**就求值，不可能错。
func _on_detach_pressed(slot: String, has_it: bool) -> void:
	_do_detach(slot, has_it)


func _on_attach_pressed(att_slot: String, att_id: String) -> void:
	_do_attach(att_slot, att_id)


## 一行：label + 右侧动作标签。label 用两行（名字 / 数值），手机上好点。
func _row(label: String, tag: String, accent: Color, cb: Callable) -> Control:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 22.0
	b.custom_minimum_size = Vector2(0, 52)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.label_text = label if tag == "" else "%s\n%s" % [label, tag]
	b.accent = accent
	b.pressed_down.connect(cb)
	return b


func _do_attach(att_slot: String, att_id: String) -> void:
	if _hideout == null or _hideout.loadout == null:
		return
	var err := _hideout.loadout.set_mod(_weapon_id(), att_slot, att_id)
	_after(err, "装上")


func _do_detach(att_slot: String, has_it: bool) -> void:
	if not has_it:
		_hint.text = "这个插槽是空的"
		return
	if _hideout == null or _hideout.loadout == null:
		return
	var err := _hideout.loadout.set_mod(_weapon_id(), att_slot, "")
	_after(err, "卸下")


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


func _slot_label(slot: String) -> String:
	match slot:
		"sight": return "瞄准镜"
		"muzzle": return "枪口"
		"grip": return "握把"
		"mag": return "弹匣"
	return slot


## 配件改了什么数值（"伤害 +2 / 散布 -0.05"）
func _mods_text(a: AttachmentDef) -> String:
	var parts: Array[String] = []
	for k in a.mods:
		var v := float(a.mods[k])
		var name_ := str(FIELD_LABEL.get(str(k), str(k)))
		if k == "reload_time":
			parts.append("%s %+.2f" % [name_, v])
		elif absf(v) < 1.0:
			parts.append("%s %+.2f" % [name_, v])
		else:
			parts.append("%s %+d" % [name_, int(round(v))])
	return "无变化" if parts.is_empty() else " / ".join(parts)


func _diff_text(d: Dictionary) -> String:
	var parts: Array[String] = []
	var keys: Array = d.keys()
	keys.sort()
	for k in keys:
		var v := float(d[k])
		parts.append("%s %+.2f" % [str(FIELD_LABEL.get(str(k), str(k))), v])
	return " / ".join(parts)
