class_name RunModifiers
extends RefCounted

## 肉鸽「局内规则变体」运行时对象（2026-10-16 · 拥有者拍板转向肉鸽）。
##
## 与地图种子的分工：
##   seed      → 让**地图结构**每局不同（BSP 布局 / 房间 / 连通性，MapGenerator）
##   本类      → 让**规则**每局不同（敌人数 / 容器丰度 / ...）
## 两层叠加才是 roguelite 的"局局不重样"。
##
## 数据来源：data/run_modifiers.json（契约见 data/SCHEMA.md §11）。
## 分层：本类在 sim/，纯 RefCounted 可 headless 单测；roll 的时机与
## HUD 显示在 view 层（raid_scene._setup_sim）。
##
## ⚠️ 倍率数值是温和默认值（±25%~40%），**待平衡专家定夺**——
##    本类只提供"变体如何生效"的机制，不擅自定难度。

## ─────────────── 一个生效中的变体（数据快照，不持 DataRegistry）─────────────

class ModifierInstance:
	var id: String = ""
	var name: String = ""              ## 中文名（HUD 直接显示）
	var desc: String = ""
	var group: String = ""             ## 互斥组：同组一局最多出一个
	var enemy_density_mul: float = 1.0 ## 敌人密度倍率（连乘）
	var loot_rolls_mul: float = 1.0    ## 容器搜索次数倍率（连乘，近似价值倍率）


	static func from_dict(d: Dictionary) -> ModifierInstance:
		var m := ModifierInstance.new()
		m.id = str(d.get("id", ""))
		m.name = str(d.get("name", ""))
		m.desc = str(d.get("desc", ""))
		m.group = str(d.get("group", ""))
		m.enemy_density_mul = float(d.get("enemy_density_mul", 1.0))
		m.loot_rolls_mul = float(d.get("loot_rolls_mul", 1.0))
		return m


# ─────────────── 一局的变体集合 ───────────────

var active: Array[ModifierInstance] = []


## 按数据表 roll 出一组变体。
##   rng       必须注入（T-32：sim/ 禁止全局随机，保证同 seed 可复现）
##   defs      data/run_modifiers.json 的 modifiers 数组（Array[Dictionary]）
##   count_min/count_max  本局变体个数范围（会夹紧到不超过"可用组数"）
## 规则：按 group 去重抽（同组最多一个）；Phase 1 组内等权。
static func roll(rng: SimRng, defs: Array, count_min: int, count_max: int) -> RunModifiers:
	var out := RunModifiers.new()
	if rng == null or defs.is_empty():
		return out

	# 按 group 聚组，组内保持数据顺序（稳定可复现）
	var groups: Dictionary = {}          ## group -> Array[ModifierInstance]
	var order: Array[String] = []        ## group 首次出现序
	for raw in defs:
		if not (raw is Dictionary):
			continue
		var m := ModifierInstance.from_dict(raw)
		if m.id == "" or m.group == "":
			continue                       # 契约违规的条目跳过（契约由 s27 钉死）
		if not groups.has(m.group):
			groups[m.group] = []
			order.append(m.group)
		(groups[m.group] as Array).append(m)

	var lo: int = maxi(0, count_min)
	var hi: int = maxi(lo, count_max)
	hi = mini(hi, order.size())           # 组数不够就少抽，绝不重复组
	if hi <= 0:
		return out

	var want: int = rng.randi_range(lo, hi) if hi > lo else hi
	# 随机决定抽哪些组：洗牌组序后取前 want 个（Fisher-Yates，注入 rng）
	var pool: Array[String] = []
	for g in order:
		pool.append(str(g))
	for i in range(pool.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var picked: Array[String] = []
	for i in range(want):
		picked.append(pool[i])
	picked.sort()                          # 输出顺序稳定（与抽中顺序无关）

	for g in picked:
		var cands: Array = groups[g]
		var idx: int = rng.randi_range(0, cands.size() - 1)
		out.active.append(cands[idx])
	return out


# ─────────────── 查询（连乘；无变体 = 1.0，调用方零分支）─────────────

func enemy_density_mul() -> float:
	var v: float = 1.0
	for m in active:
		v *= m.enemy_density_mul
	return v


func loot_rolls_mul() -> float:
	var v: float = 1.0
	for m in active:
		v *= m.loot_rolls_mul
	return v


## HUD / 结果页用："敌潮 · 富饶容器"；空集合返回 ""
func summary() -> String:
	if active.is_empty():
		return ""
	var parts: Array[String] = []
	for m in active:
		parts.append(m.name)
	return " · ".join(parts)


func is_empty() -> bool:
	return active.is_empty()


func _to_string() -> String:
	return "RunModifiers(%d 个: %s)" % [active.size(), summary()]
