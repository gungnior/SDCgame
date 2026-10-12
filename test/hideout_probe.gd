extends Node

## 藏身处布局探针 —— 验证「开始下一局」按钮是否可见。
##
## 动机：藏身处早先把所有内容塞进一个 VBox，
## 640x360 下内容总高约 586px -> **「出发」按钮被挤出屏幕**。
##
## 用法：godot --path . res://test/hideout_probe.tscn

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://art/_raw"))
	var scene: Node = load("res://view/hideout_scene.tscn").instantiate()
	add_child(scene)
	await _frames(30)

	var vp := get_viewport().get_visible_rect().size
	print("=== 视口 %s ===" % str(vp))
	print("根 Control size=%s" % str(scene.get("size")))
	print("=== 带文字的控件是否在视口内 ===")
	_report(scene, vp)

	var img := get_viewport().get_texture().get_image()
	img.save_png("res://art/_raw/_hideout.png")
	print("截图：res://art/_raw/_hideout.png  %dx%d" % [img.get_width(), img.get_height()])
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
