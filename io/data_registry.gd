class_name DataRegistry
extends RefCounted

## 数据注册表：加载 + 校验 + 建索引。
##
## 契约：data/SCHEMA.md（唯一真源）
## 设计依据：T-64 —— JSON 为唯一真源，运行时编译成 Dictionary 索引；
##           **不生成 475 个 .tres**
##
## 纯 RefCounted，可在 --headless 下运行。这是 D-06 的要求。
##
## 阶段机制（D-17 约束 5「用数据开关，不用代码分支」）：
##   每条数据带 stage（B/A/C），load_all(max_stage) 只装载 <= max_stage 的条目。
##   从 B 升级到 A，只是换一个参数 + 补数据，**不改代码**。

const DATA_DIR := "res://data"

## 阶段顺序：B 是 A 的子集，A 是 C 的子集
const STAGE_ORDER := ["B", "A", "C"]

# ─────────────── 索引（id -> Def）───────────────
var items: Dictionary = {}        # item_id    -> ItemDef
var weapons: Dictionary = {}      # weapon_id  -> WeaponDef
var enemies: Dictionary = {}      # enemy_id   -> EnemyDef
var loot_tables: Dictionary = {}  # table_id   -> LootTableDef
var room_types: Dictionary = {}   # room_id    -> RoomTypeDef

## 接口按 C 的形状先留好（roadmap-bac.md §1 约束 3）。B/A 阶段为空。
var attachments: Dictionary = {}  # attachment_id -> (A 阶段实现)
var recipes: Dictionary = {}      # recipe_id     -> (C 阶段实现)

# ─────────────── 诊断 ───────────────
var errors: Array[String] = []
var warnings: Array[String] = []

var max_stage: String = "B"


# ─────────────────────────── 加载 ───────────────────────────

## 加载全部数据表。返回 true 表示无错误。
func load_all(stage: String = "B") -> bool:
	max_stage = stage
	errors.clear()
	warnings.clear()
	items.clear()
	weapons.clear()
	enemies.clear()
	loot_tables.clear()
	room_types.clear()
	attachments.clear()
	recipes.clear()

	_load_items()
	_load_weapons()
	_load_enemies()
	_load_loot_tables()
	_load_room_types()

	_validate_cross_refs()
	_validate_map_constraints()

	return errors.is_empty()


func _stage_rank(s: String) -> int:
	var i := STAGE_ORDER.find(s)
	return i if i >= 0 else 0


func _allowed(stage_value: String) -> bool:
	return _stage_rank(stage_value) <= _stage_rank(max_stage)


func _read_json(table: String) -> Variant:
	var path := "%s/%s.json" % [DATA_DIR, table]
	if not FileAccess.file_exists(path):
		errors.append("[%s] 文件不存在: %s" % [table, path])
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		errors.append("[%s] 无法打开: %s" % [table, path])
		return null
	var text := f.get_as_text()
	f.close()

	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		errors.append("[%s] JSON 解析失败: 第 %d 行 %s" % [table, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _load_items() -> void:
	var data: Variant = _read_json("items")
	if data == null:
		return
	if not (data is Array):
		errors.append("[items] 顶层必须是数组")
		return
	var skipped := 0
	for row in data:
		if not (row is Dictionary):
			errors.append("[items] 存在非对象条目")
			continue
		var d := ItemDef.from_dict(row)
		if d.id.is_empty():
			errors.append("[items] 有条目缺少 id")
			continue
		if not _allowed(d.stage):
			skipped += 1
			continue
		if items.has(d.id):
			errors.append("[items] id 重复: %s" % d.id)
			continue
		if not ItemDef.CATEGORIES.has(d.category):
			errors.append("[items] %s: category='%s' 非法" % [d.id, d.category])
		items[d.id] = d
	if skipped > 0:
		warnings.append("[items] 按 stage<=%s 跳过了 %d 条（属于后续阶段）" % [max_stage, skipped])


func _load_weapons() -> void:
	var data: Variant = _read_json("weapons")
	if data == null:
		return
	if not (data is Array):
		errors.append("[weapons] 顶层必须是数组")
		return
	for row in data:
		if not (row is Dictionary):
			continue
		var w := WeaponDef.from_dict(row)
		if w.id.is_empty():
			errors.append("[weapons] 有条目缺少 id")
			continue
		if not _allowed(w.stage):
			continue
		if weapons.has(w.id):
			errors.append("[weapons] id 重复: %s" % w.id)
			continue
		weapons[w.id] = w


func _load_enemies() -> void:
	var data: Variant = _read_json("enemies")
	if data == null:
		return
	if not (data is Array):
		errors.append("[enemies] 顶层必须是数组")
		return
	for row in data:
		if not (row is Dictionary):
			continue
		var e := EnemyDef.from_dict(row)
		if e.id.is_empty():
			errors.append("[enemies] 有条目缺少 id")
			continue
		if not _allowed(e.stage):
			continue
		if enemies.has(e.id):
			errors.append("[enemies] id 重复: %s" % e.id)
			continue
		if not EnemyDef.ARCHETYPES.has(e.archetype):
			errors.append("[enemies] %s: archetype='%s' 非法" % [e.id, e.archetype])
		if e.is_ranged() and e.reaction_time < EnemyDef.MIN_RANGED_REACTION:
			errors.append("[enemies] %s: ranged 的 reaction_time=%.2f 低于下限 %.2f —— 会被玩家感知为不公平"
				% [e.id, e.reaction_time, EnemyDef.MIN_RANGED_REACTION])
		enemies[e.id] = e


func _load_loot_tables() -> void:
	var data: Variant = _read_json("loot_tables")
	if data == null:
		return
	if not (data is Array):
		errors.append("[loot_tables] 顶层必须是数组")
		return
	for row in data:
		if not (row is Dictionary):
			continue
		var t := LootTableDef.from_dict(row)
		if t.id.is_empty():
			errors.append("[loot_tables] 有条目缺少 id")
			continue
		if not _allowed(t.stage):
			continue
		if t.entries.is_empty():
			errors.append("[loot_tables] %s: entries 为空" % t.id)
		for e in t.entries:
			if e.min_count > e.max_count:
				errors.append("[loot_tables] %s/%s: min(%d) > max(%d)" % [t.id, e.item_id, e.min_count, e.max_count])
		loot_tables[t.id] = t


func _load_room_types() -> void:
	var data: Variant = _read_json("rooms")
	if data == null:
		return
	if not (data is Array):
		errors.append("[rooms] 顶层必须是数组")
		return
	for row in data:
		if not (row is Dictionary):
			continue
		var r := RoomTypeDef.from_dict(row)
		if r.id.is_empty():
			errors.append("[rooms] 有条目缺少 id")
			continue
		if not _allowed(r.stage):
			continue
		if not RoomTypeDef.TYPES.has(r.room_type):
			errors.append("[rooms] %s: room_type='%s' 非法" % [r.id, r.room_type])
		if r.min_count > r.max_count:
			errors.append("[rooms] %s: min_count(%d) > max_count(%d)" % [r.id, r.min_count, r.max_count])
		room_types[r.id] = r


# ─────────────────────────── 校验 ───────────────────────────

## 交叉引用校验 —— 这是 JSON 真源最需要的一层保护
func _validate_cross_refs() -> void:
	for wid in weapons:
		var w: WeaponDef = weapons[wid]
		if w.ammo_id.is_empty():
			errors.append("[weapons] %s: 缺少 ammo_id" % wid)
		elif not items.has(w.ammo_id):
			errors.append("[weapons] %s: ammo_id='%s' 在 items 中不存在" % [wid, w.ammo_id])
		elif (items[w.ammo_id] as ItemDef).category != "ammo":
			errors.append("[weapons] %s: ammo_id='%s' 的 category 不是 ammo" % [wid, w.ammo_id])

	for tid in loot_tables:
		var t: LootTableDef = loot_tables[tid]
		for e in t.entries:
			if not items.has(e.item_id):
				errors.append("[loot_tables] %s: item_id='%s' 在 items 中不存在" % [tid, e.item_id])

	for rid in room_types:
		var r: RoomTypeDef = room_types[rid]
		if not r.loot_table_id.is_empty() and not loot_tables.has(r.loot_table_id):
			errors.append("[rooms] %s: loot_table_id='%s' 在 loot_tables 中不存在" % [rid, r.loot_table_id])


## 地图生成硬约束（tech-stack.md §5.9 T-34）
func _validate_map_constraints() -> void:
	var spawn_count := 0
	var extract_count := 0
	for rid in room_types:
		var r: RoomTypeDef = room_types[rid]
		if r.is_spawn():
			spawn_count += 1
			if r.min_count != 1 or r.max_count != 1:
				errors.append("[rooms] %s: spawn 的 min/max_count 必须都为 1" % rid)
		elif r.is_extract():
			extract_count += 1
			if r.min_count < RoomTypeDef.MIN_EXTRACT_COUNT:
				errors.append("[rooms] %s: extract 的 min_count=%d 必须 >= %d（撤离点至少两个）"
					% [rid, r.min_count, RoomTypeDef.MIN_EXTRACT_COUNT])
			if r.min_graph_dist < RoomTypeDef.MIN_EXTRACT_GRAPH_DIST:
				errors.append("[rooms] %s: extract 的 min_graph_dist=%d 必须 >= %d（防止出生即撤离）"
					% [rid, r.min_graph_dist, RoomTypeDef.MIN_EXTRACT_GRAPH_DIST])

	if spawn_count != 1:
		errors.append("[rooms] 必须恰好有 1 个 spawn 房间类型，实为 %d" % spawn_count)
	if extract_count == 0:
		errors.append("[rooms] 没有 extract 房间类型")


# ─────────────────────────── 查询辅助 ───────────────────────────

func get_item(id: String) -> ItemDef:
	return items.get(id)


func get_weapon(id: String) -> WeaponDef:
	return weapons.get(id)


func get_enemy(id: String) -> EnemyDef:
	return enemies.get(id)


func get_loot_table(id: String) -> LootTableDef:
	return loot_tables.get(id)


func summary() -> String:
	return "items=%d weapons=%d enemies=%d loot=%d rooms=%d (stage<=%s)" % [
		items.size(), weapons.size(), enemies.size(),
		loot_tables.size(), room_types.size(), max_stage,
	]
