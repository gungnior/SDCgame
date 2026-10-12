extends SceneTree

## 截图工具 —— 把游戏画面渲染出来存成 PNG
##
## 为什么需要：headless 没有渲染器，看不到任何画面。
## 这个脚本开真窗口跑若干帧，把 viewport 读回来存盘，用于人工验收。
##
## 运行（不能加 --headless）：
##   godot --path . --script res://test/screenshot.gd
##   godot --path . --script res://test/screenshot.gd -- --frames 120 --out user://shot.png

var _frames := 0
var _target := 90
var _out := "res://art/_raw/_screenshot.png"
var _scene = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--frames" and i + 1 < args.size():
			_target = int(args[i + 1]); i += 2
		elif args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]; i += 2
		else:
			i += 1

	var ps: PackedScene = load("res://view/raid_scene.tscn")
	if ps == null:
		print("加载场景失败")
		quit(1)
		return
	_scene = ps.instantiate()
	root.add_child(_scene)
	print("已实例化场景，等待 %d 帧后截图" % _target)


func _process(_delta: float) -> bool:
	_frames += 1
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
