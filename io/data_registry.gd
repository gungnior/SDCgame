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
var attachments: Dictionary = {}  # attachment_id -> AttachmentDef
var recipes: Dictionary = {}      # recipe_id     -> RecipeDef
## C 阶段新增（2026-10-13）
var containers: Dictionary = {}   # container_id  -> ContainerDef（房间里可搜的容器）
var maps: Dictionary = {}         # map_id        -> MapThemeDef（森林/城区/军事基地）
## 任务（C 阶段）。框架在 sim/mission_system.gd，本表是纯内容（GameDesigner 填）。
var missions: Dictionary = {}     # mission_id    -> Dictionary（原始任务定义）
var run_modifiers: Array[Dictionary] = []  ## 肉鸽局内规则变体表（data/run_modifiers.json，见 SCHEMA §11）

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
	containers.clear()
	maps.clear()
	missions.clear()

	_load_items()
	_load_weapons()
	_load_enemies()
	_load_loot_tables()
	_load_room_types()
	_load_attachments()
	_load_recipes()
	_load_containers()
	_load_maps()
	_load_missions()
	_load_run_modifiers()

	_validate_cross_refs()
	_validate_map_constraints()

	return errors.is_empty()


func _stage_rank(s: String) -> int:
	var i := STAGE_ORDER.find(s)
	return i if i >= 0 else 0


func _allowed(stage_value: String) -> bool:
	return _stage_rank(stage_value) <= _stage_rank(max_stage)


func _read_json(table: String, optional: bool = false) -> Variant:
	var path := "%s/%s.json" % [DATA_DIR, table]
	if not FileAccess.file_exists(path):
		if not optional:
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


func _load_attachments() -> void:
	var data: Variant = _read_json("attachments", true)
	if data == null:
		return                       # A 阶段才有的表，B 阶段允许缺失
	if not (data is Array):
		errors.append("[attachments] 顶层必须是数组")
		return
	for row in data:
		if not (row is Dictionary):
			continue
		var a := AttachmentDef.from_dict(row)
		if a.id.is_empty():
			errors.append("[attachments] 有条目缺少 id")
			continue
		if not _allowed(a.stage):
			continue
		if not a.is_valid_slot():
			errors.append("[attachments] %s: slot='%s' 非法（合法：%s）" % [a.id, a.slot, str(AttachmentDef.SLOTS)])
		if attachments.has(a.id):
			errors.append("[attachments] id 重复: %s" % a.id)
			continue
		attachments[a.id] = a


func _load_recipes() -> void:
	var data: Variant = _read_json("recipes", true)
	if data == null:
		return                       # C 阶段才有的表，B/A 阶段允许缺失
	if not (data is Array):
		errors.append("[recipes] 顶层必须是数组")
		return
	for row in data:
		if not (row is Dictionary):
			continue
		var r := RecipeDef.from_dict(row)
		if r.id.is_empty():
			errors.append("[recipes] 有条目缺少 id")
			continue
		if not _allowed(r.stage):
			continue
		if not RecipeDef.STATIONS.has(r.station):
			errors.append("[recipes] %s: station='%s' 非法（合法：%s）" % [r.id, r.station, str(RecipeDef.STATIONS)])
		if recipes.has(r.id):
			errors.append("[recipes] id 重复: %s" % r.id)
			continue
		if r.output_item_id.is_empty():
			errors.append("[recipes] %s: 缺少 output_item_id" % r.id)
		recipes[r.id] = r


## 容器类型（C 阶段）。房间通过 room.containers 挂靠它。
func _load_containers() -> void:
	var data: Variant = _read_json("containers", true)
	if data == null:
		return
	if not (data is Array):
		errors.append("[containers] 顶层必须是数组")
		return
	for row in data:
		if not (row is Dictionary):
			continue
		var c := ContainerDef.from_dict(row)
		if c.id.is_empty():
			errors.append("[containers] 有条目缺少 id")
			continue
		if not _allowed(c.stage):
			continue
		if containers.has(c.id):
			errors.append("[containers] id 重复: %s" % c.id)
			continue
		containers[c.id] = c


## 地图主题（C 阶段）。森林/城区/军事基地……
func _load_maps() -> void:
	var data: Variant = _read_json("maps", true)
	if data == null:
		return
	if not (data is Array):
		errors.append("[maps] 顶层必须是数组")
		return
	for row in data:
		if not (row is Dictionary):
			continue
		var m := MapThemeDef.from_dict(row)
		if m.id.is_empty():
			errors.append("[maps] 有条目缺少 id")
			continue
		if not _allowed(m.stage):
			continue
		if maps.has(m.id):
			errors.append("[maps] id 重复: %s" % m.id)
			continue
		maps[m.id] = m


## 任务（C 阶段）。纯内容表，框架在 sim/mission_system.gd。
## 每条：id / name / stage / objectives[{type, need}] / reward{wallet, items[{item_id, count}]}
func _load_missions() -> void:
	var data: Variant = _read_json("missions", true)
	if data == null:
		return                       # 允许暂时为空表（框架就绪、内容待填）
	if not (data is Array):
		errors.append("[missions] 顶层必须是数组")
		return
	for row in data:
		if not (row is Dictionary):
			errors.append("[missions] 存在非对象条目")
			continue
		if not row.has("id") or str(row["id"]).is_empty():
			errors.append("[missions] 有条目缺少 id")
			continue
		var mid := str(row["id"])
		if not _allowed(str(row.get("stage", "C"))):
			continue
		if missions.has(mid):
			errors.append("[missions] id 重复: %s" % mid)
			continue
		# 目标结构校验
		var objs: Variant = row.get("objectives", [])
		if not (objs is Array) or objs.is_empty():
			errors.append("[missions] %s: objectives 必须是非空数组" % mid)
			continue
		for o in objs:
			if not (o is Dictionary) or not o.has("type") or not o.has("need"):
				errors.append("[missions] %s: 目标必须是 {type, need}" % mid)
				continue
			if int(o["need"]) <= 0:
				errors.append("[missions] %s: 目标 need 必须 > 0" % mid)
		missions[mid] = row


func get_mission(id: String) -> Dictionary:
	return missions.get(id, {})


## 肉鸽局内规则变体（data/run_modifiers.json，契约 SCHEMA §11）。
## 每条：id / name / group（互斥组）/ enemy_density_mul / loot_rolls_mul。
## 顶层是 {schema, modifiers:[...]} 对象而非裸数组（与 recipes 等一致）。
func _load_run_modifiers() -> void:
	var data: Variant = _read_json("run_modifiers", true)
	if data == null:
		return                       # 允许缺表：RunModifiers.roll 收到空 defs 安全返回
	if not (data is Dictionary):
		errors.append("[run_modifiers] 顶层必须是对象 {modifiers:[...]}")
		return
	var rows: Variant = data.get("modifiers", [])
	if not (rows is Array):
		errors.append("[run_modifiers] modifiers 必须是数组")
		return
	for row in rows:
		if not (row is Dictionary):
			errors.append("[run_modifiers] 存在非对象条目")
			continue
		if not row.has("id") or str(row["id"]).is_empty():
			errors.append("[run_modifiers] 有条目缺少 id")
			continue
		var mid := str(row["id"])
		if str(row.get("name", "")).is_empty():
			errors.append("[run_modifiers] %s: 缺少中文名 name" % mid)
		if str(row.get("group", "")).is_empty():
			errors.append("[run_modifiers] %s: 缺少互斥组 group" % mid)
		if float(row.get("enemy_density_mul", 1.0)) <= 0.0:
			errors.append("[run_modifiers] %s: enemy_density_mul 必须 > 0" % mid)
		if float(row.get("loot_rolls_mul", 1.0)) <= 0.0:
			errors.append("[run_modifiers] %s: loot_rolls_mul 必须 > 0" % mid)
		for prev in run_modifiers:
			if str(prev.get("id", "")) == mid:
				errors.append("[run_modifiers] id 重复: %s" % mid)
				continue
		run_modifiers.append(row)


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
		# ⚠️ 按【已加载的物品】过滤条目。
		#
		# 为什么必须过滤：数据填充到 A 阶段后，掉落表里会同时有 B 和 A 的物品，
		# 而 `load_all("B")` 只装载 B。若不过滤，表里就留着指向"未加载物品"的条目 ——
		# 运行期 LootRoller 虽然会 `continue` 跳过（不会崩），但：
		#   ① 抽到空条目 = 白白消耗一次抽样机会，掉落数量悄悄变少
		#   ② 测试里"抽到的物品必须都合法"这条断言必然失败
		# 过滤之后，**阶段开关就真的是纯数据驱动**：换一个 load_all 参数即可，
		# 表内容自动跟着变。
		# ⚠️ `entries` 是**类型化数组**，不能整体赋值一个普通 Array
		#    （会报 "Invalid assignment of property 'entries'"）。
		#    必须在原数组上原地增删。
		var kept: Array = []
		var dropped := 0
		for e in t.entries:
			if e.min_count > e.max_count:
				errors.append("[loot_tables] %s/%s: min(%d) > max(%d)" % [t.id, e.item_id, e.min_count, e.max_count])
			if items.has(e.item_id):
				kept.append(e)
			else:
				dropped += 1
		if dropped > 0:
			t.entries.clear()
			for e in kept:
				t.entries.append(e)
			warnings.append("[loot_tables] %s: 按 stage<=%s 跳过了 %d 个条目（物品未加载）"
				% [t.id, max_stage, dropped])
		if t.entries.is_empty():
			# 全被过滤掉了：这张表在当前阶段没有意义，不注册（避免空表被抽）
			warnings.append("[loot_tables] %s: 当前阶段没有可用条目，已跳过" % t.id)
			continue
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

	# 配方交叉引用：输入/输出都必须是已加载的物品
	for rid in recipes:
		var r: RecipeDef = recipes[rid]
		if not r.output_item_id.is_empty() and not items.has(r.output_item_id):
			errors.append("[recipes] %s: output_item_id='%s' 在 items 中不存在" % [rid, r.output_item_id])
		for g in r.inputs:
			if not items.has(g.item_id):
				errors.append("[recipes] %s: 输入 item_id='%s' 在 items 中不存在" % [rid, g.item_id])

	# ── 容器 → 掉落表（2026-10-13）──
	for cid in containers:
		var c: ContainerDef = containers[cid]
		if c.loot_table_id.is_empty():
			errors.append("[containers] %s: 缺少 loot_table_id" % cid)
		elif not loot_tables.has(c.loot_table_id):
			errors.append("[containers] %s: loot_table_id='%s' 在 loot_tables 中不存在" % [cid, c.loot_table_id])

	# ── 房间 → 容器 ──
	for rid in room_types:
		var rt: RoomTypeDef = room_types[rid]
		for cr in rt.containers:
			if not containers.has(cr.container_id):
				errors.append("[rooms] %s: container_id='%s' 在 containers 中不存在" % [rid, cr.container_id])

	# ── 地图主题 → 房间 / 敌人 ──
	for mid in maps:
		var m: MapThemeDef = maps[mid]
		for k in m.room_weights:
			if not room_types.has(str(k)):
				errors.append("[maps] %s: room_weights 里的 '%s' 在 rooms 中不存在" % [mid, k])
		for k in m.enemy_weights:
			if not enemies.has(str(k)):
				errors.append("[maps] %s: enemy_weights 里的 '%s' 在 enemies 中不存在" % [mid, k])

	# ── 任务奖励物品必须存在 ──
	for mid in missions:
		var r: Dictionary = missions[mid].get("reward", {})
		for it in r.get("items", []):
			var iid := str(it.get("item_id", ""))
			if not items.has(iid):
				errors.append("[missions] %s: 奖励物品 '%s' 在 items 中不存在" % [mid, iid])


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


func get_recipe(id: String) -> RecipeDef:
	return recipes.get(id)


func get_container(id: String) -> ContainerDef:
	return containers.get(id)


func get_map(id: String) -> MapThemeDef:
	return maps.get(id)


## 所有【普通房间主题】定义（room_type == "common"），按 id 稳定排序。
## MapGenerator 用它给普通房间按 weight 分配主题 —— 这就是"更多房间类型"。
func common_room_defs() -> Array[RoomTypeDef]:
	var out: Array[RoomTypeDef] = []
	for k in room_types:
		var r: RoomTypeDef = room_types[k]
		if r.room_type == "common":
			out.append(r)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func room_def_of_type(t: String) -> RoomTypeDef:
	for k in room_types:
		var r: RoomTypeDef = room_types[k]
		if r.room_type == t:
			return r
	return null


func summary() -> String:
	return "items=%d weapons=%d enemies=%d loot=%d rooms=%d containers=%d maps=%d recipes=%d (stage<=%s)" % [
		items.size(), weapons.size(), enemies.size(),
		loot_tables.size(), room_types.size(), containers.size(), maps.size(),
		recipes.size(), max_stage,
	]
