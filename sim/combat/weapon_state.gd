class_name WeaponState
extends RefCounted

## 一把枪的运行时状态：射击节流 / 换弹 / 后坐力累积与恢复
##
## 依据 specs/tech-stack.md：
##   T-50  射速节流用 rpm 换算，不依赖物理帧
##   T-51  逻辑层不依赖渲染帧
##   7.3   后坐力 = 视觉 kick 与准心真实偏移【两条独立通道】；
##         这里只管【准心真实偏移】这一条（视觉由表现层读 recoil 自行处理）
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。

const RECOIL_PER_SHOT := 0.16         ## 每发累积 0.16
const RECOIL_RECOVERY_PER_SEC := 1.5  ## 每秒恢复 1.5
const MAX_RECOIL := 1.0

var def: WeaponDef = null
var ammo_in_mag: int = 0
var reserve_ammo: int = 0

var cooldown: float = 0.0             ## 距下一发可射的剩余秒数
var reload_timer: float = 0.0         ## >0 表示正在换弹
var recoil: float = 0.0               ## 0~1 累积后坐力

var shots_fired: int = 0
var shots_hit: int = 0


func _init(weapon: WeaponDef = null, reserve: int = 0) -> void:
	def = weapon
	reserve_ammo = reserve
	if def != null:
		ammo_in_mag = def.mag_size


func is_reloading() -> bool:
	return reload_timer > 0.0


func can_fire() -> bool:
	return def != null and cooldown <= 0.0 and not is_reloading() and ammo_in_mag > 0


## 当前实际散布（度）= 基础散布 + 后坐力带来的额外散布
func current_spread_deg() -> float:
	if def == null:
		return 0.0
	return def.spread_deg + recoil * def.spread_deg * 3.0


func tick(delta: float) -> void:
	if def == null:
		return
	cooldown = maxf(0.0, cooldown - delta)
	recoil = maxf(0.0, recoil - RECOIL_RECOVERY_PER_SEC * delta)
	if MAX_RECOIL > 0.0:
		recoil = minf(recoil, MAX_RECOIL)

	if reload_timer > 0.0:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()


## 开一枪。返回 true 表示真的射出去了。
func fire() -> bool:
	if not can_fire():
		return false
	ammo_in_mag -= 1
	cooldown = def.shot_interval()
	recoil = minf(MAX_RECOIL, recoil + RECOIL_PER_SHOT)
	shots_fired += 1
	return true


## 记一次命中（仅用于统计）
func mark_hit() -> void:
	shots_hit += 1


func start_reload() -> bool:
	if def == null or is_reloading():
		return false
	if ammo_in_mag >= def.mag_size:
		return false
	if reserve_ammo <= 0:
		return false
	reload_timer = def.reload_time
	return true


func _finish_reload() -> void:
	if def == null:
		return
	var need := def.mag_size - ammo_in_mag
	var take := mini(need, reserve_ammo)
	ammo_in_mag += take
	reserve_ammo -= take


## 打断换弹（受伤 / 切枪）
func cancel_reload() -> void:
	reload_timer = 0.0


func accuracy() -> float:
	return DamageModel.accuracy_at(def, 0.0, recoil * 3.0 * (def.spread_deg if def else 0.0) / 6.0)


func _to_string() -> String:
	return "WeaponState(%s, mag=%d/%d, reserve=%d, recoil=%.2f%s)" % [
		def.id if def else "?",
		ammo_in_mag, def.mag_size if def else 0,
		reserve_ammo, recoil,
		" [reloading]" if is_reloading() else ""]
