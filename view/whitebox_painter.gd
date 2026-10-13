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
# ⚠️ 旧的 `WB_SPAWN_TINT / WB_EXTRACT_TINT` 已并入 ROOM_TINTS
#    （出生点/撤离点现在和军械库、医疗室等一样，是"房间类型配色"里的一项）。

## ── 地图主题色调（data/maps.json 的 tile_theme）──
##
## 白模阶段用**色调**区分森林 / 城区 / 军事基地 —— 不依赖美术资源。
## ⚠️⚠️ 不变量（改动前先读）：
##   1. 缺省色（"concrete"）必须与 `WB_*` 常量**逐字节相同** ——
##      `s09` 的「烘焙结果 == WhiteboxPainter.paint()」是**逐像素确定性断言**，
##      而那条路径不传主题（theme_id == ""）。
##   2. 每个主题的 wall 亮度必须 < 0.16、floor/corridor 必须 >= 0.16 ——
##      `looks_like_wall()` 用 0.16 当分界，色调一变可能让"画成墙/碰撞是墙"
##      的判据反向。s19 有断言守住这条。
const THEME_COLORS := {
	"dirt": {                                  # 森林：土黄地面
		"floor": Color(0.50, 0.42, 0.30),
		"corridor": Color(0.40, 0.33, 0.24),
		"wall": Color(0.10, 0.08, 0.06),
		"edge": Color(0.78, 0.64, 0.42),
	},
	"concrete": {                              # 城区：混凝土灰（== 历史默认）
		"floor": WB_FLOOR,
		"corridor": WB_CORRIDOR,
		"wall": WB_WALL,
		"edge": WB_WALL_EDGE,
	},
	"metal": {                                 # 军事基地：冷钢蓝
		"floor": Color(0.38, 0.44, 0.50),
		"corridor": Color(0.30, 0.35, 0.42),
		"wall": Color(0.05, 0.06, 0.09),
		"edge": Color(0.55, 0.72, 0.86),
	},
}


## 取某主题的配色。未知/空主题一律回退 concrete（== 历史行为）。
static func theme_colors(theme_id: String) -> Dictionary:
	return THEME_COLORS.get(theme_id, THEME_COLORS["concrete"])


## ── 房间类型配色（2026-10-13 真机反馈 #5）──
#
# 用户原话："白模阶段应该使用不同的地板色、墙壁色来区分房间类型"。
#
# 之前白模只按【地图主题】整体换色（森林/城区/军事基地），
# 同一张图里【所有房间长得一模一样】—— 玩家看不出"这间是军械库、
# 那间是医疗室、这间是宿舍"，白模于是丢掉了最关键的信息：
# **房间类型的可读性**。
#
# 键优先用 `Room.room_type_id`（房间主题，如 room_armory），
# 拿不到时退回 `Room.room_type`（spawn / common / extract）。
#
# ⚠️ 两条不变量（s09 用像素级断言钉着，改色前必读）：
#   1. 每格【正中心】像素的"画成墙 / 碰撞是墙"必须一致
#      -> 房间地板色亮度必须 >= 0.16；这里所有色都很亮，安全。
#        房间描边只画在格子【边缘】，碰不到中心像素，所以描边可以很亮。
#   2. 桌子/走廊/门**不参与**房间染色（门是黄色交互标记，被盖掉就读不出来了）。
const ROOM_TINTS := {
	"room_spawn": Color(0.36, 0.80, 0.54),        # 出生点：安全绿
	"spawn": Color(0.36, 0.80, 0.54),
	"room_extract": Color(0.94, 0.74, 0.30),      # 撤离点：琥珀
	"extract": Color(0.94, 0.74, 0.30),
	"room_armory": Color(0.52, 0.64, 0.90),       # 军械库：钢蓝
	"room_medical": Color(0.80, 0.95, 0.92),      # 医疗室：冷白
	"room_dorm": Color(0.88, 0.70, 0.50),         # 宿舍：暖木
	"room_warehouse": Color(0.84, 0.76, 0.46),    # 仓库：土黄
	"room_lab": Color(0.60, 0.92, 0.86),          # 实验室：荧光青
}
## 房间地板被房间色染色的强度（0 = 不染，1 = 完全覆盖）
const ROOM_TINT_STRENGTH := 0.55
## 房间墙描边的透明度（描边在格子边缘，不影响"中心像素"的判据）
const ROOM_EDGE_ALPHA := 0.62
## 普通房间（没有专属色调）的描边：几乎不可见的白
const ROOM_EDGE_PLAIN := Color(1, 1, 1, 0.16)


## 这个房间的色调。**没有专属色调时返回 null** = 保持基底观感
## （普通房间就是"基准色"，不该被染成某种特殊颜色）。
static func room_tint_of(r) -> Variant:
	var by_id: Variant = ROOM_TINTS.get(str(r.room_type_id), null)
	if by_id != null:
		return by_id
	return ROOM_TINTS.get(str(r.room_type), null)


## 房间墙描边的颜色。
static func room_edge_of(r) -> Color:
	var t: Variant = room_tint_of(r)
	if t == null:
		return ROOM_EDGE_PLAIN
	var c: Color = t
	return Color(c.r, c.g, c.b, ROOM_EDGE_ALPHA)


## 判定"这个像素看起来是不是墙"。测试与绘制共用，避免两边标准不一致。
static func looks_like_wall(c: Color) -> bool:
	# 亮底（地板/走廊/门）的亮度明显高于近黑的墙
	return c.get_luminance() < 0.16


## 画整张白模地图。grid 的每个逻辑格铺 CELL_SIZE_TILES x CELL_SIZE_TILES 个像素。
## theme_id 为 ""（或未知）时用 concrete 配色 —— 与历史输出逐像素一致。
static func paint(grid: LogicalGrid, rooms: Array = [], theme_id: String = "") -> Image:
	var n := LogicalGrid.CELL_SIZE_TILES
	var te := grid.tile_extents()
	var pal := theme_colors(theme_id)
	var c_floor: Color = pal["floor"]
	var c_corr: Color = pal["corridor"]
	var c_wall: Color = pal["wall"]
	var c_edge: Color = pal["edge"]
	var img := Image.create(te.x, te.y, false, Image.FORMAT_RGBA8)
	img.fill(c_wall)

	# ① 铺底：按格子类型刷平色
	for cy in grid.height:
		for cx in grid.width:
			var cell := Vector2i(cx, cy)
			var v := grid.get_cell(cell)
			var col := c_wall
			if v == LogicalGrid.Cell.FLOOR:
				col = c_floor
			elif v == LogicalGrid.Cell.CORRIDOR:
				col = c_corr
			elif v == LogicalGrid.Cell.DOOR:
				col = WB_DOOR
			var o := grid.cell_to_tile_origin(cell)
			for ty in n:
				for tx in n:
					img.set_pixel(o.x + tx, o.y + ty, col)

	# ①.5 房间地板色：按房间类型把地板染成不同色调（军械库 = 钢蓝、医疗室 = 冷白…）
	#      只染 FLOOR —— 走廊与门保持原色（门是黄色交互标记，不能被盖掉）
	_tint_rooms(img, grid, rooms)

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
					draw_seam(img, o, d, n, c_edge, 0, 1)

	# ③ 房间轮廓 —— 画在房间边界格【朝外】的那一圈瓦片上
	#
	# ⚠️ 这里是最初踩坑的地方：早先把描边画在 room.rect 的最外圈【瓦片】上，
	#    而 room.rect 整块都是 carve 出来的 FLOOR —— 于是绿线盖在可走格上，
	#    看起来像墙、实际能走。现在改为：**只画在房间边界格与「房间外」相邻的那一侧**，
	#    即描边落在墙上而不是地板上。
	for r in rooms:
		_outline_room(img, grid, r.rect, n, room_edge_of(r))

	# ④ 每个逻辑格画一条极淡的网格线，帮助判断距离
	for cy in grid.height:
		for cx in grid.width:
			var o := grid.cell_to_tile_origin(Vector2i(cx, cy))
			for i in n:
				blend_px(img, o.x + i, o.y, WB_GRID)
				blend_px(img, o.x, o.y + i, WB_GRID)

	return img


## 按房间类型给地板染色（见 ROOM_TINTS 的说明）。
## 没有专属色调的房间（普通房间 / 未知类型）整块跳过 —— 它们就是基准色。
static func _tint_rooms(img: Image, grid: LogicalGrid, rooms: Array) -> void:
	var n := LogicalGrid.CELL_SIZE_TILES
	for r in rooms:
		var t: Variant = room_tint_of(r)
		if t == null:
			continue
		var tint: Color = t
		for y in range(r.rect.position.y, r.rect.position.y + r.rect.size.y):
			for x in range(r.rect.position.x, r.rect.position.x + r.rect.size.x):
				var cell := Vector2i(x, y)
				if grid.get_cell(cell) != LogicalGrid.Cell.FLOOR:
					continue          # 走廊/门/墙不染
				var o := grid.cell_to_tile_origin(cell)
				for ty in n:
					for tx in n:
						var px := o.x + tx
						var py := o.y + ty
						img.set_pixel(px, py,
							img.get_pixel(px, py).lerp(tint, ROOM_TINT_STRENGTH))


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
