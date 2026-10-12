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
var bullets: Array = []          ## 表现层专用：曳光弹 {from, to, ttl}
var noises: Array = []
var drops_on_ground: Array = []  ## {pos, item_id, count}

# ─── 玩家 ───
var player_pos := Vector2.ZERO
var player_facing := Vector2.RIGHT
var player_aim := Vector2.RIGHT
var player_weapon: WeaponState

# ─── 输入 ───
var _move_input := Vector2.ZERO
var _touch_move_id := -1
var _touch_move_origin := Vector2.ZERO
var _firing := false
var _aim_dir := Vector2.RIGHT

# ─── 视图 ───
var camera: Camera2D
var hud: CanvasLayer
var hud_label: Label
var hint_label: Label
var view_label: Label
var debug_mode := 0              ## 0 普通 1 流向场 2 房间图 3 声音范围

var _rng := SimRng.new(20261012)
var _time := 0.0

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

	gen = MapGenerator.new()
	if not gen.generate(20261012, reg.room_types):
		push_error("地图生成失败：%s" % str(gen.errors))
		return

	flows = FlowFieldManager.new()
	flows.setup(gen.grid)

	# 藏身处（跨局持久）
	var hideout := Hideout.new(reg.items, 3000)
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
	camera = Camera2D.new()
	camera.zoom = Vector2(1.0, 1.0)
	add_child(camera)
	camera.make_current()

	hud = CanvasLayer.new()
	add_child(hud)

	hud_label = Label.new()
	hud_label.position = Vector2(10, 6)
	hud_label.add_theme_font_size_override("font_size", 13)
	hud_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.96))
	hud.add_child(hud_label)

	hint_label = Label.new()
	hint_label.position = Vector2(10, 342)
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	hint_label.text = "WASD 移动 · J/空格 开火 · K 换弹 · L 治疗 · Tab 调试视图 · R 重开"
	hud.add_child(hint_label)

	view_label = Label.new()
	view_label.position = Vector2(10, 328)
	view_label.add_theme_font_size_override("font_size", 11)
	view_label.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88))
	hud.add_child(view_label)

	_load_tiles()
	_build_map_texture()


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
	img.fill(Color(0.08, 0.09, 0.11))

	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012

	for cy in gen.grid.height:
		for cx in gen.grid.width:
			var cell := Vector2i(cx, cy)
			var walkable := gen.grid.is_walkable(cell)
			var key := _tile_key_for(cell, walkable)
			var variants: Array = _tiles.get(key, [])
			if variants.is_empty():
				continue
			# 每个 tile 位置按坐标哈希挑变体 —— 避免整片地板长得一模一样
			var origin := gen.grid.cell_to_tile_origin(cell)
			for ty in LogicalGrid.CELL_SIZE_TILES:
				for tx in LogicalGrid.CELL_SIZE_TILES:
					var idx: int = abs(hash(Vector2i(origin.x + tx, origin.y + ty))) % variants.size()
					var v: Image = variants[idx]
					img.blit_rect(v, Rect2i(Vector2i.ZERO, Vector2i(TILE_PX, TILE_PX)),
						Vector2i(origin.x + tx, origin.y + ty))

	# ── 结构层：在【逻辑格】级别画墙的轮廓 + 贴墙阴影 ──
	# 为什么不在 16x16 砖里做：一个逻辑格要铺 3x3 块砖，
	# 每块砖都带边会在一个格子里堆出 3 条横杠（实测踩过）。
	# 结构信息属于逻辑格，不属于砖 —— 这是分层的关键。
	_bake_structure(img)

	_map_tex = ImageTexture.create_from_image(img)


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
		_tick_player(delta)
		_tick_enemies(delta)
		_tick_tracers(delta)
		raid.tick(delta, player_pos)
		raid.hp = vitals.hp
		if vitals.dead:
			raid.take_damage(9999)

	_update_camera()
	_update_hud()
	queue_redraw()


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
			# 走路有脚步声
			if fmod(_time, 0.6) < delta:
				noises.append({"pos": player_pos, "loudness_m": NOISE_QUIET})
	else:
		_move_input = Vector2.ZERO

	# 瞄准：优先朝最近可见敌人（T-56 子弹磁性）
	var t := _nearest_enemy()
	if t != null:
		player_aim = (t.pos - player_pos).normalized()
		if _move_input == Vector2.ZERO:
			player_facing = player_aim
	elif _move_input != Vector2.ZERO:
		player_aim = _move_input.normalized()

	player_weapon.tick(delta)

	# 治疗推进
	if medical.is_treating():
		var res := medical.tick(delta, vitals)
		if bool(res.get("done", false)):
			raid.carry.remove(medical.active_item_id if medical.active_item_id != "" else "medical_bandage", 1)

	# 开火
	if _firing and not medical.is_treating():
		_try_fire()

	# 流血
	if vitals.tick(delta) > 0:
		pass


func _try_fire() -> void:
	if not player_weapon.can_fire():
		if player_weapon.ammo_in_mag <= 0:
			player_weapon.start_reload()
		return

	player_weapon.fire()
	# 开枪声很大
	noises.append({"pos": player_pos, "loudness_m": NOISE_LOUD})

	var dist := 30.0
	var tgt := _nearest_enemy()
	if tgt != null:
		dist = player_pos.distance_to(tgt.pos)

	var extra := player_weapon.current_spread_deg() - player_weapon.def.spread_deg
	var hit := DamageModel.resolve_hit(player_weapon.def, dist, extra, _rng)
	var acc := DamageModel.accuracy_at(player_weapon.def, dist, extra)

	var shot_to := player_pos + player_aim * minf(dist, float(player_weapon.def.range_m))

	if tgt != null and _rng.randf() <= clampf(0.30 + acc * 0.7, 0.05, 0.97):
		player_weapon.mark_hit()
		var dmg := int(hit["damage"])
		var died := tgt.take_damage(dmg)
		raid.damage_dealt += dmg
		if died:
			raid.register_kill()
			_drop_loot(tgt)
	else:
		# 打空：子弹打到墙或射程边缘
		var wall = Ballistics.first_blocking_cell(gen.grid, player_pos, shot_to)
		if wall != null:
			shot_to = Vector2(wall.x + 0.5, wall.y + 0.5)

	bullets.append({"from": player_pos, "to": shot_to, "ttl": 0.06})


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

	noises.clear()
	squad.tick(delta, _time)


func _tick_tracers(delta: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		bullets[i]["ttl"] -= delta
		if bullets[i]["ttl"] <= 0.0:
			bullets.remove_at(i)


func _update_camera() -> void:
	var target := player_pos * CELL_PX
	camera.global_position = camera.global_position.lerp(target, 0.18)


# ═══════════════════════ 输入 ═══════════════════════

func _read_move_input() -> Vector2:
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	if v != Vector2.ZERO:
		return v
	return _touch_move_vector()


func _touch_move_vector() -> Vector2:
	# 触屏：左半屏拖动当摇杆
	if _touch_move_id < 0:
		return Vector2.ZERO
	for i in Input.get_connected_joypads():
		pass
	var d := _last_touch_pos - _touch_move_origin
	if d.length() < 12.0:
		return Vector2.ZERO
	return d.normalized()


var _last_touch_pos := Vector2.ZERO


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		var half := get_viewport_rect().size.x * 0.5
		if t.pressed and t.position.x < half and _touch_move_id < 0:
			_touch_move_id = t.index
			_touch_move_origin = t.position
			_last_touch_pos = t.position
		elif t.pressed:
			_firing = true
		else:
			if t.index == _touch_move_id:
				_touch_move_id = -1
			else:
				_firing = false
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _touch_move_id:
			_last_touch_pos = d.position
	elif event is InputEventKey:
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
			KEY_R:
				_restart()


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
	drops_on_ground.clear()
	_setup_sim()


# ═══════════════════════ 绘制 ═══════════════════════

func _walkable(p: Vector2) -> bool:
	return gen.grid.is_walkable(Ballistics.cell_of(p))


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
	for b in bullets:
		draw_line((b["from"] as Vector2) * CELL_PX, (b["to"] as Vector2) * CELL_PX,
			Color(1.0, 0.92, 0.55, 0.85), 2.0)

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
	if raid.is_over():
		lines.append("")
		lines.append("═══ %s ═══" % raid.phase_name())
		if raid.phase_name() == "EXTRACTED":
			lines.append("撤离成功！按 R 再来一局")
		else:
			lines.append("阵亡：%s（装备已丢失）按 R 重开" % raid.death_reason)

	var dbg := ["普通", "流场方向", "房间图", "声音范围"]
	hud_label.text = "\n".join(lines)
	view_label.text = "[视图] %s" % dbg[debug_mode]
	hint_label.text = "WASD 移动 · J/空格 开火 · K 换弹 · L 治疗 · Tab 视图 · R 重开"
