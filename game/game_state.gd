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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ensure_loaded()


func ensure_loaded() -> void:
	if _ready_done:
		return
	_ready_done = true
	reg = DataRegistry.new()
	if not reg.load_all("A"):
		push_error("[Game] 数据加载失败：%s" % str(reg.errors))
		return
	hideout = Hideout.new(reg.items, 3000)
	hideout.wallet += 5000


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


## 待用的地图种子（0 = 随机）
var raid_seed: int = 0


## 全屏场景切换的简易封装（带一点淡入，避免突兀）
func _change(path_: String) -> void:
	get_tree().change_scene_to_file(path_)
