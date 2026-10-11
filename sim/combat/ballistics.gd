class_name Ballistics
extends RefCounted

## 网格射线 —— 纯数据，零物理调用
##
## 依据 specs/tech-stack.md：
##   T-50  hitscan 射线做权威判定，表现层再决定画不画飞行子弹
##   T-84  视线遮挡走【格子】而不是物理引擎 —— 纯数组操作，可 headless 单测
##   T-86  格子级可见性表是网格地图最大的红利，比任何射线调优都省
##
## 坐标约定：位置是【逻辑格单位】的浮点坐标。
##   逻辑格 (x, y) 覆盖 [x, x+1) × [y, y+1)，故 cell_of(p) = Vector2i(floor(p))。

## 网格 DDA（Amanatides-Woo）。返回从 from 到 to 经过的逻辑格序列（含起点，不含越界）。
static func raycast_cells(grid: LogicalGrid, from: Vector2, to: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if grid == null or grid.width <= 0 or grid.height <= 0:
		return out

	var cx := int(floor(from.x))
	var cy := int(floor(from.y))
	var tx := int(floor(to.x))
	var ty := int(floor(to.y))

	var dx := to.x - from.x
	var dy := to.y - from.y

	var step_x := 1 if dx > 0.0 else (-1 if dx < 0.0 else 0)
	var step_y := 1 if dy > 0.0 else (-1 if dy < 0.0 else 0)

	var t_max_x := INF
	var t_delta_x := INF
	if dx != 0.0:
		t_delta_x = absf(1.0 / dx)
		var next_boundary := float(cx + (1 if step_x > 0 else 0))
		t_max_x = (next_boundary - from.x) / dx

	var t_max_y := INF
	var t_delta_y := INF
	if dy != 0.0:
		t_delta_y = absf(1.0 / dy)
		var next_boundary_y := float(cy + (1 if step_y > 0 else 0))
		t_max_y = (next_boundary_y - from.y) / dy

	var guard := 0
	var limit := grid.width * grid.height + 8
	while guard < limit:
		guard += 1
		if cx >= 0 and cy >= 0 and cx < grid.width and cy < grid.height:
			out.append(Vector2i(cx, cy))
		if cx == tx and cy == ty:
			break
		if t_max_x < t_max_y:
			cx += step_x
			t_max_x += t_delta_x
		else:
			cy += step_y
			t_max_y += t_delta_y
	return out


## 从 from 到 to 的第一个实心格。没打到墙返回 null。
static func first_blocking_cell(grid: LogicalGrid, from: Vector2, to: Vector2) -> Variant:
	for c: Vector2i in raycast_cells(grid, from, to):
		if not grid.is_walkable(c):
			return c
	return null


## 两点之间是否通视（无墙阻挡）
static func has_line_of_sight(grid: LogicalGrid, from: Vector2, to: Vector2) -> bool:
	if grid == null:
		return false
	var cells: Array[Vector2i] = raycast_cells(grid, from, to)
	if cells.is_empty():
		return false
	# 跳过起点所在格（射手可能正贴着墙），其余必须是可走格
	for i in range(1, cells.size()):
		if not grid.is_walkable(cells[i]):
			return false
	return true


## 点 p 投影到线段 from->to 上的归一化参数 t（0=起点，1=终点），并 clamp 到 [0,1]
static func project_t(from: Vector2, to: Vector2, p: Vector2) -> float:
	var d := to - from
	var len2 := d.length_squared()
	if len2 <= 0.000001:
		return 0.0
	return clampf(((p - from).dot(d)) / len2, 0.0, 1.0)


## 点 p 到线段 from->to 的垂直距离
static func distance_to_segment(from: Vector2, to: Vector2, p: Vector2) -> float:
	var t := project_t(from, to, p)
	return from.lerp(to, t).distance_to(p)


## 从 from 沿方向 dir 找第一个角度偏差在 max_angle_deg 内、且通视的目标。
## targets 是 [{pos: Vector2, id: Variant}]，返回命中的字典或 null。
## 这是 T-84 的两级粗筛：先用数学筛，再对候选做遮挡检查。
static func acquire_target(
	grid: LogicalGrid,
	from: Vector2,
	dir: Vector2,
	targets: Array,
	max_range: float,
	max_angle_deg: float
) -> Dictionary:
	if dir.is_zero_approx() or targets.is_empty():
		return {}
	var dir_n := dir.normalized()
	var cos_limit := cos(deg_to_rad(max_angle_deg))

	# 第一级：距离平方 + 点积夹角（零物理开销）
	var cands: Array = []
	for t: Dictionary in targets:
		var tp: Vector2 = t.get("pos", Vector2.ZERO)
		var d := tp - from
		var dist2 := d.length_squared()
		if dist2 > max_range * max_range:
			continue
		var dist := sqrt(dist2)
		if dist <= 0.000001:
			cands.append({"t": t, "dist": 0.0})
			continue
		if dir_n.dot(d / dist) < cos_limit:
			continue
		cands.append({"t": t, "dist": dist})

	if cands.is_empty():
		return {}

	# 近的先判，命中即止（子弹先打到近的）
	cands.sort_custom(func(a, b): return a["dist"] < b["dist"])

	# 第二级：只对候选做遮挡检查
	for c: Dictionary in cands:
		var tp2: Vector2 = c["t"].get("pos", Vector2.ZERO)
		if has_line_of_sight(grid, from, tp2):
			return c["t"]
	return {}


## 在一次 hitscan 中，按距离排序找出最先命中的实体。
## 返回 {entity: Dictionary, dist: float, blocked_by_wall: bool}
static func hitscan_entities(
	grid: LogicalGrid,
	from: Vector2,
	to: Vector2,
	entities: Array,
	radius: float = 0.35
) -> Dictionary:
	var wall: Variant = first_blocking_cell(grid, from, to)
	var wall_t := 1.0
	if wall != null:
		# 墙中心的投影参数，作为命中上限
		wall_t = project_t(from, to, Vector2(wall.x + 0.5, wall.y + 0.5))

	var best: Dictionary = {}
	var best_t := 2.0
	for e: Dictionary in entities:
		var p: Vector2 = e.get("pos", Vector2.ZERO)
		var t := project_t(from, to, p)
		if t < 0.0 or t > 1.0 or t > wall_t:
			continue
		if distance_to_segment(from, to, p) > radius:
			continue
		if t < best_t:
			best_t = t
			var d := from.lerp(to, 1.0)
			best = {
				"entity": e,
				"t": t,
				"dist": from.distance_to(from.lerp(to, t)),
				"blocked_by_wall": false,
			}
	if best.is_empty():
		if wall != null:
			return {"entity": {}, "t": wall_t, "dist": from.distance_to(from.lerp(to, wall_t)), "blocked_by_wall": true}
		return {}
	return best


## 逻辑格中心的世界位置（供测试与表现层对齐）
static func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x + 0.5, c.y + 0.5)


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x)), int(floor(p.y)))
