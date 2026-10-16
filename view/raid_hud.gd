class_name RaidHud
extends CanvasLayer

## 突袭 HUD —— 从 `view/raid_scene.gd` 抽出来
##
## ─── 为什么抽 ───
## `raid_scene.gd` 曾长到 **1676 行 / 51 个函数 / 89 个顶层变量**，
## 而统计 36 次提交有 **50% 都要改它**。其中 `_update_hud()` 是**纯追加型**函数 ——
## 每加一个统计量就要改它一次；`_draw()` 同理。
## 这两处是 raid_scene.gd 上最大的冲突面，所以优先切出来。
##
## ─── 怎么访问场景状态 ───
## `scene` **故意不加类型**（duck typing）：
## 用 `Node2D` 类型的话，GDScript 在编译期就会拒绝 `scene.player_pos` 这类
## 场景自定义成员；不加类型则留到运行期解析。
## 这样搬过来的代码几乎只需要把 `vitals` 改成 `scene.vitals`。
## （代价：写错名字要到运行时才报错 —— 所以每次改完必须真跑场景验证。）

## 宿主场景（RaidScene）。无类型，见上面的说明。
var scene = null
var is_touch := false
var hud_fs := 13

var hud_label: Label = null
var hint_label: Label = null
var view_label: Label = null
var corpse_label: Label = null
var toast_label: Label = null

## 短提示状态（手机上唯一的即时反馈渠道）
var toast_text := ""
var toast_until := 0.0

## 文本缓存：只在变化时才赋给 Label.text
##
## ⚠️ Godot 里给 `Label.text` 赋值（**哪怕值相同**）也会触发
##    `update_minimum_size` -> 布局重算。每帧都设是移动端常见的隐形开销
##    （真机"自动开火卡顿"的次要来源）。
var _cache_hud := ""
var _cache_view := ""
var _cache_hint := ""
var _cache_toast := ""
var _cache_corpse := ""
var _cache_silent := ""


## 建立全部 HUD 控件。由场景在 _setup_view() 里调用。
func setup(p_is_touch: bool) -> void:
	is_touch = p_is_touch
	# 手机上字号要更大（真机反馈：默认 13px 在手机上偏小）
	hud_fs = 16 if is_touch else 13

	hud_label = Label.new()
	# ⚠️ 触屏时左上角有【齿轮按钮】（打开设置/暂停），HUD 第一行会被它压住。
	#    实测截图里 "HP 100/100" 的 H 直接被齿轮盖掉。
	hud_label.position = Vector2(64 if is_touch else 10, 6)
	hud_label.add_theme_font_size_override("font_size", hud_fs)
	hud_label.add_theme_color_override("font_color", UITokens.TEXT_HI)
	# 深色描边：HUD 直接压在战斗画面上，没描边时浅色文字遇上亮地面就读不出来
	# （加描边而不是加底板 —— 不占布局、不会改变任何已有位置基线）
	hud_label.add_theme_constant_override("outline_size", 3)
	hud_label.add_theme_color_override("font_outline_color", UITokens.BG_DEEP)
	add_child(hud_label)

	# ⚠️ 底部两行必须【锚定到左下】而不是写死 y 坐标。
	#    改成 stretch/aspect="expand" 后，视口高度会随设备比例变化，
	#    写死 342 在长屏上会飘到屏幕中间（真机踩过）。
	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_label.position = Vector2(10, -20)
	hint_label.add_theme_font_size_override("font_size", hud_fs - 2)
	hint_label.add_theme_color_override("font_color", UITokens.TEXT_MID)
	hint_label.add_theme_constant_override("outline_size", 2)
	hint_label.add_theme_color_override("font_outline_color", UITokens.BG_DEEP)
	add_child(hint_label)

	view_label = Label.new()
	view_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	view_label.position = Vector2(10, -38)
	view_label.add_theme_font_size_override("font_size", hud_fs - 2)
	view_label.add_theme_color_override("font_color", UITokens.TEXT_MID)
	view_label.add_theme_constant_override("outline_size", 2)
	view_label.add_theme_color_override("font_outline_color", UITokens.BG_DEEP)
	add_child(view_label)

	toast_label = Label.new()
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(-160, 56)
	toast_label.size = Vector2(320, 24)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.add_theme_font_size_override("font_size", hud_fs)
	toast_label.add_theme_color_override("font_color", UITokens.ACCENT)
	toast_label.add_theme_constant_override("outline_size", 3)
	toast_label.add_theme_color_override("font_outline_color", UITokens.BG_DEEP)
	toast_label.visible = false
	add_child(toast_label)


## 弹一条短提示（2 秒）。手机上唯一的即时反馈渠道。
func toast(msg: String, seconds: float = 2.0) -> void:
	toast_text = msg
	toast_until = (scene._time if scene != null else 0.0) + seconds
	if Tel != null:
		Tel.emit("toast", {"msg": msg})


## 搜索/背包的按键提示文案（触屏与 PC 不同）
func bag_key_hint() -> String:
	return "背包按钮" if is_touch else "B"


## 结算界面弹出时整体收起（否则会和结算文字叠在一起）
func set_all_visible(v: bool) -> void:
	if hud_label != null:
		hud_label.visible = v
	if hint_label != null:
		hint_label.visible = v
	if view_label != null:
		view_label.visible = v


## 每帧刷新全部 HUD 文本。原 `raid_scene._update_hud()`。
func refresh() -> void:
	if scene == null or scene.raid == null:
		return
	var raid = scene.raid
	var vitals = scene.vitals
	var lines: Array[String] = []
	lines.append("HP %d/%d   护甲 %d/%d   %s" % [
		vitals.hp, vitals.max_hp, vitals.armor, vitals.max_armor,
		Vitals.BLEED_NAME[vitals.bleed]])
	# 当前地图主题（森林 / 城区 / 军事基地）。theme 为 null 时不加这一行，
	# 保证旧的无主题场景 HUD 文本逐字不变（不破坏既有布局基线）。
	if scene.theme != null:
		lines.append("地图 %s  %d×%d  威胁 %.1f" % [
			scene.theme.name, scene.theme.map_w, scene.theme.map_h,
			scene.theme.enemy_density])
	# 肉鸽：本局规则变体（roguelite 仪式感——开局就让玩家看到"这局什么规则"）。
	# 无变体时一行不加，旧场景 HUD 文本逐字不变（与上面 theme 行同一纪律）。
	if raid.run_mods != null and not raid.run_mods.is_empty():
		lines.append("本局变体  %s" % raid.run_mods.summary())
	lines.append("弹药 %d / %d%s" % [
		scene.player_weapon.ammo_in_mag, scene.player_weapon.reserve_ammo,
		"  [换弹中]" if scene.player_weapon.is_reloading() else ""])
	# 装备（装备系统）。**只在身上真有东西时才加这一行** ——
	# 空配装（含回退默认枪的情况）HUD 与以前逐字一致，不动已有的布局基线。
	var eqt := _equip_text(raid.equipment)
	if eqt != "":
		lines.append("装备 %s" % eqt)
	lines.append("剩余 %ds    撤离 %.0f%%" % [
		int(raid.time_left), raid.extract_progress_ratio() * 100.0])
	# ⭐ 撤离点关闭预警（可玩性 Step1）：不提前告诉玩家「有个点要关了」，
	#   他只会觉得撤离点莫名其妙消失 —— 那是 bug 感，不是张力。
	var ex_left: float = raid.next_extract_close_in()
	if ex_left > 0.0:
		lines.append("撤离点 %d 个可用    %.0fs 后关闭一个" % [
			raid.active_extract_count(), ex_left])
	elif raid.active_extract_count() < raid.extract_points.size():
		lines.append("撤离点仅剩 %d 个（最近的已关闭）" % raid.active_extract_count())
	lines.append("携带 %s" % raid.carry.summary())
	lines.append("击杀 %d   受伤 %d   治疗 %s" % [
		raid.enemies_killed, vitals.total_damage_taken, scene.medical.status_text()])
	lines.append("小队警戒 %.2f   %s" % [
		scene.squad.alert_level,
		"交战中" if scene.squad.is_engaged() else ("警觉" if scene.squad.is_alerted() else "放松")])
	# 性能读数（真机排障用：卡顿时可以直接报数字）
	# ⚠️ 这里【不能用 Performance.TIME_PROCESS】—— 真机实测它在 Android 上
	#    给出与 FPS 自相矛盾的值（HUD 显示 "FPS 60  帧 25.2ms"，
	#    而同一时刻遥测的墙钟均值是 16.6ms）。改用 Tel 的墙钟测量值。
	lines.append("FPS %d  平均 %.1f ms  最慢 %.1f ms  敌 %d  音频掉 %d" % [
		int(Engine.get_frames_per_second()),
		0.0 if Tel == null else Tel.last_avg_ms(),
		0.0 if Tel == null else Tel.last_worst_ms(),
		scene.agents.size(),
		0 if Sfx == null else Sfx.dropped_count])

	var dbg := ["普通", "流场方向", "房间图", "声音范围"]
	var over = scene.result_overlay != null and scene.result_overlay.is_shown()
	set_all_visible(not over)
	if over:
		return
	_set_label(hud_label, "\n".join(lines), "_cache_hud")
	_set_label(view_label, "[视图] %s%s" % [dbg[scene.debug_mode],
		"  ·  白模 F5 切换" if scene.render_mode == scene.RENDER_WHITEBOX
		else "  ·  美术 F5 切换"], "_cache_view")

	# ── 附近尸体的交互提示（真机反馈 #4）──
	# 用户："和敌人尸体没法交互。（战利品系统呢）"
	# 尸体其实生成了、也能搜 —— 但**没有可见的入口**，玩家不知道按什么。
	_refresh_corpse_prompt(raid)

	# 短提示
	if toast_label != null:
		# ⚠️ 必须显式标 bool —— `scene` 是无类型的（duck typing），
		#    所以 `scene._time < toast_until` 的结果是 Variant，`:=` 推不出类型。
		var show: bool = scene._time < toast_until
		if toast_label.visible != show:
			toast_label.visible = show
		if show:
			_set_label(toast_label, toast_text, "_cache_toast")

	# ⚠️ 提示必须按平台给（真机反馈：安卓上显示的是 WASD/J/K/L 键盘键位）
	# ⚠️ 2026-10-13：右半屏改为「十字键位」，视角摇杆与开火键已删除（攻击全自动）。
	var hint := ("左摇杆移动（兼闪避方向）· 右半屏十字：中=闪避 上=换弹 左=治疗 右=背包 下=地图 · 攻击全自动"
		if is_touch
		else "WASD 移动 · Shift 闪避 · G 自动作战 · J/空格 开火 · R 换弹 · T 治疗 · B 背包 · N 地图 · Tab 视图 · K 重开 · ESC 设置 · F1~F4 无障碍 · M 静音")
	_set_label(hint_label, hint, "_cache_hint")


## 身上装备的一行文本。空配装返回 ""（调用方据此不占用 HUD 行数）。
## 这是"穿脱装备生效了"的**可见证据**：从尸体上换一把枪，这行立刻变。
func _equip_text(eq: Equipment) -> String:
	if eq == null or scene == null or scene.reg == null:
		return ""
	var parts: Array[String] = []
	for slot in Equipment.SLOTS:
		var id: String = eq.id_in(slot)
		if id == "":
			continue
		var d: ItemDef = scene.reg.get_item(id)
		parts.append(str(d.name) if d != null else id)
	return "" if parts.is_empty() else " · ".join(parts)


func _refresh_corpse_prompt(raid) -> void:
	if corpse_label == null:
		corpse_label = Label.new()
		corpse_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		corpse_label.position = Vector2(-200, -58)
		corpse_label.size = Vector2(400, 22)
		corpse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		corpse_label.add_theme_font_size_override("font_size", hud_fs + 2)
		corpse_label.add_theme_color_override("font_color", UITokens.ACCENT)
		corpse_label.add_theme_constant_override("outline_size", 3)
		corpse_label.add_theme_color_override("font_outline_color", UITokens.BG_DEEP)
		corpse_label.visible = false
		add_child(corpse_label)
	var ci_near: int = raid.corpse_near(scene.player_pos)
	var xi_near: int = raid.container_near(scene.player_pos)
	if raid.is_over() or (ci_near < 0 and xi_near < 0):
		if corpse_label.visible:
			corpse_label.visible = false
		return
	# 尸体与容器都提示，取更近的那个（和 _open_bag 的选法一致，不然提示会跳）
	var d_c := 999.0
	var d_x := 999.0
	if ci_near >= 0:
		d_c = (raid.corpses[ci_near]["pos"] as Vector2).distance_to(scene.player_pos)
	if xi_near >= 0:
		d_x = raid.containers[xi_near].pos.distance_to(scene.player_pos)
	if ci_near >= 0 and (xi_near < 0 or d_c <= d_x):
		var n_stacks := (raid.corpses[ci_near]["drops"] as Array).size()
		_set_label(corpse_label, "[%s] 搜索尸体 · %d 堆战利品"
			% [bag_key_hint(), n_stacks], "_cache_corpse")
	else:
		var c = raid.containers[xi_near]
		_set_label(corpse_label, "[%s] 搜索%s · %d 堆物资"
			% [bag_key_hint(), c.display_name(), (c.drops as Array).size()], "_cache_corpse")
	corpse_label.visible = true


## 只在文本真的变了才写 Label.text（见 _cache_* 的说明）
func _set_label(l: Label, txt: String, cache_key: String) -> void:
	if l == null:
		return
	if get(cache_key) == txt:
		return
	set(cache_key, txt)
	l.text = txt
