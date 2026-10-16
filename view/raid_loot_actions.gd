class_name RaidLootActions
extends RefCounted

## 搜刮交互 —— 从 `view/raid_scene.gd` 分出的第二刀（2026-10-13）
##
## 装什么：打开搜索面板（尸体 / 容器取更近的那个）、把容器内容倒进临时 Inventory 渲染、
## 应用面板上的动作（使用 / 丢弃 / 从容器拿）。
## **判定与数据不在这里** —— 容器与尸体的存取在 `sim/raid/raid_session.gd`，
## 面板本身在 `ui/inventory_panel.gd`；本模块只是把它们接起来。
##
## ⚠️ 与 raid_player_actions / raid_sim_runner 同款：`scene.xxx` 鸭子类型（本工程既有约定）。
## ⚠️ 凡接收方是 `scene.xxx` 的调用，**一律用无类型 `var`** ——
##    `:=` 在 Variant 链上推不出类型（AGENTS.md §4 点名过的坑，这里刻意避开）。

## 宿主场景（RaidScene）。无类型：duck typing 读场景自定义成员。
var scene = null

var _corpse_open_idx := -1
## 当前打开的容器索引（-1 = 没在搜容器）
var _container_open_idx := -1
## 当前搜索目标的名字（尸体 / 药柜 …）—— 重建面板时用它当标题，
## 免得"从药柜拿东西后标题变成『容器』"（真机反馈 #5 拾取流程里很显眼）
var _container_title := "搜索目标"


## 装备品质/词条表（面板显示品质与词条用）。
## 空表 = 面板退回旧样式（不显示品质），向后兼容没有 gear 数据的老调用方。
func _gear_defs() -> Dictionary:
	if scene == null or scene.reg == null:
		return {}
	return {"rarities": scene.reg.gear_rarities, "affixes": scene.reg.gear_affixes}


func open_bag() -> void:
	if scene == null or scene.inventory_panel == null or scene.raid.is_over():
		return
	# 地图开着时先关它（互斥，见 raid_scene._toggle_map）
	if scene.map_panel != null and scene.map_panel.is_open():
		scene.map_panel.close()
	_corpse_open_idx = -1
	_container_open_idx = -1
	var ctitle := ""
	var container: Inventory = null
	# 尸体与容器都算"搜索目标"，取**更近的那个** —— 站在两者中间时开最近的那个。
	var ci = scene.raid.corpse_near(scene.player_pos)
	var xi = scene.raid.container_near(scene.player_pos)
	var d_corpse := 999.0
	var d_cont := 999.0
	if ci >= 0:
		d_corpse = (scene.raid.corpses[ci]["pos"] as Vector2).distance_to(scene.player_pos)
	if xi >= 0:
		d_cont = scene.raid.containers[xi].pos.distance_to(scene.player_pos)
	if ci >= 0 and (xi < 0 or d_corpse <= d_cont):
		_corpse_open_idx = ci
		container = _build_corpse_inv(ci)
		ctitle = "尸体"
	elif xi >= 0:
		_container_open_idx = xi
		container = _build_container_inv(xi)
		ctitle = scene.raid.containers[xi].display_name()
	_container_title = ctitle if ctitle != "" else "搜索目标"
	scene.inventory_panel.open(scene.reg.items, scene.raid.carry, container, ctitle,
		scene.raid.equipment, _gear_defs())
	if scene.touch != null:
		scene.touch.set_controls_visible(false)   # 面板打开时收起摇杆，避免抢触点
	if Sfx != null:
		Sfx.play("ui_click")


## 把容器当前内容倒进一个临时 Inventory 供面板渲染。
## ⚠️ 与 _build_corpse_inv 同理由：take 是从【容器】里扣的，
##    临时 Inventory 只是视图 —— 不重建就会一直显示已拿走的东西。
func _build_container_inv(idx: int) -> Inventory:
	var inv := Inventory.new(24, scene.reg.items, 999.0)
	if idx < 0 or idx >= scene.raid.containers.size():
		return inv
	for d in (scene.raid.containers[idx].drops as Array):
		var dd: Dictionary = d as Dictionary
		# ⭐ 全境2化 P2：带 gear 的走 add_with_gear，否则面板**看不见**品质词条
		#    （sim 层修好了搬运，但视图 Inventory 这里丢的话玩家照样看不到）
		if dd.has("gear"):
			inv.add_with_gear(str(dd["item_id"]), (dd["gear"] as Dictionary))
		else:
			inv.add(str(dd["item_id"]), int(dd["count"]))
	return inv


## 把尸体当前的掉落物倒进一个临时 Inventory 供面板渲染。
## ⚠️ 必须每次重新构建：`take_from_corpse` 是从【尸体】里扣的，
##    临时 Inventory 只是个视图 —— 不重建的话面板会一直显示已拿走的东西。
func _build_corpse_inv(idx: int) -> Inventory:
	var inv := Inventory.new(20, scene.reg.items, 999.0)
	if idx < 0 or idx >= scene.raid.corpses.size():
		return inv
	for d in (scene.raid.corpses[idx]["drops"] as Array):
		var dd: Dictionary = d as Dictionary
		# ⭐ 同上：尸体的带词条装备也要原样进视图 Inventory
		if dd.has("gear"):
			inv.add_with_gear(str(dd["item_id"]), (dd["gear"] as Dictionary))
		else:
			inv.add(str(dd["item_id"]), int(dd["count"]))
	return inv


## 面板里的动作。count=-1 表示"使用"，-2 表示"丢弃"，>0 表示从容器拿走。
func on_panel_action(item_id: String, count: int) -> void:
	if item_id.is_empty():
		return
	if count == -1:
		# 使用：只支持医疗品（其余交给后续的制造/消耗系统）
		var d: ItemDef = scene.reg.get_item(item_id)
		if d != null and d.category == "medical":
			var err = scene.medical.start(d, scene.vitals)
			if err == "":
				scene.raid.carry.remove(item_id, 1)
				scene._toast("开始治疗 · %s" % d.name)
			else:
				scene._toast(err)
		else:
			scene._toast("现在用不了：%s" % (d.name if d != null else item_id))
		return
	if count == -2:
		var n = scene.raid.carry.remove(item_id, 1)
		if n > 0:
			scene.drops_on_ground.append({"pos": scene.player_pos, "item_id": item_id, "count": n})
			scene._toast("丢弃 %d 个" % n)
		return
	# count > 0：从搜到的容器里拿（1 = 单个 / N = 自定义数量 / 全部 = 整堆）
	if _corpse_open_idx >= 0:
		var got = scene.raid.take_from_corpse(_corpse_open_idx, item_id, count)
		if got > 0:
			if Sfx != null:
				Sfx.play("pickup")
			if got < count:
				scene._toast("背包放不下，只拿了 %d/%d" % [got, count])
			scene.inventory_panel.open(scene.reg.items, scene.raid.carry,
				_build_corpse_inv(_corpse_open_idx), _container_title,
				scene.raid.equipment, _gear_defs())
		elif Sfx != null:
			Sfx.play("ui_deny")
			scene._toast("背包放不下")
		return
	if _container_open_idx >= 0:
		var got2 = scene.raid.take_from_container(_container_open_idx, item_id, count)
		if got2 > 0:
			if Sfx != null:
				Sfx.play("pickup")
			if got2 < count:
				scene._toast("背包放不下，只拿了 %d/%d" % [got2, count])
			scene.inventory_panel.open(scene.reg.items, scene.raid.carry,
				_build_container_inv(_container_open_idx), _container_title,
				scene.raid.equipment, _gear_defs())
		elif Sfx != null:
			Sfx.play("ui_deny")
			scene._toast("背包放不下")
