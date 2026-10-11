class_name FlowFieldManager
extends RefCounted

## 流场缓存管理器 —— specs/tech-stack.md §4.2（T-81）
##
## 同一目标的所有敌人【共用一份流场】，且只在目标换格时重建。
## 这是"20–30 个敌人追同一目标"能做到手机可用的关键。
##
## 纯 RefCounted，可 headless 单测。

var _grid: LogicalGrid = null
var _fields: Dictionary = {}        ## target_cell(Vector2i) -> FlowField

## 统计（用于验证"只在换格时重建"这条优化真的生效）
var build_count: int = 0            ## 实际构建次数
var hit_count: int = 0              ## 缓存命中次数


func setup(grid: LogicalGrid) -> void:
	_grid = grid
	_fields.clear()
	build_count = 0
	hit_count = 0


## 取目标格对应的流场；不存在则构建。
func field_for(target_cell: Vector2i) -> FlowField:
	if _grid == null:
		return null
	if _fields.has(target_cell):
		hit_count += 1
		return _fields[target_cell]

	var f := FlowField.new()
	f.load_from_grid(_grid)
	f.build(target_cell)
	_fields[target_cell] = f
	build_count += 1
	return f


## 敌人调用这个拿方向。target_cell 是目标当前所在逻辑格。
func direction_for(agent_cell: Vector2i, target_cell: Vector2i) -> Vector2i:
	var f := field_for(target_cell)
	if f == null:
		return Vector2i.ZERO
	return f.get_direction(agent_cell)


func has_field(target_cell: Vector2i) -> bool:
	return _fields.has(target_cell)


# ─────────────────── 连续空间推进 ───────────────────

## 沿流场把位置从 pos 朝目标推进 speed*delta 的距离，返回新位置。
##
## ⚠️ 两个实测踩过的坑，都在这里修掉了：
##
## ① 不能「沿方向向量平移」
##    连续坐标会逐渐漂离格子中心，最终越过墙角进入实心格，
##    之后流场在该格没有方向 → 永久卡死。
##    ⇒ 本函数朝【下一个格子的中心】走。
##
## ② 对角移动的直线可能擦过墙角
##    从 (12,22) 斜走到对角格 (13,21) 时，直线会经过 (13,22)，
##    而流场允许对角移动只需【两个正交邻居之一】可通行 —— 所以 (13,22) 可能是墙。
##    ⇒ 本函数检查落点格是否可走；不可走就退化成正交单轴移动。
func step_toward(pos: Vector2, target_cell: Vector2i, speed: float, delta: float) -> Vector2:
	if speed <= 0.0 or delta <= 0.0:
		return pos
	var my_cell := Ballistics.cell_of(pos)
	if my_cell == target_cell:
		return pos
	var d := direction_for(my_cell, target_cell)
	if d == Vector2i.ZERO:
		return pos
	if not _cell_walkable(my_cell + d):
		return pos

	var step := speed * delta
	var next_center := Ballistics.cell_center(my_cell + d)
	var to_next := next_center - pos
	var dist := to_next.length()
	if dist <= 0.0001:
		return next_center
	var dir_unit := to_next / dist

	# 试完整一步（含对角）
	var full := pos + dir_unit * minf(step, dist)
	if dist <= step:
		full = next_center
	if _pos_walkable(full):
		return full

	# 擦墙角 -> 退化为正交单轴：优先走那个「单轴邻居可走」的方向
	var axes: Array[Vector2i] = []
	if d.x != 0:
		axes.append(Vector2i(d.x, 0))
	if d.y != 0:
		axes.append(Vector2i(0, d.y))
	var p := pos
	var remaining := step
	for ax in axes:
		if remaining <= 0.0:
			break
		var ac := Ballistics.cell_of(p)
		var nc := ac + ax
		if not _cell_walkable(nc):
			continue
		var center := Ballistics.cell_center(nc)
		var v := center - p
		var vl := v.length()
		if vl <= 0.0001:
			continue
		var mv := minf(remaining, vl)
		p = p + v / vl * mv
		remaining -= mv
	return p


func _cell_walkable(c: Vector2i) -> bool:
	return _grid != null and _grid.is_walkable(c)


func _pos_walkable(p: Vector2) -> bool:
	return _cell_walkable(Ballistics.cell_of(p))


## 是否已经走到目标格
func at_target(pos: Vector2, target_cell: Vector2i) -> bool:
	return Ballistics.cell_of(pos) == target_cell


func field_count() -> int:
	return _fields.size()


## 地形变化（可破坏墙被打掉 / 门开关）→ 全部失效，下次访问时重建
func invalidate_all() -> void:
	_fields.clear()


func invalidate(target_cell: Vector2i) -> void:
	_fields.erase(target_cell)


## 限制缓存规模：只保留最近 keep 个目标格（LRU 近似：随机淘汰）
func trim_to(keep: int) -> void:
	if _fields.size() <= keep:
		return
	var keys := _fields.keys()
	while _fields.size() > keep:
		_fields.erase(keys.pop_back())


func stats() -> String:
	return "流场缓存: %d 份, 构建 %d 次, 命中 %d 次 (命中率 %.0f%%)" % [
		_fields.size(), build_count, hit_count,
		(100.0 * hit_count / maxf(1.0, float(hit_count + build_count)))]


func _to_string() -> String:
	return "FlowFieldManager(%s)" % stats()
