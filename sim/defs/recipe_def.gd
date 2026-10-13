class_name RecipeDef
extends RefCounted

## 配方定义。数据来源：data/recipes.json
## 契约：data/SCHEMA.md §8
##
## 纯 RefCounted —— 不 extends Node、不引用 Control/Sprite2D、不读文件。
## 与 ItemDef / WeaponDef 一致（见 D-06 / T-69「模拟层可 headless 单测」）。

## 配方中的一个输入成分
class Ingredient extends RefCounted:
	var item_id: String = ""
	var count: int = 1

	static func from_dict(d: Dictionary) -> Ingredient:
		var g := Ingredient.new()
		g.item_id = str(d.get("item_id", ""))
		g.count = int(d.get("count", 1))
		return g

	func _to_string() -> String:
		return "Ingredient(%s x%d)" % [item_id, count]


## 可用的制造台（与 data/SCHEMA.md §8 保持一致）
const STATIONS := ["bench", "forge", "lab", "kitchen"]

var id: String = ""
var name: String = ""
var name_en: String = ""
var station: String = ""
var inputs: Array[Ingredient] = []
var output_item_id: String = ""
var output_count: int = 1
var time: float = 0.0
var stage: String = "C"


static func from_dict(d: Dictionary) -> RecipeDef:
	var o := RecipeDef.new()
	o.id = str(d.get("id", ""))
	o.name = str(d.get("name", ""))
	o.name_en = str(d.get("name_en", ""))
	o.station = str(d.get("station", ""))
	o.output_item_id = str(d.get("output_item_id", ""))
	o.output_count = int(d.get("output_count", 1))
	o.time = float(d.get("time", 0.0))
	o.stage = str(d.get("stage", "C"))
	var raw_inputs: Array = d.get("inputs", [])
	for g in raw_inputs:
		if g is Dictionary:
			o.inputs.append(Ingredient.from_dict(g))
	return o


## 输入成分总数（用于平衡/UI 展示）
func total_input_count() -> int:
	var t := 0
	for g in inputs:
		t += g.count
	return t


func _to_string() -> String:
	return "RecipeDef(%s -> %s x%d, station=%s, %d inputs)" % [
		id, output_item_id, output_count, station, inputs.size(),
	]
