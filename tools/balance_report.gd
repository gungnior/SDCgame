extends SceneTree

## 平衡报告 —— 把「门 1：难度平衡」从「凭感觉」变成「可测量的数字」
##
## 运行：
##   godot --headless --path . --script res://tools/balance_report.gd
##
## ⚠️ 定位：**测量工具，不是仲裁者**。它只把 data/*.json 与 sim/ 公式算出来的
## 真实数值摆出来（武器 TTK / 敌人威胁 / 地图规模 / 战利品期望 / 品质分布），
## **不负责判定"好不好玩"** —— 那属于拥有者与平衡专家。
##
## ⛔ 只读：不写任何文件、不改任何数据。与 test/ 下的断言型测试互补：
##    测试回答"对不对"，本报告回答"是多少、偏不偏"。

const STAGE := "C"
const MAP_SAMPLES := 8          ## 每张图采样几个 seed（地图生成有随机性，取均值）
const BASE_SEED := 20261016


func _initialize() -> void:
	var reg := DataRegistry.new()
	if not reg.load_all(STAGE):
		print("❌ 数据加载失败（stage=%s）" % STAGE)
		for e in reg.errors:
			print("   ", e)
		quit(1)
		return

	_rule("平衡报告 · stage=%s · 数据源=data/*.json 公式=sim/" % STAGE)

	_report_weapons(reg)
	_report_ttk(reg)
	_report_enemy_threat(reg)
	_report_maps(reg)
	_report_loot(reg)
	_report_gear(reg)

	print("")
	print("── 怎么读这份报告 ─────────────────────────────────────────")
	print("· TTK = 期望「几发打死」；换算成秒要再除以 (rpm/60)。")
	print("· 「敌方 DPS」是设计值上限：实际要乘命中率、距离衰减、护甲。")
	print("· 战利品期望是**单件**均值，不含容器容量与 roll 次数。")
	print("· ⚠️ 全部为机制真值；倍率是否合适由平衡专家定夺。")
	quit(0)


# ─────────────────────────── 武器 ───────────────────────────

func _report_weapons(reg: DataRegistry) -> void:
	_rule("① 武器输出（DPS = 期望伤害/秒，已含精度·部位·距离衰减）")
	print("%-22s %6s %6s %8s %8s %8s" % ["武器", "伤害", "RPM", "DPS@8m", "DPS@20m", "DPS@40m"])
	print("─".repeat(66))
	for wid in reg.weapons:
		var w: WeaponDef = reg.weapons[wid]
		print("%-22s %6d %6d %8.1f %8.1f %8.1f" % [
			w.name, w.damage, w.rpm,
			DamageModel.expected_damage_per_second(w, 8.0),
			DamageModel.expected_damage_per_second(w, 20.0),
			DamageModel.expected_damage_per_second(w, 40.0),
		])


# ─────────────────────────── TTK ───────────────────────────

## 用「标准弹」打每种敌人，期望几发 / 几秒打死。
## 这是判断"枪够不够用"最直接的一栏。
func _report_ttk(reg: DataRegistry) -> void:
	_rule("② 玩家 TTK（标准弹，距离 12m；秒 = 发数 ÷ 射速）")
	var eids: Array = []
	for eid in reg.enemies:
		eids.append(eid)
	eids.sort()

	var head := "%-16s" % "武器"
	for eid in eids:
		var e: EnemyDef = reg.enemies[eid]
		head += "%14s" % e.name
	print(head)
	print("─".repeat((16 + 14 * eids.size())))

	for wid in reg.weapons:
		var w: WeaponDef = reg.weapons[wid]
		var ammo: ItemDef = reg.items.get(w.ammo_id)
		var line := "%-16s" % w.name
		for eid in eids:
			var e2: EnemyDef = reg.enemies[eid]
			var shots: float = DamageModel.shots_to_kill_vs_armor(w, ammo, e2, 12.0)
			if is_inf(shots):
				line += "%14s" % "∞"
				continue
			var sps: float = float(w.rpm) / 60.0
			var secs: float = shots / maxf(sps, 0.001)
			line += "%14s" % ("%.1f发/%.1fs" % [shots, secs])
		print(line)


# ─────────────────────── 敌人威胁 ───────────────────────

func _report_enemy_threat(reg: DataRegistry) -> void:
	_rule("③ 敌人威胁（设计值；实战还要乘命中率·距离衰减·玩家护甲）")
	print("%-16s %6s %6s %8s %8s %10s %14s" % [
		"敌人", "HP", "护甲", "移速", "视野m", "设计DPS", "武器"])
	print("─".repeat(74))
	for eid in reg.enemies:
		var e: EnemyDef = reg.enemies[eid]
		var design_dps: float = float(e.damage) / maxf(e.attack_cooldown, 0.01)
		var wname := "（近战）"
		if e.weapon_id != "" and reg.weapons.has(e.weapon_id):
			var w: WeaponDef = reg.weapons[e.weapon_id]
			wname = w.name
		print("%-16s %6d %6d %8.1f %8.1f %10.1f %14s" % [
			e.name, e.hp, e.armor, e.move_speed, e.sight_range_m, design_dps, wname])

	# 反过来算：敌人打死满血玩家（100 血 / 护甲吸收 0.55）要多久
	print("")
	print("※ 玩家 100 血、护甲吸收 55%（sim/vitals.gd ARMOR_ABSORB）")
	for eid in reg.enemies:
		var e3: EnemyDef = reg.enemies[eid]
		var dps: float = float(e3.damage) / maxf(e3.attack_cooldown, 0.01)
		if dps <= 0.0:
			continue
		print("   %-16s 打死无甲玩家需要 %.1f 秒（持续挨打的理想值）" % [
			e3.name, 100.0 / dps])


# ─────────────────────── 地图规模 ───────────────────────

## 真跑生成器采样 —— 房间数/容器数/敌人预算是"关卡节奏"的骨架。
func _report_maps(reg: DataRegistry) -> void:
	_rule("④ 地图规模（每张图采样 %d 个 seed 取均值，真跑 MapGenerator）" % MAP_SAMPLES)
	print("%-12s %8s %10s %10s %10s %10s" % [
		"地图", "尺寸", "房间数", "容器数", "敌人预算", "可走格"])
	print("─".repeat(64))
	for mid in reg.maps:
		var theme: MapThemeDef = reg.maps[mid]
		var rooms_sum := 0
		var cont_sum := 0
		var enemy_sum := 0
		var walk_sum := 0
		var ok_n := 0
		for i in range(MAP_SAMPLES):
			var gen := MapGenerator.new()
			# clone 防共享实例污染（s27 踩过的坑）
			if not gen.generate(BASE_SEED + i * 101, reg.room_types,
					theme.map_w, theme.map_h, theme.clone()):
				continue
			ok_n += 1
			rooms_sum += gen.graph.rooms.size()
			cont_sum += gen.total_container_count()
			enemy_sum += gen.total_enemy_budget()
			walk_sum += gen.grid.walkable_count()
		if ok_n == 0:
			print("%-12s %8s %10s" % [theme.name, "%dx%d" % [theme.map_w, theme.map_h], "生成失败"])
			continue
		print("%-12s %8s %10.1f %10.1f %10.1f %10.0f" % [
			theme.name, "%dx%d" % [theme.map_w, theme.map_h],
			float(rooms_sum) / float(ok_n), float(cont_sum) / float(ok_n),
			float(enemy_sum) / float(ok_n), float(walk_sum) / float(ok_n)])


# ─────────────────────── 战利品期望 ───────────────────────

## 每张战利品表的**单次 roll 期望价值**（加权平均）。用来判断"搜刮值不值"。
func _report_loot(reg: DataRegistry) -> void:
	_rule("⑤ 战利品期望（单次 roll 的价值期望；物品 value × 平均数量，按权重加权）")
	print("%-16s %10s %10s %s" % ["战利品表", "条目数", "期望价值", "最值钱的三项"])
	print("─".repeat(80))
	for tid in reg.loot_tables:
		var t: LootTableDef = reg.loot_tables[tid]
		var entries: Array = t.entries
		if entries.is_empty():
			continue
		var wsum := 0.0
		var esum := 0.0
		var top: Array = []
		for e in entries:
			var ed: LootTableDef.Entry = e as LootTableDef.Entry
			if ed == null:
				continue
			var w: float = float(ed.weight)
			var mn: float = float(ed.min_count)
			var mx: float = float(ed.max_count)
			var it: ItemDef = reg.items.get(ed.item_id)
			var val: float = 0.0 if it == null else float(it.value)
			wsum += w
			esum += w * val * (mn + mx) * 0.5
			top.append({"v": val * (mn + mx) * 0.5, "n": ed.item_id})
		top.sort_custom(func(a, b): return (a["v"] as float) > (b["v"] as float))
		var names: Array[String] = []
		for k in range(mini(3, top.size())):
			var td: Dictionary = top[k] as Dictionary
			var ti: ItemDef = reg.items.get(str(td.get("n", "")))
			names.append(("%s(%.0f)" % [ti.name if ti != null else str(td.get("n", "")),
					td.get("v", 0.0)]))
		var exp: float = 0.0 if wsum <= 0.0 else esum / wsum
		print("%-16s %10d %10.1f %s" % [
			t.name if t.name != "" else tid, entries.size(), exp, "、".join(names)])


# ─────────────────────── 品质分布 ───────────────────────

func _report_gear(reg: DataRegistry) -> void:
	_rule("⑥ 装备品质（掉落权重归一化 + 词条数/强度/死亡保留）")
	if reg.gear_rarities.is_empty():
		print("（本 stage 无品质数据）")
		return
	var wsum := 0.0
	for r in reg.gear_rarities:
		var rd: RarityDef = r as RarityDef
		wsum += float(rd.drop_weight)
	print("%-10s %8s %10s %10s %10s %12s" % [
		"品质", "词条数", "强度倍率", "评分系数", "死亡权重", "掉落占比"])
	print("─".repeat(64))
	for r2 in reg.gear_rarities:
		var r3: RarityDef = r2 as RarityDef
		var share: float = 0.0 if wsum <= 0.0 else float(r3.drop_weight) / wsum * 100.0
		print("%-10s %8d %10.2f %10.2f %10.2f %11.1f%%" % [
			r3.name, r3.affix_count, r3.power_mul, r3.score_mul,
			r3.death_weight, share])

	print("")
	print("词条池（%d 条）：" % reg.gear_affixes.size())
	for a in reg.gear_affixes:
		var ad: AffixDef = a as AffixDef
		var kind_cn := {"pct": "正加成", "pct_neg": "反向加成(越小越好)", "flat": "固定值"}
		var cats: Array[String] = []
		for c in ad.cats:
			cats.append(str(c))
		print("   %-12s %-10s %-20s %.2f ~ %.2f  适用:%s" % [
			ad.name, ad.field, str(kind_cn.get(ad.kind, ad.kind)),
			ad.min_value, ad.max_value, ",".join(cats)])


# ─────────────────────────── 工具 ───────────────────────────

func _rule(title: String) -> void:
	print("")
	print("═".repeat(74))
	print("  " + title)
	print("═".repeat(74))
