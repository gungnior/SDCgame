class_name MapPanel
extends Control

## 战术地图覆盖层（2026-10-13 真机反馈 #2）
##
## 用户原话：
##   "需要有地图界面可以看到撤离点位置"
##
## 早先撤离点只在**世界坐标**里画一个金圈（view/raid_drawer.gd 的
## `raid.extract_points`）—— 但那只有走到附近才看得见。玩家在大地图上
## 完全不知道撤离点在哪，只能瞎走（搜打撤的核心循环直接断掉）。
##
## 本面板给一张**俯视全图**：
##   · 地形（墙 / 地板 / 走廊 / 门）
##   · 房间轮廓（**出生绿 / 撤离金** / 其他灰）
##   · **撤离点**：金色圆环 + 「撤离」字样 —— 这就是本面板存在的理由
##   · 玩家位置 + 朝向
##   · 容器（已搜变暗）与尸体
##
## ── 设计纪律 ──
##   · `_ensure_built()` 幂等 —— 测试里 `root.add_child()` 不触发 `_ready`
##     （见 MEMORY「root.add_child 不触发 _ready」）
##   · 面板**不认识战斗**：只**只读**地取 `scene.gen` / `scene.raid` 的数据，
##     不调任何会改状态的方法
##   · 纯几何换算（fit_rect / cell_to_panel）是 static，可 headless 单测 ——
##     地图比例 / letterbox 是"真机上看着对不对"的重灾区，必须能单测
##   · 地形**先烘焙成一张 ImageTexture** 再一次性放大：
##     40×40 地图逐帧画 1600 个 draw_rect 在移动端是纯浪费，
##     而地图在打开期间根本不变化

signal closed()

const C_BG := Color(0.04, 0.05, 0.07, 1.0)
const C_WALL := Color(0.09, 0.10, 0.13)
const C_FLOOR := Color(0.44, 0.47, 0.54)
const C_CORRIDOR := Color(0.28, 0.30, 0.36)
const C_DOOR := Color(0.62, 0.50, 0.30)
const C_FRAME := Color(0.52, 0.57, 0.65, 0.65)
const C_ROOM := Color(0.42, 0.46, 0.54, 0.85)
const C_SPAWN := Color(0.30, 0.72, 0.44)
const C_EXTRACT := Color(1.0, 0.80, 0.28)
const C_PLAYER := Color(0.36, 0.72, 1.0)
const C_CONTAINER := Color(0.82, 0.72, 0.42)
const C_CONTAINER_DONE := Color(0.40, 0.38, 0.32)
const C_CORPSE := Color(0.66, 0.30, 0.30)
const C_TEXT := Color(0.86, 0.90, 0.96)

var scene = null

var _open := false
var _built := false
var _close_btn: TouchButton = null
var _title: Label = null
var _legend: Label = null
var _map_rect := Rect2()
var _tex: ImageTexture = null


# ─────────────────── 纯几何（可单测） ───────────────────

## 把 grid_w × grid_h 的逻辑格等比（letterbox）放进 panel 里，
## 四周留 margin。返回"地图在面板上的矩形"。
##
## ⚠️ 必须等比：地图是方的（34×34~44×44），而手机屏幕是竖的，
##    不按比例缩放会得到一张被拉长、撤离点位置全错的地图。
static func fit_rect(grid_w: int, grid_h: int, panel: Vector2, margin: float) -> Rect2:
	if grid_w <= 0 or grid_h <= 0:
		return Rect2()
	var avail := panel - Vector2(margin, margin) * 2.0
	if avail.x <= 1.0 or avail.y <= 1.0:
		return Rect2()
	var scale := minf(avail.x / float(grid_w), avail.y / float(grid_h))
	var size := Vector2(float(grid_w), float(grid_h)) * scale
	return Rect2((panel - size) * 0.5, size)


## 逻辑格坐标（可以是小数，如玩家位置）-> 面板像素坐标。
static func cell_to_panel(cell: Vector2, map_rect: Rect2, grid_w: int, grid_h: int) -> Vector2:
	if grid_w <= 0 or grid_h <= 0:
		return map_rect.position
	return map_rect.position + Vector2(cell.x / float(grid_w), cell.y / float(grid_h)) * map_rect.size


# ─────────────────── 生命周期 ───────────────────

func _ready() -> void:
	_ensure_built()


## 幂等建界面（理由见 ui/carry_panel.gd 的同名函数）
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	visible = false
	_fit_viewport()
	if get_viewport() != null:
		get_viewport().size_changed.connect(_fit_viewport)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()


func is_open() -> bool:
	return _open


func _fit_viewport() -> void:
	# ⚠️⚠️ `size = vp` 这两行**不能省** —— 本面板挂在 `CanvasLayer` 下，
	#     父节点不是 Control，锚点**解析不到父矩形**，只设锚点会得到一块
	#     0×0 的区域：表现为"地图画不出来、关闭按钮挤到左上角"。
	#     （探针 `_tmp_r8_probe` 实测抓到；试过只设锚点，MAP_RECT 变成 0×0。）
	#     `get_viewport_rect()` 不在树里会报引擎 ERROR —— 先判在不在树。
	var vp := Vector2.ZERO
	if is_inside_tree():
		vp = get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width", 640),
			ProjectSettings.get_setting("display/window/size/viewport_height", 360))
	position = Vector2.ZERO
	size = vp
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _build() -> void:
	# ⚠️ 不再额外放一层 ColorRect 当背景：
	#    本节点自己 `mouse_filter = STOP` 且铺满视口，已经能吃掉所有触摸；
	#    再叠一层 ColorRect 只会在 draw 顺序上带来"谁盖谁"的坑。
	#    底色由 `_draw()` 第一行画（父节点先于子节点绘制，所以字/按钮在上面）。
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 2)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	_title = Label.new()
	_title.text = "战术地图"
	_title.add_theme_font_size_override("font_size", 20)
	_title.add_theme_color_override("font_color", UITokens.TEXT_HI)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)

	# ⚠️ 关闭按钮放**顶栏右侧**，不要单独占一行底部 ——
	#    地图是方的（44×44），而手机屏幕是宽的，高度就是瓶颈：
	#    底下一个 64px 的按钮行会把地图从 236px 压到 158px（探针实测）。
	_close_btn = TouchButton.new()
	_close_btn.label_text = "关闭"
	_close_btn.use_hold = false
	_close_btn.base_radius = 26.0
	_close_btn.custom_minimum_size = Vector2(130, 60)
	_close_btn.accent = UITokens.DANGER
	_close_btn.pressed_down.connect(close)
	top.add_child(_close_btn)

	_legend = Label.new()
	_legend.text = "绿=出生 · 金=撤离点 · 蓝=你"
	_legend.add_theme_font_size_override("font_size", 13)
	_legend.add_theme_color_override("font_color", Color(0.70, 0.76, 0.86))
	_legend.clip_text = true      # 不让提示文本顶大最小宽度（见 InventoryPanel 的说明）
	root.add_child(_legend)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	filler.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(filler)


# ─────────────────── 对外 ───────────────────

func open(p_scene) -> void:
	_ensure_built()
	scene = p_scene
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bake()
	_legend.text = _legend_text()
	queue_redraw()


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _close_btn != null:
		_close_btn.force_release()
	closed.emit()


func toggle(p_scene) -> void:
	if _open:
		close()
	else:
		open(p_scene)


func _legend_text() -> String:
	var ex := 0
	if scene != null and scene.raid != null:
		ex = (scene.raid.extract_points as Array).size()
	return "绿=出生 · 金=撤离点（%d 处）· 蓝=你" % ex


# ─────────────────── 烘焙 ───────────────────

## 把地形烘焙成一张 1 像素 = 1 逻辑格 的贴图（只在打开时做一次）。
func _bake() -> void:
	_tex = null
	if scene == null or scene.gen == null:
		return
	var g = scene.gen.grid
	if g == null or g.width <= 0 or g.height <= 0:
		return
	var img := Image.create(g.width, g.height, false, Image.FORMAT_RGBA8)
	for y in g.height:
		for x in g.width:
			# ⚠️ `g` 是无类型的（duck typing 到 scene.gen.grid），
			#    所以 `get_cell()` 的返回值是 Variant —— 必须显式标 int，
			#    不能用 `:=`（会报 "Cannot infer the type of v"）。
			var v: int = g.get_cell(Vector2i(x, y))
			var col := C_WALL
			if v == LogicalGrid.Cell.FLOOR:
				col = C_FLOOR
			elif v == LogicalGrid.Cell.CORRIDOR:
				col = C_CORRIDOR
			elif v == LogicalGrid.Cell.DOOR:
				col = C_DOOR
			img.set_pixel(x, y, col)
	_tex = ImageTexture.create_from_image(img)


# ─────────────────── 绘制 ───────────────────

func _draw() -> void:
	if not _open:
		return
	draw_rect(Rect2(Vector2.ZERO, size), C_BG, true)
	if scene == null or scene.gen == null:
		return
	var g = scene.gen.grid
	if g == null or g.width <= 0:
		return
	# 地图区域：顶部给标题行（60px）+ 图例（18px），下方基本全留给地图
	var top_pad := 88.0
	var bot_pad := 8.0
	var avail_panel := Vector2(size.x, maxf(1.0, size.y - top_pad - bot_pad))
	_map_rect = fit_rect(g.width, g.height, avail_panel, 12.0)
	_map_rect.position += Vector2(0.0, top_pad)
	if _map_rect.size == Vector2.ZERO:
		return

	# 外框
	draw_rect(Rect2(_map_rect.position - Vector2(2, 2), _map_rect.size + Vector2(4, 4)),
		C_FRAME, false, 2.0)

	# ① 地形（烘焙贴图，nearest 放大）
	if _tex != null:
		draw_texture_rect(_tex, _map_rect, false)

	# ② 房间轮廓（出生绿 / 撤离金 / 其余灰）
	for r in scene.gen.graph.rooms:
		var a := cell_to_panel(Vector2(r.rect.position.x, r.rect.position.y),
			_map_rect, g.width, g.height)
		var b := cell_to_panel(Vector2(r.rect.end.x, r.rect.end.y),
			_map_rect, g.width, g.height)
		var col := C_ROOM
		var w := 1.0
		if r.room_type == "spawn":
			col = C_SPAWN
			w = 2.5
		elif r.room_type == "extract":
			col = C_EXTRACT
			w = 2.5
		draw_rect(Rect2(a, b - a), col, false, w)

	# ③ 容器 / 尸体（低优先级信息，先画，避免盖住撤离点）
	if scene.raid != null:
		for c in scene.raid.containers:
			var cp := cell_to_panel(c.pos, _map_rect, g.width, g.height)
			draw_rect(Rect2(cp - Vector2(2.5, 2.5), Vector2(5, 5)),
				C_CONTAINER_DONE if bool(c.searched) else C_CONTAINER, true)
		for cp2 in scene.raid.corpses:
			var d: Dictionary = cp2
			var pp := cell_to_panel(d["pos"] as Vector2, _map_rect, g.width, g.height)
			draw_circle(pp, 3.5, C_CORPSE)

	# ④ ⭐ 撤离点（本面板的核心）
	var f := ThemeDB.fallback_font
	var extracts: Array = scene.raid.extract_points if scene.raid != null else []
	for p in extracts:
		var c := cell_to_panel(p as Vector2, _map_rect, g.width, g.height)
		draw_circle(c, 11.0, Color(1.0, 0.80, 0.28, 0.22))
		draw_arc(c, 11.0, 0, TAU, 28, C_EXTRACT, 2.5)
		draw_arc(c, 5.5, 0, TAU, 18, C_EXTRACT, 1.6)
		if f != null:
			draw_string(f, c + Vector2(14.0, 5.0), "撤离", HORIZONTAL_ALIGNMENT_LEFT,
				-1, 13, C_EXTRACT)

	# ⑤ 玩家（画在最后 —— 永远可见）
	var pc := cell_to_panel(scene.player_pos, _map_rect, g.width, g.height)
	draw_circle(pc, 6.0, C_PLAYER)
	draw_line(pc, pc + scene.player_facing * 14.0, Color(1, 1, 1, 0.85), 2.0)
