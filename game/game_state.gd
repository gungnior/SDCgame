extends Node

## 跨场景持久状态（autoload "Game"）
##
## 为什么需要：加了藏身处场景之后，"突袭"和"藏身处"是两个独立场景，
## 场景切换会销毁节点 —— 藏身处进度、玩家设置必须活在场景之外。
##
## 职责：
##   · 持有藏身处（仓库 / 资金 / 升级）
##   · 持有玩家设置（自动射击、视野跟随、无障碍选项…）
##   · 场景切换（出发突袭 / 返回藏身处）

const RAID_SCENE := "res://view/raid_scene.tscn"
const HIDEOUT_SCENE := "res://view/hideout_scene.tscn"
const MAIN_MENU_SCENE := "res://view/main_menu.tscn"

var reg: DataRegistry = null
var hideout: Hideout = null

# ─── 玩家设置（UI 可改，跨局保留）───
## 自动射击：视野锥内发现敌人就自动开火（优先最近）
var auto_fire := false
## 自动瞄准：不开自动射击时，准心自动对准锥内敌人
var auto_aim := true
## 视野跟随锁定目标：锁定后视野锥跟着目标转
var vision_follows_lock := true

## 无障碍（转发给 Feel）
var shake_enabled := true
var hitstop_enabled := true
var flash_enabled := true

var _ready_done := false
## 逻辑暂停标志（**不使用 get_tree().paused**）
##
## 用户 PC 实测按 ESC 后卡死：日志显示场景的 _process 停了 28 秒，
## 但 ALWAYS 的 Tel 仍在记录 —— 树被 pause 了而且恢复不了。
## `get_tree().paused` 同时门控【逻辑】与【输入】，只冻结前者需要精确控制
## 整棵子树的 process_mode，漏一处就是"看得见、点不动"。
## 所以改成纯逻辑冻结：场景在 _process 里自己看这个标志。
var paused := false

# ─── 存档 ───
var save: SaveManager = null
## 累计统计（跨局，写进存档）
var stats := {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0}
## 上一次存档/读档的提示（HUD 或藏身处显示用）
var save_status := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 保险：清掉任何残留的树暂停（旧版本可能留下 paused=true）
	get_tree().paused = false
	ensure_loaded()


func ensure_loaded() -> void:
	if _ready_done:
		return
	_ready_done = true
	reg = DataRegistry.new()
	# ⭐ 阶段开关（roadmap-bac.md §1 约束 5「用数据开关，不用代码分支」）：
	#   这里只改一个参数即可推进阶段，B ⊂ A ⊂ C。
	#   2026-10-12：A -> **C**，启用 C 阶段内容（制造配方 / 第 7~10 把枪 / C 敌人）。
	#   （此前是 "A"，导致 recipes.json 等 C 数据加载不进来 —— 制造面板会是空的。）
	#   ⚠️ 若要严守 roadmap 的门 1 / 门 2 节奏，把 "C" 改回 "A" 即可，不需要改任何代码。
	if not reg.load_all("C"):
		push_error("[Game] 数据加载失败：%s" % str(reg.errors))
		return
	hideout = Hideout.new(reg.items, 3000, reg.weapons, reg.attachments)
	hideout.wallet += 5000
	save = SaveManager.new()
	load_game()


# ─────────────────── 存档读写 ───────────────────

## 把藏身处 / 设置 / 统计写进存档。返回失败原因（空串 = 成功）。
func save_game() -> String:
	if save == null or hideout == null:
		return "还没初始化"
	var err := save.save({
		"hideout": hideout.to_dict(),
		"settings": {
			"auto_fire": auto_fire,
			"auto_aim": auto_aim,
			"vision_follows_lock": vision_follows_lock,
			"shake_enabled": shake_enabled,
			"hitstop_enabled": hitstop_enabled,
			"flash_enabled": flash_enabled,
		},
		"stats": stats.duplicate(),
	})
	save_status = "已保存" if err == "" else "保存失败：%s" % err
	if err != "":
		push_warning("[Game] 存档失败：%s" % err)
	return err


## 读存档并应用。返回是否成功读到了已有存档。
func load_game() -> bool:
	if save == null or hideout == null:
		return false
	var r := save.load_save()
	if not bool(r["ok"]):
		# 没有存档 = 全新开局，不算错误
		save_status = "新档：%s" % str(r["error"])
		return false
	var d: Dictionary = r["data"]
	if d.has("hideout"):
		hideout.from_dict(d["hideout"])
	if d.has("settings"):
		var s: Dictionary = d["settings"]
		auto_fire = bool(s.get("auto_fire", auto_fire))
		auto_aim = bool(s.get("auto_aim", auto_aim))
		vision_follows_lock = bool(s.get("vision_follows_lock", vision_follows_lock))
		shake_enabled = bool(s.get("shake_enabled", shake_enabled))
		hitstop_enabled = bool(s.get("hitstop_enabled", hitstop_enabled))
		flash_enabled = bool(s.get("flash_enabled", flash_enabled))
	if d.has("stats"):
		for k in stats.keys():
			stats[k] = int((d["stats"] as Dictionary).get(k, stats[k]))
	var from := int(r["migrated_from"])
	save_status = "读档成功" if from == SaveManager.SAVE_VERSION \
		else "读档成功（从 v%d 迁移）" % from
	return true


## 一局结束后记一笔统计并自动存档
func record_raid_result(win: bool, kills: int) -> void:
	stats["raids"] = int(stats["raids"]) + 1
	stats["kills"] = int(stats["kills"]) + kills
	if win:
		stats["extracts"] = int(stats["extracts"]) + 1
	else:
		stats["deaths"] = int(stats["deaths"]) + 1
	save_game()


## 应用无障碍设置到 Feel（场景加载后调用一次即可）
func apply_accessibility() -> void:
	if Feel == null:
		return
	Feel.set_accessibility(shake_enabled, hitstop_enabled, flash_enabled, 1.0)


## 启动一局突袭
func start_raid(seed_override: int = 0) -> void:
	raid_seed = seed_override
	get_tree().change_scene_to_file(RAID_SCENE)


## 返回藏身处（死亡或撤离结算后走这里，不是"重启战局"）
func go_to_hideout() -> void:
	get_tree().change_scene_to_file(HIDEOUT_SCENE)


## 回到主菜单（主页）。藏身处 / 突袭里的「主菜单」按钮走这里。
func go_to_main_menu() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## 待用的地图种子（0 = 随机）
var raid_seed: int = 0

## 下一局要打的地图主题 id（对应 data/maps.json）。
## "" = 让 raid_scene 按种子随机挑一个。
## 藏身处可以设置它来"选择去哪张图"（森林 / 城区 / 军事基地）。
var map_id: String = ""


## 全屏场景切换的简易封装（带一点淡入，避免突兀）
func _change(path_: String) -> void:
	get_tree().change_scene_to_file(path_)
