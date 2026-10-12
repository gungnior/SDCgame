extends Node

## 设置菜单布局探针（**用场景跑，不用 --script**）
##
## ⚠️ 为什么不用 `--script`：那种模式下 autoload（Game/Feel/Sfx/Tel）不会注册，
##    突袭场景一实例化就 "Identifier not found: Game"。
##    用场景当主场景跑，autoload 才会正常加载。
##
## 用法：
##   godot --path . res://test/menu_probe.tscn

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://art/_raw"))
	var scene: Node = load("res://view/raid_scene.tscn").instantiate()
	add_child(scene)
	await _frames(40)

	var sm: Node = scene.get("settings_menu")
	if sm == null:
		print("❌ 拿不到 settings_menu")
		get_tree().quit(1)
		return
	sm.call("open")
	await _frames(25)

	var vp := get_viewport().get_visible_rect().size
	print("=== 视口 %s ===" % str(vp))
	print("菜单 visible=%s size=%s" % [sm.get("visible"), str(sm.get("size"))])
	print("=== 带文字的控件是否在视口内 ===")
	_report(sm, vp)

	var img := get_viewport().get_texture().get_image()
	var path := "res://art/_raw/_menu.png"
	img.save_png(path)
	print("截图：%s  %dx%d" % [path, img.get_width(), img.get_height()])
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _report(n: Node, vp: Vector2) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).visible:
			var txt := str(c.get("label_text")) if c.get("label_text") != null else ""
			if txt != "":
				var ctl := c as Control
				var r := Rect2(ctl.global_position, ctl.size)
				var full := r.position.y >= -1.0 and r.end.y <= vp.y + 1.0 \
					and r.position.x >= -1.0 and r.end.x <= vp.x + 1.0
				var part := r.position.y < vp.y and r.end.y > 0.0
				print("  %s %-16s pos=(%.0f,%.0f) size=(%.0f,%.0f)  %s" % [
					"OK " if full else ("部分" if part else "**外**"),
					txt.replace("\n", "|").substr(0, 16),
					r.position.x, r.position.y, r.size.x, r.size.y,
					"完整可见" if full else ("部分可见" if part else "在视口外")])
		_report(c, vp)
