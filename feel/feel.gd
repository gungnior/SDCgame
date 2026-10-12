extends Node

## 手感总线（autoload "Feel"）—— hitstop / 相机震动 / 受击闪白
##
## 依据 specs/tech-stack.md §7.3「手感（Game Feel）」：
##
##   反馈性价比排序：hitstop ★★★★★ · 音效 ★★★★★ · 受击闪白 ★★★★ · trauma 震动 ★★★★
##
##   ⚠️ **比"选哪个效果"更重要的原则：反馈必须分级。**
##      轻击 / 重击 / 暴击 / 击杀走不同量级的同一套效果；
##      **全部同量级 = 手感反而变平**。→ 见下面的 FEEDBACK 表。
##
##   ⚠️ **不该做 shake 的时候**：
##      1. 连续随机震动（机枪每发都抖）→ 不适 + 毁可读性 → 用每分钟配额压制
##      2. "自己受伤"与"自己射击"用同幅度 → 分成两组参数
##      3. **像素游戏专属坑：亚像素随机偏移会撕裂像素网格**
##         → 本模块的 shake_offset() **量化到整像素**
##      4. 必须提供关闭 / 降低震动的无障碍选项 → 见 set_accessibility()

# ─────────────────── 分级表 ───────────────────
#
# hitstop_ms 硬上限 120ms（spec：超了就"卡"而不是"猛"）
# trauma 是 0~1 的累积量，实际位移用 trauma² × MAX_OFFSET_PX
#
# ⚠️ 自己受伤（PLAYER_HURT）刻意与"自己射击"分开：
#    受伤 = 大闪白 + 大震动 + 零 hitstop（不打断你的操作）
#    射击 = 小震动 + 零闪白（不能每枪都闪）
const LEVELS := {
	"light": {       # 轻击：擦到
		# ⚠️ hitstop_ms = 0 —— 这是**性能与手感的关键**。
		#    早先配 30ms。全自动步枪 600 RPM = 每 100ms 一发，
		#    每发都冻 30ms => 每秒 300ms 处于冻结 = **30% 的时间画面不动**。
		#    安卓真机反馈"自动开火有很强的卡顿"，根因就在这里。
		#    轻击的反馈交给音效 + 血雾粒子即可，不占用冻结。
		"hitstop_ms": 0.0, "trauma": 0.10, "flash": 0.00, "sfx": "hit_flesh",
		"flash_color": Color(1, 1, 1),
	},
	"heavy": {       # 重击：打实了
		"hitstop_ms": 60.0, "trauma": 0.22, "flash": 0.08, "sfx": "hit_flesh",
		"flash_color": Color(1, 1, 1),
	},
	"crit": {        # 暴击：打中要害
		"hitstop_ms": 85.0, "trauma": 0.34, "flash": 0.18, "sfx": "hit_crit",
		"flash_color": Color(1.0, 0.94, 0.72),
	},
	"kill": {        # 击杀：最后一击
		"hitstop_ms": 110.0, "trauma": 0.30, "flash": 0.14, "sfx": "kill_confirm",
		"flash_color": Color(1.0, 0.92, 0.66),
	},
	"player_hurt": { # 自己受伤：大反馈但【不打断操作】
		# ⚠️ flash_color 必须是【红】——
		#    早先这里配了白色，结果它先占住 _flash 额度，
		#    紧接着的 flash_damage() 因为 amount > _flash 判断被挡掉，
		#    整屏变成白色冲淡（实测踩过：画面整体发白）。
		"hitstop_ms": 0.0, "trauma": 0.50, "flash": 0.38, "sfx": "player_hurt",
		"flash_color": Color(0.78, 0.07, 0.09),
	},
	"player_shoot": {# 自己开枪：轻微 kick，绝不能每枪都大震
		"hitstop_ms": 0.0, "trauma": 0.07, "flash": 0.00, "sfx": "",
		"flash_color": Color(1, 1, 1),
	},
	"explosion": {   # 爆炸 / 破门
		"hitstop_ms": 100.0, "trauma": 0.75, "flash": 0.30, "sfx": "explosion",
		"flash_color": Color(1.0, 0.72, 0.35),
	},
}

## 受伤闪白的最小间隔 —— 否则被连续射击时闪白会一直挂着（实测踩过）
const DAMAGE_FLASH_COOLDOWN_MS := 180
## hitstop 最小间隔。
## ⚠️ spec 只给了【单次时长】上限（60~120ms），但**没限制频率**。
##    全自动武器下"每次命中都冻"会退化成持续卡顿 —— 安卓真机实测到了。
##    这里用配额把频率也管住（与震动配额同样的思路）。
const HITSTOP_MIN_INTERVAL_MS := 110

# ─────────────────── 参数 ───────────────────
const MAX_OFFSET_PX := 7.0        ## trauma=1 时的最大位移（像素）
const TRAUMA_DECAY := 1.7         ## 每秒衰减
## 震动配额：防止"连续随机震动"（spec 明令禁止）
const SHAKE_BUDGET_PER_SEC := 2.2

# ─────────────────── 无障碍 ───────────────────
var shake_enabled := true
var hitstop_enabled := true
var flash_enabled := true
var intensity := 1.0              ## 0.0 ~ 1.0 全局强度

# ─────────────────── 状态 ───────────────────
var trauma := 0.0
var _hitstop_until_ms := 0
var _flash := 0.0                 ## 当前闪白强度（0~1）
var _flash_color := Color(1, 1, 1)
var _last_damage_flash_ms := -99999
var _last_hitstop_ms := -99999
var _hitstop_suppressed := 0
var _shake_budget := SHAKE_BUDGET_PER_SEC
var _shake_suppressed := 0        ## 被配额压掉的次数（调试用）
var _time := 0.0

var _noise: FastNoiseLite

## 统计
var hitstop_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_noise()


## 惰性初始化噪声源。
## ⚠️ 不能只靠 _ready()：在 SceneTree 脚本里 add_child() 到 root 时
##    _ready 不一定已经跑过（实测踩过：shake_offset 在 null 上调用 get_noise_1d）。
func _ensure_noise() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = 20261012
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.9


func _process(delta: float) -> void:
	# ⚠️ hitstop 期间 Engine.time_scale = 0，delta 会是 0 ——
	#    所以恢复必须走【墙钟时间】，不能用 delta 累加。
	if _hitstop_until_ms > 0 and Time.get_ticks_msec() >= _hitstop_until_ms:
		_hitstop_until_ms = 0
		Engine.time_scale = 1.0
	if _hitstop_until_ms > 0:
		return                       # 冻结中不推进其它手感状态

	_time += delta

	# trauma 衰减
	if trauma > 0.0:
		trauma = maxf(0.0, trauma - TRAUMA_DECAY * delta)

	# 震动配额按秒补给
	_shake_budget = minf(SHAKE_BUDGET_PER_SEC, _shake_budget + SHAKE_BUDGET_PER_SEC * delta)

	# 闪白衰减（快起快落）
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 3.6)


# ─────────────────── 对外接口 ───────────────────

## 触发一次分级反馈。这是【唯一】应该被游戏代码调用的入口 ——
## 不要在业务代码里直接调 hitstop()/add_trauma()，那会绕过分级与配额。
func hit(level: String, world_pos: Vector2 = Vector2.INF,
		listen_pos: Vector2 = Vector2.INF) -> void:
	var cfg: Dictionary = LEVELS.get(level, LEVELS["light"])
	if not is_equal_approx(intensity, 1.0):
		cfg = cfg.duplicate()
		cfg["hitstop_ms"] = float(cfg["hitstop_ms"]) * intensity
		cfg["trauma"] = float(cfg["trauma"]) * intensity
		cfg["flash"] = float(cfg["flash"]) * intensity

	var ms := float(cfg["hitstop_ms"])
	if ms > 0.0:
		hitstop(ms)

	var t := float(cfg["trauma"])
	if t > 0.0:
		add_trauma(t)

	var f := float(cfg["flash"])
	if f > 0.0:
		flash(f, cfg.get("flash_color", Color(1, 1, 1)))

	# 音效（世界坐标有距离衰减，否则纯 UI 音）
	var sfx := str(cfg.get("sfx", ""))
	if sfx != "" and Sfx != null and Sfx.has(sfx):
		if world_pos.is_finite() and listen_pos.is_finite():
			Sfx.play_at(sfx, world_pos, listen_pos)
		else:
			Sfx.play(sfx)


func hitstop(ms: float) -> void:
	if not hitstop_enabled:
		return
	# 硬上限：spec 明确 60~120ms，超了就是"卡"
	ms = clampf(ms, 0.0, 120.0)
	if ms <= 0.0:
		return                       # 0 = 本档不冻结（如轻击）
	# ⚠️ 频率上限：全自动武器每发都冻会变成持续卡顿（安卓真机实测）
	var now := Time.get_ticks_msec()
	if now - _last_hitstop_ms < HITSTOP_MIN_INTERVAL_MS:
		_hitstop_suppressed += 1
		return
	_last_hitstop_ms = now
	_hitstop_until_ms = now + int(ms)
	Engine.time_scale = 0.0
	hitstop_count += 1


func add_trauma(amount: float) -> void:
	if not shake_enabled:
		return
	if _shake_budget < 0.35:
		_shake_suppressed += 1
		return                        # 配额用完：压制连续震动
	_shake_budget -= 0.35
	trauma = clampf(trauma + amount * intensity, 0.0, 1.0)


func flash(amount: float, color: Color = Color(1, 1, 1)) -> void:
	if not flash_enabled:
		return
	if amount > _flash:
		_flash = clampf(amount * intensity, 0.0, 1.0)
		_flash_color = color


func flash_damage(amount: float) -> void:
	# ⚠️ 限流：被连续射击时每帧都触发会让整屏一直泛红（实测踩过）
	var now := Time.get_ticks_msec()
	if now - _last_damage_flash_ms < DAMAGE_FLASH_COOLDOWN_MS:
		return
	_last_damage_flash_ms = now
	flash(amount, Color(0.78, 0.07, 0.09))


# ─────────────────── 供视图读取 ───────────────────

## 当前震动位移。
## ⚠️ **量化到整像素** —— 像素游戏里亚像素随机偏移会撕裂像素网格（spec §7.3）。
func shake_offset() -> Vector2:
	if not shake_enabled or trauma <= 0.0:
		return Vector2.ZERO
	_ensure_noise()
	var mag := MAX_OFFSET_PX * trauma * trauma * intensity   # trauma² 是关键
	var t := _time * 22.0
	var ox := _noise.get_noise_1d(t) * mag
	var oy := _noise.get_noise_1d(t + 137.0) * mag
	return Vector2(roundf(ox), roundf(oy))


func flash_alpha() -> float:
	return _flash if flash_enabled else 0.0


func flash_color() -> Color:
	return _flash_color


func is_frozen() -> bool:
	return _hitstop_until_ms > 0


## 无障碍：一次性配置，UI 里挂三个勾选框即可
func set_accessibility(p_shake: bool, p_hitstop: bool, p_flash: bool,
		p_intensity: float = 1.0) -> void:
	shake_enabled = p_shake
	hitstop_enabled = p_hitstop
	flash_enabled = p_flash
	intensity = clampf(p_intensity, 0.0, 1.0)
	if not hitstop_enabled and _hitstop_until_ms > 0:
		_hitstop_until_ms = 0
		Engine.time_scale = 1.0
	if not shake_enabled:
		trauma = 0.0


func reset() -> void:
	trauma = 0.0
	_flash = 0.0
	_hitstop_until_ms = 0
	Engine.time_scale = 1.0
	_shake_budget = SHAKE_BUDGET_PER_SEC
	# 计数也要清 —— "reset" 就该是彻底复位（测试与重开局都依赖这个语义）
	hitstop_count = 0
	_shake_suppressed = 0
	_hitstop_suppressed = 0
	_last_damage_flash_ms = -99999
	# ⚠️ 连"上次触发时间"也要清 —— 否则重开局后的第一个 hitstop 会被频率配额误吞
	_last_hitstop_ms = -99999


func stats() -> String:
	return "手感：hitstop %d 次, trauma %.2f, 震动被配额压掉 %d 次" % [
		hitstop_count, trauma, _shake_suppressed]
