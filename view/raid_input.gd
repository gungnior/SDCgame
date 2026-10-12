class_name RaidInput
extends RefCounted

## 突袭场景的键盘输入 —— 从 `view/raid_scene.gd` 抽出来
##
## ─── 为什么抽 ───
## `_input()` 是**追加型**代码：每加一个键位就要往里塞一个 `match` 分支。
## 拆开之后，加键位改 `raid_input.gd`（本文件），不再碰 1200 行的场景。
##
## ─── 边界 ───
## 本模块只负责「**什么键 -> 什么动作**」的分派；
## 动作本身（装弹 / 治疗 / 开背包 / 重开）仍由场景执行，
## 因为它们要读写模拟状态。所以这里通过 `scene` 回调过去。
##
## ⚠️ **故意不处理 InputEventScreenTouch。**
##    早先（还没有触屏控件时）场景把"右半屏任意触摸"当作开火，
##    真机反馈的三个问题全是它导致的：
##      ① 按右侧任意位置就开火
##      ② 点瞄准摇杆就开火（它就在右半屏）
##      ③ 按"治疗"也开火 -> 治疗永远点不到
##    现在摇杆（VirtualJoystick）与按钮（TouchButton）各自通过 GUI 系统接管触摸，
##    这里只留键盘。
##
## ⚠️ **ESC 不在这里处理。** 它由 `ui/settings_menu.gd` 独占
##    （见那个文件的 `_input`），这里也处理会 toggle 两次等于没开。

## 宿主场景（RaidScene）。无类型：duck typing 读场景自定义成员。
var scene = null


## 按下：分派动作
func handle_key(event: InputEvent) -> void:
	if scene == null:
		return
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return

	# ── 键位（用户第三轮 PC 实测指定：R 装弹 / K 重开 / T 治疗）──
	# 完整说明在 ESC 设置菜单里（用户："f1 到 f4 没有说明"）
	match k.keycode:
		KEY_J, KEY_SPACE:
			scene._firing = true
		KEY_R:
			scene.player_weapon.start_reload()
		KEY_T:
			scene._try_heal()
		KEY_B:
			scene._open_bag()
		KEY_K:
			scene._restart()
		KEY_TAB:
			scene.debug_mode = (scene.debug_mode + 1) % 4
		KEY_F5:
			# 白模 <-> 美术 tile 切换（技术验证期间主要看白模）
			scene.render_mode = (scene.RENDER_ART if scene.render_mode == scene.RENDER_WHITEBOX
				else scene.RENDER_WHITEBOX)
			scene._build_map_texture()
			if Sfx != null:
				Sfx.play("ui_click")
		# ── 无障碍开关（spec §7.3 第 4 条：务必提供关闭/降低震动的选项）──
		KEY_F1:
			Feel.shake_enabled = not Feel.shake_enabled
			if Sfx != null:
				Sfx.play("ui_click")
		KEY_F2:
			Feel.hitstop_enabled = not Feel.hitstop_enabled
			if not Feel.hitstop_enabled:
				Engine.time_scale = 1.0
			if Sfx != null:
				Sfx.play("ui_click")
		KEY_F3:
			Feel.flash_enabled = not Feel.flash_enabled
			if Sfx != null:
				Sfx.play("ui_click")
		KEY_F4:
			Feel.intensity = 0.0 if Feel.intensity > 0.5 else 1.0
			if Sfx != null:
				Sfx.play("ui_click")
		KEY_M:
			if Sfx != null:
				Sfx.enabled = not Sfx.enabled


## 松手：结束持续动作（开火是"按住"的）
func handle_key_release(event: InputEvent) -> void:
	if scene == null:
		return
	if event is InputEventKey and not (event as InputEventKey).pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_J or k.keycode == KEY_SPACE:
			scene._firing = false
