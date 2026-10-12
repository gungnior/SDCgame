class_name FxPool
extends Node2D

## 一次性粒子池 —— 枪口火光 / 血雾 / 弹着 / 弹壳
##
## 依据 specs/tech-stack.md T-03：
##   **所有粒子必须用 `CPUParticles2D`** —— Android 上 GPUParticles2D 不可靠
##   （实测：桌面 OpenGL 能跑，Android OpenGL ES 不行；结论不变）
##
## 池化的原因同音效：移动端不能每次 new 节点。

const KINDS := {
	# 枪口火光：极短、向前、亮黄
	"muzzle": {
		"amount": 5, "lifetime": 0.075, "explosiveness": 1.0,
		"direction": Vector2.RIGHT, "spread": 16.0,
		"vel_min": 90.0, "vel_max": 190.0, "gravity": Vector2.ZERO,
		"scale_min": 1.6, "scale_max": 3.2, "damping": 55.0,
		"color": Color(1.0, 0.86, 0.42, 0.95),
		"ramp": Color(1.0, 0.35, 0.08, 0.0),
	},
	# 血雾：向后喷、受重力
	"blood": {
		"amount": 14, "lifetime": 0.55, "explosiveness": 0.9,
		"direction": Vector2.RIGHT, "spread": 62.0,
		"vel_min": 40.0, "vel_max": 150.0, "gravity": Vector2(0, 210),
		"scale_min": 1.2, "scale_max": 2.8, "damping": 18.0,
		"color": Color(0.69, 0.13, 0.15, 1.0),
		"ramp": Color(0.29, 0.08, 0.09, 0.0),
	},
	# 暴击血雾：更多更大更红
	"blood_crit": {
		"amount": 26, "lifetime": 0.7, "explosiveness": 0.95,
		"direction": Vector2.RIGHT, "spread": 78.0,
		"vel_min": 60.0, "vel_max": 210.0, "gravity": Vector2(0, 240),
		"scale_min": 1.8, "scale_max": 4.0, "damping": 16.0,
		"color": Color(0.78, 0.18, 0.20, 1.0),
		"ramp": Color(0.35, 0.06, 0.07, 0.0),
	},
	# 弹着火花：小、散、短
	"impact": {
		"amount": 8, "lifetime": 0.22, "explosiveness": 1.0,
		"direction": Vector2.RIGHT, "spread": 80.0,
		"vel_min": 50.0, "vel_max": 170.0, "gravity": Vector2(0, 160),
		"scale_min": 0.9, "scale_max": 2.0, "damping": 40.0,
		"color": Color(0.92, 0.88, 0.72, 0.95),
		"ramp": Color(0.42, 0.40, 0.36, 0.0),
	},
	# 弹壳：小、抛向右后、有重力
	"casing": {
		"amount": 1, "lifetime": 0.6, "explosiveness": 1.0,
		"direction": Vector2.RIGHT, "spread": 26.0,
		"vel_min": 60.0, "vel_max": 110.0, "gravity": Vector2(0, 320),
		"scale_min": 1.0, "scale_max": 1.0, "damping": 8.0,
		"color": Color(0.78, 0.64, 0.28, 1.0),
		"ramp": Color(0.60, 0.46, 0.18, 0.0),
	},
	# 击杀确认：向外的白环
	"kill": {
		"amount": 12, "lifetime": 0.35, "explosiveness": 1.0,
		"direction": Vector2.RIGHT, "spread": 180.0,
		"vel_min": 70.0, "vel_max": 130.0, "gravity": Vector2.ZERO,
		"scale_min": 1.4, "scale_max": 2.6, "damping": 90.0,
		"color": Color(1.0, 0.95, 0.85, 0.9),
		"ramp": Color(1.0, 0.85, 0.45, 0.0),
	},
}

const POOL_PER_KIND := 10

var _pool: Dictionary = {}          ## kind -> Array[CPUParticles2D]
var _next: Dictionary = {}          ## kind -> int
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	z_index = 40                     ## 粒子压在实体之上、HUD 之下
	_rng.seed = 20261012
	for kind in KINDS:
		var arr: Array = []
		for i in POOL_PER_KIND:
			var p := _make(kind)
			add_child(p)
			arr.append(p)
		_pool[kind] = arr
		_next[kind] = 0


func _make(kind: String) -> CPUParticles2D:
	var cfg: Dictionary = KINDS[kind]
	var p := CPUParticles2D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = int(cfg["amount"])
	p.lifetime = float(cfg["lifetime"])
	p.explosiveness = float(cfg["explosiveness"])
	p.randomness = 0.5
	p.local_coords = false          ## 世界坐标，粒子和发射器解耦
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5
	p.direction = cfg["direction"]
	p.spread = float(cfg["spread"])
	p.initial_velocity_min = float(cfg["vel_min"])
	p.initial_velocity_max = float(cfg["vel_max"])
	p.gravity = cfg["gravity"]
	p.damping_min = float(cfg["damping"]) * 0.6
	p.damping_max = float(cfg["damping"])
	p.scale_amount_min = float(cfg["scale_min"])
	p.scale_amount_max = float(cfg["scale_max"])
	p.color = cfg["color"]
	var ramp := Gradient.new()
	ramp.set_color(0, cfg["color"])
	ramp.set_color(1, cfg["ramp"])
	p.color_ramp = ramp
	# 像素风：用一个小方块当粒子贴图（无美术依赖，且天然是硬边像素块）
	p.texture = _square_texture()
	return p


## 生成一个 3x3 的纯色方块纹理（一次性建好复用）
static var _sq: ImageTexture = null
static func _square_texture() -> ImageTexture:
	if _sq != null:
		return _sq
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_sq = ImageTexture.create_from_image(img)
	return _sq


## 在 pos 处喷一组粒子。dir 决定喷射方向（世界坐标）。
func burst(kind: String, pos: Vector2, dir: Vector2 = Vector2.RIGHT,
		scale: float = 1.0) -> void:
	if not _pool.has(kind):
		return
	var arr: Array = _pool[kind]
	var i: int = int(_next[kind])
	_next[kind] = (i + 1) % arr.size()
	var p: CPUParticles2D = arr[i]
	p.global_position = pos
	p.direction = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	p.scale_amount_min = float(KINDS[kind]["scale_min"]) * scale
	p.scale_amount_max = float(KINDS[kind]["scale_max"]) * scale
	p.restart()
	p.emitting = true


## 广播给所有粒子节点设置可见性（无障碍：降低闪烁）
func set_particles_enabled(on: bool) -> void:
	visible = on
