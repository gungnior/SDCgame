extends SceneTree

## Compatibility 渲染器下的粒子可见性验证 —— 像素级 A/B
##
## 为什么需要它（specs/tech-stack.md T-03）：
##   🚨 GPUParticles2D 在 Compatibility 渲染器下会【静默失效】——不报错、不警告，
##      粒子直接消失。headless 没有渲染器，测不到；肉眼在桌面上又很容易看漏。
##
## 做法：
##   在同一个画面里同时摆放 CPUParticles2D 与 GPUParticles2D，
##   渲染若干帧后【读回像素】，统计左右两个区域的亮像素数量做对比。
##
## 运行：
##   godot --path . --script res://test/test_particles_compat.gd --rendering-method gl_compatibility
##   godot --path . --script res://test/test_particles_compat.gd --rendering-method forward_plus
##
## 退出码：0 = 结论符合预期，1 = 与预期不符（或渲染器不可用）

const CPU_POS := Vector2(120, 200)
const GPU_POS := Vector2(420, 200)
const REGION := Rect2(-70, -70, 140, 140)   ## 以粒子发射点为心的统计区域
const BRIGHT_THRESHOLD := 0.25              ## 亮度阈值
const WARMUP_FRAMES := 45                   ## 等粒子铺开

var _frames := 0
var _method := ""


func _initialize() -> void:
	# ⚠️ 必须用 RenderingServer 的【运行时】接口，不能用 ProjectSettings——
	#    后者只反映 project.godot 里的配置，不反映 --rendering-method 等命令行覆盖。
	_method = RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name()

	print("")
	print("=== Compatibility 粒子可见性验证 ===")
	print("运行时渲染方式 = %s   (driver = %s)" % [_method, driver])
	print("video adapter  = %s   (api = %s)" % [
		RenderingServer.get_video_adapter_name(),
		RenderingServer.get_video_adapter_api_version(),
	])

	# 深色背景，便于统计亮像素
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 1))

	var holder := Node2D.new()
	root.add_child(holder)

	# 左：CPU 粒子（预期可见）
	var cpu := CPUParticles2D.new()
	cpu.position = CPU_POS
	cpu.amount = 64
	cpu.lifetime = 0.8
	cpu.emitting = true
	cpu.direction = Vector2.UP
	cpu.spread = 30.0
	cpu.initial_velocity_min = 40.0
	cpu.initial_velocity_max = 90.0
	cpu.gravity = Vector2.ZERO
	cpu.scale_amount_min = 3.0
	cpu.scale_amount_max = 6.0
	cpu.color = Color(1, 1, 1, 1)
	holder.add_child(cpu)

	# 右：GPU 粒子（Compatibility 下预期不可见）
	var gpu := GPUParticles2D.new()
	gpu.position = GPU_POS
	gpu.amount = 64
	gpu.lifetime = 0.8
	gpu.emitting = true
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 30.0
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 90.0
	mat.gravity = Vector3.ZERO
	mat.scale_min = 3.0
	mat.scale_max = 6.0
	gpu.process_material = mat
	holder.add_child(gpu)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < WARMUP_FRAMES:
		return false

	var img := root.get_texture().get_image()
	if img == null:
		print("无法读回画面（渲染器不可用？）")
		quit(1)
		return true

	var cpu_px := _count_bright(img, CPU_POS)
	var gpu_px := _count_bright(img, GPU_POS)

	print("")
	print("统计区域亮像素数（阈值 %.2f，区域 %s）:" % [BRIGHT_THRESHOLD, str(REGION)])
	print("  CPUParticles2D @ %s -> %d 像素" % [str(CPU_POS), cpu_px])
	print("  GPUParticles2D @ %s -> %d 像素" % [str(GPU_POS), gpu_px])
	print("")

	var code := 0
	if _method == "gl_compatibility":
		if cpu_px > 50 and gpu_px < 5:
			print("✅ 证实 T-03：Compatibility 下 CPU 粒子可见、GPU 粒子【静默失效】")
			print("   → 本项目所有粒子必须用 CPUParticles2D")
		elif cpu_px > 50 and gpu_px > 50:
			print("⚠️ 两者都可见 —— 本机/本版本上 GPU 粒子未失效。")
			print("   仍需按 T-03 保守处理（不同机型驱动可能不同），并在真机复验。")
		else:
			print("❌ CPU 粒子也不可见（%d 像素）—— 说明统计方式或渲染器有问题，需要人工排查。" % cpu_px)
			code = 1
	else:
		print("ℹ️ 非 Compatibility 渲染器（%s），此结果不作为 T-03 的依据。" % _method)
		if cpu_px > 50 and gpu_px > 50:
			print("   两者都可见，符合 Forward+ 的预期。")
		else:
			print("   ⚠️ 至少一侧不可见，需要人工排查。")
			code = 1

	print("")
	quit(code)
	return true


func _count_bright(img: Image, center: Vector2) -> int:
	var r := Rect2i(
		int(center.x + REGION.position.x), int(center.y + REGION.position.y),
		int(REGION.size.x), int(REGION.size.y))
	var w := img.get_width()
	var h := img.get_height()
	r = r.intersection(Rect2i(0, 0, w, h))

	var n := 0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var c := img.get_pixel(x, y)
			# 相对深色背景的亮度
			if (c.r + c.g + c.b) / 3.0 > BRIGHT_THRESHOLD:
				n += 1
	return n
