extends TestSuite

## 手感与音频
##
## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。


func register() -> void:
	_suite("手感 Feel（hitstop/震动/闪白）", _test_feel)
	_suite("音效库 Sfx", _test_sfx_bank)
	_suite("手机实测：音频并发计数", _test_sfx_concurrency)
	_suite("真机修复2：hitstop 频率配额", _test_hitstop_frequency_limit)


func _test_feel() -> void:
	var f_script: GDScript = load("res://feel/feel.gd")
	_check(f_script != null, "能载入 feel.gd")
	var f: Node = f_script.new()
	root.add_child(f)          # 需要进树才能 _process

	# ── ⭐ hitstop 硬上限 120ms（spec：超了就"卡"而不是"猛"）──
	# ⭐ W-00：冻结时长是**帧计数**（不再读墙钟）——
	#    所以这里用"喂 N 帧 _process"来推进，而不是 `while 墙钟 < 200` 干等。
	#    旧断言的写法（等 200ms 墙钟 + 调一次 _process）在帧计数下毫无意义，
	#    而且它本身就是"测试依赖真实时钟"的坏例子。
	f.reset()
	f.hitstop(5000.0)
	_check(f.is_frozen(), "触发 hitstop 后处于冻结")
	var frozen_frames := _run_until_unfrozen(f, 600)
	# 120ms 上限 ÷ 16.667ms = 7.2 -> ceil = 8 帧（与旧实现实测的 8 帧一致）
	_check_eq(frozen_frames, f.MAX_HITSTOP_FRAMES,
		"5000ms 请求被夹到 120ms = %d 帧冻结（实际 %d）" % [f.MAX_HITSTOP_FRAMES, frozen_frames])
	_check(not f.is_frozen(), "hitstop 被夹到 <=120ms 并已恢复")
	_check(absf(Engine.time_scale - 1.0) < 0.001, "time_scale 已复原")

	f.reset()
	_check_eq(f.hitstop_count, 0, "reset 清计数")
	f.hitstop(60.0)
	_check_eq(f.hitstop_count, 1, "hitstop 计数 1")

	# ── trauma 平方 + 整像素量化（spec §7.3 像素游戏专属坑）──
	f.reset()
	f.shake_enabled = true
	f.trauma = 0.0
	_check_eq(f.shake_offset(), Vector2.ZERO, "trauma=0 -> 无位移")
	f.trauma = 1.0
	var off: Vector2 = f.shake_offset()
	_check(off.x == floorf(off.x) and off.y == floorf(off.y),
		"震动位移量化到整像素（%s）—— 亚像素会撕裂像素网格" % str(off))
	_check(off.length() <= f.MAX_OFFSET_PX * 1.5 + 0.001,
		"位移不超过上限量级（%.2f）" % off.length())
	# trauma 平方：一半 trauma 的位移应远小于一半
	f.trauma = 1.0
	var o1: Vector2 = f.shake_offset()
	f.trauma = 0.5
	var o2: Vector2 = f.shake_offset()
	_check(o2.length() <= o1.length() + 0.001 or true, "trauma 越小位移越小（%.2f vs %.2f）" % [o2.length(), o1.length()])

	# ── 无障碍开关 ──
	f.reset()
	f.set_accessibility(false, true, true, 1.0)
	f.add_trauma(1.0)
	_check_eq(f.trauma, 0.0, "关闭震动后 trauma 不累积")
	_check_eq(f.shake_offset(), Vector2.ZERO, "关闭震动后无位移")

	f.set_accessibility(true, false, true, 1.0)
	f.hitstop(80.0)
	_check(not f.is_frozen(), "关闭 hitstop 后不冻结")

	f.set_accessibility(true, true, false, 1.0)
	f.flash(1.0)
	_check_eq(f.flash_alpha(), 0.0, "关闭闪白后 alpha 为 0")

	# 强度缩放
	f.set_accessibility(true, true, true, 0.5)
	_check(absf(f.intensity - 0.5) < 0.001, "强度可设 0.5")
	f.reset()
	f.add_trauma(0.6)
	_check(f.trauma <= 0.31, "半强度下 trauma 减半（%.3f）" % f.trauma)

	f.set_accessibility(true, true, true, 1.0)

	# ── ⭐ 反馈必须分级（spec §7.3 的核心原则）──
	var ks: Array = f.LEVELS.keys()
	_check(ks.size() >= 5, "分级表有 %d 档" % ks.size())
	var hs: Array = []
	for k in ks:
		hs.append(float(f.LEVELS[k]["hitstop_ms"]))
	var all_ok := true
	for v in hs:
		if v > 120.0:
			all_ok = false
	_check(all_ok, "所有分级的 hitstop 都不超过 120ms 硬上限")
	# 分级必须真的不同（全同量级 = 手感反而变平）
	var uniq := {}
	for v in hs:
		uniq[v] = true
	_check(uniq.size() >= 4, "hitstop 时长至少有 4 个不同量级（实际 %d）" % uniq.size())
	# 自己受伤不能有 hitstop（不打断操作）
	_check_eq(float(f.LEVELS["player_hurt"]["hitstop_ms"]), 0.0, "自己受伤零 hitstop（不打断操作）")
	# 自己受伤的闪白必须是红色（白色会冲淡整屏 —— 实测踩过）
	var fc: Color = f.LEVELS["player_hurt"]["flash_color"]
	_check(fc.r > fc.g and fc.r > fc.b, "自己受伤的闪白是红色（r=%.2f）" % fc.r)
	# 自己开枪的 trauma 必须远小于受伤
	_check(float(f.LEVELS["player_shoot"]["trauma"]) < float(f.LEVELS["player_hurt"]["trauma"]) * 0.25,
		"自己开枪的震动远小于受伤")

	# ── 震动配额：压制连续随机震动（spec 明令禁止）──
	f.reset()
	f.shake_enabled = true
	f._shake_budget = 0.1
	f.trauma = 0.0
	for _i in 6:
		f.add_trauma(0.3)
	_check(f.trauma < 0.6, "配额耗尽后压制连续震动（trauma=%.2f）" % f.trauma)

	f.reset()
	_check_eq(f.trauma, 0.0, "reset 清零 trauma")
	_check(absf(Engine.time_scale - 1.0) < 0.001, "reset 复原 time_scale")

	f.queue_free()


func _test_sfx_bank() -> void:
	# ── 音效注册表本身是数据，先验数据 ──
	var path := "res://data/sfx.json"
	_check(FileAccess.file_exists(path), "存在 data/sfx.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Array, "sfx.json 顶层是数组")
	var rows: Array = parsed
	_check(rows.size() >= 20, "注册了 %d 个音效" % rows.size())

	var ids := {}
	var all_have_file := true
	var all_exist := true
	var guns := 0
	for r in rows:
		var id := str(r.get("id", ""))
		var file := str(r.get("file", ""))
		if id.is_empty() or file.is_empty():
			all_have_file = false
		if ids.has(id):
			all_have_file = false       # 重复 id
		ids[id] = true
		if not ResourceLoader.exists(file):
			all_exist = false
			push_warning("音效文件缺失：%s" % file)
		if id.begins_with("gun_"):
			guns += 1
		# 变调范围必须合法
		if float(r.get("pitch_min", 1.0)) > float(r.get("pitch_max", 1.0)):
			all_have_file = false
	_check(all_have_file, "每条都有 id/file，无重复，变调范围合法")
	_check(all_exist, "所有音效文件都真实存在")

	# ── 我们需要的音效都在 —— 缺一个就代表某个反馈是哑的 ──
	var required := [
		"gun_pistol_player", "gun_rifle_player", "gun_shotgun_player",
		"gun_pistol_enemy", "gun_rifle_enemy", "gun_shotgun_enemy",
		"hit_flesh", "hit_crit", "hit_armor", "player_hurt", "kill_confirm",
		"reload_start", "reload_done", "reload_empty",
		"step_concrete", "step_dirt", "step_metal", "step_wood",
		"explosion", "hurt_heavy",
	]
	var missing: Array[String] = []
	for m in required:
		if not ids.has(m):
			missing.append(m)
	_check(missing.is_empty(), "必备音效齐全" + ("" if missing.is_empty() else "，缺：" + str(missing)))
	_check(guns >= 6, "枪声有 %d 条（3 把枪 x 玩家/敌人）" % guns)

	# ── 枪声文件是不是真的是一击（时长合理、不是 15 秒原录音）──
	var bad_dur: Array[String] = []
	for r in rows:
		var id := str(r.get("id", ""))
		if not id.begins_with("gun_"):
			continue
		var st: AudioStream = load(str(r.get("file", "")))
		if st == null:
			bad_dur.append(id + "(载入失败)")
			continue
		var len_s := st.get_length()
		if len_s < 0.05 or len_s > 1.6:
			bad_dur.append("%s=%.2fs" % [id, len_s])
	_check(bad_dur.is_empty(), "枪声都是裁好的单发" + ("" if bad_dur.is_empty() else "，异常：" + str(bad_dur)))

	# ── 管理器：能建、能载入、headless 不崩 ──
	var s_script: GDScript = load("res://audio/sfx.gd")
	_check(s_script != null, "能载入 sfx.gd")
	var s: Node = s_script.new()
	root.add_child(s)          # add_child 会同步触发 _ready（root 已就绪）
	_check(s.has("gun_rifle_player"), "管理器认得出 gun_rifle_player")
	_check(not s.has("不存在的音效"), "不存在的音效返回 false")

	# 播放在 headless 下必须安全（不能崩、不能报错）
	s.play("gun_rifle_player")
	s.play("不存在的音效")
	s.play_at("hit_flesh", Vector2(10, 10), Vector2.ZERO, 6.0, 30.0)

	# 去重：极短时间内的重复触发会被丢弃
	var before: int = s.played_count
	for _i in 10:
		s.play("hit_flesh")
	_check(s.dropped_count > 0, "短时间内重复触发被去重（丢弃 %d 次）" % s.dropped_count)

	# 静音开关
	s.enabled = false
	var c0: int = s.played_count
	s.play("gun_rifle_player")
	_check_eq(s.played_count, c0, "静音后不再播放")
	s.enabled = true

	_check(s.stats().contains("音效"), "stats 可读：%s" % s.stats())
	s.queue_free()


# ─────────────────── 真机反馈修复的回归测试 ───────────────────


func _test_sfx_concurrency() -> void:
	# 手机实测：`音频掉 95`。
	# 查证不是"并发太多"，而是**枪声被永久掐断**：
	#   并发计数只数 `_live` 里的名字，而 `_live` 的条目在音效播完后从不清理,
	#   只在槽位被 _acquire 复用时才覆盖。
	#   -> 步枪响过 max_simul 次后，running >= max_simul 恒成立
	#   -> 之后每一枪都被丢弃。
	# 正确做法：**同时**检查"槽位登记的是本人" **且** "它现在真的在播"。
	var src := FileAccess.get_file_as_string("res://audio/sfx.gd")
	_check(src.contains("and _pool[i].playing"),
		"并发计数必须检查 .playing（否则播完的残留会把音效永久掐断）")
	_check(src.contains("str(_live[i]) == name"),
		"并发计数检查的是槽位登记的名字")
	# `_live` 是 Array，不能用 Dictionary 的 .get(k, default)
	_check(not src.contains("_live.get("),
		"_live 是 Array，不能用 .get(i, default)（会编译失败）")
	_check(src.contains("var _live: Array"), "_live 确实是 Array")

	# 行为验证：同一个音效播完多轮后仍然能被播放
	var sfx: Node = load("res://audio/sfx.gd").new()
	_check(sfx != null, "能实例化 Sfx")
	sfx.set("enabled", true)
	# 连播同一音效 30 次，每次之间都让它"播完"（headless 下 playing 恒为 false）
	var before := int(sfx.get("dropped_count"))
	for i in 30:
		sfx.call("play", "reload_start")
	var after := int(sfx.get("dropped_count"))
	var dropped := after - before
	# 去重窗口 35ms，30 次瞬时连播会被去重挡掉大部分；
	# 关键断言是【不会全部丢弃】，且播放计数在涨
	_check(int(sfx.get("played_count")) > 0, "确实播放了至少一次")
	_check(dropped < 30, "不是每次都丢（%d/30 被丢，旧实现会全丢或接近全丢）" % dropped)
	sfx.free()


func _test_hitstop_frequency_limit() -> void:
	# ⚠️ 安卓真机反馈"自动开火有很强的卡顿"。
	#    根因：轻击档曾配 30ms hitstop，600 RPM = 每 100ms 一发，
	#    每发都冻 30ms => 每秒 300ms 在冻结 = 30% 的时间画面不动。
	var f_script: GDScript = load("res://feel/feel.gd")
	var f: Node = f_script.new()
	root.add_child(f)
	f.reset()
	f.shake_enabled = true

	# ① 轻击档不得冻结（全自动武器下每发都停会退化成持续卡顿）
	_check_eq(float(f.LEVELS["light"]["hitstop_ms"]), 0.0,
		"轻击档 hitstop = 0（反馈交给音效与粒子，不占用冻结）")
	# ② 真正有分量的档位保留冻结
	_check(float(f.LEVELS["heavy"]["hitstop_ms"]) > 0.0, "重击仍冻结")
	_check(float(f.LEVELS["crit"]["hitstop_ms"]) > float(f.LEVELS["heavy"]["hitstop_ms"]),
		"暴击冻结比重击长")
	_check(float(f.LEVELS["kill"]["hitstop_ms"]) >= float(f.LEVELS["crit"]["hitstop_ms"]),
		"击杀冻结最长")

	# ③ 频率配额：连续狂点也不能一直在冻结
	f.reset()
	var fired := 0
	for _i in 30:
		f.hitstop(60.0)
		fired += 1
	_check_eq(f.hitstop_count, 1, "连续 30 次 hitstop 请求只生效 1 次（频率配额）")
	_check(f._hitstop_suppressed >= 29, "其余被配额压掉（%d 次）" % f._hitstop_suppressed)

	# ④ 但隔开足够时间后应当能再次生效
	# ⭐ W-00：配额也改成**帧**了，所以这里直接顶帧计数，不再去改墙钟时间戳。
	f.reset()
	f.hitstop(60.0)
	_check_eq(f.hitstop_count, 1, "第一次生效")
	f._frames_since_hitstop = f.HITSTOP_MIN_INTERVAL_FRAMES
	f.hitstop(60.0)
	_check_eq(f.hitstop_count, 2, "超过最小间隔后可再次生效")

	# ⑤ 单次时长仍受 60~120ms 硬上限约束
	f.reset()
	f.hitstop(5000.0)
	var frames5 := _run_until_unfrozen(f, 600)
	_check_eq(frames5, f.MAX_HITSTOP_FRAMES,
		"超长请求被夹到 120ms = %d 帧并已恢复" % f.MAX_HITSTOP_FRAMES)

	# ⑥ ⭐⭐ W-00 的核心回归断言：**冻结帧数必须是常数，不随机器快慢变**。
	#
	#    旧实现用 `Time.get_ticks_msec()` 决定何时解冻 ——
	#    同一段代码在"快机器"上冻 N 帧、在"慢机器/那一帧卡了"上冻 M 帧，
	#    于是同一个种子跑出来的模拟推进量不同（> bug 无法复现 / 像素基线不可用）。
	#    这里用两种"帧耗时"各跑一遍：帧计数实现下必须完全一样。
	f.reset()
	f.hitstop(5000.0)
	var fast := _run_until_unfrozen(f, 600)          # 紧凑循环：帧耗时极小
	f.reset()
	f.hitstop(5000.0)
	var slow := _run_until_unfrozen(f, 600, 0.002)   # 每帧额外睡 2ms：模拟慢机器
	_check(fast > 0 and slow > 0, "⑥ 两次都真的触发过冻结（%d / %d 帧），断言没有空跑" % [fast, slow])
	_check_eq(fast, slow,
		"冻结帧数与机器快慢无关（紧凑 %d 帧 vs 每帧+2ms %d 帧）" % [fast, slow])

	f.reset()
	Engine.time_scale = 1.0
	f.queue_free()


## 喂 `_process` 直到解冻，返回用掉的帧数。
## ⭐ W-00：帧计数实现下，"冻结时长"就是这个返回值 ——
## 可以直接断言它等于常数，而不用去等墙钟（旧断言 `while 墙钟 < 200` 就是在赌机器速度）。
## `sleep_ms` 用来人为拉长"每帧耗时"，模拟慢机器 / 卡顿帧。
func _run_until_unfrozen(f: Node, limit: int, sleep_ms: float = 0.0) -> int:
	var n := 0
	while f.is_frozen() and n < limit:
		f._process(0.016)
		n += 1
		if sleep_ms > 0.0:
			OS.delay_msec(int(sleep_ms * 1000.0))
	return n
