extends Node2D

## B 阶段表现层最小闭环 —— 第一次「看得见」
##
## 渲染策略：当前没有任何美术资源，所以用 _draw() 直接画几何图形。
## 这不是占位妥协，而是刻意的第一步：先把「地图 + 实体 + 相机 + 输入」这条链路打通，
## 美术资源到位后只要替换绘制实现，逻辑一行不用改。
##
## 逻辑全部来自 sim/ —— 本文件只做三件事：
##   1. 读 sim 的状态并画出来
##   2. 把输入翻译成 sim 能理解的动作
##   3. 推进 sim 的时钟
##
## 操作：
##   桌面  WASD/方向键移动 · J/空格 开火 · K 换弹 · L 治疗 · Tab 切换调试视图
##   触屏  左半屏拖动移动 · 右半屏点按开火 · 屏幕按钮换弹/治疗

const Registry := preload("res://io/data_registry.gd")

const CELL_PX := 48.0          ## 1 逻辑格 = 48 px（T-31）
const PLAYER_SPEED := 3.2      ## 逻辑格 / 秒
const NOISE_LOUD := 22.0       ## 开枪的响度（米）
const NOISE_QUIET := 7.0       ## 走路的响度
## 曳光存活时间。
## ⚠️ 早先只有 0.06s（约 3.6 帧），安卓真机反馈"开火只听到声音看不到子弹"。
const TRACER_TTL := 0.13

# ─── 颜色 ───
const C_WALL := Color(0.13, 0.14, 0.18)
const C_FLOOR := Color(0.27, 0.29, 0.34)
const C_CORRIDOR := Color(0.21, 0.23, 0.28)
const C_ROOM_EDGE := Color(0.32, 0.35, 0.42)
const C_SPAWN := Color(0.24, 0.62, 0.38)
const C_EXTRACT := Color(0.85, 0.65, 0.22)
const C_PLAYER := Color(0.36, 0.72, 1.0)
const C_ENEMY_IDLE := Color(0.72, 0.74, 0.78)
const C_ENEMY_ALERT := Color(1.0, 0.78, 0.30)
const C_ENEMY_COMBAT := Color(1.0, 0.28, 0.28)
const C_DEAD := Color(0.35, 0.18, 0.18)
const C_ARROW := Color(0.5, 0.78, 1.0, 0.35)

# ─── 模拟层 ───
var reg: DataRegistry
var gen: MapGenerator
var flows: FlowFieldManager
var raid: RaidSession
var agents: Array = []
var squad: Squad
var vitals: Vitals
var medical: MedicalSystem
var bullets: Array = []          ## 表现层专用：曳光弹 {from, to, ttl, own}
## 枪口火光（独立于粒子画，保证一定看得见）{pos, dir, ttl}
var muzzle_flash: Array = []
var noises: Array = []
var drops_on_ground: Array = []  ## {pos, item_id, count}

# ─── 玩家 ───
var player_pos := Vector2.ZERO
var player_facing := Vector2.RIGHT
var player_aim := Vector2.RIGHT
var player_weapon: WeaponState

# ─── 输入 ───
var _move_input := Vector2.ZERO
var _firing := false

# ─── 视图 ───
var camera: Camera2D
var hud: CanvasLayer
var hud_label: Label
var hint_label: Label
var view_label: Label
var debug_mode := 0              ## 0 普通 1 流向场 2 房间图 3 声音范围

# ─── 手感 / 音频 / 触屏（specs/tech-stack.md §2 与 §7.3）───
var fx: FxPool = null            ## CPUParticles2D 池（T-03）
var touch: TouchControls = null  ## 双摇杆 + 动作按钮
var flash_rect: ColorRect = null ## 受击闪白覆盖层
var result_overlay: ResultOverlay = null   ## 结算界面（含触屏重开按钮）
var _prev_shots: Dictionary = {} ## agent.id -> 已开火数（用于播放枪声）
var _step_accum := 0.0
var _last_hint_shown := false
var _hitstop_events := 0         ## 本局触发过几次 hitstop（调试）

var _rng := SimRng.new(20261012)
var _time := 0.0
## 是否触屏设备（决定提示文案与 HUD 字号）
var _is_touch := false
## 本局地图种子。<=0 表示"开新局时随机"（见 _setup_sim）
var _raid_seed := 0
var hideout: Hideout = null      ## 藏身处跨局持久（重启不重置资金）

# ─── 地形贴图 ───
# 设计：把整张地图【烘焙成一张 81x81 像素图】，用 nearest 放大 16 倍绘制。
# 一次 draw call，而不是 6561 次 draw_texture_rect —— 手机上这是关键差异。
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
var _tiles: Dictionary = {}          # 名字 -> Array[Image]（原始像素数据）
var _map_tex: ImageTexture = null
var _map_tex_size := Vector2i.ZERO

# ─── 渲染模式 ───
## 0 = 白模（技术验证阶段默认）；1 = 美术 tile
## ⚠️ 默认白模是刻意的：当前美术 tile 的墙/地板对比度太低，
##    玩家看不出哪能走（安卓真机反馈）。技术验证优先"能读懂"。
const RENDER_WHITEBOX := 0
const RENDER_ART := 1
var render_mode := RENDER_WHITEBOX


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.06, 0.07, 0.09))
	_setup_sim()
	_setup_view()


# ═══════════════════════ 初始化 ═══════════════════════

func _setup_sim() -> void:
	reg = DataRegistry.new()
	if not reg.load_all("A"):
		push_error("数据加载失败：%s" % str(reg.errors))
		return

	# ⚠️ 每局换种子。
	#    早先这里写死 20261012，结果真机上"每局地图和出生点完全一样" ——
	#    玩家反馈"并没有随机出生"。同种子可复现是开发期的需要，
	#    正式游玩必须每局不同（T-32 的种子纪律：可复现 ≠ 写死）。
	if _raid_seed <= 0:
		_raid_seed = randi() & 0x7FFFFFFF
	_rng = SimRng.new(_raid_seed)

	gen = MapGenerator.new()
	if not gen.generate(_raid_seed, reg.room_types):
		push_error("地图生成失败：%s" % str(gen.errors))
		return

	flows = FlowFieldManager.new()
	flows.setup(gen.grid)

	# 藏身处（跨局持久）
	if hideout == null:
		hideout = Hideout.new(reg.items, 3000)
		hideout.wallet += 5000
		hideout.wallet += 5000

	raid = RaidSession.new(reg.items, _rng, hideout.stash)
	raid.load_map(gen)
	raid.start(240.0)

	vitals = Vitals.new()
	vitals.reset(100, 40)
	medical = MedicalSystem.new()

	# 玩家武器：步枪 + 自动装配件（展示 A 阶段改装系统）
	var loadout := WeaponModding.create_loadout(reg.get_weapon("weapon_rifle"), WeaponModding.SLOTS_A)
	WeaponModding.auto_fit(loadout, reg.attachments)
	player_weapon = WeaponState.new(loadout.to_weapon_def(), 180)
	print("[装填] %s" % loadout.summary())

	var spawn := gen.spawn_room()
	player_pos = Ballistics.cell_center(spawn.center)
	raid.hp = vitals.hp

	# 敌人
	squad = Squad.new(1)
	var scav := reg.get_enemy("enemy_scav")
	var infected := reg.get_enemy("enemy_infected")
	var eid := 0
	for r in gen.graph.rooms:
		if r.room_type == "spawn":
			continue
		for i in r.enemy_budget:
			var d: EnemyDef = scav if (i % 2 == 0) else infected
			var a := EnemyAgent.new(eid, d, Ballistics.cell_center(r.center))
			if d.is_ranged():
				a.equip(reg.get_weapon("weapon_pistol"), 60)
			a.facing = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			squad.add_member(a)
			agents.append(a)
			eid += 1
	print("[地图] %s" % gen.summary())
	print("[敌方] %d 名" % agents.size())


func _setup_view() -> void:
	# 触屏设备：决定提示文案与 HUD 字号
	_is_touch = DisplayServer.is_touchscreen_available() \
		or OS.has_feature("mobile") or OS.get_name() == "Android"

	camera = Camera2D.new()
	camera.zoom = Vector2(1.0, 1.0)
	add_child(camera)
	camera.make_current()

	hud = CanvasLayer.new()
	add_child(hud)

	# 手机上字号要更大（真机反馈：默认 13px 在手机上偏小）
	var fs := 16 if _is_touch else 13

	hud_label = Label.new()
	hud_label.position = Vector2(10, 6)
	hud_label.add_theme_font_size_override("font_size", fs)
	hud_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	hud.add_child(hud_label)

	hint_label = Label.new()
	hint_label.position = Vector2(10, 342)
	hint_label.add_theme_font_size_override("font_size", fs - 2)
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	hud.add_child(hint_label)

	view_label = Label.new()
	view_label.position = Vector2(10, 328)
	view_label.add_theme_font_size_override("font_size", fs - 2)
	view_label.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	hud.add_child(view_label)

	_load_tiles()
	_build_map_texture()
	_setup_feel_and_touch()


## 手感 / 音频 / 触屏的挂载点
func _setup_feel_and_touch() -> void:
	# ── 粒子池（CPUParticles2D，T-03）──
	fx = FxPool.new()
	add_child(fx)

	# ── 受击闪白覆盖层（放在 HUD 之下、世界之上）──
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0, 0, 0, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 50          # HUD(layer 默认 1) 之上
	flash_layer.add_child(flash_rect)
	add_child(flash_layer)

	# ── 触屏控件（即使桌面也建出来，方便用鼠标验证布局）──
	touch = TouchControls.new()
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	ui_layer.add_child(touch)
	add_child(ui_layer)
	touch.reload_pressed.connect(func():
		player_weapon.start_reload()
		if Sfx != null:
			Sfx.play("reload_start"))
	touch.heal_pressed.connect(_try_heal)

	# ── 结算界面（触屏可用的重开出口）──
	result_overlay = ResultOverlay.new()
	result_overlay.restart_requested.connect(_restart)
	result_overlay.hideout_requested.connect(_restart)
	var ro_layer := CanvasLayer.new()
	ro_layer.layer = 40
	ro_layer.add_child(result_overlay)
	add_child(ro_layer)


## 载入程序化生成的 16x16 tile（art/tiles/，由 tools/art/gen_tiles.py 产出）
func _load_tiles() -> void:
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
func _build_map_texture() -> void:
	if gen == null:
		return
	var te := gen.grid.tile_extents()      # 81 x 81 tile
	_map_tex_size = te
	var img := Image.create(te.x, te.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.05, 0.07))

	if render_mode == RENDER_WHITEBOX:
		_build_whitebox(img)
	else:
		_build_tiles(img)

	_map_tex = ImageTexture.create_from_image(img)


# ─────────── 白模（技术验证阶段的默认渲染）───────────
#
# ⚠️ 为什么默认用白模（安卓真机反馈 + 用户建议）：
#   带了美术 tile 之后，墙和地板都是暗灰，玩家**看不出哪能走**。
#   技术验证阶段要的是"能读懂"，不是"好看"。
#   白模的语义极简单：**亮 = 可走，暗 + 描边 = 阻挡**。
#   美术资源留着，`render_mode` 一改就切回来（frameworks 已就位）。
const WB_FLOOR := Color(0.42, 0.46, 0.52)        ## 可走：亮
const WB_CORRIDOR := Color(0.34, 0.37, 0.42)     ## 走廊：略暗一档
const WB_WALL := Color(0.07, 0.08, 0.10)         ## 阻挡：近黑
const WB_WALL_EDGE := Color(0.62, 0.68, 0.78)    ## 墙的描边：亮，一眼可辨
const WB_DOOR := Color(0.82, 0.68, 0.24)
const WB_GRID := Color(1, 1, 1, 0.035)           ## 格子网格：几乎不可见但帮助判距
const WB_SPAWN_TINT := Color(0.20, 0.85, 0.42)
const WB_EXTRACT_TINT := Color(1.0, 0.72, 0.20)


func _build_whitebox(img: Image) -> void:
	var g := gen.grid
	var n := LogicalGrid.CELL_SIZE_TILES

	# ① 铺底：按格子类型刷平色
	for cy in g.height:
		for cx in g.width:
			var cell := Vector2i(cx, cy)
			var v := g.get_cell(cell)
			var col := WB_WALL
			if v == LogicalGrid.Cell.FLOOR:
				col = WB_FLOOR
			elif v == LogicalGrid.Cell.CORRIDOR:
				col = WB_CORRIDOR
			elif v == LogicalGrid.Cell.DOOR:
				col = WB_DOOR
			var o := g.cell_to_tile_origin(cell)
			for ty in n:
				for tx in n:
					img.set_pixel(o.x + tx, o.y + ty, col)

	# ② 墙的描边：只画【朝向可走格】的那一侧（内部不画线，读起来才干净）
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for cy in g.height:
		for cx in g.width:
			var cell := Vector2i(cx, cy)
			if g.is_walkable(cell):
				continue
			var o := g.cell_to_tile_origin(cell)
			for d in dirs:
				if g.is_walkable(cell + d):
					_draw_seam(img, o, d, n, WB_WALL_EDGE, 0, 1)

	# ③ 房间轮廓 + 类型着色
	for r in gen.graph.rooms:
		var tint := Color(1, 1, 1, 0.16)
		if r.room_type == "spawn":
			tint = WB_SPAWN_TINT
		elif r.room_type == "extract":
			tint = WB_EXTRACT_TINT
		_outline_rect(img, r.rect, n, tint)

	# ④ 每个逻辑格画一条极淡的网格线，帮助判断距离
	for cy in g.height:
		for cx in g.width:
			var o := g.cell_to_tile_origin(Vector2i(cx, cy))
			for i in n:
				_blend_px(img, o.x + i, o.y, WB_GRID)
				_blend_px(img, o.x, o.y + i, WB_GRID)


## 在逻辑格级别给矩形描边（cell 坐标 -> tile 坐标）
func _outline_rect(img: Image, rect: Rect2i, n: int, col: Color) -> void:
	var x0 := rect.position.x * n
	var y0 := rect.position.y * n
	var x1 := (rect.position.x + rect.size.x) * n - 1
	var y1 := (rect.position.y + rect.size.y) * n - 1
	var iw := img.get_width()
	var ih := img.get_height()
	for x in range(x0, x1 + 1):
		_blend_px(img, x, y0, col)
		_blend_px(img, x, y1, col)
	for y in range(y0, y1 + 1):
		_blend_px(img, x0, y, col)
		_blend_px(img, x1, y, col)


func _blend_px(img: Image, x: int, y: int, col: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if col.a >= 1.0:
		img.set_pixel(x, y, col)
	else:
		img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, col.a))


## 美术 tile 版（render_mode == RENDER_ART 时用）
func _build_tiles(img: Image) -> void:
	var g := gen.grid
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var n := LogicalGrid.CELL_SIZE_TILES

	for cy in g.height:
		for cx in g.width:
			var cell := Vector2i(cx, cy)
			var walkable := g.is_walkable(cell)
			var key := _tile_key_for(cell, walkable)
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
	_bake_structure(img)


func _bake_structure(img: Image) -> void:
	var g := gen.grid
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
func _tile_key_for(cell: Vector2i, walkable: bool) -> String:
	var h: int = abs(int(hash(cell)))
	if walkable:
		var room := _room_at(cell)
		if room != null:
			# 房间地面：混凝土 / 泥土 交替，让不同房间有质感差异
			return ["floor_concrete", "floor_metal", "floor_dirt"][room.id % 3]
		return ["floor_asphalt", "floor_concrete"][h % 2]
	# 墙：混凝土为主，少量砖 / 金属
	return ["wall_concrete", "wall_concrete", "wall_brick", "wall_metal"][h % 4]


func _room_at(cell: Vector2i) -> Room:
	if gen == null:
		return null
	for r in gen.graph.rooms:
		if r.rect.has_point(cell):
			return r
	return null


# ═══════════════════════ 主循环 ═══════════════════════

func _process(delta: float) -> void:
	if gen == null or raid == null:
		return
	_time += delta

	if not raid.is_over():
		Tel.mark("player")
		_tick_player(delta)
		Tel.mark("enemies")
		_tick_enemies(delta)
		Tel.mark("tracers")
		_tick_tracers(delta)
		Tel.mark("raid")
		raid.tick(delta, player_pos)
		raid.hp = vitals.hp
		if vitals.dead:
			raid.take_damage(9999)
	else:
		_show_result_once()
		# ⚠️ 回合结束后绝不能还卡在 hitstop 里（Engine.time_scale = 0）
		#    否则画面完全不动，玩家会以为"游戏卡死了"（安卓真机反馈）
		if Engine.time_scale <= 0.0:
			Engine.time_scale = 1.0

	Tel.mark("camera")
	_update_camera()
	Tel.mark("hud")
	_update_hud()
	Tel.mark("flash")
	_update_flash()
	Tel.push_stat("hp", vitals.hp)
	Tel.push_stat("armor", vitals.armor)
	Tel.push_stat("enemies_total", agents.size())
	Tel.push_stat("enemies_alive", _alive_count())
	Tel.push_stat("ammo", player_weapon.ammo_in_mag)
	Tel.push_stat("kills", raid.enemies_killed)
	Tel.push_stat("phase", raid.phase_name())
	Tel.push_stat("seed", _raid_seed)
	Tel.push_stat("spawn_safe", MapGenerator.SPAWN_SAFE_GRAPH_DIST)
	Tel.mark("redraw")
	queue_redraw()


func _alive_count() -> int:
	var n := 0
	for a in agents:
		if a.is_alive():
			n += 1
	return n


## 结算只弹一次（避免每帧重建文本）
func _show_result_once() -> void:
	if result_overlay == null or result_overlay.is_shown():
		return
	var win := raid.phase_name() == "EXTRACTED"
	var rep: Dictionary = raid.settle()
	var lines: Array = []
	if win:
		lines.append("用时 %.0f 秒   剩余 HP %d" % [raid.raid_seconds - raid.time_left, raid.hp])
		lines.append("带出战利品 %d 堆，价值 %d 元" % [
			(rep.get("brought_out", []) as Array).size(), int(rep.get("brought_out_value", 0))])
	else:
		lines.append("死因：%s" % raid.death_reason)
		lines.append("携带的 %d 格装备全部丢失（价值 %d 元）" % [
			int(rep.get("lost_slots", 0)), int(rep.get("lost_value", 0))])
	lines.append("击杀 %d   搜刮容器 %d" % [raid.enemies_killed, raid.containers_looted])
	lines.append("地图种子 %d" % _raid_seed)
	result_overlay.show_result(win, lines)
	Tel.emit("raid_end", {
		"win": win, "reason": raid.death_reason,
		"kills": raid.enemies_killed, "looted": raid.containers_looted,
		"hp": raid.hp, "seed": _raid_seed,
		"time_used": snappedf(raid.raid_seconds - raid.time_left, 0.1),
		"brought_value": int(rep.get("brought_out_value", 0)),
		"lost_slots": int(rep.get("lost_slots", 0)),
	})
	# 结算时把摇杆/按钮整体收起（否则会透过结算遮罩露出来）
	if touch != null:
		touch.set_controls_visible(false)


## 受击闪白 —— ★★★★ 项（spec §7.3）
func _update_flash() -> void:
	if flash_rect == null or Feel == null:
		return
	var a := Feel.flash_alpha()
	if a <= 0.001:
		if flash_rect.color.a != 0.0:
			flash_rect.color = Color(0, 0, 0, 0)
		return
	flash_rect.color = Color(Feel.flash_color(), a)


func _tick_player(delta: float) -> void:
	var prev := player_pos

	# 移动（治疗中不能动 —— reference-teardown §9 的取舍）
	if not medical.is_treating():
		_move_input = _read_move_input()
		if _move_input != Vector2.ZERO:
			var step := _move_input.normalized() * PLAYER_SPEED * vitals.speed_multiplier(raid.carry.weight_ratio()) * delta
			# 分轴碰撞：哪个轴撞墙就只撤销那个轴
			var try_x := Vector2(player_pos.x + step.x, player_pos.y)
			if _walkable(try_x):
				player_pos.x = try_x.x
			var try_y := Vector2(player_pos.x, player_pos.y + step.y)
			if _walkable(try_y):
				player_pos.y = try_y.y
			player_facing = _move_input.normalized()
			# 脚步：按节奏播放 + 发出声响给 AI 听觉
			_step_accum += delta * _move_input.length()
			var interval := 0.46 * lerpf(1.35, 1.0, clampf(vitals.speed_multiplier(raid.carry.weight_ratio()), 0.0, 1.0))
			if _step_accum >= interval:
				_step_accum = 0.0
				noises.append({"pos": player_pos, "loudness_m": NOISE_QUIET})
				if Sfx != null:
					Sfx.play("step_%s" % _floor_material())
	else:
		_move_input = Vector2.ZERO

	# ── 瞄准方向 ──
	# ⚠️ 这里【绝不】把准心吸附到最近敌人。
	#    T-56 明确：角度吸附容易让玩家觉得"被抢枪"；辅助只在开火时以
	#    「子弹磁性」的形式生效（见 _try_fire 里的 AimAssist.pick）。
	var av := Vector2.ZERO
	if touch != null:
		av = touch.aim_vector()
	if av.length() > 0.14:
		player_aim = av.normalized()
		player_facing = player_aim
	elif _mouse_aiming():
		var world := get_global_mouse_position() / CELL_PX
		var d := world - player_pos
		if d.length() > 0.15:
			player_aim = d.normalized()
			player_facing = player_aim
	elif _move_input != Vector2.ZERO:
		player_facing = _move_input.normalized()

	# 换弹完成音（检测状态跳变）
	var was_reloading := player_weapon.is_reloading()
	player_weapon.tick(delta)
	if was_reloading and not player_weapon.is_reloading():
		if Sfx != null:
			Sfx.play("reload_done")

	# 治疗推进
	if medical.is_treating():
		var res := medical.tick(delta, vitals)
		if bool(res.get("done", false)):
			raid.carry.remove(medical.active_item_id if medical.active_item_id != "" else "medical_bandage", 1)

	# 开火：键盘或触屏开火按钮（两者并联）
	# ⚠️ 早先只读 _firing（键盘），触屏开火按钮的 is_down 根本没人读 ——
	#    表现为"必须按屏幕任意处才能开火"（真机反馈）。
	var want_fire := _firing or (touch != null and touch.is_firing())
	if want_fire and not medical.is_treating():
		_try_fire()

	# 流血
	if vitals.tick(delta) > 0:
		pass


func _try_fire() -> void:
	if not player_weapon.can_fire():
		if player_weapon.ammo_in_mag <= 0:
			if Sfx != null:
				Sfx.play("reload_empty")
			player_weapon.start_reload()
			if Sfx != null:
				Sfx.play("reload_start")
		return

	player_weapon.fire()
	# 开枪声很大
	noises.append({"pos": player_pos, "loudness_m": NOISE_LOUD})
	Tel.mark("fire")

	var w := player_weapon.def

	# ── 枪械表现：音效 + 枪口火光 + 抛壳 ──
	if Sfx != null:
		Sfx.play("gun_%s_player" % _weapon_kind(w))
	if fx != null:
		fx.burst("muzzle", player_pos + player_aim * 0.34, player_aim)
		var side := Vector2(-player_aim.y, player_aim.x)
		fx.burst("casing", player_pos + side * 0.22 + player_aim * 0.1, side, 1.0)
	# 自己开枪只给最轻的 kick（spec §7.3：不能每枪都大震）
	Feel.hit("player_shoot")

	# ── 子弹磁性（T-56 首选：射线加粗，**不改准心**）──
	var push := _aim_push()
	var half_angle := AimAssist.half_angle_for_viewport(get_viewport_rect().size.x)
	var assist := AimAssist.pick(player_pos, player_aim, push,
		_aim_targets(), gen.grid, half_angle, float(w.range_m))
	var shot_dir := player_aim
	var tgt: EnemyAgent = null
	if not assist.is_empty():
		shot_dir = assist["dir"]
		tgt = assist["target"].get("agent")

	var dist := float(w.range_m)
	if tgt != null:
		dist = player_pos.distance_to(tgt.pos)

	var extra := player_weapon.current_spread_deg() - w.spread_deg
	var acc := DamageModel.accuracy_at(w, dist, extra)
	var shot_to := player_pos + shot_dir * minf(maxf(dist, 2.0), float(w.range_m))

	if tgt != null and _rng.randf() <= clampf(0.30 + acc * 0.7, 0.05, 0.97):
		player_weapon.mark_hit()
		var hit := DamageModel.resolve_hit(w, dist, extra, _rng)
		var dmg := int(hit["damage"])
		var part := str(hit.get("part", DamageModel.PART_TORSO))
		var died := tgt.take_damage(dmg)
		raid.damage_dealt += dmg
		shot_to = tgt.pos

		# ── 反馈分级（spec §7.3 的核心原则）──
		var lvl := "light"
		if died:
			lvl = "kill"
		elif part == DamageModel.PART_HEAD:
			lvl = "crit"
		elif dmg >= int(0.28 * float(w.damage) * 2.0):
			lvl = "heavy"
		Feel.hit(lvl, tgt.pos, player_pos)
		if fx != null:
			fx.burst("blood_crit" if lvl == "crit" or lvl == "kill" else "blood",
				tgt.pos, shot_dir)
			if died:
				fx.burst("kill", tgt.pos, shot_dir)
		if died:
			raid.register_kill()
			_drop_loot(tgt)
			Tel.emit("kill", {"enemy": tgt.def.id, "part": part, "dmg": dmg,
				"dist": snappedf(dist, 0.1), "kills": raid.enemies_killed})
	else:
		# 打空：子弹打到墙或射程边缘
		var wall: Variant = Ballistics.first_blocking_cell(gen.grid, player_pos, shot_to)
		if wall != null:
			shot_to = Vector2(wall.x + 0.5, wall.y + 0.5)
		if fx != null:
			fx.burst("impact", shot_to, -shot_dir)
		if Sfx != null and player_pos.distance_to(shot_to) < 34.0:
			Sfx.play_at("hit_concrete", shot_to, player_pos, 4.0, 22.0)

	bullets.append({"from": player_pos, "to": shot_to, "ttl": TRACER_TTL, "own": true})
	muzzle_flash.append({"pos": player_pos, "dir": shot_dir, "ttl": 0.07})


## 武器类别 -> 音效后缀（gun_{kind}_player / _enemy）
func _weapon_kind(w: WeaponDef) -> String:
	var id := w.id
	if id.contains("shotgun") or id.contains("shell"):
		return "shotgun"
	if id.contains("pistol"):
		return "pistol"
	return "rifle"


## 桌面鼠标瞄准：只有鼠标真的在动才算（避免静止鼠标误接管朝向）
func _mouse_aiming() -> bool:
	if DisplayServer.is_touchscreen_available():
		return false
	return Input.get_last_mouse_velocity().length() > 1.0


## 摇杆推力。桌面（键盘/鼠标）也给一个恒定值，保证辅助瞄准在桌面上可测。
func _aim_push() -> float:
	var p := 0.0
	if touch != null:
		p = touch.aim_push()
	if p <= 0.01 and _move_input != Vector2.ZERO:
		p = 0.45
	return clampf(p, 0.0, 1.0)


## 给 aim assist 的目标列表。
## ⚠️ 必须带 faction —— spec §7.7 硬原则 2：不能吸附中立 NPC 或同伴。
func _aim_targets() -> Array:
	var out: Array = []
	for a in agents:
		if not a.is_alive():
			continue
		out.append({
			"id": a.id,
			"agent": a,
			"pos": a.pos,
			"faction": "enemy",
			"alive": true,
		})
	return out


func _drop_loot(a: EnemyAgent) -> void:
	var table: LootTableDef = reg.get_loot_table("loot_enemy_drop")
	if table == null:
		return
	var drops := LootRoller.roll_container(table, _rng, 2)
	for d in drops:
		drops_on_ground.append({"pos": a.pos, "item_id": d["item_id"], "count": int(d["count"])})


func _tick_enemies(delta: float) -> void:
	var ctx := {
		"grid": gen.grid,
		"flows": flows,
		"targets": [{"id": "player", "pos": player_pos, "hp": vitals.hp}],
		"rng": _rng,
		"now": _time,
		"noises": noises,
	}
	for a in agents:
		if not a.is_alive():
			continue
		a.tick(delta, ctx)

		# ── 敌人开火的表现：枪声（mid distance 版，自带距离感）+ 枪口火光 ──
		var prev: int = int(_prev_shots.get(a.id, 0))
		if a.shots_fired > prev:
			_prev_shots[a.id] = a.shots_fired
			# 目前所有远程敌人都装的手枪（见 _setup_sim 的 equip 调用）
			var kind := _weapon_kind(a.weapon.def) if a.weapon != null else "pistol"
			if Sfx != null:
				Sfx.play_at("gun_%s_enemy" % kind, a.pos, player_pos, 7.0, 30.0)
			if fx != null:
				fx.burst("muzzle", a.pos + a.facing * 0.3, a.facing, 0.8)
			# 敌人开火也要看得见曳光（真机反馈：只听到声音看不到子弹）
			var e_to: Vector2 = a.pos + a.facing * 6.0
			var e_wall: Variant = Ballistics.first_blocking_cell(gen.grid, a.pos, e_to)
			if e_wall != null:
				e_to = Vector2(e_wall.x + 0.5, e_wall.y + 0.5)
			bullets.append({"from": a.pos, "to": e_to, "ttl": TRACER_TTL, "own": false})
			muzzle_flash.append({"pos": a.pos, "dir": a.facing, "ttl": 0.06})

	# 敌人造成的伤害回写到 vitals
	var target_hp := int((ctx["targets"][0] as Dictionary)["hp"])
	if target_hp < vitals.hp:
		var dealt := vitals.hp - target_hp
		var applied := vitals.take_damage(dealt)
		if medical.should_interrupt(applied):
			medical.cancel()
		if applied > 0:
			var heavy := applied >= 20
			vitals.apply_bleed(Vitals.Bleed.HEAVY if heavy else Vitals.Bleed.LIGHT)
			# ── 自己受伤：大闪白 + 大震动，但【零 hitstop】（不打断操作）──
			Feel.hit("player_hurt", player_pos, player_pos)
			Feel.flash_damage(0.45 if heavy else 0.28)
			if heavy:
				if applied >= 35 and Sfx != null:
					Sfx.play("hurt_heavy")

	noises.clear()
	squad.tick(delta, _time)


func _tick_tracers(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		bullets[i]["ttl"] -= delta
		if bullets[i]["ttl"] <= 0.0:
			bullets.remove_at(i)
	for i in range(muzzle_flash.size() - 1, -1, -1):
		muzzle_flash[i]["ttl"] -= delta
		if muzzle_flash[i]["ttl"] <= 0.0:
			muzzle_flash.remove_at(i)


func _update_camera() -> void:
	var target := player_pos * CELL_PX
	camera.global_position = camera.global_position.lerp(target, 0.18)
	# trauma 震动（trauma² + 整像素量化 —— spec §7.3）
	if Feel != null:
		camera.offset = Feel.shake_offset()
	else:
		camera.offset = Vector2.ZERO


# ═══════════════════════ 输入 ═══════════════════════

func _read_move_input() -> Vector2:
	# 触屏优先（双摇杆写 InputMap action，touch_controls 读回模拟量）
	if touch != null:
		var tv := touch.move_vector()
		if tv != Vector2.ZERO:
			return tv
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v


func _input(event: InputEvent) -> void:
	# ⚠️ 这里【故意不处理 InputEventScreenTouch】。
	#    早先（还没有触屏控件时）本函数把"右半屏任意触摸"当作开火，
	#    真机反馈的三个问题全是它导致的：
	#      ① 按右侧任意位置就开火
	#      ② 点瞄准摇杆就开火（它就在右半屏）
	#      ③ 按"治疗"也开火 -> 治疗永远点不到
	#    现在摇杆（VirtualJoystick）与按钮（TouchButton）各自通过 GUI 系统接管触摸，
	#    这里只留键盘。
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_J, KEY_SPACE:
				_firing = true
			KEY_K:
				player_weapon.start_reload()
			KEY_L:
				_try_heal()
			KEY_TAB:
				debug_mode = (debug_mode + 1) % 4
			KEY_F5:
				# 白模 <-> 美术 tile 切换（技术验证期间主要看白模）
				render_mode = RENDER_ART if render_mode == RENDER_WHITEBOX else RENDER_WHITEBOX
				_build_map_texture()
				if Sfx != null:
					Sfx.play("ui_click")
			KEY_R:
				_restart()
			# ── 无障碍开关（spec §7.3 第 4 条：务必提供关闭/降低震动的选项）──
			KEY_F1:
				Feel.shake_enabled = not Feel.shake_enabled
				if Sfx != null:
					Sfx.play("ui_click")
			KEY_F2:
				Feel.hitstop_enabled = not Feel.hitstop_enabled
				if not Feel.hitstop_enabled:
					Engine.time_scale = 1.0
				if Sfx != null:
					Sfx.play("ui_click")
			KEY_F3:
				Feel.flash_enabled = not Feel.flash_enabled
				if Sfx != null:
					Sfx.play("ui_click")
			KEY_F4:
				Feel.intensity = 0.0 if Feel.intensity > 0.5 else 1.0
				if Sfx != null:
					Sfx.play("ui_click")
			KEY_M:
				if Sfx != null:
					Sfx.enabled = not Sfx.enabled


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and not (event as InputEventKey).pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_J or k.keycode == KEY_SPACE:
			_firing = false


func _try_heal() -> void:
	if medical.is_treating():
		medical.cancel()
		return
	for med_id in ["medical_kit", "medical_bandage", "medical_painkiller"]:
		if raid.carry.has_item(med_id):
			var err := medical.start(reg.get_item(med_id), vitals)
			if err == "":
				raid.carry.remove(med_id, 1)
				return
	push_warning("没有可用的医疗物品")


func _restart() -> void:
	agents.clear()
	bullets.clear()
	muzzle_flash.clear()
	drops_on_ground.clear()
	_prev_shots.clear()
	_step_accum = 0.0
	_time = 0.0
	# 新一局：换种子、清手感状态、收起结算界面
	_raid_seed = 0                 # <=0 -> _setup_sim 会随机
	if Feel != null:
		Feel.reset()
	Engine.time_scale = 1.0
	if result_overlay != null:
		result_overlay.hide_result()
	if touch != null:
		touch.set_controls_visible(true)
	_setup_sim()


# ═══════════════════════ 绘制 ═══════════════════════

func _walkable(p: Vector2) -> bool:
	return gen.grid.is_walkable(Ballistics.cell_of(p))


## 玩家脚下的地面材质 -> 脚步音效后缀
func _floor_material() -> String:
	var key := _tile_key_for(Ballistics.cell_of(player_pos), true)
	if key.contains("metal"):
		return "metal"
	if key.contains("dirt"):
		return "dirt"
	if key.contains("wood"):
		return "wood"
	return "concrete"


func _nearest_enemy() -> EnemyAgent:
	var best: EnemyAgent = null
	var bd := INF
	for a in agents:
		if not a.is_alive():
			continue
		var d: float = player_pos.distance_to(a.pos)
		if d > float(player_weapon.def.range_m):
			continue
		if not Ballistics.has_line_of_sight(gen.grid, player_pos, a.pos):
			continue
		if d < bd:
			bd = d
			best = a
	return best


func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c.x, c.y) * CELL_PX, Vector2(CELL_PX, CELL_PX))


func _draw() -> void:
	if gen == null:
		return
	if Tel != null:
		Tel.mark("draw_body")
	var g := gen.grid

	# ── 地形：一次画完整张烘焙图（nearest 放大 16 倍）──
	if _map_tex != null:
		draw_texture_rect(_map_tex,
			Rect2(Vector2.ZERO, Vector2(_map_tex_size) * TILE_PX), false)
	else:
		# 贴图缺失时的降级绘制
		for y in g.height:
			for x in g.width:
				var c := Vector2i(x, y)
				var v := g.get_cell(c)
				var col := C_WALL
				if v == LogicalGrid.Cell.FLOOR:
					col = C_FLOOR
				elif v == LogicalGrid.Cell.CORRIDOR:
					col = C_CORRIDOR
				draw_rect(_cell_rect(c), col, true)

	# ── 房间类型着色 ──
	for r in gen.graph.rooms:
		var col := C_ROOM_EDGE
		if r.room_type == "spawn":
			col = C_SPAWN
		elif r.room_type == "extract":
			col = C_EXTRACT
		if r.room_type != "common":
			draw_rect(Rect2(Vector2(r.rect.position) * CELL_PX, Vector2(r.rect.size) * CELL_PX), col, false, 3.0)

	# ── 流场调试 ──
	if debug_mode == 1:
		var ex := gen.extract_rooms()
		if not ex.is_empty():
			var f := flows.field_for(ex[0].center)
			if f != null:
				for y in g.height:
					for x in g.width:
						var c := Vector2i(x, y)
						if not g.is_walkable(c):
							continue
						var d := f.get_direction(c)
						if d == Vector2i.ZERO:
							continue
						var ctr := (Vector2(c) + Vector2(0.5, 0.5)) * CELL_PX
						draw_line(ctr, ctr + Vector2(d).normalized() * CELL_PX * 0.42, C_ARROW, 1.5)

	# ── 撤离点 ──
	for p in raid.extract_points:
		var ctr := p * CELL_PX
		draw_arc(ctr, CELL_PX * raid.extract_radius, 0, TAU, 24, C_EXTRACT, 2.0)

	# ── 地上掉落 ──
	for d in drops_on_ground:
		var ctr: Vector2 = (d["pos"] as Vector2) * CELL_PX
		draw_rect(Rect2(ctr - Vector2(5, 5), Vector2(10, 10)), Color(0.95, 0.85, 0.35), true)

	# ── 敌人 ──
	for a in agents:
		var ctr: Vector2 = a.pos * CELL_PX
		if not a.is_alive():
			draw_rect(Rect2(ctr - Vector2(6, 6), Vector2(12, 12)), C_DEAD, true)
			continue
		var col := C_ENEMY_IDLE
		if squad.is_engaged():
			col = C_ENEMY_COMBAT
		elif squad.is_alerted():
			col = C_ENEMY_ALERT
		var r := 9.0 if a.def.is_ranged() else 7.0
		draw_circle(ctr, r, col)
		# 朝向
		draw_line(ctr, ctr + a.facing * r * 1.9, col.lightened(0.35), 2.0)
		# 血条
		var hpr := float(a.hp) / maxf(1.0, float(a.def.hp))
		draw_rect(Rect2(ctr + Vector2(-10, -15), Vector2(20, 3)), Color(0.2, 0.2, 0.22), true)
		draw_rect(Rect2(ctr + Vector2(-10, -15), Vector2(20 * hpr, 3)), Color(0.9, 0.3, 0.3), true)

	# ── 曳光 ──
	# ⚠️ 早先 ttl 只有 0.06s（约 3.6 帧）且线很细，真机上"只听到枪声看不到子弹"。
	#    现在加长到 0.13s，加粗，并在头部画一个亮点。
	for b in bullets:
		var a: Vector2 = (b["from"] as Vector2) * CELL_PX
		var c: Vector2 = (b["to"] as Vector2) * CELL_PX
		var own: bool = bool(b.get("own", true))
		var life: float = clampf(float(b["ttl"]) / TRACER_TTL, 0.0, 1.0)
		var col := (Color(1.0, 0.94, 0.58) if own else Color(1.0, 0.72, 0.55))
		col.a = 0.35 + 0.65 * life
		draw_line(a, c, col, 3.0 if own else 2.0)
		draw_circle(c, 3.0 if own else 2.0, col)

	# ── 枪口火光（画在粒子之外，保证一定看得见）──
	for m in muzzle_flash:
		var p: Vector2 = (m["pos"] as Vector2) * CELL_PX
		var d: Vector2 = m["dir"] as Vector2
		var t: float = clampf(float(m["ttl"]) / 0.07, 0.0, 1.0)
		var f := Vector2(-d.y, d.x)
		# 一个朝向前方的四角星形闪
		var tip := p + d * (16.0 + 10.0 * t)
		var s1 := p + f * 7.0 - d * 4.0
		var s2 := p - f * 7.0 - d * 4.0
		draw_colored_polygon(PackedVector2Array([tip, s1, p - d * 3.0, s2]),
			Color(1.0, 0.90, 0.52, 0.85 * t))
		draw_circle(p + d * 6.0, 5.0 + 4.0 * t, Color(1.0, 0.78, 0.35, 0.55 * t))

	# ── 玩家 ──
	var pc := player_pos * CELL_PX
	draw_circle(pc, 10.0, C_PLAYER)
	draw_line(pc, pc + player_aim * 26.0, Color(1, 1, 1, 0.8), 2.5)
	# 朝向指示器（art-pipeline §3.2 的"朝向可视化"三件套之一）
	draw_arc(pc, 13.0, player_facing.angle() - 0.5, player_facing.angle() + 0.5, 8, C_PLAYER.lightened(0.4), 2.0)

	# ── 调试：声音范围 ──
	if debug_mode == 3 and not noises.is_empty():
		for nz in noises:
			draw_arc((nz["pos"] as Vector2) * CELL_PX, float(nz["loudness_m"]) * CELL_PX * 0.25,
				0, TAU, 24, Color(1, 1, 0.4, 0.25), 1.0)


func _update_hud() -> void:
	if raid == null:
		return
	var lines: Array[String] = []
	lines.append("HP %d/%d   护甲 %d/%d   %s" % [
		vitals.hp, vitals.max_hp, vitals.armor, vitals.max_armor,
		Vitals.BLEED_NAME[vitals.bleed]])
	lines.append("弹药 %d / %d%s" % [
		player_weapon.ammo_in_mag, player_weapon.reserve_ammo,
		"  [换弹中]" if player_weapon.is_reloading() else ""])
	lines.append("剩余 %ds    撤离 %.0f%%" % [int(raid.time_left), raid.extract_progress_ratio() * 100.0])
	lines.append("携带 %s" % raid.carry.summary())
	lines.append("击杀 %d   受伤 %d   治疗 %s" % [
		raid.enemies_killed, vitals.total_damage_taken, medical.status_text()])
	lines.append("小队警戒 %.2f   %s" % [
		squad.alert_level, "交战中" if squad.is_engaged() else ("警觉" if squad.is_alerted() else "放松")])
	# 性能读数（真机排障用：卡顿时可以直接报数字）
	lines.append("FPS %d   帧 %.1f ms   敌 %d   音频掉 %d" % [
		int(Engine.get_frames_per_second()),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		agents.size(),
		0 if Sfx == null else Sfx.dropped_count])

	var dbg := ["普通", "流场方向", "房间图", "声音范围"]
	# 结算界面弹出时藏掉 HUD 正文（否则会和结算文字叠在一起）
	var over := result_overlay != null and result_overlay.is_shown()
	hud_label.visible = not over
	hint_label.visible = not over
	view_label.visible = not over
	if over:
		return
	# ⚠️ 只在文本变化时才赋值。
	#    Godot 里给 Label.text 赋值（哪怕值相同）也会触发 update_minimum_size -> 布局重算，
	#    每帧都设是移动端常见的隐形开销（真机"自动开火卡顿"的次要来源）。
	_set_label(hud_label, "\n".join(lines), "_cache_hud")
	_set_label(view_label, "[视图] %s" % dbg[debug_mode], "_cache_view")
	# ⚠️ 提示必须按平台给（真机反馈：安卓上显示的是 WASD/J/K/L 键盘键位）
	var hint := ("左摇杆移动 · 右摇杆瞄准 · ◉ 开火 · ⟳ 换弹 · ✚ 治疗"
		if _is_touch
		else "WASD 移动 · J/空格 开火 · K 换弹 · L 治疗 · Tab 视图 · R 重开 · F1~F4 无障碍 · M 静音")
	_set_label(hint_label, hint, "_cache_hint")


var _cache_hud := ""
var _cache_view := ""
var _cache_hint := ""


func _set_label(l: Label, txt: String, cache_key: String) -> void:
	if get(cache_key) == txt:
		return
	set(cache_key, txt)
	l.text = txt
