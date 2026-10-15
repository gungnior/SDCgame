class_name MapThemeDef
extends RefCounted

## 地图主题定义。数据来源：data/maps.json
## 契约：data/SCHEMA.md §10
##
## 一个主题（森林 / 城区 / 军事基地）一次性决定 5 件事：
##   ① 地图多大（map_w/map_h 逻辑格）
##   ② 房间配额（room_weights：普通房间按权重抽主题）
##   ③ 敌人种类（enemy_weights：这个主题刷哪些敌人）
##   ④ 敌人密度（enemy_density：敌人总数 ≈ 房间数 × density）
##   ⑤ 白模色调（tile_theme —— 白模阶段用色调区分主题，不给美术写死）
##
## 纯 RefCounted，可 headless 单测。

## 白模阶段的主题色调（渲染层按它选色；换成美术资源时只改渲染层）
const TILE_THEMES := ["dirt", "concrete", "metal"]

var id: String = ""
var name: String = ""
var desc: String = ""
var map_w: int = 34
var map_h: int = 34
var enemy_density: float = 1.0
var tile_theme: String = "concrete"
var room_weights: Dictionary = {}    ## room_def_id -> weight
var enemy_weights: Dictionary = {}   ## enemy_id    -> weight
var stage: String = "C"


static func from_dict(d: Dictionary) -> MapThemeDef:
	var o := MapThemeDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.desc = str(d.get("desc", ""))
	o.map_w = int(d.get("map_w", 34))
	o.map_h = int(d.get("map_h", 34))
	o.enemy_density = float(d.get("enemy_density", 1.0))
	o.tile_theme = str(d.get("tile_theme", "concrete"))
	o.room_weights = (d.get("room_weights", {}) as Dictionary).duplicate()
	o.enemy_weights = (d.get("enemy_weights", {}) as Dictionary).duplicate()
	o.stage = str(d.get("stage", "C"))
	return o


## 按权重抽一个【房间类型 id】。rng 必须注入（T-32 禁止全局随机）。
func roll_room_def(rng: SimRng) -> String:
	return _weighted_pick(room_weights, rng)


## 按权重抽一个【敌人 id】。
func roll_enemy(rng: SimRng) -> String:
	return _weighted_pick(enemy_weights, rng)


## 通用加权抽取。权重非正的条目会被跳过。
static func _weighted_pick(weights: Dictionary, rng: SimRng) -> String:
	if weights.is_empty() or rng == null:
		return ""
	var keys: Array = []
	var ws: Array = []
	for k in weights:
		var w := int(weights[k])
		if w > 0:
			keys.append(str(k))
			ws.append(w)
	if keys.is_empty():
		return ""
	# keys 顺序必须稳定 —— Dictionary 迭代顺序在 Godot 里是插入序，
	# 但为了可复现，这里额外排序一次，避免将来换数据顺序导致行为漂移。
	var order: Array = []
	for i in keys.size():
		order.append(i)
	order.sort_custom(func(a, b): return keys[a] < keys[b])
	var sorted_keys: Array = []
	var sorted_ws: Array = []
	for i in order:
		sorted_keys.append(keys[i])
		sorted_ws.append(ws[i])
	var idx := rng.weighted_index(sorted_ws)
	if idx < 0 or idx >= sorted_keys.size():
		return sorted_keys[0]
	return sorted_keys[idx]


## 敌人总数目标：房间数 × 密度（供 MapGenerator 参考地图大小分配敌人）
func target_enemy_count(room_count: int) -> int:
	return maxi(0, int(round(float(room_count) * enemy_density)))


## 深拷贝。⭐ 任何"本局临时改主题"的路径必须先 clone() ——
## reg.get_map() 返回的是 **registry 里的共享实例**，直接改 enemy_density
## 会污染全局（后续每一局都带着倍率，且跨局累积）。
## 肉鸽变体（RunModifiers）乘密度、以及未来任何局内修正都走这条路。
func clone() -> MapThemeDef:
	var o := MapThemeDef.new()
	o.id = id
	o.name = name
	o.desc = desc
	o.map_w = map_w
	o.map_h = map_h
	o.enemy_density = enemy_density
	o.tile_theme = tile_theme
	o.room_weights = room_weights.duplicate()
	o.enemy_weights = enemy_weights.duplicate()
	o.stage = stage
	return o


func _to_string() -> String:
	return "MapThemeDef(%s, %dx%d, density=%.2f)" % [id, map_w, map_h, enemy_density]
