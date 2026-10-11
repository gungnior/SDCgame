class_name FlowField
extends RefCounted

## 流场寻路 —— specs/tech-stack.md §4.2（T-81）
##
## 三层数据（全部是纯数组，无 Node 依赖，可 headless 单测）：
##   Cost Field        墙不可通行 / 地面代价
##   Integration Field 从目标出发的 Dijkstra 距离场（正交 10 / 对角 14）
##   Direction Field   每格指向 integration 最小的邻居
##
## ⚠️ 为什么自己写：Godot Asset Library 检索 "flow field" 实测返回 0 条，
##    生态里没有可用的流场插件。起点参考 Griiimon/Manymies（MIT），
##    但它用 `active_points.remove_at(0)` 做队列 —— GDScript 里这是 O(n) 头删，
##    整个 BFS 会退化成 O(n²)。**本实现用二叉堆，不存在这个问题。**

const ORTHO := 10
const DIAG := 14
const IMPASSABLE := 0x0FFFFFFF

## 8 邻域方向。索引即方向编号，写进 _dir。
const DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

var width: int = 0
var height: int = 0
var target: Vector2i = Vector2i(-1, -1)
var valid: bool = false

var _cost: PackedByteArray = PackedByteArray()        ## 0 = 不可通行，>0 = 通行代价倍数
var _integration: PackedInt32Array = PackedInt32Array()
var _dir: PackedInt32Array = PackedInt32Array()       ## 方向编号；-1 = 无方向（该格即目标或不可达）

# 二叉堆（用两个平行数组，避免 Array[Array] 的开销）
var _heap_node: PackedInt32Array = PackedInt32Array()
var _heap_prio: PackedInt32Array = PackedInt32Array()


func setup(w: int, h: int) -> void:
	width = maxi(0, w)
	height = maxi(0, h)
	_cost = PackedByteArray()
	_cost.resize(width * height)
	_cost.fill(1)
	_integration = PackedInt32Array()
	_integration.resize(width * height)
	_dir = PackedInt32Array()
	_dir.resize(width * height)
	valid = false


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func _idx(c: Vector2i) -> int:
	return c.y * width + c.x


## 从逻辑网格载入地形。可走 = cost 1，不可走 = cost 0。
func load_from_grid(g: LogicalGrid, walk_cost: int = 1) -> void:
	setup(g.width, g.height)
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			_cost[_idx(c)] = walk_cost if g.is_walkable(c) else 0
	valid = false


func set_blocked(c: Vector2i, blocked: bool) -> void:
	if not in_bounds(c):
		return
	_cost[_idx(c)] = 0 if blocked else 1
	valid = false


func set_cost(c: Vector2i, cost: int) -> void:
	if not in_bounds(c):
		return
	_cost[_idx(c)] = clampi(cost, 0, 255)
	valid = false


func cost_at(c: Vector2i) -> int:
	if not in_bounds(c):
		return 0
	return _cost[_idx(c)]


func integration_at(c: Vector2i) -> int:
	if not in_bounds(c):
		return IMPASSABLE
	return _integration[_idx(c)]


func is_reachable(c: Vector2i) -> bool:
	return in_bounds(c) and _integration[_idx(c)] < IMPASSABLE


# ─────────────────── 构建 ───────────────────

## 从 target 出发构建整个流场。O(n log n)。
func build(t: Vector2i) -> void:
	target = t
	valid = false
	if width <= 0 or height <= 0:
		return

	_integration.fill(IMPASSABLE)
	_dir.fill(-1)

	if not in_bounds(t) or _cost[_idx(t)] == 0:
		return   # 目标在墙里 —— 整个场视为无效

	_integration[_idx(t)] = 0
	_heap_node.clear()
	_heap_prio.clear()
	_heap_push(_idx(t), 0)

	while not _heap_node.is_empty():
		var cur_i := _heap_pop()
		var cur := Vector2i(cur_i % width, cur_i / width)
		var cur_d := _integration[cur_i]

		for di in DIRS.size():
			var d: Vector2i = DIRS[di]
			var nb := cur + d
			if not in_bounds(nb):
				continue
			var nb_i := _idx(nb)
			var c := _cost[nb_i]
			if c == 0:
				continue

			var is_diag := d.x != 0 and d.y != 0
			if is_diag:
				# 防贴角穿墙：对角移动要求两个正交邻居至少一个可通行
				# 等价于 AStarGrid2D 的 DIAGONAL_MODE_AT_LEAST_ONE_WALKABLE
				var a := Vector2i(cur.x + d.x, cur.y)
				var b := Vector2i(cur.x, cur.y + d.y)
				if cost_at(a) == 0 and cost_at(b) == 0:
					continue

			var step := DIAG if is_diag else ORTHO
			var nd := cur_d + step * c
			if nd < _integration[nb_i]:
				_integration[nb_i] = nd
				_heap_push(nb_i, nd)

	# Direction Field：每格指向 integration 最小的邻居
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			var ci := _idx(c)
			if _cost[ci] == 0 or _integration[ci] >= IMPASSABLE:
				continue
			if c == t:
				_dir[ci] = -1
				continue
			var best := -1
			var best_v := _integration[ci]
			for di in DIRS.size():
				var nb: Vector2i = c + DIRS[di]
				if not in_bounds(nb):
					continue
				var v := _integration[_idx(nb)]
				if v < best_v:
					best_v = v
					best = di
			_dir[ci] = best

	valid = true


## 该格应当往哪个方向走。返回 Vector2i.ZERO 表示无方向（目标格 / 不可达）。
func get_direction(c: Vector2i) -> Vector2i:
	if not valid or not in_bounds(c):
		return Vector2i.ZERO
	var d := _dir[_idx(c)]
	if d < 0:
		return Vector2i.ZERO
	return DIRS[d]


## 从任意格沿流场走到目标，返回路径（含起点，不含目标时也返回）。
## 供调试与"是否需要重算"判断使用；正常寻路不必生成路径。
func trace_path(from: Vector2i, max_steps: int = 512) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not valid or not is_reachable(from):
		return out
	var c := from
	var guard := 0
	while c != target and guard < max_steps:
		out.append(c)
		var d := get_direction(c)
		if d == Vector2i.ZERO:
			break
		c += d
		guard += 1
	if c == target:
		out.append(target)
	return out


# ─────────────────── 二叉堆 ───────────────────

func _heap_swap(i: int, j: int) -> void:
	var tn := _heap_node[i]
	_heap_node[i] = _heap_node[j]
	_heap_node[j] = tn
	var tp := _heap_prio[i]
	_heap_prio[i] = _heap_prio[j]
	_heap_prio[j] = tp


func _heap_push(node: int, prio: int) -> void:
	_heap_node.append(node)
	_heap_prio.append(prio)
	var i := _heap_node.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if _heap_prio[p] <= _heap_prio[i]:
			break
		_heap_swap(i, p)
		i = p


func _heap_pop() -> int:
	var n := _heap_node.size()
	if n == 0:
		return -1
	var top := _heap_node[0]
	if n > 1:
		_heap_node[0] = _heap_node[n - 1]
		_heap_prio[0] = _heap_prio[n - 1]
	_heap_node.resize(n - 1)
	_heap_prio.resize(n - 1)

	var i := 0
	var m := _heap_node.size()
	while true:
		var l := 2 * i + 1
		var r := 2 * i + 2
		var best := i
		if l < m and _heap_prio[l] < _heap_prio[best]:
			best = l
		if r < m and _heap_prio[r] < _heap_prio[best]:
			best = r
		if best == i:
			break
		_heap_swap(i, best)
		i = best
	return top


# ─────────────────── 调试 ───────────────────

## 用箭头画出方向场（不可达为 '#'，目标为 'T'，地面为 '.'）
func to_ascii_arrows() -> String:
	var glyph := {0: "→", 1: "←", 2: "↓", 3: "↑", 4: "↘", 5: "↙", 6: "↗", 7: "↖"}
	var out := ""
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			var ci := _idx(c)
			if _cost[ci] == 0:
				out += "#"
			elif c == target:
				out += "T"
			elif _dir[ci] < 0:
				out += " "   # 不可达
			else:
				out += glyph.get(_dir[ci], "?")
		out += "\n"
	return out


## 用两位十六进制打印 integration（调试距离场）
func to_ascii_integration() -> String:
	var out := ""
	for y in height:
		for x in width:
			var v := _integration[y * width + x]
			if v >= IMPASSABLE:
				out += " ."
			else:
				out += "%2d" % mini(v / 10, 99)
		out += "\n"
	return out


func _to_string() -> String:
	return "FlowField(%dx%d, target=%s, valid=%s)" % [width, height, str(target), str(valid)]
