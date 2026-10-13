extends SceneTree

## W-00 复现性探针 —— 截图 **+ 打印模拟状态指纹**
##
## 为什么需要它（而不是直接用 test/screenshot.gd）：
##   像素不一致只能告诉你"有东西分叉了"，**不告诉你是什么先分叉**。
##   这个探针在同一帧额外打印一组状态（模拟时间 / hitstop / 敌人位置 / RNG 游标 …），
##   于是可以按字段定位"第一个分叉量"，而不是靠猜。
##
## 它同时是 W-00 的验收工具：同参数跑 N 次，两两比像素 + 比状态指纹。
##
## 用法（不能加 --headless，要真渲染器）：
##   godot --path . --fixed-fps 60 --rendering-driver opengl3 `
##     --rendering-method gl_compatibility --resolution 1280x720 `
##     --script res://tools/determinism_probe.gd -- `
##     --seed 424242 --frames 300 --hide-hud --out res://_install/tmp/det/run_1.png
##
## 可选：
##   --combat             开自动瞄准 + 自动射击（默认局面根本不触发 hitstop）
##   --hitstop-frame N    在第 N 帧触发一次 Feel.hit(<level>)（默认 heavy）
##   --hitstop-level L    light / heavy / crit / kill / explosion
##   --show-hud           不藏 HUD（藏 HUD 是默认，见下面的说明）
##
## ⚠️ 只读探针：不改任何游戏状态，也不改 Game/存档。
##
## ─── 两个"踩过才知道"的坑（都写在这里，别在别处重犯）──
##
## ① **必须每帧藏 HUD，而且不能只在 `_initialize` 里藏一次。**
##    HUD 是 `raid_scene._ready() -> _setup_view()` 里才 new 出来的，
##    `_initialize` 里 `_scene.get("raid_hud")` 还是 **null** —— 那次 hide 静默失效
##    （`if n != null` 直接跳过）。而 HUD 里有一行
##    `FPS %d 平均 %.1f ms 最慢 %.1f ms`，**是墙钟读数**。
##    于是"世界像素基线"里混进了一个天生不可复现的仪表读数 ——
##    实测那 0.018% 的"帧时序噪声"**全部**来自它（藏掉之后 6/6 对逐像素一致）。
##
## ② **截图必须挂在 `RenderingServer.frame_post_draw` 上，不能在 `_process` 里直接读。**
##    `get_image()` 拿到的是**上一帧已渲染的那张**。如果目标帧的 `_process` 里直接读，
##    拿到的是第 N-1 帧，而"到底落后一帧还是零帧"随真实时序浮动。
##    静止的东西看不出来，**正在转的视野锥会整块差出来**（实测：4 次里 1 次差 5.48%，
##    而状态指纹完全相同 —— 差点被误判成"模拟不可复现"）。

var _frames := 0
var _target := 300
var _out := "res://_install/tmp/det/probe.png"
var _seed := 0
var _hide_hud := true
var _combat := false
var _hitstop_frame := 0
var _hitstop_every := 0
var _hitstop_level := "heavy"
var _diag_printed := false
var _pending_capture := false
var _scene = null


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i] == "--frames" and i + 1 < args.size():
			_target = int(args[i + 1]); i += 2
		elif args[i] == "--out" and i + 1 < args.size():
			_out = args[i + 1]; i += 2
		elif args[i] == "--seed" and i + 1 < args.size():
			_seed = int(args[i + 1]); i += 2
		elif args[i] == "--show-hud":
			_hide_hud = false; i += 1
		elif args[i] == "--combat":
			_combat = true; i += 1
		elif args[i] == "--hitstop-frame" and i + 1 < args.size():
			_hitstop_frame = int(args[i + 1]); i += 2
		elif args[i] == "--hitstop-level" and i + 1 < args.size():
			_hitstop_level = str(args[i + 1]); i += 2
		elif args[i] == "--hitstop-every" and i + 1 < args.size():
			# 每 N 帧触发一次 hitstop（"顿帧风暴"）：
			# 单次冻结的墙钟抖动看不出差别，但累积 20+ 次就会把
			# "模拟推进量不同"放大到 sim_time 上，一眼可见。
			_hitstop_every = int(args[i + 1]); i += 2
		elif args[i] == "":
			i += 1
		else:
			i += 1

	var ps: PackedScene = load("res://view/raid_scene.tscn")
	if ps == null:
		print("PROBE_ERROR 加载场景失败")
		quit(1)
		return
	_scene = ps.instantiate()
	# ⚠️ 必须在 add_child 之前注入种子：_ready -> _setup_sim 会读 _raid_seed
	if _seed != 0:
		_scene.set("_raid_seed", _seed)
		seed(_seed)
	root.add_child(_scene)
	# ⭐ 把"鼠标瞄准"钉住：它是**外部输入**（读操作系统的鼠标速度），
	#    验收时只要有人在动鼠标，视野锥就会整块变、像素差 5%~7%，
	#    而模拟时间/RNG/实体位置都不变（实测：4 次里 1 次 aim 变了）。
	#    固定输入才能真正比较两次运行；正常游玩不受影响（默认 true）。
	_scene.set("allow_mouse_aim", false)
	if _combat:
		var game: Node = root.get_node_or_null("Game")
		if game != null:
			game.set("auto_fire", true)
			game.set("auto_aim", true)
	if _hide_hud:
		_set_hud_visible(false)     # 这一步通常是 no-op（HUD 还没建），靠 _process 里每帧补
	RenderingServer.frame_post_draw.connect(_on_frame_post_draw)
	print("PROBE_HEAD seed=%d frames=%d hide_hud=%s combat=%s hitstop_frame=%d level=%s" % [
		_seed, _target, str(_hide_hud), str(_combat), _hitstop_frame, _hitstop_level])


func _set_hud_visible(v: bool) -> void:
	for name in ["raid_hud", "touch"]:
		var n = _scene.get(name)
		if not _diag_printed:
			print("PROBE_DIAG hud_arg=%s node=%s visible=%s" % [
				name, ("null" if n == null else str(n)),
				("n/a" if n == null else str(n.visible))])
		if n != null:
			n.visible = v
	_diag_printed = true


func _process(_delta: float) -> bool:
	_frames += 1
	# 见文件头 ①：每帧都要藏
	if _hide_hud:
		_set_hud_visible(false)

	# W-00 的核心用例：在固定帧触发一次 hitstop，看"冻结了几帧"是否可复现
	if _hitstop_frame > 0 and _frames == _hitstop_frame:
		var feel: Node = root.get_node_or_null("Feel")
		if feel != null:
			feel.call("hit", _hitstop_level)
			print("PROBE_HITSTOP frame=%d level=%s" % [_frames, _hitstop_level])
	# 顿帧风暴：每 N 帧一次（累积抖动）
	if _hitstop_every > 0 and _frames % _hitstop_every == 0:
		var feel2: Node = root.get_node_or_null("Feel")
		if feel2 != null:
			feel2.call("hit", _hitstop_level)

	if _frames < _target:
		return false
	# 见文件头 ②：截图交给 frame_post_draw，保证抓的是同一帧
	_pending_capture = true
	return false


func _on_frame_post_draw() -> void:
	if not _pending_capture:
		return
	_pending_capture = false

	var feel: Node = root.get_node_or_null("Feel")
	var feel_time := 0.0
	var trauma := 0.0
	var flash := 0.0
	var hitstop_count := 0
	var hitstop_suppressed := 0
	var hitstop_frames := 0
	var frozen := false
	if feel != null:
		feel_time = _q(float(feel.get("_time")))
		trauma = _q(float(feel.get("trauma")))
		flash = _q(float(feel.get("_flash")))
		hitstop_count = int(feel.get("hitstop_count"))
		hitstop_suppressed = int(feel.get("_hitstop_suppressed"))
		var hf = feel.get("_hitstop_frames")
		hitstop_frames = 0 if hf == null else int(hf)
		frozen = bool(feel.call("is_frozen"))

	var aim: Vector2 = _scene.get("player_aim")
	var cam: Camera2D = _scene.get("camera")

	# ── 状态指纹：JSON 一行（python 侧按字段比）──
	var st: Dictionary = {
		"frames": _frames,
		"sim_time": _q(float(_scene.get("_time"))),
		"hp": int(_scene.get("vitals").hp),
		"dead": bool(_scene.get("vitals").dead),
		"kills": int(_scene.get("raid").enemies_killed),
		"player_x": _q(float(_scene.get("player_pos").x)),
		"player_y": _q(float(_scene.get("player_pos").y)),
		"aim_x": _q(aim.x),
		"aim_y": _q(aim.y),
		"cam_x": _q(cam.global_position.x),
		"cam_y": _q(cam.global_position.y),
		"cam_off_x": _q(cam.offset.x),
		"cam_off_y": _q(cam.offset.y),
		"agents_alive": _agents_alive(),
		"agents_pos": _agents_pos(),
		"agents_detail": _agents_detail(),
		"bullets": int(_scene.get("bullets").size()),
		"muzzle": _count("muzzle_flash"),
		"feel_time": feel_time,
		"trauma": trauma,
		"flash": flash,
		"hitstop_count": hitstop_count,
		"hitstop_suppressed": hitstop_suppressed,
		"hitstop_frames": hitstop_frames,
		"frozen": frozen,
		"time_scale": _q(Engine.time_scale),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		# ⭐ RNG 游标：如果这个不同，说明"随机数消耗的次数"不同 ——
		#    那比"某个位置差一点"更接近根因。
		#    ⚠️ `_rng` 是 sim/rng.gd 的 SimRng 包装（RefCounted），
		#    真正的 RandomNumberGenerator 在它的 `_rng` 里 —— 直接读 `.state` 会报
		#    "Invalid access to property 'state' on RefCounted (SimRng)"（实测踩过）。
		"rng_state": _rng_state(),
	}
	print("PROBE_STATE " + JSON.stringify(st))

	var img := root.get_texture().get_image()
	if img == null:
		print("PROBE_ERROR 读回画面失败（无渲染器？）")
		quit(1)
		return
	var abs_path := _out
	if _out.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(_out)
	var dir := abs_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(abs_path)
	if err != OK:
		print("PROBE_ERROR 保存失败 %s (err %d)" % [abs_path, err])
		quit(1)
		return
	print("PROBE_SHOT %s %dx%d" % [abs_path, img.get_width(), img.get_height()])
	quit(0)


func _q(v: float) -> float:
	# 十位小数：足够暴露一帧级的差异，又不被浮点打印格式搅乱
	return snappedf(v, 1e-10)


func _count(member: String) -> int:
	var arr = _scene.get(member)
	return -1 if arr == null else int(arr.size())


func _rng_state() -> String:
	var srng = _scene.get("_rng")
	if srng == null:
		return "n/a"
	var inner = srng.get("_rng")
	if inner == null:
		return "n/a"
	return str(inner.state)


func _agents_alive() -> int:
	var n := 0
	for a in _scene.get("agents"):
		if a.is_alive():
			n += 1
	return n


func _agents_pos() -> Array:
	# 按 id 排序，保证顺序本身也是确定性的
	var out: Array = []
	for a in _scene.get("agents"):
		if a.is_alive():
			out.append([int(a.id), _q(float(a.pos.x)), _q(float(a.pos.y))])
	out.sort_custom(func(p, q): return p[0] < q[0])
	return out


func _agents_detail() -> Array:
	# 位置之外的状态：朝向、开火次数、血量。位置相同但朝向不同也会让像素不同。
	var out: Array = []
	for a in _scene.get("agents"):
		out.append([
			int(a.id), int(a.hp), a.is_alive(),
			_q(float(a.facing.x)), _q(float(a.facing.y)),
			int(a.shots_fired),
		])
	out.sort_custom(func(p, q): return p[0] < q[0])
	return out
