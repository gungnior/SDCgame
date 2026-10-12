extends Node

## 遥测（autoload "Tel"）—— 让 AI 能"直接看数据"而不是听玩家口述
##
## 为什么这么做：
##   真机问题（卡顿、输入错乱、AI 行为异常）靠口述描述损失极大。
##   本模块把运行期数据以**结构化单行 JSON** 打到 stdout，
##   Android 上 Godot 的 stdout 会进 logcat，主机端用
##   `tools/monitor_game.py` 通过 adb 实时解析成仪表盘。
##
## ⚠️ 与「不联网」约束（D-16）**不冲突**：
##   adb logcat 走 USB 调试通道，不需要 INTERNET 权限，游戏本身零网络请求。
##
## 输出格式（主机端按前缀过滤）：
##   DSHTEL|{"k":"stats","t":12.5,"fps":58.2,...}
##   DSHTEL|{"k":"spike","t":12.6,"ms":48.2,"ctx":"shot",...}
##   DSHTEL|{"k":"event","t":12.7,"e":"kill",...}
##
## 开销：每 0.5 秒一行 + 事件行 + 卡顿帧行。全部 < 1 KB/s，logcat 毫无压力。

const PREFIX := "DSHTEL|"
## 采样间隔（秒）。2 Hz 足够看趋势，又不会淹掉 logcat
const SAMPLE_INTERVAL := 0.5
## 单帧超过这个毫秒数算"卡顿帧"（33ms ≈ 掉到 30fps 以下）
const SPIKE_MS := 33.0
## 最多留多少条卡顿记录（供 dump 用）
const SPIKE_BUFFER := 60

var enabled := true

var _acc := 0.0
var _frames := 0
var _worst_ms := 0.0
var _worst_ctx := ""
var _spikes: Array = []
var _event_count := 0
var _run_started_ms := 0

## ⚠️ 帧耗时必须自己用墙钟测。
##    早先用 `Performance.TIME_PROCESS` —— 在 Android 上它给出的值前后矛盾：
##    报告了 1787 次"80ms 卡顿"，而同一时段 avg_ms = 16.13ms（正好 60fps）。
##    两者不可能同时成立。改用 `Time.get_ticks_usec()` 的相邻差，语义无歧义。
var _last_usec := 0
## 本采样窗内的卡顿计数（早先错报成环形缓冲区大小，永远是 60）
var _spike_window := 0
var _spike_total := 0
## 卡顿日志限流 —— 否则"卡顿 -> 打日志 -> 更卡"会形成正反馈
const SPIKE_PRINT_PER_SEC := 5
var _spike_print_sec := 0
var _spike_prints := 0
var _window_t0_usec := 0

## 游戏侧调 mark() 记录"此刻在做什么"，卡顿帧会带上它
##
## ⚠️ 只记"最后一个标记"是不够的 —— 实测踩过：
##    卡顿帧全都报 ctx=draw_body，但 ctx_age_ms 只有 2~3ms，
##    说明 80ms 其实花在 _draw 之前的某个阶段，draw_body 只是最后一个标记。
##    所以这里改成**逐阶段计时**：记录每个阶段的耗时，上报最慢的三个。
var _ctx := "idle"
var _ctx_ms := 0
var _phase_name := ""
var _phase_t0 := 0
var _phase_max: Dictionary = {}
var _phase_sum: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run_started_ms = Time.get_ticks_msec()
	# 环境信息只发一次
	emit("boot", {
		"engine": Engine.get_version_info().get("string", "?"),
		"platform": OS.get_name(),
		"renderer": RenderingServer.get_video_adapter_name(),
		"api": RenderingServer.get_video_adapter_api_version(),
		"screen": "%dx%d" % [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y],
		"touch": DisplayServer.is_touchscreen_available(),
		"dpi": DisplayServer.screen_get_dpi(),
		"scene": get_tree().current_scene.scene_file_path if get_tree().current_scene != null else "",
	})


## 标记阶段切换。会结算【上一个阶段】的耗时并记入统计。
func mark(ctx: String) -> void:
	var now := Time.get_ticks_usec()
	if _phase_name != "":
		var dt := float(now - _phase_t0) / 1000.0
		if dt > float(_phase_max.get(_phase_name, 0.0)):
			_phase_max[_phase_name] = dt
		_phase_sum[_phase_name] = float(_phase_sum.get(_phase_name, 0.0)) + dt
	_phase_name = ctx
	_phase_t0 = now
	_ctx = ctx
	_ctx_ms = Time.get_ticks_msec()


## 取本窗最慢的几个阶段（名字, 最慢ms, 累计ms）
func _top_phases(n: int = 3) -> Array:
	var arr: Array = []
	for k in _phase_max:
		arr.append([k, snappedf(float(_phase_max[k]), 0.01),
			snappedf(float(_phase_sum.get(k, 0.0)), 0.01)])
	arr.sort_custom(func(a, b): return a[1] > b[1])
	return arr.slice(0, n)


func _process(delta: float) -> void:
	if not enabled:
		return
	_frames += 1

	# 自己测墙钟帧间隔（不依赖 Performance，见字段注释）
	var now_usec := Time.get_ticks_usec()
	if _last_usec == 0:
		_last_usec = now_usec
		_window_t0_usec = now_usec
		return
	var frame_ms := float(now_usec - _last_usec) / 1000.0
	_last_usec = now_usec

	if frame_ms > _worst_ms:
		_worst_ms = frame_ms
		_worst_ctx = _ctx

	# ⚠️ hitstop 期间 delta 为 0，是【故意冻结】，不算卡顿
	var frozen := delta <= 0.0001 or Engine.time_scale <= 0.0
	if frame_ms >= SPIKE_MS and not frozen:
		_spike_window += 1
		_spike_total += 1
		_maybe_log_spike(frame_ms)

	_acc += delta
	if _acc >= SAMPLE_INTERVAL:
		_flush_stats()
		_acc = 0.0
		_frames = 0
		_worst_ms = 0.0
		_worst_ctx = ""
		_spike_window = 0
		_phase_max.clear()
		_phase_sum.clear()
		_window_t0_usec = Time.get_ticks_usec()


## 卡顿日志限流（每秒最多 N 条）
func _maybe_log_spike(ms: float) -> void:
	var sec := Time.get_ticks_msec() / 1000
	if sec != _spike_print_sec:
		_spike_print_sec = sec
		_spike_prints = 0
	if _spike_prints >= SPIKE_PRINT_PER_SEC:
		return
	_spike_prints += 1
	_note_spike(ms)


func _note_spike(ms: float) -> void:
	var rec := {
		"k": "spike",
		"t": _now(),
		"ms": snappedf(ms, 0.01),
		"ctx": _ctx,
		"ctx_age_ms": Time.get_ticks_msec() - _ctx_ms,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
	}
	_spikes.append(rec)
	if _spikes.size() > SPIKE_BUFFER:
		_spikes.pop_front()
	print(PREFIX, JSON.stringify(rec, "", false))


func _flush_stats() -> void:
	var fps := Engine.get_frames_per_second()
	# ⚠️ avg_ms 必须用【真实墙钟】算。
	#    早先用 SAMPLE_INTERVAL/_frames 假设窗口正好 0.5 秒，
	#    但 hitstop 期间 delta=0，窗口实际会拖得更长，avg_ms 就被高估了。
	var wall := 0.0
	if _window_t0_usec > 0:
		wall = float(Time.get_ticks_usec() - _window_t0_usec) / 1000.0
	var d := {
		"k": "stats",
		"t": _now(),
		"fps": int(fps),
		"avg_ms": snappedf(wall / maxf(1.0, float(_frames)), 0.01),
		"worst_ms": snappedf(_worst_ms, 0.01),
		"worst_ctx": _worst_ctx,
		"spikes": _spike_window,
		"spikes_total": _spike_total,
		# 最慢的三个阶段：名字 / 最慢ms / 累计ms
		"phases": _top_phases(5),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objs": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"physics_objs": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"ctx": _ctx,
		"events": _event_count,
	}
	# 游戏侧可以往 stats 里塞自定义字段（血量、敌人数、弹药…）
	d.merge(_extra, true)
	_extra.clear()
	print(PREFIX, JSON.stringify(d, "", false))


## 每帧采样期间累积的额外字段（游戏侧调 push_stat 塞入）
var _extra: Dictionary = {}


## 游戏侧用这个附加业务数据到下一次 stats 行
func push_stat(key: String, value: Variant) -> void:
	_extra[key] = value


## 立即发一个事件（击杀 / 死亡 / 撤离 / 报错…）
func emit(kind: String, data: Dictionary = {}) -> void:
	if not enabled:
		return
	_event_count += 1
	var d := data.duplicate()
	d["k"] = kind
	d["t"] = _now()
	d["ctx"] = _ctx
	print(PREFIX, JSON.stringify(d, "", false))


## 一次性把所有卡顿记录汇总打出（排查时用）
func dump_spikes() -> void:
	emit("spike_dump", {"count": _spikes.size(), "items": _spikes})


func _now() -> float:
	return snappedf(float(Time.get_ticks_msec() - _run_started_ms) / 1000.0, 0.01)


## 手动开关（HUD 或调试键）
func set_enabled(v: bool) -> void:
	enabled = v
	emit("telemetry", {"enabled": v})
