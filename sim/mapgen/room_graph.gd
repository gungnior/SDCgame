class_name RoomGraph
extends RefCounted

## 房间邻接图 —— specs/tech-stack.md §5.2 的 ②③④ 步
##
##   ② 房间邻接图      由房间中心距离构成完全图
##   ③ Kruskal MST     保证全连通（这是「全连通」硬约束的结构性保证）
##   ④ 回加 10%~20% 边 造环（TinyKeep 用 15%）—— 无环的地图是树，走起来很闷
##
## 纯 RefCounted，可 headless 单测。

var rooms: Array[Room] = []
## 无向边，存为 (小 id, 大 id) 保证唯一
var edges: Array[Vector2i] = []

var mst_edges: Array[Vector2i] = []
var cycle_edges: Array[Vector2i] = []


func add_room(r: Rect2i) -> int:
	var room := Room.new(rooms.size(), r)
	rooms.append(room)
	return room.id


func get_room(id: int) -> Room:
	if id < 0 or id >= rooms.size():
		return null
	return rooms[id]


func room_count() -> int:
	return rooms.size()


static func _edge_key(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


func has_edge(a: int, b: int) -> bool:
	return edges.has(_edge_key(a, b))


func _add_edge(a: int, b: int) -> void:
	var k := _edge_key(a, b)
	if a != b and not edges.has(k):
		edges.append(k)


## 相邻房间的 id 列表（按边表构建）
func neighbors(id: int) -> Array[int]:
	var out: Array[int] = []
	for e in edges:
		if e.x == id:
			out.append(e.y)
		elif e.y == id:
			out.append(e.x)
	return out


func _dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a).distance_to(Vector2(b))


# ─────────────────── ③ Kruskal MST ───────────────────

## 用 Kruskal 算法建最小生成树，保证全连通。返回是否成功（房间数 <= 1 时视为成功）。
func build_mst() -> bool:
	mst_edges.clear()
	if rooms.size() <= 1:
		return true

	# 收集所有房间对，按距离升序
	var cands: Array = []
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			cands.append({"a": i, "b": j, "w": _dist(rooms[i].center, rooms[j].center)})
	cands.sort_custom(func(x, y): return x["w"] < y["w"])

	# 并查集
	var parent := PackedInt32Array()
	parent.resize(rooms.size())
	for i in parent.size():
		parent[i] = i

	for c in cands:
		var ra := _find(parent, c["a"])
		var rb := _find(parent, c["b"])
		if ra != rb:
			parent[ra] = rb
			var k := _edge_key(c["a"], c["b"])
			mst_edges.append(k)
			edges.append(k)

	# 校验：MST 应当恰好 n-1 条边
	return mst_edges.size() == rooms.size() - 1


func _find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x


# ─────────────────── ④ 回加环 ───────────────────

## 从非 MST 的边里按距离随机回加约 ratio 比例，制造环路。
## 返回实际回加的边数。
func add_cycle_edges(ratio: float, rng: SimRng) -> int:
	cycle_edges.clear()
	if rooms.size() <= 2:
		return 0

	# 候选 = 完全图里不在 MST 上的边，且距离不能太远（太远会横穿整张图）
	var cands: Array = []
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			var k := _edge_key(i, j)
			if mst_edges.has(k):
				continue
			cands.append({"a": i, "b": j, "w": _dist(rooms[i].center, rooms[j].center), "k": k})
	if cands.is_empty():
		return 0
	cands.sort_custom(func(x, y): return x["w"] < y["w"])

	# 只从最近的 50% 候选里挑，避免生成横穿地图的怪走廊
	var pool := cands.slice(0, maxi(1, int(cands.size() * 0.5)))
	var want := int(round(float(pool.size()) * clampf(ratio, 0.0, 1.0) / 0.5))
	want = clampi(want, 0, pool.size())

	var picked := {}
	for _i in want:
		var idx := rng.randi_range(0, pool.size() - 1)
		var tries := 0
		while picked.has(idx) and tries < pool.size():
			idx = rng.randi_range(0, pool.size() - 1)
			tries += 1
		if picked.has(idx):
			break
		picked[idx] = true
		var k: Vector2i = pool[idx]["k"]
		cycle_edges.append(k)
		edges.append(k)

	return cycle_edges.size()


# ─────────────────── 图距离与连通性 ───────────────────

## 从 from_id 出发的 BFS 跳数表 {room_id: 跳数}
func bfs_depths(from_id: int) -> Dictionary:
	var dist := {}
	if get_room(from_id) == null:
		return dist
	dist[from_id] = 0
	var queue: Array[int] = [from_id]
	var head := 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		for nb in neighbors(cur):
			if not dist.has(nb):
				dist[nb] = dist[cur] + 1
				queue.append(nb)
	return dist


func is_graph_connected() -> bool:
	if rooms.is_empty():
		return false
	return bfs_depths(0).size() == rooms.size()


## 把每个房间的 depth 写成距 from_id 的跳数
func assign_depths(from_id: int) -> void:
	var d := bfs_depths(from_id)
	for r in rooms:
		r.depth = int(d.get(r.id, -1))


## 图距离（跳数）矩阵访问器：不可达返回 -1
func graph_distance(a: int, b: int) -> int:
	var d := bfs_depths(a)
	return int(d.get(b, -1))


func _to_string() -> String:
	return "RoomGraph(rooms=%d, edges=%d [mst=%d, cycle=%d])" % [
		rooms.size(), edges.size(), mst_edges.size(), cycle_edges.size()]
