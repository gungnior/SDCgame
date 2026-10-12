class_name WhiteboxPainter
extends RefCounted

## 白模地图绘制（技术验证阶段的默认渲染）
##
## ⚠️ 抽成独立模块的原因（真机反馈 #1）：
##   早先这段代码长在 `view/raid_scene.gd` 里，**没法单独测试**，
##   结果出现了"黑墙能穿过、绿线挡路"这种视觉与碰撞不一致的问题。
##   现在它是纯函数：`paint(grid) -> Image`，可以用像素级断言验证
##   **「图上看起来是墙的格子，碰撞层也必须判定为墙」**。
##
## 语义必须极端简单（技术验证优先"能读懂"）：
##   **亮 = 可走，暗 + 描边 = 阻挡**

const WB_FLOOR := Color(0.42, 0.46, 0.52)        ## 可走：亮
const WB_CORRIDOR := Color(0.34, 0.37, 0.42)     ## 走廊：略暗一档
const WB_WALL := Color(0.07, 0.08, 0.10)         ## 阻挡：近黑
const WB_WALL_EDGE := Color(0.62, 0.68, 0.78)    ## 墙的描边：亮
const WB_DOOR := Color(0.82, 0.68, 0.24)
const WB_GRID := Color(1, 1, 1, 0.035)           ## 格子网格：几乎不可见
const WB_SPAWN_TINT := Color(0.20, 0.85, 0.42)
const WB_EXTRACT_TINT := Color(1.0, 0.72, 0.20)

## 判定"这个像素看起来是不是墙"。测试与绘制共用，避免两边标准不一致。
static func looks_like_wall(c: Color) -> bool:
	# 亮底（地板/走廊/门）的亮度明显高于近黑的墙
	return c.get_luminance() < 0.16


## 画整张白模地图。grid 的每个逻辑格铺 CELL_SIZE_TILES x CELL_SIZE_TILES 个像素。
static func paint(grid: LogicalGrid, rooms: Array = []) -> Image:
	var n := LogicalGrid.CELL_SIZE_TILES
	var te := grid.tile_extents()
	var img := Image.create(te.x, te.y, false, Image.FORMAT_RGBA8)
	img.fill(WB_WALL)

	# ① 铺底：按格子类型刷平色
	for cy in grid.height:
		for cx in grid.width:
			var cell := Vector2i(cx, cy)
			var v := grid.get_cell(cell)
			var col := WB_WALL
			if v == LogicalGrid.Cell.FLOOR:
				col = WB_FLOOR
			elif v == LogicalGrid.Cell.CORRIDOR:
				col = WB_CORRIDOR
			elif v == LogicalGrid.Cell.DOOR:
				col = WB_DOOR
			var o := grid.cell_to_tile_origin(cell)
			for ty in n:
				for tx in n:
					img.set_pixel(o.x + tx, o.y + ty, col)

	# ② 墙的描边：只画【朝向可走格】的那一侧（墙体内部不画线，读起来才干净）
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cy in grid.height:
		for cx in grid.width:
			var cell := Vector2i(cx, cy)
			if grid.is_walkable(cell):
				continue
			var o := grid.cell_to_tile_origin(cell)
			for d in dirs:
				if grid.is_walkable(cell + d):
					draw_seam(img, o, d, n, WB_WALL_EDGE, 0, 1)

	# ③ 房间轮廓 —— 画在房间边界格【朝外】的那一圈瓦片上
	#
	# ⚠️ 这里是最初踩坑的地方：早先把描边画在 room.rect 的最外圈【瓦片】上，
	#    而 room.rect 整块都是 carve 出来的 FLOOR —— 于是绿线盖在可走格上，
	#    看起来像墙、实际能走。现在改为：**只画在房间边界格与「房间外」相邻的那一侧**，
	#    即描边落在墙上而不是地板上。
	for r in rooms:
		var tint := Color(1, 1, 1, 0.16)
		if r.room_type == "spawn":
			tint = WB_SPAWN_TINT
		elif r.room_type == "extract":
			tint = WB_EXTRACT_TINT
		_outline_room(img, grid, r.rect, n, tint)

	# ④ 每个逻辑格画一条极淡的网格线，帮助判断距离
	for cy in grid.height:
		for cx in grid.width:
			var o := grid.cell_to_tile_origin(Vector2i(cx, cy))
			for i in n:
				blend_px(img, o.x + i, o.y, WB_GRID)
				blend_px(img, o.x, o.y + i, WB_GRID)

	return img


## 房间描边：沿着房间边界的【外缘】画，落在墙格上（不是地板上）
static func _outline_room(img: Image, grid: LogicalGrid, rect: Rect2i, n: int, col: Color) -> void:
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			var cell := Vector2i(x, y)
			if not grid.is_walkable(cell):
				continue
			var o := grid.cell_to_tile_origin(cell)
			for d in dirs:
				# 房间【外】的墙格才有描边（这样线落在墙上，不遮住可走区域）
				var out := cell + d
				if rect.has_point(out):
					continue          # 还在房间内，跳过
				if not grid.is_walkable(out):
					draw_seam(img, o, d, n, col, 0, 1)


## 沿 cell 的某一侧画一条线。d 指向邻居，线画在朝邻居的那条边上。
static func draw_seam(img: Image, origin: Vector2i, d: Vector2i, n: int,
		col: Color, inset: int, thickness: int) -> void:
	var iw := img.get_width()
	var ih := img.get_height()
	for t in thickness:
		for i in n:
			var x := -1
			var y := -1
			if d == Vector2i(0, 1):
				x = origin.x + i
				y = origin.y + n - 1 - inset - t
			elif d == Vector2i(0, -1):
				x = origin.x + i
				y = origin.y + inset + t
			elif d == Vector2i(1, 0):
				x = origin.x + n - 1 - inset - t
				y = origin.y + i
			else:
				x = origin.x + inset + t
				y = origin.y + i
			blend_px(img, x, y, col)


static func blend_px(img: Image, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if col.a >= 1.0:
		img.set_pixel(x, y, col)
	else:
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, col.a))
