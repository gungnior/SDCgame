extends Control

## 藏身处场景（真机反馈 #7）
##
## 用户原话："完善藏身处系统。比如死亡后点击的藏身处，玩家可以真正的返回，
##            而不是重启战局。"
##
## 所以它是一个**独立场景**，不是突袭场景里的一个弹窗：
##   突袭（死亡/撤离）-> 结算界面点「回藏身处」-> 切到这个场景
##   这个场景点「出发」-> 切回突袭场景（新地图、新种子）
##
## 持久状态放在 Game（autoload）里，场景切换不会丢。
##
## 布局刻意用最简单的纵向列表 —— 技术验证阶段先要"能用"。

const CELL := 4.0

var _root: VBoxContainer
var _wallet_label: Label
var _stash_label: Label
var _status: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.07, 0.08, 0.10))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if Game != null:
		Game.ensure_loaded()
		Game.apply_accessibility()
	_build()
	_refresh()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	_root = VBoxContainer.new()
	_root.add_theme_constant_override("separation", 8)
	margin.add_child(_root)

	_root.add_child(_title("藏身处", 30, Color(0.94, 0.96, 1.0)))

	_wallet_label = _title("", 18, Color(0.95, 0.82, 0.40))
	_root.add_child(_wallet_label)

	_root.add_child(_title("仓库", 16, Color(0.70, 0.78, 0.90)))
	_stash_label = _title("", 14, Color(0.80, 0.84, 0.90))
	_stash_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stash_label.custom_minimum_size = Vector2(0, 90)
	_root.add_child(_stash_label)

	_root.add_child(_title("升级", 16, Color(0.70, 0.78, 0.90)))
	var ups := HBoxContainer.new()
	ups.add_theme_constant_override("separation", 10)
	_root.add_child(ups)
	for id in Hideout.UPGRADES.keys():
		ups.add_child(_make_upgrade_button(id))

	_root.add_child(_title("辅助瞄准", 16, Color(0.70, 0.78, 0.90)))
	var toggles := HBoxContainer.new()
	toggles.add_theme_constant_override("separation", 10)
	_root.add_child(toggles)
	toggles.add_child(_make_toggle("自动射击", "auto_fire"))
	toggles.add_child(_make_toggle("自动瞄准", "auto_aim"))
	toggles.add_child(_make_toggle("视野跟随", "vision_follows_lock"))

	_status = _title("", 14, Color(0.55, 0.90, 0.62))
	_root.add_child(_status)

	# 出发按钮 —— 放到最后，占满宽
	var go := TouchButton.new()
	go.label_text = "出 发"
	go.icon_text = "▶"
	go.use_hold = false
	go.accent = Color(0.42, 0.82, 0.52)
	go.base_radius = 40.0
	go.custom_minimum_size = Vector2(0, 110)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed_down.connect(_on_go)
	_root.add_child(go)


func _title(txt: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


func _make_upgrade_button(id: String) -> TouchButton:
	var u: Dictionary = Hideout.UPGRADES[id]
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 30.0
	b.custom_minimum_size = Vector2(112, 96)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("upgrade_id", id)
	b.pressed_down.connect(_on_upgrade.bind(id))
	_refresh_upgrade_button(b, id)
	return b


func _refresh_upgrade_button(b: TouchButton, id: String) -> void:
	var h := _hideout()
	if h == null:
		return
	var u: Dictionary = Hideout.UPGRADES[id]
	var lv := h.level_of(id)
	var mx := h.max_level_of(id)
	var cost := h.upgrade_cost(id)
	b.label_text = "%s\nLv%d/%d\n%s" % [
		str(u["name"]), lv, mx,
		"满级" if cost < 0 else "%d 元" % cost]
	b.accent = Color(0.42, 0.72, 0.95) if cost >= 0 and h.wallet >= cost else Color(0.45, 0.48, 0.55)


func _make_toggle(label: String, key: String) -> TouchButton:
	var b := TouchButton.new()
	b.use_hold = false
	b.base_radius = 30.0
	b.custom_minimum_size = Vector2(112, 76)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.set_meta("setting_key", key)
	b.pressed_down.connect(_on_toggle.bind(key))
	_refresh_toggle_button(b, key, label)
	return b


func _refresh_toggle_button(b: TouchButton, key: String, label: String) -> void:
	var on := bool(Game.get(key)) if Game != null else false
	b.label_text = "%s\n%s" % [label, "开" if on else "关"]
	b.accent = Color(0.42, 0.82, 0.52) if on else Color(0.45, 0.48, 0.55)


func _hideout() -> Hideout:
	return Game.hideout if Game != null else null


func _refresh() -> void:
	var h := _hideout()
	if h == null:
		_status.text = "数据未加载"
		return
	_wallet_label.text = "资金  %d 元" % h.wallet
	# 仓库清单（按价值从高到低，只列前若干项避免刷屏）
	# ⚠️ Inventory 没有公开的 items 字典，必须从 slots 汇总
	#    （实测踩过：直接访问 h.stash.items 会 Invalid access）
	var counts: Dictionary = {}
	for s in h.stash.slots:
		if s == null:
			continue
		counts[str(s["item_id"])] = int(counts.get(str(s["item_id"]), 0)) + int(s["count"])
	var entries: Array = []
	for item_id in counts:
		var n: int = int(counts[item_id])
		if n <= 0:
			continue
		var d: ItemDef = Game.reg.items.get(item_id)
		entries.append([item_id, n, 0 if d == null else d.value * n,
			0 if d == null else str(d.name)])
	entries.sort_custom(func(a, b): return a[2] > b[2])
	var lines: Array[String] = []
	lines.append("槽位 %d/%d · 共 %d 种" % [h.stash.used_slots(), h.stash.slot_count(), entries.size()])
	for e in entries.slice(0, 10):
		lines.append("  %s x%d" % [e[3], e[1]])
	if entries.size() > 10:
		lines.append("  …还有 %d 种" % (entries.size() - 10))
	_stash_label.text = "\n".join(lines)
	_status.text = ""


func _on_upgrade(id: String) -> void:
	var h := _hideout()
	if h == null:
		return
	var err := h.buy_upgrade(id)
	_status.text = "升级成功" if err == "" else err
	if Sfx != null:
		Sfx.play("ui_confirm" if err == "" else "ui_deny")
	# 刷新所有升级按钮（价格会变）
	for c in _root.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				if b is TouchButton and b.has_meta("upgrade_id"):
					_refresh_upgrade_button(b, str(b.get_meta("upgrade_id")))
	_refresh()


func _on_toggle(key: String) -> void:
	if Game == null:
		return
	Game.set(key, not bool(Game.get(key)))
	if Sfx != null:
		Sfx.play("ui_click")
	for c in _root.get_children():
		if c is HBoxContainer:
			for b in c.get_children():
				if b is TouchButton and b.has_meta("setting_key"):
					var k := str(b.get_meta("setting_key"))
					_refresh_toggle_button(b, k, _label_for_key(k))
	_refresh()


func _label_for_key(k: String) -> String:
	match k:
		"auto_fire": return "自动射击"
		"auto_aim": return "自动瞄准"
		"vision_follows_lock": return "视野跟随"
	return k


func _on_go() -> void:
	if Sfx != null:
		Sfx.play("ui_confirm")
	if Game != null:
		Game.start_raid()


func _input(event: InputEvent) -> void:
	# 桌面调试：回车/空格出发
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_SPACE):
			_on_go()
