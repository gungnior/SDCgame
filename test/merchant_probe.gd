extends Node

## 商人面板探针：验证在售列表真的渲染出来、并且能买能卖。

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://art/_raw"))
	var g: Node = get_node_or_null("/root/Game")
	if g == null:
		print("❌ 拿不到 Game")
		get_tree().quit(1)
		return
	g.call("ensure_loaded")
	var h: RefCounted = g.get("hideout")
	var stash: RefCounted = h.get("stash")
	stash.call("add", "valuables_gpu", 2)
	stash.call("add", "medical_kit", 3)
	h.set("wallet", 99999)

	var scene: Node = load("res://view/hideout_scene.tscn").instantiate()
	add_child(scene)
	await _f(20)
	var mp: Node = scene.get("merchant_panel")
	if mp == null:
		print("❌ 拿不到 merchant_panel")
		get_tree().quit(1)
		return

	var reg: RefCounted = g.get("reg")
	mp.call("open", h, reg.get("items"))
	await _f(20)

	var vp := get_viewport().get_visible_rect().size
	print("=== 视口 %s ===" % str(vp))
	_report(mp, vp)
	get_viewport().get_texture().get_image().save_png("res://art/_raw/_merchant.png")
	print("截图：res://art/_raw/_merchant.png")

	# ── 买卖功能验证 ──
	var before := int(h.get("wallet"))
	var err: String = h.call("buy", "ammo_rifle", 30)
	print("买入 30 发步枪弹 -> '%s'   资金 %d -> %d" % [err, before, int(h.get("wallet"))])
	mp.call("_refresh")
	await _f(8)
	get_viewport().get_texture().get_image().save_png("res://art/_raw/_merchant2.png")
	print("截图2：res://art/_raw/_merchant2.png（买入后右栏应出现步枪弹）")
	get_tree().quit(0)


func _f(n: int) -> void:
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
				print("  %s %-24s pos=(%.0f,%.0f) size=(%.0f,%.0f)" % [
					"OK " if full else "部分",
					txt.replace("\n", "|").substr(0, 24),
					r.position.x, r.position.y, r.size.x, r.size.y])
		_report(c, vp)
