class_name RaidMapBaker
extends RefCounted

## 地图烘焙 —— 从 `view/raid_scene.gd` 抽出来
##
## 职责：把逻辑网格烘成**一张像素图**（白模或美术 tile），供场景一次性绘制。
##
## ─── 为什么是它先被切出来 ───
## `raid_scene.gd` 曾 1676 行 / 51 函数，50% 的提交都要改它。
## 这块是其中**边界最干净**的：纯图像生成 ——
## 不画东西、不碰坐标空间、不依赖节点树、不读玩家状态。
## 所以它可以（也应该）被 headless 单测，而留在场景里的时候做不到。
##
## ⚠️ 搬迁的是**原文**，没有手抄 —— 避免抄错像素逻辑。


const TILE_PX := 16

const TILE_NAMES := {
	"floor_concrete": ["tile_floor_concrete_0", "tile_floor_concrete_1", "tile_floor_concrete_2"],
	"floor_dirt":     ["tile_floor_dirt_0", "tile_floor_dirt_1", "tile_floor_dirt_2"],
	"floor_asphalt":  ["tile_floor_asphalt_0", "tile_floor_asphalt_1", "tile_floor_asphalt_2"],
	"floor_metal":    ["tile_floor_metal_0", "tile_floor_metal_1", "tile_floor_metal_2"],
	"wall_concrete":  ["tile_wall_concrete_0", "tile_wall_concrete_1", "tile_wall_concrete_2"],
	"wall_brick":     ["tile_wall_brick_0", "tile_wall_brick_1", "tile_wall_brick_2"],
	"wall_metal":     ["tile_wall_metal_0", "tile_wall_metal_1", "tile_wall_metal_2"],
}

var _tiles: Dictionary = {}          ## 已加载的 tile 变体：key -> Array[Image]
var _grid: LogicalGrid = null        ## 当前地图（tile_key_for 要用）
var _rooms: Array = []               ## 当前地图的房间（tile_key_for 要用）          # 名字 -> Array[Image]（原始像素数据）


## 载入程序化生成的 16x16 tile（art/tiles/，由 tools/art/gen_tiles.py 产出）
func load_tiles() -> void:
	var loaded := 0
	for key in TILE_NAMES.keys():
		var arr: Array = []
		var bases: Array = TILE_NAMES[key]
		for b in bases:
			var base_name: String = str(b)
			var p: String = "res://art/tiles/%s.png" % base_name
			if ResourceLoader.exists(p):
				var tex: Texture2D = load(p)
				if tex != null:
					arr.append(tex.get_image())
		if not arr.is_empty():
			_tiles[str(key)] = arr
			loaded += arr.size()
	print("[地形] 载入 %d 张 tile（%d 类）" % [loaded, _tiles.size()])


## 把整张地图烘焙成一张像素图


## 烘焙整张地图为纹理。whitebox=true 走白模，否则走美术 tile。
func build(grid: LogicalGrid, rooms: Array, whitebox: bool) -> ImageTexture:
	set_map(grid, rooms)
	var te := grid.tile_extents()
	var img := Image.create(te.x, te.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.05, 0.07))
	if whitebox:
		_build_whitebox(grid, rooms, img)
	else:
		_build_tiles(grid, img)
	return ImageTexture.create_from_image(img)


## 记住当前地图。
## ⚠️ 为什么要有状态：`tile_key_for()` 需要按"这个格属于哪个房间"选材质，
##    而它同时被 `_floor_material()`（脚步音效）在**不烘焙**的时候调用。
##    所以房间信息必须留在 baker 里，不能只当作 build() 的临时参数。
func set_map(grid: LogicalGrid, rooms: Array) -> void:
	_grid = grid
	_rooms = rooms


func _room_at(cell: Vector2i) -> Room:
	for r in _rooms:
		if r.rect.has_point(cell):
			return r
	return null


# ─────────── 白模（技术验证阶段的默认渲染）───────────
#
# ⚠️ 绘制已抽到 view/whitebox_painter.gd —— 它是纯函数，可以像素级单测。
#    真机反馈黑墙能穿过、绿线挡路就是因为当初这段逻辑长在场景里、测不到。
const WB_FLOOR := WhiteboxPainter.WB_FLOOR
const WB_WALL := WhiteboxPainter.WB_WALL
const WB_WALL_EDGE := WhiteboxPainter.WB_WALL_EDGE


func _build_whitebox(grid: LogicalGrid, rooms: Array, img: Image) -> void:
	var painted := WhiteboxPainter.paint(grid, rooms)
	# 直接拷贝像素（尺寸一致，都是 tile_extents）
	img.blit_rect(painted, Rect2i(Vector2i.ZERO, painted.get_size()), Vector2i.ZERO)


## 美术 tile 版（render_mode == RENDER_ART 时用）


func _build_tiles(grid: LogicalGrid, img: Image) -> void:
	var g := grid
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var n := LogicalGrid.CELL_SIZE_TILES

	for cy in g.height:
		for cx in g.width:
			var cell := Vector2i(cx, cy)
			var walkable := g.is_walkable(cell)
			var key := tile_key_for(cell, walkable)
			var variants: Array = _tiles.get(key, [])
			if variants.is_empty():
				continue
			var origin := g.cell_to_tile_origin(cell)
			for ty in n:
				for tx in n:
					var idx: int = abs(int(hash(Vector2i(origin.x + tx, origin.y + ty)))) % variants.size()
					var v: Image = variants[idx]
					img.blit_rect(v, Rect2i(Vector2i.ZERO, Vector2i(TILE_PX, TILE_PX)),
						Vector2i(origin.x + tx, origin.y + ty))

	# 结构层：逻辑格级别的墙轮廓 + 贴墙 AO
	_bake_structure(g, img)


func _bake_structure(grid: LogicalGrid, img: Image) -> void:
	var g := grid
	var n := LogicalGrid.CELL_SIZE_TILES
	var outline := Color(0.04, 0.05, 0.07, 1.0)
	var ao := Color(0.0, 0.0, 0.0, 0.30)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	for cy in g.height:
		for cx in g.width:
			var cell := Vector2i(cx, cy)
			var origin := g.cell_to_tile_origin(cell)
			if not g.is_walkable(cell):
				# 墙：只在【朝向可走格】的那一侧描边，墙体内部不画线
				for d in dirs:
					if g.is_walkable(cell + d):
						_draw_seam(img, origin, d, n, outline, 0, 1)
				continue
			# 地面：贴墙的内侧压暗（廉价 AO，可读性提升很大）
			for d in dirs:
				if not g.is_walkable(cell + d):
					_draw_seam(img, origin, d, n, ao, 1, 2)


## 沿 cell 的某一侧画一条线。d 指向【邻居】，线画在朝邻居的那条边上。


func _draw_seam(img: Image, origin: Vector2i, d: Vector2i, n: int,
		col: Color, inset: int, thickness: int) -> void:
	var iw := img.get_width()
	var ih := img.get_height()
	for t in thickness:
		for i in n:
			var x := -1
			var y := -1
			if d == Vector2i(0, 1):          # 邻居在下 -> 画下边
				x = origin.x + i
				y = origin.y + n - 1 - inset - t
			elif d == Vector2i(0, -1):       # 上边
				x = origin.x + i
				y = origin.y + inset + t
			elif d == Vector2i(1, 0):        # 右边
				x = origin.x + n - 1 - inset - t
				y = origin.y + i
			else:                            # 左边
				x = origin.x + inset + t
				y = origin.y + i
			if x < 0 or y < 0 or x >= iw or y >= ih:
				continue
			if col.a >= 1.0:
				img.set_pixel(x, y, col)
			else:
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, col.a))


## 给一个逻辑格挑 tile 类型（按房间类型 + 坐标哈希做变化）


func tile_key_for(cell: Vector2i, walkable: bool) -> String:
	var h: int = abs(int(hash(cell)))
	if walkable:
		var room := _room_at(cell)
		if room != null:
			# 房间地面：混凝土 / 泥土 交替，让不同房间有质感差异
			return ["floor_concrete", "floor_metal", "floor_dirt"][room.id % 3]
		return ["floor_asphalt", "floor_concrete"][h % 2]
	# 墙：混凝土为主，少量砖 / 金属
	return ["wall_concrete", "wall_concrete", "wall_brick", "wall_metal"][h % 4]
