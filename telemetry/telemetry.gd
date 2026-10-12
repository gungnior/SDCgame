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

## 游戏侧调 mark() 记录"此刻在做什么"，卡顿帧会带上它
var _ctx := "idle"
var _ctx_ms := 0


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


## 标记"此刻在做什么"。卡顿帧的诊断价值全在这里 ——
## 光知道"卡了 48ms"没用，要知道"卡在开枪那一帧"。
func mark(ctx: String) -> void:
	_ctx = ctx
	_ctx_ms = Time.get_ticks_msec()


func _process(delta: float) -> void:
	if not enabled:
		return
	_frames += 1
	var ms := delta * 1000.0

	# 单调时钟下的真实帧耗时（delta 会被 time_scale 影响，所以另取 Performance）
	var frame_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if frame_ms > _worst_ms:
		_worst_ms = frame_ms
		_worst_ctx = _ctx

	if frame_ms >= SPIKE_MS and Engine.time_scale > 0.0:
		# hitstop 期间冻结是【故意的】，不算卡顿
		_note_spike(frame_ms)

	_acc += delta
	if _acc >= SAMPLE_INTERVAL:
		_flush_stats()
		_acc = 0.0
		_frames = 0
		_worst_ms = 0.0
		_worst_ctx = ""


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
	var d := {
		"k": "stats",
		"t": _now(),
		"fps": int(fps),
		"avg_ms": snappedf((SAMPLE_INTERVAL * 1000.0) / maxf(1.0, float(_frames)), 0.01),
		"worst_ms": snappedf(_worst_ms, 0.01),
		"worst_ctx": _worst_ctx,
		"spikes": _spikes.size(),
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
