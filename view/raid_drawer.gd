class_name RaidDrawer
extends Node2D

## 世界绘制 —— 从 `view/raid_scene.gd` 抽出来
##
## ─── 为什么抽 ───
## `_draw()` 是 raid_scene.gd 上最典型的**纯追加型**函数：
## 每加一个视觉元素（曳光、枪口火光、视野锥、血条…）都要往里塞一段。
## 1676 行的场景里它自己就占 181 行，是最大的单块冲突面。
##
## ─── 为什么是这个节点 ───
## 它是场景的**子 Node2D**，放在原点，所以绘制坐标系与父节点完全一致
## （父场景的 `_draw` 也是画在同一空间里）。
##
## ⚠️ **z 序**：子节点画在父节点**之上**，子节点之间按加入顺序。
##    所以这个 drawer 必须在 FxPool（粒子）**之前**加进场景，
##    才能保持"世界在下、粒子在上"的原观感。
##
## ─── 状态从哪来 ───
## `scene` 故意不加类型（duck typing）：用 Node2D 的话 GDScript 编译期
## 就拒绝 `scene.player_pos` 这类场景自定义成员。

## 宿主场景（RaidScene）
var scene = null


const C_WALL := Color(0.13, 0.14, 0.18)
const C_FLOOR := Color(0.27, 0.29, 0.34)
const C_CORRIDOR := Color(0.21, 0.23, 0.28)
const C_ROOM_EDGE := Color(0.32, 0.35, 0.42)
const C_SPAWN := Color(0.24, 0.62, 0.38)
const C_EXTRACT := Color(0.85, 0.65, 0.22)
const C_PLAYER := Color(0.36, 0.72, 1.0)
## ⚠️ 这三个是**警戒状态环**的颜色（不再是敌人本体填充色）——
##    本体填充色现在来自敌人类型的 `EnemyDef.color`（真机反馈 #3）。
const C_ENEMY_IDLE := Color(0.72, 0.74, 0.78, 0.55)
const C_ENEMY_ALERT := Color(1.0, 0.78, 0.30)
const C_ENEMY_COMBAT := Color(1.0, 0.28, 0.28)
const C_DEAD := Color(0.35, 0.18, 0.18)
const C_ARROW := Color(0.5, 0.78, 1.0, 0.35)

## ── 可搜索容器 / 尸体的配色（真机反馈 #4：地图的容器看不到）──
#
# ⚠️ 本轮修复前，`raid.containers`（世界容器）与 `raid.corpses`（尸体）
#    **从来没有被绘制过** —— 逻辑上它们存在、能搜、HUD 也会提示，
#    但屏幕上什么都没有。玩家因此完全找不到可搜的东西。
#    这里按容器类型给不同颜色 + 形状（药柜是白十字、枪架是竖长条…），
#    并且**搜空的容器会变暗**，让"还有一个没搜"一眼可辨。
const C_CONTAINER := Color(0.82, 0.72, 0.42)
const C_CONTAINER_OPEN := Color(0.42, 0.40, 0.34)     ## 已搜过：暗下去
const C_CORPSE := Color(0.66, 0.30, 0.30)
const C_CORPSE_LOOTED := Color(0.34, 0.22, 0.22)
const C_LOOT_DOT := Color(1.0, 0.88, 0.42)
## 附近可交互目标的高亮环
const C_FOCUS_RING := Color(1.0, 0.92, 0.60, 0.9)

## 容器类型 -> 颜色（按 data/containers.json 的 id）
const CONTAINER_COLORS := {
	"container_crate": Color(0.72, 0.56, 0.34),
	"container_supply_case": Color(0.52, 0.72, 0.46),
	"container_weapon_rack": Color(0.62, 0.64, 0.72),
	"container_ammo_box": Color(0.78, 0.66, 0.32),
	"container_med_cabinet": Color(0.86, 0.90, 0.94),
	"container_locker": Color(0.58, 0.62, 0.70),
	"container_cargo_crate": Color(0.70, 0.52, 0.30),
	"container_lab_case": Color(0.55, 0.82, 0.78),
}


## 逻辑格矩形 -> 世界像素矩形
func _cell_rect(c: Vector2i) -> Rect2:
	return Rect2(Vector2(c.x, c.y) * scene.CELL_PX, Vector2(scene.CELL_PX, scene.CELL_PX))


## 画可搜索容器 + 尸体，并在【最近可交互目标】上套一圈高亮环。
##
## 高亮环的选法与 `raid_scene._open_bag()` / `raid_hud._refresh_corpse_prompt()`
## 完全一致（同为"尸体与容器取更近的那个"）—— 三处不一致的话，
## 玩家会看到"A 被高亮、按 B 却开了 B"。
func _draw_containers() -> void:
	var raid = scene.raid
	if raid == null:
		return
	var pc: Vector2 = scene.player_pos

	# ① 世界容器
	for c in raid.containers:
		var ctr: Vector2 = c.pos * scene.CELL_PX
		var open := bool(c.searched)
		var col: Color = CONTAINER_COLORS.get(str(c.def.id), C_CONTAINER) if c.def != null \
			else C_CONTAINER
		if open:
			col = col.lerp(C_CONTAINER_OPEN, 0.62)
		_draw_container_shape(ctr, str(c.def.id) if c.def != null else "", col)
		# 还有东西没拿 -> 右上角一个亮点，等于"没搜空"
		if not c.is_done():
			draw_circle(ctr + Vector2(9, -9), 2.6, C_LOOT_DOT)

	# ② 尸体（敌人死亡后落下的可搜索容器）
	for cp in raid.corpses:
		var d: Dictionary = cp
		var ctr2: Vector2 = (d["pos"] as Vector2) * scene.CELL_PX
		var empty := bool(d["searched"]) and (d["drops"] as Array).is_empty()
		var ccol := C_CORPSE_LOOTED if empty else C_CORPSE
		# 躯干：一个横躺的小人（区别于敌人的圆）
		draw_rect(Rect2(ctr2 - Vector2(10, 5), Vector2(20, 10)), ccol, true)
		draw_circle(ctr2 + Vector2(-11, 0), 4.0, ccol)
		if not empty:
			draw_circle(ctr2 + Vector2(9, -9), 2.6, C_LOOT_DOT)

	# ③ 最近可交互目标的高亮环（与交互选法一致）
	var ci: int = raid.corpse_near(pc)
	var xi: int = raid.container_near(pc)
	if ci < 0 and xi < 0:
		return
	var d_c := 999.0
	var d_x := 999.0
	if ci >= 0:
		d_c = ((raid.corpses[ci]["pos"]) as Vector2).distance_to(pc)
	if xi >= 0:
		d_x = raid.containers[xi].pos.distance_to(pc)
	var focus: Vector2
	if ci >= 0 and (xi < 0 or d_c <= d_x):
		focus = (raid.corpses[ci]["pos"] as Vector2) * scene.CELL_PX
	else:
		focus = raid.containers[xi].pos * scene.CELL_PX
	draw_arc(focus, 20.0, 0, TAU, 28, C_FOCUS_RING, 2.0)


## 按容器类型画一个**形状**（不只是颜色不同）——
## 色盲玩家与"白模/像素风"下，形状比颜色可靠得多。
func _draw_container_shape(ctr: Vector2, id: String, col: Color) -> void:
	var edge := col.darkened(0.45)
	match id:
		"container_weapon_rack":
			# 枪架：竖长条 + 两斜线
			draw_rect(Rect2(ctr - Vector2(7, 16), Vector2(14, 32)), col, true)
			draw_line(ctr + Vector2(-7, -10), ctr + Vector2(7, 6), edge, 2.0)
			draw_line(ctr + Vector2(7, -10), ctr + Vector2(-7, 6), edge, 2.0)
		"container_locker":
			# 储物柜：竖长条 + 中缝
			draw_rect(Rect2(ctr - Vector2(9, 15), Vector2(18, 30)), col, true)
			draw_line(ctr + Vector2(0, -15), ctr + Vector2(0, 15), edge, 2.0)
		"container_med_cabinet":
			# 药柜：白底红十字
			draw_rect(Rect2(ctr - Vector2(11, 11), Vector2(22, 22)), col, true)
			var rc := Color(0.85, 0.22, 0.24)
			draw_rect(Rect2(ctr - Vector2(3, 9), Vector2(6, 18)), rc, true)
			draw_rect(Rect2(ctr - Vector2(9, 3), Vector2(18, 6)), rc, true)
		"container_ammo_box":
			# 弹药箱：小方箱 + 两条弹带
			draw_rect(Rect2(ctr - Vector2(9, 8), Vector2(18, 16)), col, true)
			draw_line(ctr + Vector2(-6, -4), ctr + Vector2(6, -4), edge, 2.0)
			draw_line(ctr + Vector2(-6, 3), ctr + Vector2(6, 3), edge, 2.0)
		"container_lab_case":
			# 实验柜：菱形
			var pts := PackedVector2Array([
				ctr + Vector2(0, -13), ctr + Vector2(11, 0),
				ctr + Vector2(0, 13), ctr + Vector2(-11, 0)])
			draw_colored_polygon(pts, col)
			draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), edge, 2.0)
		"container_cargo_crate":
			# 货运箱：大方箱 + 交叉带
			draw_rect(Rect2(ctr - Vector2(13, 13), Vector2(26, 26)), col, true)
			draw_line(ctr + Vector2(-13, -13), ctr + Vector2(13, 13), edge, 2.0)
			draw_line(ctr + Vector2(13, -13), ctr + Vector2(-13, 13), edge, 2.0)
		"container_supply_case":
			# 补给箱：方箱 + 十字（与药柜区分：用深色边而不是红）
			draw_rect(Rect2(ctr - Vector2(11, 11), Vector2(22, 22)), col, true)
			draw_line(ctr + Vector2(0, -11), ctr + Vector2(0, 11), edge, 3.0)
			draw_line(ctr + Vector2(-11, 0), ctr + Vector2(11, 0), edge, 3.0)
		_:
			# 默认（木箱等）：方箱 + 顶盖亮边
			draw_rect(Rect2(ctr - Vector2(10, 10), Vector2(20, 20)), col, true)
			draw_line(ctr + Vector2(-10, -10), ctr + Vector2(10, -10), col.lightened(0.35), 3.0)
	draw_rect(Rect2(ctr - Vector2(1, 1), Vector2(2, 2)), edge, true)


func _draw() -> void:
	if scene.gen == null:
		return
	if Tel != null:
		Tel.mark("draw_body")
	var g = scene.gen.grid

	# ── 地形：一次画完整张烘焙图（nearest 放大 16 倍）──
	if scene._map_tex != null:
		draw_texture_rect(scene._map_tex,
			Rect2(Vector2.ZERO, Vector2(scene._map_tex_size) * RaidMapBaker.TILE_PX), false)
	else:
		# 贴图缺失时的降级绘制
		for y in g.height:
			for x in g.width:
				var c = Vector2i(x, y)
				var v = g.get_cell(c)
				var col = C_WALL
				if v == LogicalGrid.Cell.FLOOR:
					col = C_FLOOR
				elif v == LogicalGrid.Cell.CORRIDOR:
					col = C_CORRIDOR
				draw_rect(_cell_rect(c), col, true)

	# ── 房间类型着色 ──
	for r in scene.gen.graph.rooms:
		var col = C_ROOM_EDGE
		if r.room_type == "spawn":
			col = C_SPAWN
		elif r.room_type == "extract":
			col = C_EXTRACT
		if r.room_type != "common":
			draw_rect(Rect2(Vector2(r.rect.position) * scene.CELL_PX, Vector2(r.rect.size) * scene.CELL_PX), col, false, 3.0)

	# ── 流场调试 ──
	if scene.debug_mode == 1:
		var ex = scene.gen.extract_rooms()
		if not ex.is_empty():
			var f = scene.flows.field_for(ex[0].center)
			if f != null:
				for y in g.height:
					for x in g.width:
						var c = Vector2i(x, y)
						if not g.is_walkable(c):
							continue
						var d = f.get_direction(c)
						if d == Vector2i.ZERO:
							continue
						var ctr = (Vector2(c) + Vector2(0.5, 0.5)) * scene.CELL_PX
						draw_line(ctr, ctr + Vector2(d).normalized() * scene.CELL_PX * 0.42, C_ARROW, 1.5)

	# ── 撤离点 ──
	for p in scene.raid.extract_points:
		var ctr = p * scene.CELL_PX
		draw_arc(ctr, scene.CELL_PX * scene.raid.extract_radius, 0, TAU, 24, C_EXTRACT, 2.0)

	# ── 地上掉落 ──
	for d in scene.drops_on_ground:
		var ctr: Vector2 = (d["pos"] as Vector2) * scene.CELL_PX
		draw_rect(Rect2(ctr - Vector2(5, 5), Vector2(10, 10)), Color(0.95, 0.85, 0.35), true)

	# ── 可搜索容器 + 尸体（真机反馈 #4）──
	_draw_containers()

	# ── 敌人 ──
	# 两条**独立**信息通道（2026-10-13 真机反馈 #3：不同敌人要有不同特征颜色）：
	#   ① **填充色 = 类型身份**（a.def.color，来自 data/enemies.json）
	#   ② **外圈环 = 警戒状态**（放松灰 / 警觉黄 / 交战红）
	# 早先两者挤在同一条颜色通道上（敌人只会"警戒变色"），
	# 于是感染体和重装暴徒长得一模一样，玩家分不清面前是谁。
	var engaged: bool = scene.squad.is_engaged()
	var alerted: bool = scene.squad.is_alerted()
	var ring_col := C_ENEMY_IDLE
	if engaged:
		ring_col = C_ENEMY_COMBAT
	elif alerted:
		ring_col = C_ENEMY_ALERT
	for a in scene.agents:
		var ctr: Vector2 = a.pos * scene.CELL_PX
		if not a.is_alive():
			draw_rect(Rect2(ctr - Vector2(6, 6), Vector2(12, 12)), C_DEAD, true)
			continue
		var body: Color = a.def.color
		var r = 9.0 if a.def.is_ranged() else 7.0
		# ① 类型身份：填充色
		draw_circle(ctr, r, body)
		# ② 警戒状态：外圈环（交战最粗，放松最细）
		var rw := 3.0 if engaged else (2.2 if alerted else 1.4)
		draw_arc(ctr, r + 2.5, 0, TAU, 24, ring_col, rw)
		# 远程/近战再用**形状**区分一次（色盲玩家也能读）
		if a.def.is_ranged():
			draw_arc(ctr, r * 0.45, 0, TAU, 12, body.lightened(0.45), 1.5)
		# 朝向
		draw_line(ctr, ctr + a.facing * r * 1.9, body.lightened(0.45), 2.0)
		# 血条
		var hpr = float(a.hp) / maxf(1.0, float(a.def.hp))
		draw_rect(Rect2(ctr + Vector2(-10, -15), Vector2(20, 3)), Color(0.2, 0.2, 0.22), true)
		draw_rect(Rect2(ctr + Vector2(-10, -15), Vector2(20 * hpr, 3)), Color(0.9, 0.3, 0.3), true)

	# ── 曳光 ──
	# ⚠️ 早先 ttl 只有 0.06s（约 3.6 帧）且线很细，真机上"只听到枪声看不到子弹"。
	#    现在加长到 0.13s，加粗，并在头部画一个亮点。
	for b in scene.bullets:
		var a: Vector2 = (b["from"] as Vector2) * scene.CELL_PX
		var c: Vector2 = (b["to"] as Vector2) * scene.CELL_PX
		var own: bool = bool(b.get("own", true))
		var life: float = clampf(float(b["ttl"]) / scene.TRACER_TTL, 0.0, 1.0)
		var col = (Color(1.0, 0.94, 0.58) if own else Color(1.0, 0.72, 0.55))
		col.a = 0.35 + 0.65 * life
		draw_line(a, c, col, 3.0 if own else 2.0)
		draw_circle(c, 3.0 if own else 2.0, col)

	# ── 枪口火光（画在粒子之外，保证一定看得见）──
	for m in scene.muzzle_flash:
		var p: Vector2 = (m["pos"] as Vector2) * scene.CELL_PX
		var d: Vector2 = m["dir"] as Vector2
		var t: float = clampf(float(m["ttl"]) / 0.07, 0.0, 1.0)
		var f = Vector2(-d.y, d.x)
		# 一个朝向前方的四角星形闪
		var tip = p + d * (16.0 + 10.0 * t)
		var s1 = p + f * 7.0 - d * 4.0
		var s2 = p - f * 7.0 - d * 4.0
		draw_colored_polygon(PackedVector2Array([tip, s1, p - d * 3.0, s2]),
			Color(1.0, 0.90, 0.52, 0.85 * t))
		draw_circle(p + d * 6.0, 5.0 + 4.0 * t, Color(1.0, 0.78, 0.35, 0.55 * t))

	# ── 锥形视野 + 锁定指示（真机反馈 #5）──
	# 必须把视野范围画出来 —— 玩家要能看见自己锁到了谁。
	# 锥角来自枪械数据（weapon.aim_cone_deg），所以换枪视野就变。
	#
	# ⚠️ 用户实测："视野锥会透视，对于白模地图来说没有遮挡，
	#    会导致透视到敌人对墙开火。"
	#    早先锥体是个**固定半径的扇形**，直接穿过墙体 —— 视觉上在告诉你
	#    "你能看到墙后面"，而实际上打不到。现在**每条锥线都做射线裁切**，
	#    锥体贴着墙就停住。这既符合真实视野，也消除了"看得见却打不到"的误导。
	if scene.player_weapon != null and not scene.raid.is_over():
		var pcz = scene.player_pos * scene.CELL_PX
		var half = deg_to_rad(scene.aim_cone_deg())
		var base = scene.player_aim.angle()
		var has_lock = scene.auto_aim.has_lock()
		var cone_col = (Color(1.0, 0.55, 0.35, 0.085) if has_lock
			else Color(0.55, 0.85, 1.0, 0.055))
		var edge_col = (Color(1.0, 0.62, 0.38, 0.42) if has_lock
			else Color(0.55, 0.85, 1.0, 0.20))
		# 视觉半径不必超过屏幕对角线 —— 屏幕外的部分看不见，白算
		var vp = get_viewport_rect().size
		var screen_diag_cells = (vp.length() / scene.CELL_PX) + 2.0
		var cone_r_cells = minf(float(scene.player_weapon.def.range_m), screen_diag_cells)
		var segs = 22
		var pts = PackedVector2Array()
		pts.append(pcz)
		var edge_a = Vector2.ZERO
		var edge_b = Vector2.ZERO
		for i in segs + 1:
			var a = base - half + (2.0 * half) * (float(i) / float(segs))
			var d = Vector2.from_angle(a)
			# 逐条射线算"撞墙前的距离"，锥体于是被墙截断
			var dist = Ballistics.los_distance(scene.gen.grid, scene.player_pos, d, cone_r_cells)
			var end = pcz + d * (dist * scene.CELL_PX)
			pts.append(end)
			if i == 0:
				edge_a = end
			elif i == segs:
				edge_b = end
		draw_colored_polygon(pts, cone_col)
		draw_line(pcz, edge_a, edge_col, 1.5)
		draw_line(pcz, edge_b, edge_col, 1.5)
		if has_lock:
			var lp = scene.auto_aim.locked_pos * scene.CELL_PX
			var s = 13.0
			# 只在**当前可见**时用实线 —— 粘性期间的锁定改成虚线感（画角标）
			var vis = bool(scene._lock_info.get("visible", false))
			var lc = (Color(1.0, 0.45, 0.35, 0.95) if vis
				else Color(1.0, 0.45, 0.35, 0.35))
			draw_line(lp + Vector2(-s, -s), lp + Vector2(s, -s), lc, 2.0)
			draw_line(lp + Vector2(s, -s), lp + Vector2(s, s), lc, 2.0)
			draw_line(lp + Vector2(s, s), lp + Vector2(-s, s), lc, 2.0)
			draw_line(lp + Vector2(-s, s), lp + Vector2(-s, -s), lc, 2.0)

	# ── 玩家 ──
	var pc = scene.player_pos * scene.CELL_PX
	draw_circle(pc, 10.0, C_PLAYER)
	draw_line(pc, pc + scene.player_aim * 26.0, Color(1, 1, 1, 0.8), 2.5)
	# 朝向指示器（art-pipeline §3.2 的"朝向可视化"三件套之一）
	draw_arc(pc, 13.0, scene.player_facing.angle() - 0.5, scene.player_facing.angle() + 0.5, 8, C_PLAYER.lightened(0.4), 2.0)

	# ── 调试：声音范围 ──
	if scene.debug_mode == 3 and not scene.noises.is_empty():
		for nz in scene.noises:
			draw_arc((nz["pos"] as Vector2) * scene.CELL_PX, float(nz["loudness_m"]) * scene.CELL_PX * 0.25,
				0, TAU, 24, Color(1, 1, 0.4, 0.25), 1.0)

	# 收尾标记：把「_draw 里搬了多少绘制指令」与
	# 「搬完之后引擎渲染 + 呈现 + 等 vsync 花了多久」分开。
	# 不分开的话 draw_body 会把 vsync 等待全算进去，看不出真实瓶颈（实测踩过）。
	if Tel != null:
		Tel.mark("draw_end")
