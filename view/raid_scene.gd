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
## 技术验证阶段：敌人数量上限（真机反馈 #2）
## 现阶段要的是验证技术，不是打怪。每种敌人各 1 个、总数不超过 4 个足够暴露问题。
## 调成 0 表示不限制（恢复正式刷怪）。
const MAX_TEST_ENEMIES := 4
## 技术验证阶段：简化枪械。
## 真机反馈 #2："不测试具体枪械系统，玩家开火不需要挂载后坐力之类的"。
## 打开时：散布 = 0、后坐力 = 0、备弹给足（装弹/弹匣保留，那是核心循环的一部分）。
const SIMPLE_WEAPON := true
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
var touch: TouchControls = null  ## 双摇杆 + 动作按钮
var flash_rect: ColorRect = null ## 受击闪白覆盖层
var inventory_panel: InventoryPanel = null   ## 背包/搜索面板（#3 / #6）
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

func _setup_sim() -> void:
	reg = DataRegistry.new()
	if not reg.load_all("A"):
		push_error("数据加载失败：%s" % str(reg.errors))
		return

	# ⚠️ 每局换种子。
	#    早先这里写死 20261012，结果真机上"每局地图和出生点完全一样" ——
	#    玩家反馈"并没有随机出生"。同种子可复现是开发期的需要，
	#    正式游玩必须每局不同（T-32 的种子纪律：可复现 ≠ 写死）。
	if Game != null:
		Game.apply_accessibility()
	if _raid_seed <= 0:
		_raid_seed = Game.raid_seed if (Game != null and Game.raid_seed > 0) else (randi() & 0x7FFFFFFF)
	_rng = SimRng.new(_raid_seed)

	gen = MapGenerator.new()
	if not gen.generate(_raid_seed, reg.room_types):
		push_error("地图生成失败：%s" % str(gen.errors))
		return

	flows = FlowFieldManager.new()
	flows.setup(gen.grid)

	# 藏身处：用 Game（autoload）里的**跨场景持久**实例
	# 真机反馈 #7：死亡后要能真正回藏身处，所以它必须活在场景之外
	if Game != null:
		Game.ensure_loaded()
		hideout = Game.hideout
		reg = Game.reg if Game.reg != null else reg
	if hideout == null:
		hideout = Hideout.new(reg.items, 3000)
		hideout.wallet += 5000

	# ⚠️ 把藏身处的升级效果传进本局 —— 否则升级花了钱但毫无作用。
	#    （早先 raid_modifiers() 从未被调用。）
	raid = RaidSession.new(reg.items, _rng, hideout.stash, hideout.raid_modifiers())
	raid.load_map(gen)
	raid.start(240.0)

	vitals = Vitals.new()
	vitals.reset(100, 40)
	medical = MedicalSystem.new()
	# 藏身处「战地急救」升级：治疗更快
	medical.set_speed_multiplier(raid.heal_speed)

	# 玩家武器：步枪 + 自动装配件（展示 A 阶段改装系统）
	var loadout := WeaponModding.create_loadout(reg.get_weapon("weapon_rifle"), WeaponModding.SLOTS_A)
	WeaponModding.auto_fit(loadout, reg.attachments)
	var wdef := loadout.to_weapon_def()
	# ── 技术验证阶段：不测枪械系统 ──
	# 真机反馈 #2："现阶段不测试具体枪械系统，玩家开火不需要挂载后坐力之类的"。
	# 所以去掉散布与后坐力，备弹给足；装弹/弹匣仍然保留（那是搜打撤核心循环的一部分）。
	if SIMPLE_WEAPON:
		wdef.spread_deg = 0.0
		wdef.recoil_v = 0.0
		wdef.recoil_h = 0.0
	player_weapon = WeaponState.new(wdef, 9999 if SIMPLE_WEAPON else 180)
	print("[装填] %s  视野锥 %.0f°%s" % [loadout.summary(), wdef.aim_cone_deg,
		"（简化模式：无后坐力/散布）" if SIMPLE_WEAPON else ""])

	var spawn := gen.spawn_room()
	player_pos = Ballistics.cell_center(spawn.center)
	raid.hp = vitals.hp

	# ── 起始配装 ──
	# ⚠️ 真机反馈 #3："按治疗按钮没反应"。查明原因：按钮是好的，
	#    但 `_setup_sim` 从来没给玩家发过任何物品，背包是空的（0/12 槽），
	#    所以找不到任何药。这里补上最小可用的起始配装。
	raid.carry.add("medical_bandage", 2)
	raid.carry.add("medical_kit", 1)
	raid.carry.add("ammo_rifle", 90)
	print("[配装] %s" % raid.carry.summary())

	# 敌人
	squad = Squad.new(1)
	var scav := reg.get_enemy("enemy_scav")
	var infected := reg.get_enemy("enemy_infected")
	var eid := 0
	# ⚠️ **从数据里取全部敌人类型**，不要硬编码 ——
	#    数据填充到 A 阶段后（2 -> 4 种），硬编码会让新敌人永远不出现。
	#    `reg.enemies` 已经是按 stage 过滤过的（load_all("A") 只装 B+A）。
	var kinds: Array[EnemyDef] = []
	for id in reg.enemies:
		kinds.append(reg.enemies[id])
	kinds.sort_custom(func(a, b): return a.id < b.id)   # 稳定顺序，便于复现
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
			var a := EnemyAgent.new(eid, d, Ballistics.cell_center(r.center))
			if d.is_ranged():
				a.equip(reg.get_weapon("weapon_pistol"), 60)
			a.facing = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
			squad.add_member(a)
			agents.append(a)
			eid += 1
	else:
		for r in gen.graph.rooms:
			if r.room_type == "spawn":
				continue
			for i in r.enemy_budget:
				var d2: EnemyDef = kinds[eid % kinds.size()]
				var a2 := EnemyAgent.new(eid, d2, Ballistics.cell_center(r.center))
				if d2.is_ranged():
					a2.equip(reg.get_weapon("weapon_pistol"), 60)
				a2.facing = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
				squad.add_member(a2)
				agents.append(a2)
				eid += 1
	print("[地图] %s" % gen.summary())
	print("[敌方] %d 名（类型池 %d：%s）%s" % [agents.size(), kinds.size(),
		", ".join(kinds.map(func(k): return k.name)),
		"（技术验证模式，上限 %d）" % MAX_TEST_ENEMIES if MAX_TEST_ENEMIES > 0 else ""])


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
	inventory_panel.action.connect(_on_panel_action)
	inventory_panel.closed.connect(func():
		if touch != null:
			touch.set_controls_visible(true))
	var inv_layer := CanvasLayer.new()
	inv_layer.layer = 45
	inv_layer.add_child(inventory_panel)
	add_child(inv_layer)
	touch.bag_pressed.connect(_open_bag)
	touch.menu_pressed.connect(_open_settings)

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

	# ── 逻辑冻结（设置菜单打开时）──
	# 不用 get_tree().paused：它同时门控输入，导致菜单看得见点不动（PC 实测卡死）。
	# 这里只跳过游戏逻辑；HUD / 绘制 / 输入 / 相机全部照常。
	var frozen := game_paused or (Game != null and Game.paused)
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
func _mouse_aiming() -> bool:
	if DisplayServer.is_touchscreen_available():
		return false
	return Input.get_last_mouse_velocity().length() > 1.0


## 摇杆推力。桌面（键盘/鼠标）也必须给恒定值 —— 否则辅助瞄准在 PC 上直接失效。
##
## ⚠️ 真机/桌面实测：`AimAssist.pick` 在 `push < MIN_PUSH(0.22)` 时**直接返回空**。
##    而早先这里在桌面用鼠标瞄准时返回 0（只有"同时按住移动"才给 0.45），
##    于是 PC 上"子弹磁性"几乎从不生效 -> 有效判定只剩那条 4.2° 的窄锥
##    -> 表现就是"子弹从敌人身上穿过去"。**这是穿模的第二个原因。**
func _aim_push() -> float:
	if touch != null:
		var p := touch.aim_push()
		if p > 0.01:
			return clampf(p, 0.0, 1.0)
	# 桌面：鼠标瞄准 / 键盘瞄准时给一个稳定值
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


## 视野锥半角（度）—— 供绘制与调试视图使用
func aim_cone_deg() -> float:
	return player_weapon.def.aim_cone_deg if player_weapon != null else 45.0


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
func _open_bag() -> void:
	if inventory_panel == null or raid.is_over():
		return
	var ci := raid.corpse_near(player_pos)
	_corpse_open_idx = ci
	var ctitle := ""
	var container: Inventory = null
	if ci >= 0:
		container = _build_corpse_inv(ci)
		ctitle = "尸体"
	inventory_panel.open(reg.items, raid.carry, container, ctitle)
	if touch != null:
		touch.set_controls_visible(false)   # 面板打开时收起摇杆，避免抢触点
	if Sfx != null:
		Sfx.play("ui_click")


## 把尸体当前的掉落物倒进一个临时 Inventory 供面板渲染。
## ⚠️ 必须每次重新构建：`take_from_corpse` 是从【尸体】里扣的，
##    临时 Inventory 只是个视图 —— 不重建的话面板会一直显示已拿走的东西。
func _build_corpse_inv(idx: int) -> Inventory:
	var inv := Inventory.new(20, reg.items, 999.0)
	if idx < 0 or idx >= raid.corpses.size():
		return inv
	for d in (raid.corpses[idx]["drops"] as Array):
		inv.add(str(d["item_id"]), int(d["count"]))
	return inv


## 面板里的动作。count=-1 表示"使用"，-2 表示"丢弃"，>0 表示从容器拿走。
func _on_panel_action(item_id: String, count: int) -> void:
	if item_id.is_empty():
		return
	if count == -1:
		# 使用：只支持医疗品（其余交给后续的制造/消耗系统）
		var d: ItemDef = reg.get_item(item_id)
		if d != null and d.category == "medical":
			var err := medical.start(d, vitals)
			if err == "":
				raid.carry.remove(item_id, 1)
				_toast("开始治疗 · %s" % d.name)
			else:
				_toast(err)
		else:
			_toast("现在用不了：%s" % (d.name if d != null else item_id))
		return
	if count == -2:
		var n := raid.carry.remove(item_id, 1)
		if n > 0:
			drops_on_ground.append({"pos": player_pos, "item_id": item_id, "count": n})
			_toast("丢弃 %d 个" % n)
		return
	# count > 0：从搜到的容器里拿
	if _corpse_open_idx >= 0:
		var got := raid.take_from_corpse(_corpse_open_idx, item_id, count)
		if got > 0:
			if Sfx != null:
				Sfx.play("pickup")
			# 重建视图 —— 见 _build_corpse_inv 的说明
			inventory_panel.open(reg.items, raid.carry,
				_build_corpse_inv(_corpse_open_idx), "尸体")
		elif Sfx != null:
			Sfx.play("ui_deny")
			_toast("背包放不下")


var _corpse_open_idx := -1


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
		render_mode == RENDER_WHITEBOX)


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

