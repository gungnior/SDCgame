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
## 技术验证阶段：敌人数量上限。
## ⚠️ 2026-10-13 改为 **0（不再钳制）**：用户要求"敌人数量按地图大小来"。
##    现在总数由**地图主题的 enemy_density** 决定
##    （见 MapThemeDef.target_enemy_count / MapGenerator._apply_enemy_density）。
##    保留这个开关只为调试时能临时把敌人压到极少。
const MAX_TEST_ENEMIES := 0
## 技术验证阶段：简化枪械。
## 换枪备弹（3b）：备弹 = 背包里该弹种的携带量，夹在 [下限, 上限]。
## ⚠️ 数值属【平衡范畴】，交给平衡专家调；想"严格只给携带量"就把 BASE_RESERVE 设为 0。
const BASE_RESERVE := 60
const MAX_RESERVE := 300
## 自动瞄准每秒最多转多少度。太快会像甩枪（手感很假）。
const AUTO_AIM_TURN_DEG := 540.0
## 开局宽限期（秒）：这段时间内敌人不索敌。
## 实测：没有它时玩家 3.3 秒就死、0 击杀（安卓真机遥测）。
## 这不是"降低难度"，而是给玩家看懂地形与局势的时间 —— 搜打撤的前提是"能观察"。
const GRACE_SECONDS := 6.0

# ─── 颜色 ───

# ─── 模拟层 ───
var reg: DataRegistry
var gen: MapGenerator
## 本局地图主题（森林/城区/军事基地）。null = 旧行为（无主题）。
var theme: MapThemeDef = null
var flows: FlowFieldManager
## 玩家侧流场（自动寻路用）—— 与敌人那本预算**分开**，互不挤占
var player_flows: FlowFieldManager
## 敌人固定弹道（2026-10-13 用户需求：宽度 2 倍身位、锁定人物中心）
var lane_shots: LaneShotManager
## 玩家闪避（位移 1.5 倍身位 + 无敌帧）
var dodge: DodgeState
## 自动作战决策（寻路 / 搜刮 / 交战）
var autopilot: PlayerAutopilot
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
## 突袭 HUD（Labels / toast / 尸体提示）—— 实现在 view/raid_hud.gd
var raid_hud: RaidHud



var debug_mode := 0              ## 0 普通 1 流向场 2 房间图 3 声音范围

# ─── 手感 / 音频 / 触屏（specs/tech-stack.md §2 与 §7.3）───
var fx: FxPool = null            ## CPUParticles2D 池（T-03）
## 世界绘制器（view/raid_drawer.gd）。
## 场景不再自己 _draw —— 所有世界图形都在 drawer 里。
var drawer: RaidDrawer = null
## 键盘输入分派器（view/raid_input.gd）—— 加键位只改那里
var raid_input: RaidInput = null
## 模拟调度器（view/raid_sim_runner.gd）—— 玩家/敌人 tick、自动瞄准、开火
var sim_runner: RaidSimRunner = null
## 玩家动作（闪避 / 自动作战开关）—— 2026-10-13 从本文件分出的第一刀（见 AGENTS.md §4.5）
var player_actions: RaidPlayerActions = null
## 搜刮交互（打开背包 / 构建容器视图 / 应用拿取）—— 2026-10-13 第二刀
var loot_actions: RaidLootActions = null
var touch: TouchControls = null  ## 双摇杆 + 动作按钮
var flash_rect: ColorRect = null ## 受击闪白覆盖层
var inventory_panel: InventoryPanel = null   ## 背包/搜索面板（#3 / #6）
var map_panel: MapPanel = null               ## 战术地图（真机反馈 #2：看撤离点）
## 设置 / 暂停菜单（第三轮 #3：ESC / 齿轮 / 安卓返回键都开它）
var settings_menu: SettingsMenu = null
var result_overlay: ResultOverlay = null   ## 结算界面（含触屏重开按钮）
var _prev_shots: Dictionary = {} ## agent.id -> 已开火数（用于播放枪声）
var _step_accum := 0.0
## 听觉代价场缓存（共享给所有敌人）—— 见 HearingFieldCache 的说明
var _hearing_cache := HearingFieldCache.new()
## 锥形视野 + 锁定 + 自动瞄准（真机反馈 #4/#5）
var auto_aim := AutoAim.new()
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
var _map_tex: ImageTexture = null
var _map_tex_size := Vector2i.ZERO
## 地图烘焙器（view/raid_map_baker.gd）—— 纯图像生成，不画东西、不碰坐标空间，
## 所以能脱离场景树 headless 单测。它是本文件里边界最干净的一块。
var map_baker: RaidMapBaker = null

# ─── 渲染模式 ───
## 0 = 白模（技术验证阶段默认）；1 = 美术 tile
## ⚠️ 默认白模是刻意的：当前美术 tile 的墙/地板对比度太低，
##    玩家看不出哪能走（安卓真机反馈）。技术验证优先"能读懂"。
const RENDER_WHITEBOX := 0
const RENDER_ART := 1
var render_mode := RENDER_WHITEBOX


func _ready() -> void:
	# ⚠️ 场景切换必须重置阶段计时 —— 否则新场景第一次 mark() 会把
	#    在【上一个场景】待了多久 算成某一阶段的耗时
	#    （实测出现过 draw_end=4917ms 的幽灵卡顿，其实只是在藏身处待了 4.7 秒）
	if Tel != null:
		Tel.reset_phases()
	RenderingServer.set_default_clear_color(Color(0.06, 0.07, 0.09))
	_setup_sim()
	_setup_view()


# ═══════════════════════ 初始化 ═══════════════════════

## 随机朝向 —— 走 **_rng**，不走全局 RNG。
##
## ⚠️ 为什么要有这个函数：全局 `randf_range` 会被别的系统消耗，
##    最典型的是 `audio/sfx.gd` 给每个音效随机挑音高 ——
##    **消耗次数随音频状态浮动**。
##    后果实测过：同种子同参数两次截图，世界区域差 5.76%
##    （敌人朝向不同 -> AI 行为分化 -> 位置全乱）。
##    **可复现的 bug 报告**是本项目的硬需求，所以游戏逻辑一律走 _rng。
func _rng_dir() -> Vector2:
	return Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()


# ─────────────── 地图主题 / 敌人池 / 容器（2026-10-13）───────────────

## 抽一个地图主题。Game.map_id 指定了就用它（藏身处选图），否则按种子随机。
func _pick_map_theme() -> MapThemeDef:
	if reg == null or reg.maps.is_empty():
		return null
	if Game != null:
		var want := str(Game.map_id)
		if want != "" and reg.maps.has(want):
			return reg.get_map(want)
	var ids: Array = reg.maps.keys()
	ids.sort()
	return reg.get_map(str(ids[_rng.randi_range(0, ids.size() - 1)]))


## 本局可用的敌人类型池。有地图主题时**只取该主题敌池里的**；
## 否则退回全部敌人（旧行为）。
func _enemy_pool() -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	if theme != null and not theme.enemy_weights.is_empty():
		for k in theme.enemy_weights:
			var d: EnemyDef = reg.get_enemy(str(k))
			if d != null:
				out.append(d)
		out.sort_custom(func(a, b): return a.id < b.id)
		if not out.is_empty():
			return out
	for id in reg.enemies:
		out.append(reg.enemies[id])
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


## 抽一个敌人类型：有主题时按 theme.enemy_weights 权重抽，
## 否则按 seq 轮转（旧行为，保证种类覆盖均匀）。
func _pick_enemy(kinds: Array[EnemyDef], seq: int) -> EnemyDef:
	if kinds.is_empty():
		return null
	if theme == null or theme.enemy_weights.is_empty():
		return kinds[seq % kinds.size()]
	var keys: Array = theme.enemy_weights.keys()
	keys.sort()
	var ws: Array = []
	var usable: Array = []
	for k in keys:
		var d: EnemyDef = reg.get_enemy(str(k))
		var w := int(theme.enemy_weights[k])
		if d != null and w > 0:
			usable.append(str(k))
			ws.append(w)
	if usable.is_empty():
		return kinds[seq % kinds.size()]
	var idx := _rng.weighted_index(ws)
	if idx < 0 or idx >= usable.size():
		return kinds[seq % kinds.size()]
	var picked: EnemyDef = reg.get_enemy(str(usable[idx]))
	return picked if picked != null else kinds[seq % kinds.size()]


## 敌人在房间内的刷点。
##
## ⚠️ 不能都刷在 `r.center` —— 同一个房间有多个敌人时它们会**完全重叠**：
##   渲染上是同一个圆、移动/朝向逐帧一致，玩家看到的就是"只有一个敌人"。
##   这里用注入的 _rng 在房间矩形里挑一个**可走格**（确定性，满足 T-32）。
func _enemy_spawn_point(r: Room) -> Vector2:
	var w := maxi(1, r.rect.size.x)
	var h := maxi(1, r.rect.size.y)
	for _i in 12:
		var c := Vector2i(
			r.rect.position.x + _rng.randi_range(0, w - 1),
			r.rect.position.y + _rng.randi_range(0, h - 1))
		if gen.grid.is_walkable(c):
			return Ballistics.cell_center(c)
	return Ballistics.cell_center(r.center)   # 兜底（房间全被占满的极端情况）


## 按房间的容器布点生成**可搜索容器**。
## ⚠️ 物品抽取在这里做 —— MapGenerator 只负责布点（sim/mapgen 拿不到 loot_tables，
##    保持分层干净）。抽取次数由容器容量决定：大箱子装得更多、更值钱。
func _spawn_containers() -> void:
	if raid == null or gen == null or reg == null:
		return
	for r in gen.graph.rooms:
		for cs in r.container_spawns:
			var def: ContainerDef = reg.get_container(str(cs.get("container_id", "")))
			if def == null:
				continue
			var table: LootTableDef = reg.get_loot_table(def.loot_table_id)
			if table == null:
				continue
			var rolls := clampi(def.capacity / 4, 1, 5)
			# 肉鸽变体：容器丰度倍率（Phase 1 用"多 roll 几次"近似价值倍率，
			# 不碰 LootRoller 内部逻辑；上限放到 8，否则 +40% 会被 clamp 砍掉）。
			if raid != null and raid.run_mods != null and not raid.run_mods.is_empty():
				rolls = clampi(int(round(float(rolls) * raid.run_mods.loot_rolls_mul())), 1, 8)
			var drops := LootRoller.roll_for_room(table, _rng, r.depth, rolls)
			if drops.is_empty():
				continue
			raid.add_container(def, Ballistics.cell_center(cs.get("pos", r.center)), drops)


# ─────────────── 弹药 / 护甲 / 损耗（2026-10-13）───────────────

## 玩家当前装的弹种（由武器的 ammo_id 决定）。
## 弹种分标准 / 穿甲 / 肉伤，对"有甲 / 无甲"目标差别很大。
func _player_ammo() -> ItemDef:
	if reg == null or player_weapon == null or player_weapon.def == null:
		return null
	return reg.get_item(player_weapon.def.ammo_id)


## 武器磨损对伤害的折损（全新 1.0 -> 完全损坏 0.6）
func _weapon_wear_factor() -> float:
	if raid == null or raid.equipment == null:
		return 1.0
	return raid.equipment.weapon_damage_factor()


## 身上装备提供的护甲值（没穿 = 0）。**这是玩家护甲的唯一来源。**
##
## ⚠️ 真机反馈 #3："下图后自动有了护甲值，哪怕身上没有护甲"。
##    根因是 `_setup_sim` 里写死了 `vitals.reset(100, 40)` ——
##    40 点护甲跟装备毫无关系，白送。现在改成从配装里取。
func _player_armor() -> int:
	if raid == null or raid.equipment == null:
		return 0
	return raid.equipment.worn_armor()


## 玩家受击结算（**唯一的一处护甲逻辑**）。返回【实际进血量的伤害】。
##
## ⚠️ 这里曾经有两套护甲**同时**生效：
##   ① `Vitals.armor` 池按 55% 吸收
##   ② 本函数（装备护甲 + 弹型）
##   叠起来等于"护甲吸了两遍"，而且 `_setup_sim` 白送 40 点护甲。
##   现在只有一条路径：
##     · 护甲池 = 身上装备的护甲值（`_player_armor()`，没穿就是 0）
##     · 弹型决定"这套甲能挡下多少"：`DamageModel.armor_multiplier(pen, armor)`
##       穿甲弹 -> 穿透比例接近 1 -> 甲基本挡不住；肉伤弹 -> 甲挡得多
##     · 吸收到的伤害按比例磨损护甲/头盔；打坏 -> 护甲池清零 + 提示维修
func _resolve_player_hit(raw: int) -> int:
	if vitals == null:
		return 0
	if raw <= 0:
		return 0
	var eq: Equipment = raid.equipment if raid != null else null
	if eq == null:
		return vitals.take_damage(raw)

	# 敌人目前统一按"标准弹"结算（pen=3）—— 与敌人的数值体系对称
	var std: ItemDef = reg.get_item("ammo_rifle") if reg != null else null
	var pen := float(std.pen) if std != null else 3.0
	var through := DamageModel.armor_multiplier(pen, float(vitals.armor))
	var before := vitals.armor
	var applied := vitals.take_hit(raw, through)
	var absorbed := before - vitals.armor
	if absorbed > 0:
		# 每吸收 6 点伤害 = 磨损 1 点耐久（护甲、头盔各摊一半）
		var wear := maxi(1, int(round(float(absorbed) / 6.0)))
		var broke := false
		if not eq.is_empty("armor"):
			broke = eq.wear_slot("armor", wear) or broke
		if not eq.is_empty("helmet"):
			broke = eq.wear_slot("helmet", maxi(1, wear / 2)) or broke
		if broke:
			if Sfx != null:
				Sfx.play("ui_deny")
			_toast("护甲已损坏 —— 回藏身处维修")
			vitals.armor = 0        # 打坏的甲不再提供任何减伤
	return applied


func _setup_sim() -> void:
	reg = DataRegistry.new()
	if not reg.load_all("C"):
		push_error("数据加载失败：%s" % str(reg.errors))
		return

	# ⚠️ 每局换种子。
	#    早先这里写死 20261012，结果真机上"每局地图和出生点完全一样" ——
	#    玩家反馈"并没有随机出生"。同种子可复现是开发期的需要，
	#    正式游玩必须每局不同（T-32 的种子纪律：可复现 ≠ 写死）。
	if Game != null:
		Game.apply_accessibility()
		# ⚠️⚠️ 先把 Game 的**跨场景注册表（C 档）**接过来，**再生成地图**。
		#    早先顺序是反的：先用本地 A 档的 room_types 生成地图，
		#    之后才 `reg = Game.reg` 换成 C 档 ——
		#    结果 C 档的房间类型 / 容器 / 地图主题**永远进不来**。
		Game.ensure_loaded()
		if Game.reg != null:
			reg = Game.reg
	if _raid_seed <= 0:
		_raid_seed = Game.raid_seed if (Game != null and Game.raid_seed > 0) else (randi() & 0x7FFFFFFF)
	_rng = SimRng.new(_raid_seed)

	# ⭐ 地图主题（森林 / 城区 / 军事基地）：决定地图多大、房间配额、
	#    敌人种类与密度。theme == null 时退化为旧的固定 27×27 单一主题。
	theme = _pick_map_theme()
	# ⭐ 防御性拷贝：reg.get_map() 返回的是 **registry 里的共享实例**，
	#    肉鸽变体要乘 enemy_density，直接改会污染全局（后续每局累积倍率）。
	if theme != null:
		theme = theme.clone()
	# ── 肉鸽：roll 本局规则变体（2026-10-16 拥有者拍板转向）──
	#    与 seed 的分工：seed 管**地图结构**每局不同，本类管**规则**每局不同。
	#    用 _rng（_raid_seed 驱动）保证同 seed 整局可复现；mapgen 内部另持
	#    自己的 rng，这次消耗不影响地图输出，只影响本局容器/敌人抽取序列。
	var run_mods := RunModifiers.roll(_rng, reg.run_modifiers, 1, 2)
	if theme != null and not run_mods.is_empty():
		theme.enemy_density *= run_mods.enemy_density_mul()
	gen = MapGenerator.new()
	var mw: int = theme.map_w if theme != null else 27
	var mh: int = theme.map_h if theme != null else 27
	if not gen.generate(_raid_seed, reg.room_types, mw, mh, theme):
		push_error("地图生成失败：%s" % str(gen.errors))
		return

	flows = FlowFieldManager.new()
	flows.setup(gen.grid)

	# ── 玩家自动作战相关（2026-10-13 用户需求）──
	# 玩家侧流场单独一本：与敌人共用会让两边互相挤占每帧构建预算
	# （敌人那边被降级成「朝目标直走」就会顶墙）。
	player_flows = FlowFieldManager.new()
	player_flows.setup(gen.grid)
	lane_shots = LaneShotManager.new()
	dodge = DodgeState.new()
	autopilot = PlayerAutopilot.new()

	# 藏身处：用 Game（autoload）里的**跨场景持久**实例
	# 真机反馈 #7：死亡后要能真正回藏身处，所以它必须活在场景之外
	if Game != null:
		Game.ensure_loaded()
		hideout = Game.hideout
	if hideout == null:
		hideout = Hideout.new(reg.items, 3000, reg.weapons, reg.attachments)
		hideout.wallet += 5000

	# ⚠️ 把藏身处的升级效果传进本局 —— 否则升级花了钱但毫无作用。
	#    （早先 raid_modifiers() 从未被调用。）
	var mods := hideout.raid_modifiers()

	# ── 3a：装备的背包决定本局容量/负重（真机缺口补全）──
	#    raid_modifiers() 只给了升级带来的负重上限；背包 ItemDef 自己的
	#    carry_slots / carry_weight 必须在这里接进来，否则"换个背包"毫无效果。
	#    默认（没装备背包）回退到 raid_modifiers 的 12 格 / 升级上限，不回归。
	var bp_id := hideout.loadout.id_in("backpack")
	if bp_id != "":
		var bp: ItemDef = reg.get_item(bp_id)
		if bp != null:
			if bp.carry_slots > 0:
				mods["carry_slots"] = bp.carry_slots
			if bp.carry_weight > 0.0:
				mods["carry_weight_limit"] = maxf(float(mods.get("carry_weight_limit", 0.0)), bp.carry_weight)

	raid = RaidSession.new(reg.items, _rng, hideout.stash, mods, reg.missions)
	raid.load_map(gen)
	# 肉鸽：把本局变体挂进 session（HUD / 容器抽取的唯一真源）
	raid.run_mods = run_mods
	raid.start(240.0)

	# ⭐ 装备系统：把藏身处的**配装**接进本局。
	#    这一步让"死亡掉装备"真正有承担物：
	#      · 局内捡到的枪装上身 -> 撤离后就是你的新配装（同一个对象，无需搬运）
	#      · 死了 -> RaidSession._on_death 连身上这套一起清掉
	#    在此之前 Equipment 只有单测、没人调用（= 一个不可见的大号衣柜）。
	raid.equipment = hideout.loadout

	# ⭐ 可搜索容器（2026-10-13）：按房间类型挂靠生成。
	#    军械库里有枪架、医疗室里有药柜 —— 全部由数据驱动，不是硬编码。
	#    必须在 raid.setup 之后、面板/地图烘焙之前调用。
	_spawn_containers()
	print("[容器] %d 个可搜索容器（按房间类型挂靠生成）" % raid.containers.size())

	vitals = Vitals.new()
	# 护甲来自【身上装备】：没穿护甲就是 0（真机反馈 #3）。
	vitals.reset(100, _player_armor())
	medical = MedicalSystem.new()
	# 藏身处「战地急救」升级：治疗更快
	medical.set_speed_multiplier(raid.heal_speed)

	# ── 玩家武器：**优先用藏身处配装的枪** ──
	# 技术验证阶段：不测枪械系统
	# 真机反馈 #2："现阶段不测试具体枪械系统，玩家开火不需要挂载后坐力之类的"。
	# 所以去掉散布与后坐力，备弹给足；装弹/弹匣仍然保留（那是搜打撤核心循环的一部分）。
	player_weapon = _make_player_weapon()

	var spawn := gen.spawn_room()
	player_pos = Ballistics.cell_center(spawn.center)
	raid.hp = vitals.hp

	# ── 起始配装 ──
	# ⭐ 真机反馈 #2：优先搬【藏身处选的携带背包】——
	#    这才是"自己决定带什么进局"的落点。
	#    携带背包是空的才退回一份最小起始物资，保证"不复配也能开一局"。
	#
	# ⚠️ 真机反馈 #3（上一轮）："按治疗按钮没反应"，根因是 `_setup_sim`
	#    从来没给玩家发过任何物品、背包是空的（0/12 槽），所以找不到任何药。
	var carried := 0
	if hideout != null and hideout.pack != null:
		carried = hideout.drain_pack_into(raid.carry)
	if carried > 0:
		print("[配装] 从携带背包搬入 %d 种物资" % carried)
	else:
		raid.carry.add("medical_bandage", 2)
		raid.carry.add("medical_kit", 1)
		raid.carry.add("ammo_rifle", 90)
		print("[配装] 携带背包是空的 -> 发一份最小起始物资（去藏身处「携带」自己配）")
	print("[配装] %s" % raid.carry.summary())

	# 敌人
	squad = Squad.new(1)
	var scav := reg.get_enemy("enemy_scav")
	var infected := reg.get_enemy("enemy_infected")
	var eid := 0
	# ⚠️ **从数据里取全部敌人类型**，不要硬编码 ——
	#    数据填充到 A 阶段后（2 -> 4 种），硬编码会让新敌人永远不出现。
	#    `reg.enemies` 已经是按 stage 过滤过的（load_all("A") 只装 B+A）。
	var kinds: Array[EnemyDef] = _enemy_pool()
	if kinds.is_empty():
		printerr("[敌方] 数据里一个敌人都没有，检查 data/enemies.json")
		return
	# ── 技术验证模式：敌人数量被钳制（真机反馈 #2）──
	# 现在要的是"验证技术"，不是"打怪"。每种敌人各放 1 个、总数 <= MAX_TEST_ENEMIES。
	if MAX_TEST_ENEMIES > 0:
		for r in gen.graph.rooms:
			if agents.size() >= MAX_TEST_ENEMIES:
				break
			if r.room_type == "spawn":
				continue
			var d: EnemyDef = kinds[eid % kinds.size()]
			var a := EnemyAgent.new(eid, d, _enemy_spawn_point(r))
			if d.is_ranged():
				a.equip(reg.get_weapon("weapon_pistol"), 60)
			# ⚠️ 用 **_rng**（由 _raid_seed 播种）而**不是全局 randf_range**。
			#    全局 RNG 会被别的系统消耗 —— 最典型的是 audio/sfx.gd 给每个音效
			#    随机挑音高，**消耗次数随音频状态浮动**。
			#    后果实测过：同种子同参数的两次截图，世界区域差 5.76%
			#    （敌人朝向不同 -> AI 行为分化 -> 位置全乱）。
			#    **可复现的 bug 报告**是本项目的硬需求，所以游戏逻辑一律走 _rng。
			a.facing = _rng_dir()
			squad.add_member(a)
			agents.append(a)
			eid += 1
	else:
		for r in gen.graph.rooms:
			if r.room_type == "spawn":
				continue
			for i in r.enemy_budget:
				var d2: EnemyDef = _pick_enemy(kinds, eid)
				var a2 := EnemyAgent.new(eid, d2, _enemy_spawn_point(r))
				if d2.is_ranged():
					a2.equip(reg.get_weapon("weapon_pistol"), 60)
				a2.facing = _rng_dir()
				squad.add_member(a2)
				agents.append(a2)
				eid += 1
	print("[地图] %s" % gen.summary())
	print("[敌方] %d 名（类型池 %d：%s）%s" % [agents.size(), kinds.size(),
		", ".join(kinds.map(func(k): return k.name)),
		"（技术验证模式，上限 %d）" % MAX_TEST_ENEMIES if MAX_TEST_ENEMIES > 0 else ""])


## 按藏身处**配装**造出玩家手里的枪。
##
## ⚠️⚠️ 这里是装备系统"真的生效"的唯一地方。
##    只把枪放进装备槽而不影响战斗，那套系统就只是个大号衣柜 ——
##    "配装"的全部意义在于进局后打的是你选的那把枪（含改的配件）。
##
## 装备槽是空的（或数据缺失）时**回退到默认步枪 + 自动装配件**：
##   · 保证"不复配装也能直接开一局"（技术验证期的容错）
##   · 迁移过来的老存档（v3 及以前没有 loadout）也走这条路，不会一进局就空手
func _make_player_weapon() -> WeaponState:
	var lo: WeaponModding.Loadout = null
	var eq: Equipment = raid.equipment if raid != null else null
	var from_loadout := false
	if eq != null:
		lo = eq.build_loadout(WeaponModding.SLOTS_C)
		from_loadout = lo != null
	if lo == null:
		var fallback := reg.get_weapon("weapon_rifle")
		if fallback == null:
			push_error("[装填] 连回退步枪都取不到（weapon_rifle 缺失）")
			return null
		lo = WeaponModding.create_loadout(fallback, WeaponModding.SLOTS_A)
		WeaponModding.auto_fit(lo, reg.attachments)
		print("[装填] 装备槽是空的 -> 回退默认步枪（去藏身处「配装」换上自己的枪）")
	var wdef := lo.to_weapon_def()
	# ── 3b：备弹按【武器弹种】取（真机缺口补全）──
	#    早先无论换什么枪都给固定 180/9999，于是"手枪在手、背包只有步枪弹"
	#    也能随便打。现在：备弹 = 背包里该弹种(ammo_id)的携带量，
	#    下限 BASE_RESERVE（保证起步有几匣）、上限 MAX_RESERVE（防刷爆）。
	#    ⚠️ 数值属【平衡范畴】，常量交给平衡专家调；想要"严格只给携带量"把 BASE 设 0。
	var carried := 0
	if raid != null and raid.carry != null:
		carried = raid.carry.count_of(wdef.ammo_id)
	var reserve: int = clampi(carried, BASE_RESERVE, MAX_RESERVE)
	var st := WeaponState.new(wdef, reserve)
	print("[装填] %s%s  视野锥 %.0f°" % [
		lo.summary(),
		"（藏身处配装）" if from_loadout else "",
		wdef.aim_cone_deg])
	return st


## 换枪后重建手里的枪。
## ⚠️ 不重建的话，"捡到一把好枪装身上"只是背包里的名字变了，打起来还是旧枪 ——
##    这正是"装备系统没打通"的典型症状。
## 简化：新枪按满弹匣 + 备弹给足（不做"换枪要重新装弹"的中间态）。
func _rebuild_player_weapon() -> void:
	var before := player_weapon.def.id if player_weapon != null else ""
	var st := _make_player_weapon()
	if st == null:
		return
	player_weapon = st
	if st.def.id != before:
		_toast("切换到 %s" % st.def.name)


# ═══════════════════ 装备：局内穿脱 ═══════════════════
#
# 面板只发信号（它不认识战斗），穿脱判定在 RaidSession / Equipment 里（有单测），
# 这里只做三件事：调 API、报结果、换枪时重建手里的枪。

func _on_equip_requested(item_id: String) -> void:
	var err := raid.equip_from_carry(item_id)
	if err != "":
		if Sfx != null:
			Sfx.play("ui_deny")
		_toast(err)
	else:
		if Sfx != null:
			Sfx.play("ui_confirm")
		_toast("已装备 %s" % _item_name(item_id))
		# 装上的正好是武器 -> 手里的枪必须换成它
		if raid.equipment != null and raid.equipment.id_in("weapon") == item_id:
			_rebuild_player_weapon()
	if inventory_panel != null:
		inventory_panel.refresh()


func _on_unequip_requested(slot: String) -> void:
	var err := raid.unequip_from_carry(slot)
	if err != "":
		if Sfx != null:
			Sfx.play("ui_deny")
		_toast(err)
	else:
		if Sfx != null:
			Sfx.play("ui_confirm")
		_toast("已脱下")
		# 武器槽被清空 -> 退回默认步枪（不能手里没枪）
		if slot == "weapon":
			_rebuild_player_weapon()
	if inventory_panel != null:
		inventory_panel.refresh()


func _item_name(id: String) -> String:
	var d: ItemDef = reg.get_item(id)
	return str(d.name) if d != null else id


func _setup_view() -> void:
	# 触屏设备：决定提示文案与 HUD 字号
	_is_touch = DisplayServer.is_touchscreen_available() \
		or OS.has_feature("mobile") or OS.get_name() == "Android"

	camera = Camera2D.new()
	camera.zoom = Vector2(1.0, 1.0)
	add_child(camera)
	camera.make_current()

	# ── HUD（Labels / toast / 尸体提示）全部在 view/raid_hud.gd ──
	# 抽出去的原因：_update_hud 是「纯追加型」函数，每加一个统计量都要改，
	# 是 raid_scene.gd 上最大的冲突面之一。
	raid_hud = RaidHud.new()
	raid_hud.scene = self
	raid_hud.setup(_is_touch)
	add_child(raid_hud)

	# 地图烘焙交给 RaidMapBaker（纯图像生成，可 headless 单测）
	if map_baker == null:
		map_baker = RaidMapBaker.new()
	map_baker.load_tiles()
	_build_map_texture()

	# ── 世界绘制交给 RaidDrawer（view/raid_drawer.gd）──
	# `_draw()` 是纯追加型函数（每加一个视觉元素都要塞一段），是场景里最大的一块冲突面。
	#
	# ⚠️ **必须加在 fx（粒子池）之前** ——
	#    子节点画在父节点之上、子节点之间按加入顺序。
	#    原先是「场景自己的 _draw 先画，fx 后画」，所以要维持
	#    「世界在下、粒子在上」的观感，drawer 就得比 fx 先加进来。
	drawer = RaidDrawer.new()
	drawer.scene = self
	add_child(drawer)

	# 键盘分派器（加键位改 view/raid_input.gd，不碰这个文件）
	raid_input = RaidInput.new()
	raid_input.scene = self

	# 模拟调度器（玩家/敌人 tick、自动瞄准、开火）
	# 抽出去是为了把「AI / 战斗手感」与「场景搭建 / UI 胶水」分到不同文件，
	# 两个人可以同时开工。四个函数调用图闭合，所以一起搬。
	sim_runner = RaidSimRunner.new()
	sim_runner.scene = self

	# 玩家动作模块（纯搬运：闪避 / 自动作战开关）
	player_actions = RaidPlayerActions.new()
	player_actions.scene = self
	loot_actions = RaidLootActions.new()
	loot_actions.scene = self

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
	# ⚠️ 真机反馈 #7：点回藏身处必须**真正切到藏身处场景**，
	#    早先错误地接到了 _restart（等于原地重开一局），玩家根本回不去。
	result_overlay.hideout_requested.connect(_go_hideout)
	var ro_layer := CanvasLayer.new()
	ro_layer.layer = 40
	ro_layer.add_child(result_overlay)
	add_child(ro_layer)

	# ── 背包 / 搜索面板（#3 / #6）──
	inventory_panel = InventoryPanel.new()
	inventory_panel.action.connect(loot_actions.on_panel_action)
	# 装备系统：面板只发"我想穿/脱"，判定与重建武器都在场景这边
	inventory_panel.equip_requested.connect(_on_equip_requested)
	inventory_panel.unequip_requested.connect(_on_unequip_requested)
	inventory_panel.closed.connect(func():
		if touch != null:
			touch.set_controls_visible(true))
	var inv_layer := CanvasLayer.new()
	inv_layer.layer = 45
	inv_layer.add_child(inventory_panel)
	add_child(inv_layer)
	touch.bag_pressed.connect(loot_actions.open_bag)
	# 闪避（用户需求：位移 1.5 倍人物身位）。PC 用 Shift。
	touch.dodge_pressed.connect(player_actions.try_dodge)
	touch.menu_pressed.connect(_open_settings)
	touch.map_pressed.connect(_toggle_map)              # 地图（真机反馈 #2）

	# ── 战术地图覆盖层（真机反馈 #2）──
	# 层级放在背包(45)之上、设置菜单(60)之下：
	# 地图是"看一眼就走"的轻覆盖层，设置菜单永远是最后一道。
	map_panel = MapPanel.new()
	map_panel.closed.connect(func():
		if touch != null:
			touch.set_controls_visible(true))
	var map_layer := CanvasLayer.new()
	map_layer.layer = 46
	map_layer.add_child(map_panel)
	add_child(map_layer)

	# ── 设置 / 暂停菜单（第三轮 #3）──
	# PC：ESC 开关；安卓：左上角齿轮 + 系统返回键（都走 ui_cancel）
	settings_menu = SettingsMenu.new()
	settings_menu.bind_scene(self, true)
	settings_menu.went_hideout.connect(_go_hideout)
	var set_layer := CanvasLayer.new()
	set_layer.layer = 60          # 盖在背包面板之上
	set_layer.add_child(settings_menu)
	add_child(set_layer)


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

	# ── 逻辑冻结（设置菜单 / 战术地图打开时）──
	# 不用 get_tree().paused：它同时门控输入，导致菜单看得见点不动（PC 实测卡死）。
	# 这里只跳过游戏逻辑；HUD / 绘制 / 输入 / 相机全部照常。
	#
	# ⚠️ 地图也冻结逻辑：地图是铺满全屏的覆盖层，玩家此刻看不到战场 ——
	#    不冻结就是"低头看地图被背后打死"，那不叫硬核，叫罚站。
	var map_open: bool = map_panel != null and map_panel.is_open()
	var frozen := game_paused or (Game != null and Game.paused) or map_open
	if frozen:
		_firing = false
		_move_input = Vector2.ZERO
	elif not raid.is_over():
		Tel.mark("player")
		sim_runner.tick_player(delta)
		Tel.mark("enemies")
		sim_runner.tick_enemies(delta)
		Tel.mark("tracers")
		_tick_tracers(delta)
		Tel.mark("raid")
		raid.tick(delta, player_pos)
		raid.hp = vitals.hp
		if vitals.dead:
			raid.take_damage(9999)
	elif raid.is_over():
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
	# 世界图形由 RaidDrawer 画（原先是场景自己的 _draw）
	if drawer != null:
		drawer.queue_redraw()


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
	# 任务奖励的钱并入藏身处钱包（物品已在 RaidSession 里直接进了 stash）。
	var mw := int(rep.get("mission_wallet", 0))
	if mw > 0:
		hideout.wallet += mw
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
	# 存档：累计统计 + 自动落盘
	# ⚠️ 必须在 settle() 【之后】调用 —— 撤离时战利品是在 settle 里
	#    写进 hideout.stash 的，早于它存档会把这一局的收获漏掉。
	if Game != null:
		Game.record_raid_result(win, raid.enemies_killed)
		lines.append(Game.save_status)
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


func _weapon_kind(w: WeaponDef) -> String:
	var id := w.id
	if id.contains("shotgun") or id.contains("shell"):
		return "shotgun"
	if id.contains("pistol"):
		return "pistol"
	return "rifle"


## 桌面鼠标瞄准：只有鼠标真的在动才算（避免静止鼠标误接管朝向）
##
## ⚠️⚠️ 这是**外部状态进模拟**的第二条通道**（第一条是 feel.gd 的墙钟）——
##     `Input.get_last_mouse_velocity()` 读的是**操作系统**的鼠标状态：
##     验收/回放跑在真窗口里，只要有人在动鼠标（或窗口出现时系统给了一次移动事件），
##     瞄准方向就会变 -> 视野锥整块变 -> 像素差 5%~7%，
##     而**模拟时间、RNG 游标、所有实体位置都不变**。
##     W-00 实测：4 次运行里 1 次的 `player_aim` 变成 (-0.256,-0.967)，
##     其余 3 次都是 (1,0)；`sim_time` 四次完全相同 —— 分叉来自这里，不是来自模拟。
##
## `allow_mouse_aim` 是给**验收/回放**用的开关：固定输入才能真正比较两次运行。
## 正常游玩永远是 true（默认值），手感一点没变。
var allow_mouse_aim := true


func _mouse_aiming() -> bool:
	if DisplayServer.is_touchscreen_available():
		return false
	if not allow_mouse_aim:
		return false
	return Input.get_last_mouse_velocity().length() > 1.0


## 摇杆推力。桌面（键盘/鼠标）也必须给恒定值 —— 否则辅助瞄准在 PC 上直接失效。
##
## ⚠️ 真机/桌面实测：`AimAssist.pick` 在 `push < MIN_PUSH(0.22)` 时**直接返回空**。
##    而早先这里在桌面用鼠标瞄准时返回 0（只有"同时按住移动"才给 0.45），
##    于是 PC 上"子弹磁性"几乎从不生效 -> 有效判定只剩那条 4.2° 的窄锥
##    -> 表现就是"子弹从敌人身上穿过去"。**这是穿模的第二个原因。**
func _aim_push() -> float:
	# ⚠️ 2026-10-13：视角摇杆已删除，触屏端不再有「推力」这个概念。
	# 恒返回桌面用的稳定值 —— AimAssist 要求 push >= MIN_PUSH 才生效，
	# 返回 0 会让子弹磁性彻底失效（PC 上踩过这个坑，见函数上方的说明）。
	return 0.55


## 散布对有效 hitbox 的收缩系数。
## 0 散布 -> 1.0（满半径）；散布越大半径越小，但不低于 0.35（不能变成完全打不中）
func _spread_radius_factor(extra_spread_deg: float) -> float:
	return clampf(1.0 - maxf(extra_spread_deg, 0.0) / 10.0, 0.35, 1.0)


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


## 敌人死亡 -> 生成一具【可搜索的尸体容器】（真机反馈 #6）
## 「敌人死亡后会有战利品在尸体里，配合背包框架给玩家搜索」
func _spawn_corpse(a: EnemyAgent) -> void:
	var table: LootTableDef = reg.get_loot_table("loot_enemy_drop")
	if table == null:
		return
	var drops := LootRoller.roll_container(table, _rng, 2)
	# ⭐ 敌人装备系统：把敌人**身上穿戴的**枪 / 护甲 / 头盔也掉进尸体。
	#   这是"打敌人换装备"这条循环的来源（数据见 enemies.json 的
	#   weapon_id / armor_id / helmet_id，字段定义在 sim/defs/enemy_def.gd）。
	#   武器已作为 item 存在（id 与 weapons.json 一致），所以能直接进尸体背包。
	if a.def.weapon_id != "":
		drops.append({"item_id": a.def.weapon_id, "count": 1})
	if a.def.armor_id != "":
		drops.append({"item_id": a.def.armor_id, "count": 1})
	if a.def.helmet_id != "":
		drops.append({"item_id": a.def.helmet_id, "count": 1})
	var cid := raid.add_corpse(a.pos, a.def.id, drops)
	if Tel != null:
		var total := 0
		for d in drops:
			total += int(d["count"])
		Tel.emit("corpse", {"id": cid, "enemy": a.def.id,
			"stacks": drops.size(), "count": total})


var _roles_cooldown := 0.0
## 包夹角色重分间隔（秒）
const SQUAD_ROLES_INTERVAL := 0.4


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
	# 键盘分派全在 view/raid_input.gd（加键位改那里，不碰这个 1200 行的文件）
	if raid_input != null:
		raid_input.handle_key(event)


func _unhandled_key_input(event: InputEvent) -> void:
	if raid_input != null:
		raid_input.handle_key_release(event)


func _try_heal() -> void:
	if medical.is_treating():
		medical.cancel()
		_toast("已中断治疗")
		return
	if vitals.dead:
		return
	# 按优先级找一种能用的药
	var last_err := ""
	var found_any := false
	for med_id in ["medical_kit", "medical_bandage", "medical_painkiller"]:
		if not raid.carry.has_item(med_id):
			continue
		found_any = true
		var err := medical.start(reg.get_item(med_id), vitals)
		if err == "":
			raid.carry.remove(med_id, 1)
			_toast("开始治疗 · %s" % med_id)
			if Sfx != null:
				Sfx.play("reload_start")
			return
		last_err = err
	# ── 失败必须有【看得见】的反馈 ──
	# 真机反馈 #3："按治疗按钮没反应"。查明原因是背包里根本没有药，
	# 而失败只调了 push_warning —— 手机上完全看不见，所以表现为"按钮坏了"。
	if not found_any:
		_toast("没有医疗物品")
	else:
		_toast("用不了：%s" % last_err)
	if Sfx != null:
		Sfx.play("ui_deny")


var _lock_info: Dictionary = {}


## 有效视野锥半角（度）—— 供绘制与调试视图使用。
##
## ⚠️ 2026-10-13 真机反馈 #1：**必须与锁定逻辑同源**。
##    以前这里直接返回枪械 aim_cone_deg（步枪 55°），而辅助锁定还会
##    在近距离绕过锥角 —— 结果玩家看到的锥比实际能锁的范围还大，
##    并且朝上瞄会锁到下方敌人。现在返回
##    `AimAssist.effective_cone_deg()` = 枪械锥 ∩ 玩家视野锥门限，
##    绘制与 scan_nearest 用的是同一个上限。
func aim_cone_deg() -> float:
	if player_weapon == null:
		return AimAssist.effective_cone_deg(45.0)
	return AimAssist.effective_cone_deg(player_weapon.def.aim_cone_deg)


func _toast(msg: String, seconds: float = 2.0) -> void:
	if raid_hud != null:
		raid_hud.toast(msg, seconds)


func _bag_key_hint() -> String:
	return raid_hud.bag_key_hint() if raid_hud != null else "B"


func _open_settings() -> void:
	if settings_menu == null:
		return
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()
	settings_menu.open()


## 打开面板。附近有尸体就进入搜索模式，否则就是纯背包。


## 开关战术地图（真机反馈 #2）。地图打开时冻结模拟（见 _process）。
func _toggle_map() -> void:
	if map_panel == null or raid.is_over():
		return
	# 与背包面板互斥：两个都是全屏覆盖层，同时开着会打架
	if inventory_panel != null and inventory_panel.is_open():
		inventory_panel.close()
	map_panel.toggle(self)
	if touch != null:
		touch.set_controls_visible(not map_panel.is_open())
	if Sfx != null:
		Sfx.play("ui_click" if map_panel.is_open() else "ui_confirm")


func _go_hideout() -> void:
	if Feel != null:
		Feel.reset()
	Engine.time_scale = 1.0
	if Game != null:
		Game.go_to_hideout()
	else:
		_restart()


## 供 SettingsMenu 调用（它不知道场景内部怎么切）
func toggle_debug() -> void:
	debug_mode = (debug_mode + 1) % 4


func toggle_whitebox() -> void:
	render_mode = RENDER_ART if render_mode == RENDER_WHITEBOX else RENDER_WHITEBOX
	_build_map_texture()


## 设置菜单打开时置位：暂停期间不处理移动/开火
var game_paused := false


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
	# 地图换了，听觉场缓存必须清空（否则会用上一张图的代价场）
	_hearing_cache.clear()
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
	var key := map_baker.tile_key_for(Ballistics.cell_of(player_pos), true)
	if key.contains("metal"):
		return "metal"
	if key.contains("dirt"):
		return "dirt"
	if key.contains("wood"):
		return "wood"
	return "concrete"


## 重建地图烘焙图。
## 真正的像素逻辑在 RaidMapBaker 里（纯函数，可 headless 单测）；
## 这里只负责把结果接到场景的 `_map_tex`。
func _build_map_texture() -> void:
	if gen == null:
		return
	if map_baker == null:
		map_baker = RaidMapBaker.new()
	_map_tex_size = gen.grid.tile_extents()
	_map_tex = map_baker.build(gen.grid, gen.graph.rooms,
		render_mode == RENDER_WHITEBOX,
		theme.tile_theme if theme != null else "")


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


func _update_hud() -> void:
	# HUD 的全部文本与提示都在 RaidHud 里（view/raid_hud.gd）——
	# 这里只留委托，避免 _update_hud 继续当「每加一个统计量都要改」的冲突点。
	if raid_hud != null:
		raid_hud.refresh()

