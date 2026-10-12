extends SceneTree

## 手感 / 触屏修复的自动验证 —— 截图存证
##
## 为什么需要：本轮修的 4 个问题（子弹不可见、死亡卡死无法重开、
## PC 键位提示、出生点贴脸遇敌）**都是真机才暴露的视觉/交互问题**，
## headless 测试查不出来。所以这个脚本强制触发这些状态并截图，供人工核对。
##
## 运行（不能加 --headless）：
##   godot --path . --script res://test/verify_feel.gd

var _scene: Node = null
var _frame := 0
var _stage := 0
var _out_dir := "res://art/_raw/verify"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	var ps: PackedScene = load("res://view/raid_scene.tscn")
	_scene = ps.instantiate()
	root.add_child(_scene)
	print("[验证] 场景已加载，开始分阶段截图")


func _shot(tag: String) -> void:
	var img := root.get_texture().get_image()
	if img == null:
		print("  ✗ 读回画面失败")
		return
	var p := "%s/%s.png" % [_out_dir, tag]
	img.save_png(ProjectSettings.globalize_path(p))
	print("  ✓ %s" % p)


func _process(_delta: float) -> bool:
	_frame += 1
	if _scene == null:
		return true

	match _stage:
		# 阶段 0：等场景初始化完成
		0:
			if _frame >= 60:
				print("[阶段1] 检查出生点是否安全")
				_report_spawn_safety()
				_shot("01_spawn")
				_stage = 1
				_frame = 0

		# 阶段 1：强制持续开火若干帧，抓一张有曳光/枪口火光的画面
		1:
			_scene.set("_firing", true)
			if _frame >= 14:
				_shot("02_firing")
				_scene.set("_firing", false)
				print("[阶段2] 已抓取开火画面（曳光 + 枪口火光 + 粒子）")
				_stage = 2
				_frame = 0

		# 阶段 2：强制玩家死亡，验证结算界面与"不再卡死"
		2:
			if _frame >= 6:
				var raid = _scene.get("raid")
				if raid != null:
					raid.take_damage(99999)
				_stage = 3
				_frame = 0

		3:
			if _frame >= 40:
				var ov = _scene.get("result_overlay")
				var shown: bool = ov != null and bool(ov.is_shown())
				print("[阶段3] 结算界面显示 = %s ; time_scale = %.2f" % [str(shown), Engine.time_scale])
				_shot("03_death")
				_stage = 4
				_frame = 0

		# 阶段 3：点"再来一局"，验证确实是新地图新种子
		4:
			if _frame >= 6:
				var ov = _scene.get("result_overlay")
				if ov != null:
					ov.restart_requested.emit()
				_stage = 5
				_frame = 0

		5:
			if _frame >= 90:
				var ov2 = _scene.get("result_overlay")
				print("[阶段4] 重开后 结算界面显示 = %s" % str(ov2 != null and ov2.is_shown()))
				_report_spawn_safety()
				_shot("04_after_restart")
				print("[验证] 完成")
				quit(0)
				return true

	return false


## 出生点安全区检查：出生点 2 跳内不得有敌人，且最近的敌人有多远
func _report_spawn_safety() -> void:
	var gen = _scene.get("gen")
	var agents = _scene.get("agents")
	if gen == null or agents == null:
		return
	var spawn = gen.spawn_room()
	var depths: Dictionary = gen.graph.bfs_depths(spawn.id)
	var nearest := 999
	var violating := 0
	for a in agents:
		if not a.is_alive():
			continue
		var cell: Vector2i = Ballistics.cell_of(a.pos)
		var room = _room_at(gen, cell)
		if room == null:
			continue
		var d: int = int(depths.get(room.id, 999))
		nearest = mini(nearest, d)
		if d <= gen.SPAWN_SAFE_GRAPH_DIST:
			violating += 1
	print("       种子=%d  出生点安全区=%d 跳  最近的敌人=%d 跳  违规=%d  敌人总数=%d"
		% [_scene.get("_raid_seed"), gen.SPAWN_SAFE_GRAPH_DIST, nearest, violating, agents.size()])


func _room_at(gen, cell: Vector2i):
	for r in gen.graph.rooms:
		if r.rect.has_point(cell):
			return r
	return null
