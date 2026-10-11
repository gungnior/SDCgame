class_name Perception
extends RefCounted

## 感知：视野锥 + 听觉（基于格子）
##
## 依据 specs/tech-stack.md：
##   T-84  视线遮挡走【格子】而不是物理引擎；两级粗筛（数学 → 遮挡）
##   T-85  Godot 没有游戏逻辑层面的听觉 API —— 自己写。
##         推荐：全局 noise_emitted + 【基于格子的声音强度场】，穿墙衰减天然正确
##
## 纯静态方法，可 headless 单测。

## 声音穿越一格实心墙的额外代价（代价单位 = 1 格空气）
const DEFAULT_WALL_PENALTY := 6


## 能否看见目标。两级粗筛：距离² + 点积夹角 → 格子遮挡。
static func can_see(grid: LogicalGrid, from_pos: Vector2, facing: Vector2, target_pos: Vector2, def: EnemyDef) -> bool:
	if def == null or grid == null:
		return false
	var d := target_pos - from_pos
	var dist2 := d.length_squared()
	var range_m := float(def.sight_range_m)
	if dist2 > range_m * range_m:
		return false
	var dist := sqrt(dist2)
	if dist <= 0.000001:
		return true
	var f := facing
	if f.is_zero_approx():
		return false
	# 视野锥：dot(facing, to_target) > cos(半角)
	if f.normalized().dot(d / dist) < def.sight_cos_half_angle():
		return false
	# 遮挡检查
	return Ballistics.has_line_of_sight(grid, from_pos, target_pos)


## 从声源做代价 Dijkstra 得到"到 listener 的传播代价"。
## 走空气 = 1，穿墙 = 1 + wall_penalty。这样"隔墙传声衰减"天然正确。
## 返回代价（整数，越小越响）；不可达返回 -1。
static func hearing_cost(grid: LogicalGrid, from_pos: Vector2, to_pos: Vector2,
		wall_penalty: int = DEFAULT_WALL_PENALTY) -> int:
	if grid == null or grid.width <= 0:
		return -1
	var w := grid.width
	var h := grid.height
	var src := Ballistics.cell_of(from_pos)
	var dst := Ballistics.cell_of(to_pos)
	if src.x < 0 or src.y < 0 or src.x >= w or src.y >= h:
		return -1
	if dst.x < 0 or dst.y < 0 or dst.x >= w or dst.y >= h:
		return -1
	if src == dst:
		return 0

	const IMPASSABLE := 0x0FFFFFFF
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(IMPASSABLE)

	var heap_node := PackedInt32Array()
	var heap_prio := PackedInt32Array()

	var src_i := src.y * w + src.x
	dist[src_i] = 0
	heap_node.append(src_i)
	heap_prio.append(0)

	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while not heap_node.is_empty():
		# 弹出最小
		var cur := heap_node[0]
		var cur_d := heap_prio[0]
		var n := heap_node.size()
		if n > 1:
			heap_node[0] = heap_node[n - 1]
			heap_prio[0] = heap_prio[n - 1]
		heap_node.resize(n - 1)
		heap_prio.resize(n - 1)
		var i := 0
		var m := heap_node.size()
		while true:
			var l := 2 * i + 1
			var r := 2 * i + 2
			var best := i
			if l < m and heap_prio[l] < heap_prio[best]:
				best = l
			if r < m and heap_prio[r] < heap_prio[best]:
				best = r
			if best == i:
				break
			var tn := heap_node[i]; heap_node[i] = heap_node[best]; heap_node[best] = tn
			var tp := heap_prio[i]; heap_prio[i] = heap_prio[best]; heap_prio[best] = tp
			i = best

		if cur_d > dist[cur]:
			continue
		if cur == dst.y * w + dst.x:
			return cur_d

		var cx := cur % w
		var cy := cur / w
		for d: Vector2i in dirs:
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var ni := ny * w + nx
			var step := 1
			if not grid.is_walkable(Vector2i(nx, ny)):
				step += wall_penalty
			var nd := cur_d + step
			if nd < dist[ni]:
				dist[ni] = nd
				heap_node.append(ni)
				heap_prio.append(nd)
				# 上浮
				var k := heap_node.size() - 1
				while k > 0:
					var p := (k - 1) / 2
					if heap_prio[p] <= heap_prio[k]:
						break
					var a := heap_node[p]; heap_node[p] = heap_node[k]; heap_node[k] = a
					var b := heap_prio[p]; heap_prio[p] = heap_prio[k]; heap_prio[k] = b
					k = p

	return -1


## 能否听到。loudness_m 是"响度半径"（米 ≈ 逻辑格）。
static func can_hear(grid: LogicalGrid, noise_pos: Vector2, listener_pos: Vector2,
		loudness_m: float, wall_penalty: int = DEFAULT_WALL_PENALTY) -> bool:
	if loudness_m <= 0.0:
		return false
	var cost := hearing_cost(grid, noise_pos, listener_pos, wall_penalty)
	if cost < 0:
		return false
	return float(cost) <= loudness_m


## 从声源求出受影响的格子集合（供表现层/调试用）
static func hearing_reach(grid: LogicalGrid, noise_pos: Vector2, loudness_m: float,
		wall_penalty: int = DEFAULT_WALL_PENALTY) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if grid == null:
		return out
	for y in grid.height:
		for x in grid.width:
			var c := Vector2i(x, y)
			var cost := hearing_cost(grid, noise_pos, Ballistics.cell_center(c), wall_penalty)
			if cost >= 0 and float(cost) <= loudness_m:
				out.append(c)
	return out


## 单个敌人的默认听觉半径（用 EnemyDef.hear_range_m）
static func hears_noise(grid: LogicalGrid, def: EnemyDef, noise_pos: Vector2, listener_pos: Vector2,
		noise_loudness_m: float) -> bool:
	if def == null:
		return false
	var reach := minf(float(def.hear_range_m), noise_loudness_m)
	return can_hear(grid, noise_pos, listener_pos, reach)
