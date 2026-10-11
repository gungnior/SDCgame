extends Node2D

## M0 真机验证场景
##
## 为什么必须真机跑（而不是 headless 测试）：
##   🚨 炸弹 1 —— include_text_server_data 在编辑器里【恒真】，headless 测不出差别。
##                它只影响【导出包】。不导到手机上跑，就不知道中文断行到底对不对。
##   🚨 炸弹 2 —— GPUParticles2D 在 Compatibility 渲染器下【静默失效，不报错】。
##                headless 没有渲染器，根本测不到。
##
## 用法：
##   1. 导出安卓 APK（渲染器必须是 Compatibility / gl_compatibility）
##   2. 装到手机，打开
##   3. 按屏幕上的 3 项检查单目视确认
##
## 全部通过 → M0 这两个坑排除，可以安心写 B 阶段。

const FONT_PATH := "res://art/fonts/NotoSansSC-VF.ttf"
const BG := Color(0.07, 0.08, 0.10)
const FG := Color(0.92, 0.94, 0.96)
const WARN := Color(1.0, 0.78, 0.30)
const OK := Color(0.42, 0.88, 0.52)

var _font: FontFile
var _checks: VBoxContainer
var _status: Label


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG)
	_font = load(FONT_PATH)
	if _font == null:
		push_error("字体加载失败：%s" % FONT_PATH)

	_build_header()
	_build_check_1_chinese()
	_build_check_2_particles()
	_build_check_3_renderer()
	_build_status()


# ─────────────────────────── 通用构件 ───────────────────────────

func _label(text: String, size: int, color: Color, width: float) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(width, 0)
	return l


func _panel(pos: Vector2) -> PanelContainer:
	var p := PanelContainer.new()
	p.position = pos
	add_child(p)
	return p


func _build_header() -> void:
	_checks = VBoxContainer.new()
	_checks.position = Vector2(12, 10)
	_checks.add_theme_constant_override("separation", 18)
	_checks.custom_minimum_size = Vector2(616, 0)
	add_child(_checks)

	_checks.add_child(_label("M0 设备验证 · 搜打撤", 20, FG, 616))
	_checks.add_child(_label(
		"渲染器 %s  ·  Godot %s" % [
			RenderingServer.get_video_adapter_name(),
			Engine.get_version_info().string,
		], 11, Color(0.6, 0.66, 0.74), 616))


func _section(title: String) -> void:
	var l := _label(title, 14, WARN, 616)
	_checks.add_child(l)


# ─────────────── 检查 1：中文显示与断行 ───────────────

func _build_check_1_chinese() -> void:
	_section("检查 1 —— 中文显示与断行")

	# 这段文字【故意很长且没有空格】，只有 ICU 断行规则生效时才能在窄宽度内正确换行。
	# 如果 include_text_server_data 没打进导出包，你会看到：
	#   · 整行冲出屏幕不换行，或
	#   · 在奇怪的位置断开，或
	#   · 满屏方块（字体没加载）
	var long_cn := "在倒计时结束之前带着你的战利品撤离，否则本次行动的所有装备都会丢失。"
	var box := _panel(Vector2(0, 0))
	box.custom_minimum_size = Vector2(300, 0)   # 故意限宽 —— 必须换行
	box.add_child(_label(long_cn, 14, FG, 280))
	_checks.add_child(box)

	_checks.add_child(_label(
		"✅ 期望：上面这段中文在本框内【正确换行】，无方块、无溢出。", 12, OK, 616))

	# 字形覆盖抽查
	_checks.add_child(_label(
		"字形抽查：撤离 枪械 医疗 背包 弹药 护甲 战利品 倒计时 拾荒者", 13, FG, 616))


# ─────────────── 检查 2：CPU vs GPU 粒子 ───────────────

func _build_check_2_particles() -> void:
	_section("检查 2 —— 粒子可见性（Compatibility 渲染器的隐形坑）")

	_checks.add_child(_label(
		"左：CPUParticles2D（必须有火焰）　　右：GPUParticles2D（Compatibility 下多半没有）",
		12, Color(0.7, 0.76, 0.84), 616))

	# 左侧：CPU 粒子 —— 应该是可见的
	var holder := Node2D.new()
	holder.position = Vector2(80, 0)
	add_child(holder)

	var cpu := CPUParticles2D.new()
	cpu.amount = 48
	cpu.lifetime = 0.6
	cpu.one_shot = false
	cpu.emitting = true
	cpu.direction = Vector2.UP
	cpu.spread = 25.0
	cpu.initial_velocity_min = 60.0
	cpu.initial_velocity_max = 140.0
	cpu.gravity = Vector2(0, 120)
	cpu.scale_amount_min = 1.5
	cpu.scale_amount_max = 3.0
	cpu.color = Color(1.0, 0.75, 0.25)
	holder.add_child(cpu)

	var cpu_tag := _label("CPU", 12, OK, 120)
	cpu_tag.position = Vector2(50, 26)
	holder.add_child(cpu_tag)

	# 右侧：GPU 粒子 —— Compatibility 下预期不可见
	var holder2 := Node2D.new()
	holder2.position = Vector2(300, 0)
	add_child(holder2)

	var gpu := GPUParticles2D.new()
	gpu.amount = 48
	gpu.lifetime = 0.6
	gpu.one_shot = false
	gpu.emitting = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 25.0
	mat.initial_velocity_min = 60.0
	mat.initial_velocity_max = 140.0
	mat.gravity = Vector3(0, 120, 0)
	mat.scale_min = 1.5
	mat.scale_max = 3.0
	gpu.process_material = mat
	holder2.add_child(gpu)

	var gpu_tag := _label("GPU", 12, WARN, 120)
	gpu_tag.position = Vector2(270, 26)
	holder2.add_child(gpu_tag)

	_checks.add_child(_label(
		"✅ 期望：左侧有火焰 = CPU 粒子正常。右侧无火焰 = 证实必须用 CPUParticles2D（T-03）。",
		12, OK, 616))


# ─────────────── 检查 3：渲染器确认 ───────────────

func _build_check_3_renderer() -> void:
	_section("检查 3 —— 渲染器确认")

	var method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	var method_mobile := str(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "?"))
	var api := RenderingServer.get_video_adapter_api_version()
	var adapter := RenderingServer.get_video_adapter_name()

	_checks.add_child(_label(
		"rendering_method        = %s\nrendering_method.mobile = %s\n显卡 API                 = %s\n显卡                     = %s" % [
			method, method_mobile, api, adapter,
		], 12, FG, 616))

	_checks.add_child(_label(
		"✅ 期望：手机上实际使用的是 OpenGL/Compatibility 路径。若显示 Vulkan，说明用的不是 mobile 覆盖项。",
		12, OK, 616))


# ─────────────── 状态footer ───────────────

func _build_status() -> void:
	_status = _label("点按屏幕任意处退出", 11, Color(0.55, 0.6, 0.68), 616)
	_checks.add_child(_status)


func _unhandled_input(event: InputEvent) -> void:
	var tapped: bool = false
	if event is InputEventScreenTouch:
		tapped = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		tapped = (event as InputEventMouseButton).pressed
	if tapped or event.is_action_pressed("ui_cancel"):
		get_tree().quit()
