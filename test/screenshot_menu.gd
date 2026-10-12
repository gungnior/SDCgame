extends SceneTree

## 打开设置菜单后截图，用来验证"继续"按钮是否可见。
##
## ⚠️ 为什么专门写这个：用户反馈"esc 了看不到继续"，
##    而我当时只能靠读代码猜布局。截图能直接看到结果。
##
## 用法：
##   godot --path . --script res://test/screenshot_menu.gd

func _init() -> void:
	var out_dir := "res://art/_raw"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var scene: Node = load("res://view/raid_scene.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	# 让场景跑几帧把 UI 建好
	for i in 30:
		await process_frame

	# 打开设置菜单
	var sm: Node = scene.get("settings_menu")
	if sm == null:
		print("❌ 拿不到 settings_menu")
		quit(1)
		return
	sm.call("open")
	for i in 20:
		await process_frame

	# 等一帧让布局生效
	await process_frame
	await process_frame

	# 报告关键控件的可达性 —— 这是"看不看得到继续"的客观判据
	var vp := root.get_viewport().get_visible_rect().size
	print("视口: %s" % str(vp))
	print("菜单 visible=%s  size=%s  pos=%s" % [
		sm.get("visible"), str(sm.get("size")), str(sm.get("position"))])

	var found := 0
	_report(sm, vp, found)

	var img := root.get_texture().get_image()
	var path := out_dir + "/_menu.png"
	img.save_png(path)
	print("截图已保存：%s  %dx%d" % [path, img.get_width(), img.get_height()])
	quit(0)


## 递归找出所有可见的 TouchButton，报告它们是否真的落在视口内
func _report(n: Node, vp: Vector2, found: int) -> void:
	for c in n.get_children():
		if c is Control and c.get("visible") == true:
			var txt := ""
			if c.get("label_text") != null:
				txt = str(c.get("label_text"))
			if txt != "" and c is Control:
				var r: Rect2 = Rect2((c as Control).global_position, (c as Control).size)
				var in_vp := r.position.y >= 0 and r.end.y <= vp.y \
					and r.position.x >= 0 and r.end.x <= vp.x
				var partial := r.position.y < vp.y and r.end.y > 0
				print("  [%s] %-14s pos=(%.0f,%.0f) size=(%.0f,%.0f) %s" % [
					"✓" if in_vp else ("~" if partial else "✗"),
					txt.replace("\n", "|"), r.position.x, r.position.y,
					r.size.x, r.size.y,
					"完整可见" if in_vp else ("部分可见" if partial else "**在视口外**")])
		_report(c, vp, found)
