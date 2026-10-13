extends SceneTree

## 截图工具 —— 把游戏画面渲染出来存成 PNG，**并支持可复现**
##
## 为什么需要：headless 没有渲染器，看不到任何画面。
## 这个脚本开真窗口跑若干帧，把 viewport 读回来存盘，用于人工验收。
##
## 运行（不能加 --headless）：
##   godot --path . --script res://test/screenshot.gd
##   godot --path . --script res://test/screenshot.gd -- --frames 120 --out user://shot.png
##
## ─────────────────────────────────────────────────────────────
## ⭐ 可复现模式（为了给重构做**像素级前后对比**）
## ─────────────────────────────────────────────────────────────
## 光固定随机种子**不够**，有三个不确定性来源，都要按住：
##   ① 地图种子 —— 每局随机 -> `--seed N`，并在 `add_child` **之前**注入
##      （`_ready` 里会读 `_raid_seed`，加进去就晚了）
##   ② 每帧 delta —— 真实帧率会抖，实体走的距离就不同
##      -> 用 Godot 自带的 `--fixed-fps 60` 命令行参数（本脚本右侧说明）
##   ③ HUD 里的 FPS / 帧耗时 —— 每次都不同
##      -> `--hide-hud`：截图前把 HUD 与触屏控件藏起来，只比世界部分
##
## 用法：
##   godot --path . --fixed-fps 60 --script res://test/screenshot.gd \
##     -- --seed 12345 --frames 260 --hide-hud --out res://art/_raw/x.png

var _frames := 0
var _target := 90
var _out := "res://art/_raw/_screenshot.png"
var _seed := 0
var _hide_hud := false
var _scene = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--frames" and i + 1 < args.size():
			_target = int(args[i + 1]); i += 2
		elif args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]; i += 2
		elif args[i] == "--seed" and i + 1 < args.size():
			_seed = int(args[i + 1]); i += 2
		elif args[i] == "--hide-hud":
			_hide_hud = true; i += 1
		else:
			i += 1

	var ps: PackedScene = load("res://view/raid_scene.tscn")
	if ps == null:
		print("加载场景失败")
		quit(1)
		return
	_scene = ps.instantiate()
	# ⚠️ 必须在 add_child 之前设：_ready -> _setup_sim 会读 _raid_seed
	if _seed != 0:
		_scene.set("_raid_seed", _seed)
		seed(_seed)          # 同时固定全局 RNG（敌人朝向等用 randf_range）
	root.add_child(_scene)

	if _hide_hud:
		_hide_hud_nodes()

	print("已实例化场景，等待 %d 帧后截图（seed=%d hide_hud=%s）" % [
		_target, _seed, str(_hide_hud)])


## 藏掉 HUD 与触屏控件。
##
## ⚠️⚠️ **必须在每一帧都调用**，而且**不能只靠下面 `_initialize` 里那一次**：
##     HUD 是 `raid_scene._ready() -> _setup_view()` 里才 new 出来的，
##     而这里（`_initialize`）刚 `add_child` 完，`_scene.get("raid_hud")` 还是 **null** ——
##     那一次藏 HUD **静默失效**（`if hud != null` 直接跳过）。
##     后果不是"少了点东西"，而是：
##       ① HUD 一直可见到截图帧，于是"世界像素基线"里混进了 HUD；
##       ② HUD 有一行 `FPS %d 平均 %.1f ms 最慢 %.1f ms` —— **墙钟读数**，
##          天生不可能两次跑一样。
##     实测：修掉它之后，同参数 4 次运行的两两像素差异从 0.018% 直接变成 **0**。
##     （这正是 AGENTS.md 里那条"0.02% 帧时序噪声"的真实来源。）
func _hide_hud_nodes() -> void:
	var hud = _scene.get("raid_hud")
	if hud != null:
		hud.visible = false
	var touch = _scene.get("touch")
	if touch != null:
		touch.visible = false


func _process(_delta: float) -> bool:
	_frames += 1
	# ⭐ 每帧都藏（原因见 _hide_hud_nodes 的注释）
	if _hide_hud:
		_hide_hud_nodes()
	if _frames < _target:
		return false

	var img := root.get_texture().get_image()
	if img == null:
		print("读回画面失败（无渲染器？）")
		quit(1)
		return true

	var abs_path := _out
	if _out.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(_out)
	var err := img.save_png(abs_path)
	if err != OK:
		print("保存失败：%s (err %d)" % [abs_path, err])
		quit(1)
		return true

	print("截图已保存：%s  %dx%d" % [abs_path, img.get_width(), img.get_height()])
	quit(0)
	return true
