extends Node

## 结算面板探针 —— 我改了它的锚点策略（去掉 FULL_RECT，改零锚点手动钉尺寸），
## **必须验证它仍然铺满全屏**，不能只看警告消失。

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://art/_raw"))
	var scene: Node = load("res://view/raid_scene.tscn").instantiate()
	add_child(scene)
	await _f(40)

	var ro: Node = scene.get("result_overlay")
	if ro == null:
		print("❌ 拿不到 result_overlay")
		get_tree().quit(1)
		return

	# 直接让它显示（模拟阵亡结算）
	ro.call("_fit_viewport")
	ro.call("show_result", false, ["死因：测试", "携带的 3 格装备全部丢失（价值 120 元）", "击杀 2   搜刮容器 1", "地图种子 12345"])
	await _f(16)
	ro.call("_fit_viewport")
	await _f(6)

	var vp := get_viewport().get_visible_rect().size
	print("=== 视口 %s ===" % str(vp))
	print("  overlay size=%s  visible=%s" % [str(ro.get("size")), str(ro.get("visible"))])
	var panel: Node = ro.get("_panel")
	if panel != null:
		var p := panel as Control
		print("  遮罩 pos=%s size=%s" % [str(p.position), str(p.size)])
		var covers := p.size.x >= vp.x - 1.0 and p.size.y >= vp.y - 1.0
		print("  %s 遮罩铺满视口" % ("✅" if covers else "❌"))
	_report(ro, vp)

	get_viewport().get_texture().get_image().save_png("res://art/_raw/_result.png")
	print("截图：res://art/_raw/_result.png")
	get_tree().quit(0)


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _report(n: Node, vp: Vector2) -> void:
	for c in n.get_children():
		if c is Control and (c as Control).visible:
			var txt := str(c.get("label_text")) if c.get("label_text") != null else ""
			if txt == "" and c is Label:
				txt = str((c as Label).text)
			if txt != "":
				var ctl := c as Control
				var r := Rect2(ctl.global_position, ctl.size)
				var full := r.position.y >= -1.0 and r.end.y <= vp.y + 1.0 \
					and r.position.x >= -1.0 and r.end.x <= vp.x + 1.0
				print("  %s %-26s pos=(%.0f,%.0f) size=(%.0f,%.0f)" % [
					"OK " if full else "部分",
					txt.replace("\n", "|").substr(0, 26),
					r.position.x, r.position.y, r.size.x, r.size.y])
		_report(c, vp)
