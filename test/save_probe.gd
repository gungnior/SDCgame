extends Node

## Game 级存档集成探针
##
## ⚠️ 为什么单独写：`test/run_tests.gd` 跑在 `--script` 模式下，
##    **autoload（Game）不注册**，所以测不到 Game 这一层。
##    用**场景**当主场景跑，autoload 才在。
##
## 用法：godot --headless --path . res://test/save_probe.tscn

func _ready() -> void:
	var g: Node = get_node_or_null("/root/Game")
	if g == null:
		print("❌ 拿不到 Game autoload")
		get_tree().quit(1)
		return

	print("=== 存档路径 ===")
	print("  %s" % str(g.get("save_status")))
	var sm: RefCounted = g.get("save")
	print("  路径: %s" % str(sm.get("path")))
	print("  是否回退路径: %s" % str(sm.get("used_fallback")))

	# 清干净，从新档开始
	sm.call("delete")
	var h: RefCounted = g.get("hideout")
	# ⚠️ 光删文件不够：Game._ready() 在探针跑之前就已经 load_game() 过了，
	#    内存里可能残留上一次运行的状态（实测踩过：等级被累加成 Lv2）。
	#    所以还必须**显式重置内存状态**。
	h.call("from_dict", {"wallet": 8000, "upgrades": {},
		"stash": {"slots": [], "max_weight": 999.0}})
	g.set("stats", {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0})
	print("\n=== 改状态 ===")
	# 注意：这里故意【不再】设 wallet —— 它是 from_dict 给的 8000，
	# 买升级会扣钱，所以要记录"买完之后"的值来断言（见下）。
	h.set("wallet", 8000)
	h.call("buy_upgrade", "stash_size")
	h.call("buy_upgrade", "carry_size")
	var stash: RefCounted = h.get("stash")
	stash.call("add", "medical_bandage", 5)
	stash.call("add", "ammo_rifle", 90)
	# ⚠️ 记下【买完升级之后】的资金再存 ——
	#    第一版直接断言 wallet == 7777，忘了扣升级费用（1500+1200），
	#    结果是我的断言错了，不是存档错了。
	var wallet_before := int(h.get("wallet"))
	print("  资金=%d stash_size=Lv%d carry_size=Lv%d 槽位=%d 负重=%.1f" % [
		wallet_before, h.call("level_of", "stash_size"),
		h.call("level_of", "carry_size"), h.call("slot_count"),
		h.call("carry_weight_limit")])
	g.set("auto_fire", true)
	g.set("auto_aim", false)
	g.set("vision_follows_lock", false)
	g.set("stats", {"raids": 9, "extracts": 6, "deaths": 3, "kills": 42})

	print("\n=== 存档 ===")
	var err: String = g.call("save_game")
	print("  返回: '%s'" % err)
	print("  状态: %s" % str(g.get("save_status")))
	print("  文件存在: %s" % str(sm.call("exists")))

	# ── 模拟"重启"：把状态全部改乱，再读档 ──
	print("\n=== 模拟重启后读档 ===")
	h.set("wallet", 0)
	h.call("from_dict", {"wallet": 0, "upgrades": {}, "stash": {"slots": [], "max_weight": 999.0}})
	g.set("auto_fire", false)
	g.set("auto_aim", true)
	g.set("vision_follows_lock", true)
	g.set("stats", {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0})
	print("  已重置: 资金=%d auto_fire=%s" % [h.get("wallet"), str(g.get("auto_fire"))])

	var ok: bool = g.call("load_game")
	print("  load_game 返回: %s" % str(ok))
	print("  状态: %s" % str(g.get("save_status")))

	# ── 断言 ──
	var fails: Array[String] = []
	if int(h.get("wallet")) != wallet_before:
		fails.append("资金没恢复: %d（期望 %d）" % [int(h.get("wallet")), wallet_before])
	if int(h.call("level_of", "stash_size")) != 1:
		fails.append("stash_size 等级没恢复")
	if int(h.call("level_of", "carry_size")) != 1:
		fails.append("carry_size 等级没恢复")
	if int(stash.call("count_of", "medical_bandage")) != 5:
		fails.append("绷带没恢复")
	if int(stash.call("count_of", "ammo_rifle")) != 90:
		fails.append("弹药没恢复")
	if h.call("slot_count") <= 40:
		fails.append("升级效果没重新应用（槽位还是 %d）" % h.call("slot_count"))
	if not bool(g.get("auto_fire")):
		fails.append("auto_fire 设置没恢复")
	if bool(g.get("auto_aim")):
		fails.append("auto_aim 设置没恢复")
	if bool(g.get("vision_follows_lock")):
		fails.append("vision_follows_lock 设置没恢复")
	var st: Dictionary = g.get("stats")
	if int(st.get("kills", 0)) != 42:
		fails.append("统计没恢复: %s" % str(st))

	print("\n=== 结果 ===")
	if fails.is_empty():
		print("✅ 全部通过（存档往返 + 设置 + 统计 + 升级效果重新应用）")
		sm.call("delete")
		print("（已清理测试存档）")
		get_tree().quit(0)
	else:
		for f in fails:
			print("❌ %s" % f)
		get_tree().quit(1)
