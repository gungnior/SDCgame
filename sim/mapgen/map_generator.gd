class_name MapGenerator
extends RefCounted

## 地图生成器 —— 编排 specs/tech-stack.md §5.2 的完整图优先链路
##
##   seed
##    → ① BSP 房间布点
##    → ② 房间邻接图
##    → ③ Kruskal MST 保证全连通
##    → ④ 回加 10%~20% 边造环
##    → ⑤ 固定宽度走廊（恒 1 逻辑格 = 3 tile）
##    → ⑥ 按「图距离 + 深度」分配房间类型
##    → ⑦ ★ 图论校验不通过就换 seed 重来（最多 MAX_ATTEMPTS 次）
##
## 纯 RefCounted，无 Node 依赖，可 headless 单测。

## ⚠️ 24 -> 64（2026-10-12 实测）：
##   多数种子需要重试 **2~18 次**才能通过图论校验（房间多、撤离点距离约束难满足），
##   24 次余量太小 —— 实测 seed 476761045 会**耗尽 24 次仍失败**，
##   表现为"点开始下一局却生成不出地图 / 刷不出敌人"（集成测试正好撞到）。
##   放宽到 64 后该 seed 可通过；这是**兜底余量**，不是约束本身的修复。
const MAX_ATTEMPTS := 64
const CYCLE_RATIO := 0.15          ## TinyKeep 用 15%
const BSP_MIN_ROOM_CELLS := 3      ## 房间最小 3x3 逻辑格
## 出生点周围多少跳内不刷敌人。
## ⚠️ 安卓真机实测：没有这条时玩家一出生就贴脸遇敌，几秒内被打死。
const SPAWN_SAFE_GRAPH_DIST := 2
## 上一局出生安全区清掉了几个房间的敌人（调试/测试用）
var spawn_safe_cleared := 0
const BSP_MAX_DEPTH := 5           ## 最多 2^5 = 32 个叶子
const ROOM_INSET := 1              ## 房间四周留 1 格，避免房间互相贴住

var rng: SimRng
var grid: LogicalGrid
var graph: RoomGraph
var errors: Array[String] = []

var used_seed: int = 0
var attempts_used: int = 0
var grid_w: int = 27               ## 逻辑格宽（27 * 3 = 81 tile，贴合 80x80 的目标地图尺寸）
var grid_h: int = 27

## 由 data/rooms.json 注入
var _room_defs: Dictionary = {}

## 地图主题（2026-10-13）。决定地图多大、房间配额、敌人池与密度、白模色调。
##
## ⚠️ **null = 旧行为**：普通房间只用同一个 room_common 定义、
##    不按密度缩放敌人、不生成容器。这样所有既有测试（不传 theme）
##    的行为**逐字节不变** —— 新能力全靠显式传主题开启。
var theme: MapThemeDef = null
## 本局实际刷出的可搜索容器总数（生成后统计）
var container_total: int = 0


## 主入口。room_defs 是 {room_type_id: RoomTypeDef}。
## 成功返回 true；失败时 errors 里有原因。
## theme 传 null 时保持旧行为（见 theme 字段的说明）。
func generate(seed_value: int, room_defs: Dictionary, w: int = 27, h: int = 27,
		p_theme: MapThemeDef = null) -> bool:
	_room_defs = room_defs
	theme = p_theme
	grid_w = w
	grid_h = h
	errors.clear()

	for attempt in MAX_ATTEMPTS:
		attempts_used = attempt + 1
		var s := seed_value + attempt * 7919   # 换 seed 重来（用大质数步进，避免相邻 seed）
		if _try_generate(s):
			used_seed = s
			return true

	errors.append("连续 %d 次尝试均未通过图论校验（起始 seed=%d）" % [MAX_ATTEMPTS, seed_value])
	return false


func _try_generate(seed_value: int) -> bool:
	rng = SimRng.new(seed_value)
	grid = LogicalGrid.new(grid_w, grid_h)
	graph = RoomGraph.new()

	# ① BSP 房间布点
	var leaves: Array[Rect2i] = []
	_bsp_split(Rect2i(1, 1, grid_w - 2, grid_h - 2), leaves, 0)
	if leaves.size() < 4:
		errors.append("seed %d: BSP 只分出 %d 个房间，太少" % [seed_value, leaves.size()])
		return false
	for r in leaves:
		graph.add_room(r)

	# ②③ 邻接图 + Kruskal MST
	if not graph.build_mst():
		errors.append("seed %d: MST 构建失败" % seed_value)
		return false

	# ④ 回加环
	graph.add_cycle_edges(CYCLE_RATIO, rng)

	# ⑤ 挖房间与走廊
	for room in graph.rooms:
		grid.carve_rect(room.rect, LogicalGrid.Cell.FLOOR)
	for e in graph.edges:
		var a := graph.get_room(e.x)
		var b := graph.get_room(e.y)
		if a != null and b != null:
			grid.carve_corridor_l(a.center, b.center, LogicalGrid.Cell.CORRIDOR)

	# ⑥ 分配房间类型（按图距离）
	if not _assign_room_types():
		return false

	# ⑥.5 容器布点（按房间类型挂靠；只有带主题时才生成）
	_place_containers()

	# ⑦ 校验：连通性 + 地图硬约束
	if not grid.is_fully_connected():
		errors.append("seed %d: 地图不连通（逻辑格级）" % seed_value)
		return false
	if not _validate_hard_constraints(seed_value):
		return false

	return true


# ─────────────────── ① BSP ───────────────────

func _bsp_split(area: Rect2i, out: Array[Rect2i], depth: int) -> void:
	# 到达深度上限，或再切就小于两倍最小房间 → 成为叶子
	var can_h := area.size.x >= BSP_MIN_ROOM_CELLS * 2 + 1
	var can_v := area.size.y >= BSP_MIN_ROOM_CELLS * 2 + 1
	if depth >= BSP_MAX_DEPTH or (not can_h and not can_v):
		out.append(_inset(area))
		return

	# 选长边切；长宽接近时随机
	var split_h: bool
	if can_h and can_v:
		if area.size.x > area.size.y * 1.25:
			split_h = true
		elif area.size.y > area.size.x * 1.25:
			split_h = false
		else:
			split_h = rng.randf() < 0.5
	elif can_h:
		split_h = true
	else:
		split_h = false

	if split_h:
		var lo := BSP_MIN_ROOM_CELLS
		var hi := area.size.x - BSP_MIN_ROOM_CELLS - 1
		var cut := rng.randi_range(lo, maxi(lo, hi))
		_bsp_split(Rect2i(area.position, Vector2i(cut, area.size.y)), out, depth + 1)
		_bsp_split(Rect2i(area.position + Vector2i(cut, 0), Vector2i(area.size.x - cut, area.size.y)), out, depth + 1)
	else:
		var lo2 := BSP_MIN_ROOM_CELLS
		var hi2 := area.size.y - BSP_MIN_ROOM_CELLS - 1
		var cut2 := rng.randi_range(lo2, maxi(lo2, hi2))
		_bsp_split(Rect2i(area.position, Vector2i(area.size.x, cut2)), out, depth + 1)
		_bsp_split(Rect2i(area.position + Vector2i(0, cut2), Vector2i(area.size.x, area.size.y - cut2)), out, depth + 1)


## 房间四周内缩，避免两个房间共墙
func _inset(a: Rect2i) -> Rect2i:
	var r := Rect2i(
		a.position + Vector2i(ROOM_INSET, ROOM_INSET),
		a.size - Vector2i(ROOM_INSET * 2, ROOM_INSET * 2))
	if r.size.x < BSP_MIN_ROOM_CELLS:
		r.size.x = BSP_MIN_ROOM_CELLS
	if r.size.y < BSP_MIN_ROOM_CELLS:
		r.size.y = BSP_MIN_ROOM_CELLS
	return r


# ─────────────────── ⑥ 房间类型分配 ───────────────────

func _def_for(type_str: String) -> RoomTypeDef:
	for k in _room_defs:
		var d: RoomTypeDef = _room_defs[k]
		if d.room_type == type_str:
			return d
	return null


func _assign_room_types() -> bool:
	var spawn_def := _def_for("spawn")
	var extract_def := _def_for("extract")
	var common_def := _def_for("common")
	if spawn_def == null or extract_def == null:
		errors.append("rooms.json 缺少 spawn 或 extract 定义")
		return false

	# ⚠️ 实测教训：出生点【不能随机选】。
	#    随机选时，图里大部分房间离出生点只有 1~3 跳，满足
	#    depth >= min_graph_dist(5) 的房间经常只有 0~1 个 → 撤离点分配失败
	#    → 24 次换 seed 尝试全部挂掉。
	#    正确做法：把出生点放在图的【近似直径端点】上，最远的房间才真的远。
	var candidates := _spawn_candidates()
	for spawn_idx in candidates:
		if _try_assign_with_spawn(spawn_idx, spawn_def, extract_def, common_def):
			return true

	errors.append("seed: 所有出生点候选都不满足撤离点约束（房间数 %d）" % graph.rooms.size())
	return false


## 出生点候选：双 BFS 求近似直径端点，再加若干随机点兜底
func _spawn_candidates() -> Array[int]:
	var out: Array[int] = []
	if graph.rooms.is_empty():
		return out
	var a := _farthest_from(0)
	var b := _farthest_from(a)
	out.append(b)
	if not out.has(a):
		out.append(a)
	for _i in mini(6, graph.rooms.size()):
		var r := rng.randi_range(0, graph.rooms.size() - 1)
		if not out.has(r):
			out.append(r)
	return out


func _farthest_from(from_id: int) -> int:
	var d := graph.bfs_depths(from_id)
	var best := from_id
	var best_d := -1
	for k in d:
		var v := int(d[k])
		if v > best_d:
			best_d = v
			best = int(k)
	return best


func _try_assign_with_spawn(spawn_idx: int, spawn_def: RoomTypeDef, extract_def: RoomTypeDef, common_def: RoomTypeDef) -> bool:
	graph.assign_depths(spawn_idx)

	var far: Array[int] = []
	for r in graph.rooms:
		if r.id == spawn_idx:
			continue
		if r.depth >= extract_def.min_graph_dist:
			far.append(r.id)
	if far.size() < extract_def.min_count:
		return false

	# 清掉上一次候选留下的分配
	for r in graph.rooms:
		r.room_type = ""
		r.room_type_id = ""
		r.loot_table_id = ""
		r.enemy_budget = 0
		r.container_spawns.clear()

	var spawn_room := graph.get_room(spawn_idx)
	spawn_room.room_type_id = spawn_def.id
	spawn_room.room_type = "spawn"
	spawn_room.loot_table_id = spawn_def.loot_table_id
	spawn_room.enemy_budget = spawn_def.roll_enemy_budget(rng)

	_shuffle(far)
	var want := extract_def.roll_count(rng)
	want = clampi(want, extract_def.min_count, mini(extract_def.max_count, far.size()))
	for i in want:
		var r := graph.get_room(far[i])
		r.room_type_id = extract_def.id
		r.room_type = "extract"
		r.loot_table_id = extract_def.loot_table_id
		r.enemy_budget = extract_def.roll_enemy_budget(rng)

	# ── 普通房间：分配「房间主题」（可有多个 common 类定义）──
	# theme == null 时退化为旧行为：全部用同一个 common 定义（room_common）。
	var pool := _common_defs()
	if pool.is_empty() and common_def != null:
		pool.append(common_def)
	for r in graph.rooms:
		if r.room_type == "common" or r.room_type.is_empty():
			r.room_type = "common"
			var cd: RoomTypeDef = _pick_common_def(pool)
			if cd != null:
				r.room_type_id = cd.id
				r.loot_table_id = cd.loot_table_id
				r.enemy_budget = cd.roll_enemy_budget(rng)

	# ── 敌人密度：按地图主题把总数拉向「房间数 × density」──
	_apply_enemy_density()

	# ── 出生安全区 ──
	# ⚠️ 实测（安卓真机）：没有这条时，玩家一出生就贴脸遇敌，几秒内被打死，
	#    根本活不到能观察地图的程度。所以出生点周围 SPAWN_SAFE_GRAPH_DIST 跳内
	#    **一律不刷敌人**。
	_apply_spawn_safe_zone(spawn_idx)
	return true


## 把出生点周围 N 跳内的敌人预算清零
func _apply_spawn_safe_zone(spawn_idx: int) -> void:
	var depths := graph.bfs_depths(spawn_idx)
	var cleared := 0
	for r in graph.rooms:
		if r.id == spawn_idx:
			r.enemy_budget = 0
			continue
		var d: int = int(depths.get(r.id, 999))
		if d <= SPAWN_SAFE_GRAPH_DIST:
			if r.enemy_budget > 0:
				cleared += 1
			r.enemy_budget = 0
	spawn_safe_cleared = cleared


# ─────────────────── 房间主题 / 敌人密度 / 容器（2026-10-13）───────────────────

## 所有 room_type == "common" 的定义，**按 id 稳定排序**（保证可复现）
func _common_defs() -> Array[RoomTypeDef]:
	var out: Array[RoomTypeDef] = []
	for k in _room_defs:
		var d: RoomTypeDef = _room_defs[k]
		if d.room_type == "common":
			out.append(d)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


## 给一个普通房间抽「房间主题」（军械库 / 医疗室 / 宿舍 / 仓库 / 实验室 …）。
##   · 有主题且主题里配了权重 -> 按 theme.room_weights 抽
##   · 否则退回各定义自带的 `weight` 字段
##   · theme == null -> 取第一个（= room_common），保持旧行为
func _pick_common_def(pool: Array[RoomTypeDef]) -> RoomTypeDef:
	if pool.is_empty():
		return null
	if theme == null:
		return pool[0]
	var keys: Array = []
	var ws: Array = []
	for d in pool:
		var w := int(theme.room_weights.get(d.id, 0))
		if w <= 0:
			w = d.weight
		if w > 0:
			keys.append(d.id)
			ws.append(w)
	if keys.is_empty():
		return pool[0]
	var idx := rng.weighted_index(ws)
	if idx < 0 or idx >= keys.size():
		return pool[0]
	var picked: RoomTypeDef = _room_defs.get(str(keys[idx]))
	return picked if picked != null else pool[0]


## 按地图主题的密度，把敌人总数缩放到「房间数 × enemy_density」。
## ⚠️ 这就是用户说的"具体人数参考地图大小"：地图越大 -> 房间越多 -> 敌人越多，
##    而密度本身由主题决定（森林稀疏、军事基地密集）。
## theme == null 时不动（旧行为）。
func _apply_enemy_density() -> void:
	if theme == null:
		return
	var target := theme.target_enemy_count(graph.rooms.size())
	var total := total_enemy_budget()
	if target <= 0:
		for r in graph.rooms:
			r.enemy_budget = 0
		return
	if total <= 0:
		return
	var k := float(target) / float(total)
	for r in graph.rooms:
		if r.room_type == "spawn":
			continue
		r.enemy_budget = maxi(0, int(round(float(r.enemy_budget) * k)))


## 按房间类型挂靠生成【容器布点】。
## `room_type.containers[]` 里每条 ContainerRef 展开成 count_min~count_max 个具体位置。
## ⚠️ 只布点、不抽物品：MapGenerator 拿不到 loot_tables（分层），
##    物品抽取由 raid_scene 用掉落表执行。
## theme == null 时不生成（保持旧行为不变）。
func _place_containers() -> void:
	container_total = 0
	if theme == null:
		return
	for r in graph.rooms:
		r.container_spawns.clear()
		var rd: RoomTypeDef = _room_defs.get(r.room_type_id)
		if rd == null:
			continue
		for cr in rd.containers:
			var n := cr.roll_count(rng)
			for _i in n:
				var p := _random_floor_in(r)
				if p.x >= 0:
					r.container_spawns.append({"container_id": cr.container_id, "pos": p})
					container_total += 1


## 在房间矩形内随机找一个可走格（布容器用）。找不到返回 (-1, -1)。
func _random_floor_in(r: Room) -> Vector2i:
	var w := maxi(1, r.rect.size.x)
	var h := maxi(1, r.rect.size.y)
	for _t in 16:
		var c := Vector2i(
			rng.randi_range(r.rect.position.x, r.rect.position.x + w - 1),
			rng.randi_range(r.rect.position.y, r.rect.position.y + h - 1))
		if grid.get_cell(c) == LogicalGrid.Cell.FLOOR:
			return c
	return Vector2i(-1, -1)


## 本局刷出的可搜索容器总数
func total_container_count() -> int:
	return container_total


func _shuffle(a: Array[int]) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t := a[i]
		a[i] = a[j]
		a[j] = t


# ─────────────────── ⑦ 硬约束校验 ───────────────────

func _validate_hard_constraints(seed_value: int) -> bool:
	var spawn_n := 0
	var extract_n := 0
	var extract_min_depth := 999999

	for r in graph.rooms:
		if r.room_type == "spawn":
			spawn_n += 1
		elif r.room_type == "extract":
			extract_n += 1
			extract_min_depth = mini(extract_min_depth, r.depth)

	var extract_def := _def_for("extract")
	if extract_def == null:
		return false

	if spawn_n != 1:
		errors.append("seed %d: 出生点数量 %d != 1" % [seed_value, spawn_n])
		return false
	if extract_n < extract_def.min_count:
		errors.append("seed %d: 撤离点 %d < %d" % [seed_value, extract_n, extract_def.min_count])
		return false
	if extract_min_depth < extract_def.min_graph_dist:
		errors.append("seed %d: 撤离点最小图距离 %d < %d（出生即撤离）"
			% [seed_value, extract_min_depth, extract_def.min_graph_dist])
		return false
	if not graph.is_graph_connected():
		errors.append("seed %d: 房间图不连通" % seed_value)
		return false
	return true


# ─────────────────── 查询/调试 ───────────────────

func spawn_room() -> Room:
	for r in graph.rooms:
		if r.room_type == "spawn":
			return r
	return null


func extract_rooms() -> Array[Room]:
	var out: Array[Room] = []
	for r in graph.rooms:
		if r.room_type == "extract":
			out.append(r)
	return out


func total_enemy_budget() -> int:
	var n := 0
	for r in graph.rooms:
		n += r.enemy_budget
	return n


## 逻辑格视角的 ASCII 图（叠加房间类型首字母）
func to_ascii() -> String:
	var overlay := {}
	for r in graph.rooms:
		var ch := "c"
		if r.room_type == "spawn":
			ch = "S"
		elif r.room_type == "extract":
			ch = "E"
		overlay[r.center] = ch

	var base := grid.to_ascii()
	var lines := base.split("\n")
	for c in overlay:
		if c.y >= 0 and c.y < lines.size() and c.x >= 0 and c.x < lines[c.y].length():
			var line: String = lines[c.y]
			lines[c.y] = line.substr(0, c.x) + overlay[c] + line.substr(c.x + 1)
	return "\n".join(lines)


func summary() -> String:
	var extra := ""
	if theme != null:
		extra = " 主题=%s %dx%d 密度%.1f 容器=%d" % [
			theme.name, grid_w, grid_h, theme.enemy_density, container_total]
	return "seed=%d 尝试%d次 房间=%d 边=%d(MST %d/环 %d) 可走格=%d 敌人预算=%d%s" % [
		used_seed, attempts_used, graph.rooms.size(), graph.edges.size(),
		graph.mst_edges.size(), graph.cycle_edges.size(),
		grid.walkable_count(), total_enemy_budget(), extra]
