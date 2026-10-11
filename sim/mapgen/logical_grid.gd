class_name LogicalGrid
extends RefCounted

## 逻辑网格 —— T-31 的落地（specs/tech-stack.md §5.3）
##
## 【这是整个 B 阶段最关键的一个决策】
##
## 把逻辑格定为 **3×3 tile**，走廊恒宽 **1 逻辑格**，于是：
##   1. 「最小可行走宽度 ≥3 格」从"每处都要小心"变成【结构上不可能违反】
##      —— 手机触屏操作，1 格宽的走廊是灾难（feasibility.md §4.2）
##   2. 寻路与生成规模缩小 9 倍（直接利好手机性能）
##   3. 走廊宽度恒定，AI 群体协同的包夹槽位计算更简单
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。

## 一个逻辑格 = 3 × 3 tile
const CELL_SIZE_TILES := 3
## tile 像素尺寸（art-pipeline.md §2）
const TILE_PX := 16
## 逻辑格像素尺寸（导出给表现层用）
const CELL_PX := CELL_SIZE_TILES * TILE_PX   # 48

enum Cell {
	SOLID = 0,      ## 实心（墙）
	FLOOR = 1,      ## 可走地面
	CORRIDOR = 2,   ## 走廊（生成期标记，语义等同于可走）
	DOOR = 3,       ## 门（可走，但表现层不同）
}

var width: int = 0    ## 逻辑格数
var height: int = 0
var _cells: PackedByteArray = PackedByteArray()


func _init(w: int = 0, h: int = 0) -> void:
	resize(w, h)


func resize(w: int, h: int) -> void:
	width = max(0, w)
	height = max(0, h)
	_cells = PackedByteArray()
	_cells.resize(width * height)
	_cells.fill(Cell.SOLID)   # 默认全是墙，由生成器挖开


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func _index(c: Vector2i) -> int:
	return c.y * width + c.x


func get_cell(c: Vector2i) -> int:
	if not in_bounds(c):
		return Cell.SOLID
	return _cells[_index(c)]


func set_cell(c: Vector2i, v: int) -> void:
	if not in_bounds(c):
		return
	_cells[_index(c)] = v


## 可走 = 非 SOLID。CORRIDOR / DOOR / FLOOR 都可走。
func is_walkable(c: Vector2i) -> bool:
	return get_cell(c) != Cell.SOLID


func walkable_count() -> int:
	var n := 0
	for v in _cells:
		if v != Cell.SOLID:
			n += 1
	return n


# ─────────────────── tile ↔ 逻辑格 坐标换算 ───────────────────

## 逻辑格 → 该格左上角 tile 坐标
func cell_to_tile_origin(c: Vector2i) -> Vector2i:
	return Vector2i(c.x * CELL_SIZE_TILES, c.y * CELL_SIZE_TILES)


## 逻辑格 → 覆盖的 tile 矩形
func cell_to_tile_rect(c: Vector2i) -> Rect2i:
	return Rect2i(cell_to_tile_origin(c), Vector2i(CELL_SIZE_TILES, CELL_SIZE_TILES))


## tile 坐标 → 所属逻辑格
func tile_to_cell(t: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(t.x) / CELL_SIZE_TILES)),
		int(floor(float(t.y) / CELL_SIZE_TILES)))


## tile 坐标是否可走 —— 展开自所属逻辑格。
## 表现层/物理层用这个；逻辑层直接用 is_walkable() 即可。
func tile_is_walkable(t: Vector2i) -> bool:
	return is_walkable(tile_to_cell(t))


## 整张地图的 tile 尺寸（供 TileMapLayer 使用）
func tile_extents() -> Vector2i:
	return Vector2i(width * CELL_SIZE_TILES, height * CELL_SIZE_TILES)


# ─────────────────── 生成期操作 ───────────────────

## 把矩形区域（逻辑格坐标，含端点）挖成 floor
func carve_rect(r: Rect2i, v: int = Cell.FLOOR) -> void:
	for y in range(max(0, r.position.y), min(height, r.position.y + r.size.y)):
		for x in range(max(0, r.position.x), min(width, r.position.x + r.size.x)):
			_cells[y * width + x] = v


## 挖一条 L 形走廊（先横后竖）。走廊恒宽 1 逻辑格 = 3 tile。
## 这就是「宽度约束结构上不可能违反」的实现点。
func carve_corridor_l(from: Vector2i, to: Vector2i, v: int = Cell.CORRIDOR) -> void:
	var cx := from.x
	var step_x := 1 if to.x >= from.x else -1
	while cx != to.x:
		_cells[from.y * width + cx] = v
		cx += step_x
	_cells[from.y * width + to.x] = v

	var cy := from.y
	var step_y := 1 if to.y >= from.y else -1
	while cy != to.y:
		_cells[cy * width + to.x] = v
		cy += step_y
	_cells[to.y * width + to.x] = v


# ─────────────────── 连通性校验（图论硬约束的第一步） ───────────────────

## 从 start 做 BFS，返回可达的逻辑格集合。
## 用于 specs/tech-stack.md §5.2 第 ⑧ 步：图论校验不通过就换 seed 重来。
func flood_fill(start: Vector2i) -> Dictionary:
	var seen := {}
	if not in_bounds(start) or not is_walkable(start):
		return seen
	var queue: Array[Vector2i] = [start]
	seen[start] = true
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in dirs:
			var n: Vector2i = c + d
			if in_bounds(n) and not seen.has(n) and is_walkable(n):
				seen[n] = true
				queue.append(n)
	return seen


## 全图是否连通（所有可走格互相可达）
func is_fully_connected() -> bool:
	var start: Variant = first_walkable()
	if start == null:
		return false
	return flood_fill(start).size() == walkable_count()


func first_walkable() -> Variant:
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			if is_walkable(c):
				return c
	return null


## 返回一张 ASCII 图，便于目视调试与测试断言
##   '#' = 墙   '.' = 地面   '+' = 走廊   'D' = 门
func to_ascii() -> String:
	var glyph := {Cell.SOLID: "#", Cell.FLOOR: ".", Cell.CORRIDOR: "+", Cell.DOOR: "D"}
	var out := ""
	for y in height:
		for x in width:
			out += glyph.get(_cells[y * width + x], "?")
		out += "\n"
	return out


func _to_string() -> String:
	return "LogicalGrid(%dx%d 逻辑格 = %dx%d tile，可走 %d 格)" % [
		width, height, width * CELL_SIZE_TILES, height * CELL_SIZE_TILES, walkable_count()]
