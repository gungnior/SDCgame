class_name RaidPlayerActions
extends RefCounted

## 玩家的「输入 → 场景动作」—— 从 `view/raid_scene.gd` 分出来的第一刀（2026-10-13）
##
## ─── 为什么拆 ───
## `raid_scene.gd` 一度是 1676 行的上帝对象；拆过一轮之后又长回约 1380 行。
## 按 AGENTS.md §4.5 的「大文件阈值」：超过约 1000 行就是"一次只能一个人动"的文件，
## 该按既有分节**纯搬运**地拆 —— 本文件就是那一刀，**不改任何行为**。
##
## ─── 装什么、不装什么 ───
## 只装"由按键 / 按钮触发、直接落在场景上"的动作：闪避、自动作战开关，以及它们依赖的冻结判定。
## **判定逻辑不在这里** —— 闪避在 `sim/combat/dodge.gd`，自动作战在 `sim/ai/player_autopilot.gd`；
## 本模块只负责把输入接到它们身上。
##
## ⚠️ 仍然是 `scene.xxx` 鸭子类型（与 raid_sim_runner / raid_drawer / raid_hud 同款）——
##    这是本工程的既有约定，本次拆分不改它。

## 宿主场景（RaidScene）。无类型：duck typing 读场景自定义成员。
var scene = null


## 覆盖层（背包 / 地图）打开时不接受战场操作 —— 与 raid_scene._process 的冻结口径一致。
func frozen_by_overlay() -> bool:
	if scene == null:
		return true
	if scene.inventory_panel != null and scene.inventory_panel.is_open():
		return true
	return scene.map_panel != null and scene.map_panel.is_open()


## 闪避（用户需求：位移 1.5 倍人物身位）。
##
## 方向取「正在推的方向」—— 与移动同一套输入，符合"操作方式沿用既有手感"；
## 没推方向时用瞄准方向（桌面用鼠标瞄准时就是这个）。
## 触发条件（冷却 / 时长 / 无敌帧）全在 DodgeState 里，这里只负责给方向。
func try_dodge() -> void:
	if scene == null or scene.dodge == null or scene.raid == null or scene.raid.is_over():
		return
	if scene.game_paused or (Game != null and Game.paused) or frozen_by_overlay():
		return
	# ── 任意方向闪避（2026-10-13 用户需求）──
	# 优先取**方向摇杆的原始向量**（只有触屏有）：它可以是任意角度，
	# 所以「推着摇杆 + 点闪避」= 朝那个方向闪。
	# 放在 _move_input 之前，是为了让玩家在"自动作战接管移动"时仍能自己决定闪避方向。
	var dir := Vector2.ZERO
	if scene.touch != null:
		dir = scene.touch.move_vector()
	if dir.length() < 0.15:
		dir = scene._move_input
	if dir.length() < 0.15:
		dir = scene.player_aim
	if not scene.dodge.start(dir):
		return
	if Sfx != null:
		Sfx.play("ui_click")


## 自动作战开关（用户需求：自动寻路 / 自动搜刮 / 自动攻击）。
## 设置持久在 Game（跨场景），这里只做切换与提示。
func toggle_autopilot() -> void:
	if Game == null or scene == null:
		return
	Game.autopilot = not Game.autopilot
	if not Game.autopilot:
		scene._move_input = Vector2.ZERO
	if Sfx != null:
		Sfx.play("ui_click" if Game.autopilot else "ui_deny")
	scene._toast("自动作战：%s" % ("开 —— 自动寻路 / 自动搜刮 / 自动交火" if Game.autopilot else "关"))
