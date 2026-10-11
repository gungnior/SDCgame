extends SceneTree

## 地图生成可视化 —— 把生成结果打到终端
##
## 运行：
##   godot --headless --path . --script res://test/show_map.gd
##   godot --headless --path . --script res://test/show_map.gd -- 42        # 指定 seed
##
## 输出：
##   1. 生成摘要（房间数 / 边数 / 可走格 / 敌人预算）
##   2. ASCII 地图（S = 出生点，E = 撤离点，c = 普通房间中心）
##   3. 从出生点到撤离点的流场方向图（验证寻路真的通）


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_value := 12345
	if args.size() > 0 and args[0].is_valid_int():
		seed_value = int(args[0])

	var reg := DataRegistry.new()
	if not reg.load_all("B"):
		print("数据加载失败：")
		for e in reg.errors:
			print("  ", e)
		quit(1)
		return

	var gen := MapGenerator.new()
	if not gen.generate(seed_value, reg.room_types):
		print("生成失败（seed=%d）：" % seed_value)
		for e in gen.errors:
			print("  ", e)
		quit(1)
		return

	print("")
	print("══════════ 地图生成结果 ══════════")
	print("  %s" % gen.summary())
	var spawn := gen.spawn_room()
	var extracts := gen.extract_rooms()
	print("  出生点   %s  图距离 0" % str(spawn.center))
	for e in extracts:
		print("  撤离点   %s  图距离 %d" % [str(e.center), e.depth])
	print("  房间图距离分布：")
	var buckets := {}
	for r in gen.graph.rooms:
		buckets[r.depth] = int(buckets.get(r.depth, 0)) + 1
	var keys := buckets.keys()
	keys.sort()
	var line := "    "
	for k in keys:
		line += "d%s:%d  " % [str(k), int(buckets[k])]
	print(line)

	print("")
	print("══════════ ASCII 地图（逻辑格）══════════")
	print("  # = 墙   . = 房间地面   + = 走廊   S = 出生点   E = 撤离点")
	print("")
	print(gen.to_ascii())

	# 流场方向图：从出生点朝第一个撤离点
	print("══════════ 流场方向图（出生点 → 撤离点）══════════")
	print("  # = 墙   T = 目标(撤离点)   空格 = 不可达")
	print("")
	var ff := FlowField.new()
	ff.load_from_grid(gen.grid)
	ff.build(extracts[0].center)
	var path := ff.trace_path(spawn.center)
	print("  从出生点到撤离点：%d 格" % path.size())
	print("")
	print(ff.to_ascii_arrows())

	quit(0)
