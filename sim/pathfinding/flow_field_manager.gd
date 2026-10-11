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
