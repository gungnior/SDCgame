extends Node

## 主菜单 / 藏身处 UI 截图探针（**用场景跑，不用 --script**）
##
## 用法：
##   godot --path . res://test/ui_shot_probe.tscn
##
## ⚠️ 必须用场景模式：`--script` 模式下 autoload（Game/Sfx/Tel）不注册，
##    场景一实例化就 "Identifier not found: Game"。

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://art/_raw"))
	# ① 主菜单
	var menu: Node = load("res://view/main_menu.tscn").instantiate()
	add_child(menu)
	await _frames(40)
	_shot("res://art/_raw/_main_menu.png")
	_report(menu)
	menu.queue_free()
	await _frames(3)

	# ② 主菜单 -> 设置
	var menu2: Node = load("res://view/main_menu.tscn").instantiate()
	add_child(menu2)
	await _frames(30)
	var sm: Node = menu2.get("_settings")
	if sm != null:
		sm.call("open")
		await _frames(20)
		_shot("res://art/_raw/_main_menu_settings.png")
	menu2.queue_free()
	await _frames(3)

	# ③ 藏身处（新的选图 / 修理区）
	var hs: Node = load("res://view/hideout_scene.tscn").instantiate()
	add_child(hs)
	await _frames(40)
	_shot("res://art/_raw/_hideout.png")
	_report(hs)
	hs.queue_free()
	await _frames(3)

	get_tree().quit(0)


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("截图：%s  %dx%d" % [path, img.get_width(), img.get_height()])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 报告带文字的控件是否完整落在视口内（按钮被挤出屏幕是历史高发问题）
func _report(n: Node) -> void:
	var vp := get_viewport().get_visible_rect().size
	print("=== 视口 %s ===" % str(vp))
	_report_rec(n, vp)


func _report_rec(n: Node, vp: Vector2) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).visible:
			var txt := ""
			if c.get("label_text") != null:
				txt = str(c.get("label_text"))
			elif c.get("text") != null:
				txt = str(c.get("text"))
			if txt != "":
				var ctl := c as Control
				var r := Rect2(ctl.global_position, ctl.size)
				var full := r.position.y >= -1.0 and r.end.y <= vp.y + 1.0 \
					and r.position.x >= -1.0 and r.end.x <= vp.x + 1.0
				var part := r.position.y < vp.y and r.end.y > 0.0 \
					and r.position.x < vp.x and r.end.x > 0.0
				print("  %s %-14s pos=(%.0f,%.0f) size=(%.0f,%.0f)  %s" % [
					"OK " if full else ("部分" if part else "**外**"),
					txt.replace("\n", "|").substr(0, 14),
					r.position.x, r.position.y, r.size.x, r.size.y,
					"完整可见" if full else ("部分可见" if part else "在视口外")])
		_report_rec(c, vp)
