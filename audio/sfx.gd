extends Node

## 音效管理器（autoload "Sfx"）
##
## 设计依据 specs/tech-stack.md §7.3（音效与 hitstop 并列 ★★★★★）：
##   · **池化** AudioStreamPlayer —— 移动端不能每次 new（GC 压力）
##   · **随机变调** —— 同一音效反复播会听出机关枪式的重复感
##   · **每音效并发上限** —— 一帧内 5 个敌人同时开枪不能叠成噪音
##   · **headless 安全** —— 无音频设备（测试/CI）时静默降级，不报错
##   · **无障碍开关** —— 玩家可整体静音
##
## 音效表在 data/sfx.json（数据驱动，见 data/SCHEMA.md §8）。

const POOL_SIZE := 32
## 同一音效在这个时间窗内重复触发会被丢弃（秒）
const DEDUPE_WINDOW := 0.035

var enabled := true:
	set(v):
		enabled = v
		if not enabled:
			stop_all()

## 主音量（线性 0~1），走 AudioServer 的 Master 总线
var master_volume := 0.85:
	set(v):
		master_volume = clampf(v, 0.0, 1.0)
		var idx := AudioServer.get_bus_index("Master")
		if idx >= 0:
			AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(master_volume, 0.0001)))
			AudioServer.set_bus_mute(idx, master_volume <= 0.0)

var _bank: Dictionary = {}          ## name -> {stream, volume_db, pitch_min, pitch_max, max_simul}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _live: Array = []               ## 每个 player 正在播的音效名（或 ""）
var _last_played: Dictionary = {}   ## name -> msec
var _audible := true

## 统计（测试与调试用）
var played_count := 0
var dropped_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_ready()


## 惰性初始化。
## ⚠️ 不能只靠 _ready()：在 SceneTree 脚本里 add_child() 到 root 时
##    _ready 不一定已经跑过（实测踩过：has() 返回 false、stop_all() 越界）。
var _inited := false
func _ensure_ready() -> void:
	if _inited:
		return
	_inited = true
	_audible = _detect_audio()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_pool.append(p)
		_live.append("")
	_load_bank()
	if not _audible:
		print("[音效] 无可用音频设备，已静默降级（headless / CI 正常现象）")
	else:
		print("[音效] 载入 %d 个音效，池 %d" % [_bank.size(), POOL_SIZE])


func _detect_audio() -> bool:
	# headless 用 Dummy 驱动，AudioServer 仍然存在但不会出声；这里只判断驱动名
	var drv := AudioServer.get_driver_name()
	return drv != "" and drv.to_lower() != "dummy"


func _load_bank() -> void:
	var path := "res://data/sfx.json"
	if not FileAccess.file_exists(path):
		push_warning("[音效] 缺少 data/sfx.json")
		return
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Array):
		push_warning("[音效] sfx.json 顶层必须是数组")
		return
	for row in parsed:
		if not (row is Dictionary):
			continue
		var name := str(row.get("id", ""))
		if name.is_empty():
			continue
		var file := str(row.get("file", ""))
		if not ResourceLoader.exists(file):
			continue                      # 文件缺失就跳过，不阻塞游戏
		var stream: AudioStream = load(file)
		if stream == null:
			continue
		# 变调：AudioStreamPlayer.pitch_scale 范围
		_bank[name] = {
			"stream": stream,
			"volume_db": float(row.get("volume_db", 0.0)),
			"pitch_min": float(row.get("pitch_min", 1.0)),
			"pitch_max": float(row.get("pitch_max", 1.0)),
			"max_simul": int(row.get("max_simul", 3)),
			"bus": str(row.get("bus", "Master")),
		}


func has(name: String) -> bool:
	_ensure_ready()
	return _bank.has(name)


## 播放一个音效。
##   volume_scale：线性音量倍率（距离衰减用）
##   pitch_scale ：额外变调倍率（如后坐力随连发上扬）
func play(name: String, volume_scale: float = 1.0, pitch_scale: float = 1.0) -> void:
	_ensure_ready()
	if not enabled:
		return
	var e: Dictionary = _bank.get(name, {})
	if e.is_empty():
		return

	# ── 闸门：去重 + 并发上限 ──
	# ⚠️ 这两道闸门必须在 _audible 检查【之前】跑。
	#    否则 headless（无音频设备）下 play() 会在第一行就返回，
	#    去重/并发逻辑永远测不到，stats() 也永远是 0（实测踩过）。
	var now := Time.get_ticks_msec()
	var last: int = _last_played.get(name, -9999)
	if now - last < int(DEDUPE_WINDOW * 1000.0):
		dropped_count += 1
		return

	var max_simul: int = e["max_simul"]
	# ⚠️⚠️ 并发计数必须【同时】满足：这个槽位登记的是本人 **且** 它现在真的在播。
	#
	# 早先只数 `_live` 里的名字，而 `_live` 的条目在音效播完后**从不清理** ——
	# 只在槽位被 _acquire 复用时才被覆盖。后果极其严重：
	#   步枪响过 max_simul 次之后，_live 里就永远留着那么多条同名记录
	#   -> running >= max_simul 恒成立 -> **之后每一枪都被丢弃，枪声彻底消失**。
	# 真机实测 dropped=95 就是这么来的（不是"并发太多"，是被永久掐断）。
	var running := 0
	# ⚠️ `_live` 是 **Array**（不是 Dictionary）—— 不能用 .get(i, "")，
	#    那样会 "Too many arguments for get()" 直接编译失败（实测踩过）。
	for i in _pool.size():
		if i < _live.size() and str(_live[i]) == name and _pool[i].playing:
			running += 1
	if running >= max_simul:
		dropped_count += 1
		return

	_last_played[name] = now
	played_count += 1
	if not _audible:
		return                       # 无设备：闸门照常走，只是不出声

	var p := _acquire()
	if p == null:
		return

	p.stream = e["stream"]
	p.bus = e["bus"]
	p.volume_db = float(e["volume_db"]) + linear_to_db(maxf(volume_scale, 0.0001))
	var pm: float = e["pitch_min"]
	var px: float = e["pitch_max"]
	var base_pitch := pm if is_equal_approx(pm, px) else randf_range(pm, px)
	p.pitch_scale = clampf(base_pitch * pitch_scale, 0.05, 4.0)
	p.play()
	_live[_pool.find(p)] = name


func _acquire() -> AudioStreamPlayer:
	# 先找空闲的
	for i in POOL_SIZE:
		var idx := (_next + i) % POOL_SIZE
		if not _pool[idx].playing:
			_next = (idx + 1) % POOL_SIZE
			_live[idx] = ""
			return _pool[idx]
	# 全忙：抢占最早的那个（比丢音更好听）
	var idx2 := _next
	_next = (_next + 1) % POOL_SIZE
	return _pool[idx2]


func stop_all() -> void:
	# 池可能还没建（enabled setter 会在 _ready 之前被调用）—— 必须防越界
	for i in _pool.size():
		_pool[i].stop()
		if i < _live.size():
			_live[i] = ""


## 播放一个"世界坐标"的音效（按距离衰减）。
## listen_pos 由调用方传入（不用 AudioListener2D，见 tech-stack T-xx：
## 那是给音频混音用的听者位置，玩家位置我们自己知道得更准）
func play_at(name: String, world_pos: Vector2, listen_pos: Vector2,
		ref_dist: float = 6.0, max_dist: float = 26.0) -> void:
	_ensure_ready()
	if not enabled or not _audible:
		return
	var d := world_pos.distance_to(listen_pos)
	if d > max_dist:
		return
	var att := clampf(1.0 - (d - ref_dist) / maxf(1.0, max_dist - ref_dist), 0.0, 1.0)
	# 距离越远，音调略降（心理声学的"远"感）
	play(name, att * att, lerpf(1.06, 0.94, 1.0 - att))


func stats() -> String:
	return "音效：%d 个已注册，播放 %d 次，丢弃 %d 次%s" % [
		_bank.size(), played_count, dropped_count,
		"" if _audible else "（无设备）"]
