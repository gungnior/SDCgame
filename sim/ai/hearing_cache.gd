class_name HearingFieldCache
extends RefCounted

## 听觉代价场的缓存
##
## ⚠️ 为什么需要（安卓 profiler 实测）：
##   敌人 AI 阶段单帧冲到 **257 ms**，根因是每个敌人对每个噪声都跑一次
##   全网格 Dijkstra（`Perception.hearing_cost`），每敌人每帧都是新的分配 + 全图松弛。
##
##   代价函数是对称的（cost(噪声→听者) == cost(听者→噪声)），
##   所以从**听者所在格**出发跑一次场，就能 O(1) 查到**任意**噪声的位置。
##   而敌人移动很慢 —— 按【格子】缓存，绝大多数帧直接命中。
##
## 用法：
##   var cache := HearingFieldCache.new()
##   var f := cache.field_for(grid, pos)          # 每帧每敌人一次（大概率命中）
##   if Perception.can_hear_at(f, grid, noise_pos, loudness): ...

## 最多缓存多少个格子。48 约等于 3~4 帧内全部敌人的位置数，够用且省内存
const MAX_ENTRIES := 48

var _fields: Dictionary = {}      ## cell_index -> PackedInt32Array
var _order: Array[int] = []       ## 简易 LRU：最近用过的排后面

## 统计（测试与调试用）
var hits := 0
var misses := 0
var builds := 0


## 取某个位置所在的「听觉代价场」。命中缓存则几乎零成本。
func field_for(grid: LogicalGrid, listener_pos: Vector2,
		wall_penalty: int = Perception.DEFAULT_WALL_PENALTY) -> PackedInt32Array:
	if grid == null or grid.width <= 0:
		return PackedInt32Array()
	var c := Ballistics.cell_of(listener_pos)
	if c.x < 0 or c.y < 0 or c.x >= grid.width or c.y >= grid.height:
		return PackedInt32Array()
	var key := c.y * grid.width + c.x

	var cached: Variant = _fields.get(key)
	if cached != null:
		hits += 1
		_touch(key)
		return cached

	misses += 1
	builds += 1
	var f := Perception.hearing_field(grid, Ballistics.cell_center(c), wall_penalty)
	_fields[key] = f
	_order.append(key)
	while _order.size() > MAX_ENTRIES:
		var old: int = _order.pop_front()
		_fields.erase(old)
	return f


func _touch(key: int) -> void:
	var i := _order.find(key)
	if i >= 0 and i < _order.size() - 1:
		_order.remove_at(i)
		_order.append(key)


## 地图变了（重开一局）必须清空 —— 否则会用到上一张图的场
func clear() -> void:
	_fields.clear()
	_order.clear()


func size() -> int:
	return _fields.size()


func stats() -> String:
	var total := hits + misses
	var rate := 0.0 if total == 0 else float(hits) / float(total) * 100.0
	return "听觉场缓存：%d 份，命中 %d / 构建 %d（命中率 %.0f%%）" % [
		_fields.size(), hits, builds, rate]
